#!/usr/bin/env python3
import argparse
import sys
from typing import Callable

import udp_crypto_control as ctrl


DEFAULT_BENCH_TIMEOUT = 10.0
MIN_BENCH_TIMEOUT = 2.0


def transact_raw(client: ctrl.ControlClient, packet: bytes) -> ctrl.ControlMessage:
    client.sock.sendto(packet, (client.ip, client.port))
    data, _addr = client.sock.recvfrom(4096)
    return ctrl.unpack_control_message(data)


def require_status(message: ctrl.ControlMessage, expected_status: int, label: str) -> None:
    if message.status_code != expected_status:
        raise RuntimeError(f"{label}: expected status {expected_status}, got {message.status_code}")


def _emit_status(emit: Callable[[str], None], status: dict[str, int]) -> None:
    for key, value in status.items():
        emit(f"{key}={value}")


def _emit_bench(emit: Callable[[str], None], bench: dict[str, object]) -> None:
    emit(f"algo={bench['algo']} repeats={bench['repeats']}")
    for record in bench["records"]:
        emit(f"len={record['length']} sw_us={record['sw_us']} hw_us={record['hw_us']}")


def run_regression(
    ip: str,
    source_ip: str,
    timeout: float,
    bench_timeout: float,
    port: int,
    bench_repeats: int,
    *,
    client_factory: Callable[..., ctrl.ControlClient] = ctrl.ControlClient,
    raw_transact: Callable[[ctrl.ControlClient, bytes], ctrl.ControlMessage] = transact_raw,
    emit: Callable[[str], None] = print,
) -> None:
    first_client = client_factory(ip=ip, source_ip=source_ip, timeout=timeout, port=port)
    first_session_id = 0
    try:
        emit("CASE hello")
        hello = first_client.hello()
        first_session_id = hello.session_id
        emit(f"session_id=0x{hello.session_id:08x}")
        emit(f"binding_id=0x{first_client.binding_id:08x}")

        emit("CASE set-key aes")
        first_client.set_key("aes")
        emit("authorized=aes")

        emit("CASE status")
        status = ctrl.decode_status_payload(first_client.status().payload)
        _emit_status(emit, status)

        emit("CASE replay")
        replay_seq = first_client.seq_id + 1
        replay_packet = ctrl.pack_control_message(
            msg_type=ctrl.MSG_STATUS,
            session_id=first_client.session_id,
            seq_id=replay_seq,
            binding_id=first_client.binding_id,
        )
        first = raw_transact(first_client, replay_packet)
        require_status(first, ctrl.STATUS_OK, "replay-first")
        second = raw_transact(first_client, replay_packet)
        require_status(second, ctrl.STATUS_REPLAY, "replay-second")
        first_client.seq_id = replay_seq
        emit("replay_drop=1")

        emit("CASE lock")
        first_client.lock()
        locked = ctrl.decode_status_payload(first_client.status().payload)
        emit(f"locked={locked['locked']}")
        if locked["locked"] != 1:
            raise RuntimeError("lock status did not assert")

        emit("CASE unlock")
        first_client.unlock()
        unlocked = ctrl.decode_status_payload(first_client.status().payload)
        emit(f"locked_after_unlock={unlocked['locked']}")
        if unlocked["locked"] != 0:
            raise RuntimeError("unlock status did not clear")
    finally:
        first_client.close()

    bench_client = client_factory(ip=ip, source_ip=source_ip, timeout=bench_timeout, port=port)
    try:
        emit("CASE hello bench")
        bench_hello = bench_client.hello()
        emit(f"bench_session_id=0x{bench_hello.session_id:08x}")
        emit(f"bench_binding_id=0x{bench_client.binding_id:08x}")
        if bench_hello.session_id == first_session_id:
            raise RuntimeError("bench session_id did not rotate after unlock")

        emit("CASE set-key dual")
        bench_client.set_key("aes", dual_enable=True)
        dual_status = ctrl.decode_status_payload(bench_client.status().payload)
        emit(f"authorized_mask=0x{dual_status['authorized_mask']:02x}")
        if dual_status["authorized_mask"] != (ctrl.ALGO_FLAG_AES | ctrl.ALGO_FLAG_SM4):
            raise RuntimeError(f"unexpected authorized_mask 0x{dual_status['authorized_mask']:02x}")

        for algo in ("aes", "sm4"):
            emit(f"CASE bench {algo}")
            bench = ctrl.decode_bench_payload(bench_client.bench(algo, repeats=bench_repeats).payload)
            _emit_bench(emit, bench)
    finally:
        bench_client.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Run control-plane regression against the AX7020 UDP crypto gateway.")
    parser.add_argument("--ip", default=ctrl.DEFAULT_IP, help="Board IPv4 address")
    parser.add_argument("--source-ip", default=ctrl.DEFAULT_SOURCE_IP, help="Local source IP to bind")
    parser.add_argument("--timeout", type=float, default=ctrl.DEFAULT_TIMEOUT, help="Receive timeout in seconds")
    parser.add_argument("--bench-timeout", type=float, default=DEFAULT_BENCH_TIMEOUT, help="Receive timeout in seconds for BENCH responses")
    parser.add_argument("--port", type=int, default=ctrl.CONTROL_PORT, help="Control UDP port")
    parser.add_argument("--bench-repeats", type=int, default=ctrl.DEFAULT_BENCH_REPEATS, help="Repeat count for BENCH")
    args = parser.parse_args()

    if args.bench_timeout < MIN_BENCH_TIMEOUT:
        print(f"CONTROL_REGRESSION_FAIL error=bench_timeout must be >= {MIN_BENCH_TIMEOUT:.1f}s", file=sys.stderr)
        return 2

    try:
        run_regression(
            ip=args.ip,
            source_ip=args.source_ip,
            timeout=args.timeout,
            bench_timeout=args.bench_timeout,
            port=args.port,
            bench_repeats=args.bench_repeats,
        )
        print("CONTROL_REGRESSION_PASS")
        return 0
    except Exception as exc:
        print(f"CONTROL_REGRESSION_FAIL error={exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
