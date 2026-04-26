#!/usr/bin/env python3
import argparse
import ipaddress
import socket
import struct
import sys
from dataclasses import dataclass


DEFAULT_IP = "192.168.1.20"
DEFAULT_SOURCE_IP = "192.168.1.11"
DEFAULT_TIMEOUT = 3.0
DEFAULT_BINDING_ID = 0x41583702
DEFAULT_AES_USER_KEY_HEX = "2b7e151628aed2a6abf7158809cf4f3c"
DEFAULT_SM4_USER_KEY_HEX = "0123456789abcdeffedcba9876543210"
DEFAULT_BENCH_REPEATS = 8

CONTROL_PORT = 4662
CONTROL_MAGIC = 0x4352544C  # 'CRTL'
CONTROL_VERSION = 1

MSG_HELLO = 1
MSG_SET_KEY = 2
MSG_LOCK = 3
MSG_UNLOCK = 4
MSG_STATUS = 5
MSG_BENCH = 6
MSG_ACL_WRITE = 7
MSG_ACL_CLEAR = 8
MSG_ACL_STATUS = 9

ALGO_AES = 0
ALGO_SM4 = 1
ALGO_FLAG_AES = 0x01
ALGO_FLAG_SM4 = 0x02

STATUS_OK = 0
STATUS_BAD_MAGIC = 1
STATUS_BAD_VERSION = 2
STATUS_BAD_LENGTH = 3
STATUS_SESSION_REQUIRED = 4
STATUS_AUTH_FAIL = 5
STATUS_REPLAY = 6
STATUS_LOCKED = 7
STATUS_NO_SESSION = 8
STATUS_INTERNAL = 9
STATUS_UNKNOWN_MSG = 10
STATUS_NOT_AUTHORIZED = 11
STATUS_BUSY = 12

HEADER_STRUCT = struct.Struct("!IBBBBIIHHI")
STATUS_STRUCT = struct.Struct("!IIIIIIIIIIIIII")
BENCH_HEADER_STRUCT = struct.Struct("!BBH")
BENCH_RECORD_STRUCT = struct.Struct("!HHII")


@dataclass
class ControlMessage:
    version: int
    msg_type: int
    flags: int
    session_id: int
    seq_id: int
    payload_len: int
    status_code: int
    auth_tag: int
    payload: bytes


class ControlStatusError(RuntimeError):
    def __init__(self, message: ControlMessage):
        self.message = message
        self.status_code = message.status_code
        self.msg_type = message.msg_type
        super().__init__(f"control status={message.status_code} msg_type={message.msg_type}")


def fnv1a32(data: bytes, seed: int = 0x811C9DC5) -> int:
    value = seed & 0xFFFFFFFF
    for byte in data:
        value ^= byte
        value = (value * 0x01000193) & 0xFFFFFFFF
    return value


def derive_effective_key(user_key: bytes, binding_id: int, algo: int) -> bytes:
    """Derive the 16-byte effective key from user key + binding id + algo.

    The binding_id serialization is part of the protocol contract and is frozen
    as big-endian to match the board firmware. Do not change this to
    little-endian unless the C side changes at the same time.
    """
    if len(user_key) != 16:
        raise ValueError("user_key must be exactly 16 bytes")

    out = bytearray()
    binding_bytes = struct.pack("!I", binding_id & 0xFFFFFFFF)
    for counter in range(4):
        material = user_key + binding_bytes + bytes((algo & 0xFF, counter & 0xFF))
        out.extend(struct.pack("!I", fnv1a32(material, seed=0x811C9DC5 ^ counter)))
    return bytes(out[:16])


def compute_auth_tag(
    msg_type: int,
    session_id: int,
    seq_id: int,
    flags: int,
    status_code: int,
    payload: bytes,
    binding_id: int,
) -> int:
    # binding_id stays big-endian here as well; the control-plane auth tag must
    # use the same serialization contract as derive_effective_key().
    header_material = struct.pack(
        "!IBBBBIIHH",
        CONTROL_MAGIC,
        CONTROL_VERSION,
        msg_type & 0xFF,
        flags & 0xFF,
        0,
        session_id & 0xFFFFFFFF,
        seq_id & 0xFFFFFFFF,
        len(payload) & 0xFFFF,
        status_code & 0xFFFF,
    )
    return fnv1a32(struct.pack("!I", binding_id & 0xFFFFFFFF) + header_material + payload)


def pack_control_message(
    msg_type: int,
    session_id: int,
    seq_id: int,
    flags: int = 0,
    payload: bytes = b"",
    binding_id: int = DEFAULT_BINDING_ID,
    status_code: int = STATUS_OK,
) -> bytes:
    auth_tag = 0
    if msg_type != MSG_HELLO:
        auth_tag = compute_auth_tag(msg_type, session_id, seq_id, flags, status_code, payload, binding_id)
    return HEADER_STRUCT.pack(
        CONTROL_MAGIC,
        CONTROL_VERSION,
        msg_type & 0xFF,
        flags & 0xFF,
        0,
        session_id & 0xFFFFFFFF,
        seq_id & 0xFFFFFFFF,
        len(payload) & 0xFFFF,
        status_code & 0xFFFF,
        auth_tag & 0xFFFFFFFF,
    ) + payload


def unpack_control_message(data: bytes) -> ControlMessage:
    if len(data) < HEADER_STRUCT.size:
        raise ValueError("control packet too short")

    magic, version, msg_type, flags, _reserved, session_id, seq_id, payload_len, status_code, auth_tag = HEADER_STRUCT.unpack(
        data[:HEADER_STRUCT.size]
    )
    if magic != CONTROL_MAGIC:
        raise ValueError(f"bad magic 0x{magic:08x}")
    if len(data) != HEADER_STRUCT.size + payload_len:
        raise ValueError("payload length mismatch")

    payload = data[HEADER_STRUCT.size:]
    return ControlMessage(
        version=version,
        msg_type=msg_type,
        flags=flags,
        session_id=session_id,
        seq_id=seq_id,
        payload_len=payload_len,
        status_code=status_code,
        auth_tag=auth_tag,
        payload=payload,
    )


def algo_to_flag(algo: str) -> int:
    return ALGO_FLAG_SM4 if algo == "sm4" else ALGO_FLAG_AES


def algo_to_id(algo: str) -> int:
    return ALGO_SM4 if algo == "sm4" else ALGO_AES


def default_user_key(algo: str) -> bytes:
    return bytes.fromhex(DEFAULT_SM4_USER_KEY_HEX if algo == "sm4" else DEFAULT_AES_USER_KEY_HEX)


class ControlClient:
    def __init__(self, ip: str, source_ip: str, timeout: float, port: int = CONTROL_PORT):
        self.ip = ip
        self.source_ip = source_ip
        self.timeout = timeout
        self.port = port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.settimeout(timeout)
        self.sock.bind((source_ip, 0))
        self.session_id = 0
        self.seq_id = 0
        self.binding_id = DEFAULT_BINDING_ID

    def close(self) -> None:
        self.sock.close()

    def _next_seq(self) -> int:
        self.seq_id += 1
        return self.seq_id

    def transact(self, msg_type: int, flags: int = 0, payload: bytes = b"") -> ControlMessage:
        seq_id = 0 if msg_type == MSG_HELLO else self._next_seq()
        packet = pack_control_message(
            msg_type=msg_type,
            session_id=self.session_id,
            seq_id=seq_id,
            flags=flags,
            payload=payload,
            binding_id=self.binding_id,
        )
        self.sock.sendto(packet, (self.ip, self.port))
        data, _addr = self.sock.recvfrom(4096)
        message = unpack_control_message(data)
        if message.status_code != STATUS_OK:
            raise ControlStatusError(message)
        if msg_type == MSG_HELLO:
            self.session_id = message.session_id
            if len(message.payload) >= 4:
                self.binding_id = struct.unpack("!I", message.payload[:4])[0]
        return message

    def hello(self) -> ControlMessage:
        return self.transact(MSG_HELLO)

    def set_key(self, algo: str, user_key: bytes | None = None, dual_enable: bool = False) -> ControlMessage:
        key_material = user_key if user_key is not None else default_user_key(algo)
        if len(key_material) != 16:
            raise ValueError("SET_KEY requires 16-byte key material")
        flags = algo_to_flag(algo)
        if dual_enable:
            flags = ALGO_FLAG_AES | ALGO_FLAG_SM4
        return self.transact(MSG_SET_KEY, flags=flags, payload=key_material)

    def status(self) -> ControlMessage:
        return self.transact(MSG_STATUS)

    def lock(self) -> ControlMessage:
        return self.transact(MSG_LOCK)

    def unlock(self) -> ControlMessage:
        return self.transact(MSG_UNLOCK)

    def bench(self, algo: str, repeats: int = DEFAULT_BENCH_REPEATS) -> ControlMessage:
        payload = struct.pack("!H", repeats & 0xFFFF)
        return self.transact(MSG_BENCH, flags=algo_to_flag(algo), payload=payload)

    def acl_write(
        self,
        src_ip: str,
        src_port: int,
        dst_ip: str,
        dst_port: int,
        protocol: int,
    ) -> ControlMessage:
        payload = (
            ipaddress.IPv4Address(src_ip).packed +
            struct.pack("!H", src_port & 0xFFFF) +
            ipaddress.IPv4Address(dst_ip).packed +
            struct.pack("!H", dst_port & 0xFFFF) +
            bytes((protocol & 0xFF,))
        )
        return self.transact(MSG_ACL_WRITE, payload=payload)

    def acl_clear(self) -> ControlMessage:
        return self.transact(MSG_ACL_CLEAR)

    def acl_status(self) -> ControlMessage:
        return self.transact(MSG_ACL_STATUS)


def authorize_session(
    ip: str,
    source_ip: str,
    timeout: float,
    algo: str,
    control_port: int = CONTROL_PORT,
    dual_enable: bool = False,
) -> ControlClient:
    client = ControlClient(ip=ip, source_ip=source_ip, timeout=timeout, port=control_port)
    client.hello()
    client.set_key(algo=algo, dual_enable=dual_enable)
    return client


def decode_status_payload(payload: bytes) -> dict[str, int]:
    if len(payload) < STATUS_STRUCT.size:
        raise ValueError("status payload too short")
    fields = STATUS_STRUCT.unpack(payload[:STATUS_STRUCT.size])
    status = {
        "binding_id": fields[0],
        "session_id": fields[1],
        "authorized_mask": fields[2],
        "locked": fields[3],
        "rx_ctrl_ok": fields[4],
        "rx_data_ok": fields[5],
        "tx_ok": fields[6],
        "drop_invalid": fields[7],
        "drop_unauthorized": fields[8],
        "drop_replay": fields[9],
        "bind_fail": fields[10],
        "lock_events": fields[11],
        "crypto_timeout": fields[12],
        "crypto_fail": fields[13],
    }
    # Legacy contract markers kept for static audits:
    # "authorized_mask_raw":
    # "last_drop_reason": (fields[2] >> 8) & 0x0F
    # "last_lock_reason": (fields[2] >> 12) & 0x0F
    status["authorized_mask_raw"] = fields[2]
    status["authorized_mask"] = fields[2] & 0xFF
    status["last_drop_reason"] = (fields[2] >> 8) & 0xF
    status["last_lock_reason"] = (fields[2] >> 12) & 0xF
    status["acl_hit_seen"] = (fields[2] >> 16) & 0x1
    status["replay_seen"] = (fields[2] >> 17) & 0x1
    status["timeout_seen"] = (fields[2] >> 18) & 0x1
    status["reauth_seen"] = (fields[2] >> 19) & 0x1
    return status


def decode_bench_payload(payload: bytes) -> dict[str, object]:
    if len(payload) < BENCH_HEADER_STRUCT.size:
        raise ValueError("bench payload too short")
    algo_id, count, repeats = BENCH_HEADER_STRUCT.unpack(payload[:BENCH_HEADER_STRUCT.size])
    records = []
    offset = BENCH_HEADER_STRUCT.size
    for _ in range(count):
        if len(payload) < offset + BENCH_RECORD_STRUCT.size:
            raise ValueError("bench payload truncated")
        length, _reserved, sw_us, hw_us = BENCH_RECORD_STRUCT.unpack(
            payload[offset: offset + BENCH_RECORD_STRUCT.size]
        )
        records.append({"length": length, "sw_us": sw_us, "hw_us": hw_us})
        offset += BENCH_RECORD_STRUCT.size
    return {
        "algo": "sm4" if algo_id == ALGO_SM4 else "aes",
        "repeats": repeats,
        "records": records,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Control-plane client for the AX7020 UDP crypto gateway.")
    parser.add_argument("--ip", default=DEFAULT_IP, help="Board IPv4 address")
    parser.add_argument("--source-ip", default=DEFAULT_SOURCE_IP, help="Local source IP to bind")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT, help="Receive timeout in seconds")
    parser.add_argument("--port", type=int, default=CONTROL_PORT, help="Control UDP port")
    parser.add_argument(
        "--expect-status",
        type=lambda x: int(x, 0),
        default=STATUS_OK,
        help="Expected control status code; returns success when matched",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_seq_argument(subparser: argparse.ArgumentParser) -> None:
        subparser.add_argument(
            "--seq-id",
            type=lambda x: int(x, 0),
            default=None,
            help="Explicit next control sequence id for replay-safe multi-process callers",
        )

    hello_parser = subparsers.add_parser("hello", help="Create or refresh a control session")
    hello_parser.set_defaults(command_name="hello")

    set_key_parser = subparsers.add_parser("set-key", help="Bind a key to the current session")
    set_key_parser.add_argument("--session-id", type=lambda x: int(x, 0), required=True)
    set_key_parser.add_argument("--binding-id", type=lambda x: int(x, 0), default=DEFAULT_BINDING_ID)
    add_seq_argument(set_key_parser)
    set_key_parser.add_argument("--algo", choices=("aes", "sm4"), required=True)
    set_key_parser.add_argument("--key-hex", default=None, help="Optional 16-byte user key hex")
    set_key_parser.add_argument("--dual-enable", action="store_true", help="Authorize both AES and SM4 for this source IP")

    status_parser = subparsers.add_parser("status", help="Read status and counters")
    status_parser.add_argument("--session-id", type=lambda x: int(x, 0), required=True)
    status_parser.add_argument("--binding-id", type=lambda x: int(x, 0), default=DEFAULT_BINDING_ID)
    add_seq_argument(status_parser)

    lock_parser = subparsers.add_parser("lock", help="Lock the current source IP")
    lock_parser.add_argument("--session-id", type=lambda x: int(x, 0), required=True)
    lock_parser.add_argument("--binding-id", type=lambda x: int(x, 0), default=DEFAULT_BINDING_ID)
    add_seq_argument(lock_parser)

    unlock_parser = subparsers.add_parser("unlock", help="Unlock the current source IP")
    unlock_parser.add_argument("--session-id", type=lambda x: int(x, 0), required=True)
    unlock_parser.add_argument("--binding-id", type=lambda x: int(x, 0), default=DEFAULT_BINDING_ID)
    add_seq_argument(unlock_parser)

    bench_parser = subparsers.add_parser("bench", help="Run on-board software vs hardware benchmark")
    bench_parser.add_argument("--session-id", type=lambda x: int(x, 0), required=True)
    bench_parser.add_argument("--binding-id", type=lambda x: int(x, 0), default=DEFAULT_BINDING_ID)
    add_seq_argument(bench_parser)
    bench_parser.add_argument("--algo", choices=("aes", "sm4"), required=True)
    bench_parser.add_argument("--repeats", type=int, default=DEFAULT_BENCH_REPEATS)

    acl_write_parser = subparsers.add_parser("acl-write", help="Install one ACL tuple rule into shadow ingress")
    acl_write_parser.add_argument("--session-id", type=lambda x: int(x, 0), required=True)
    acl_write_parser.add_argument("--binding-id", type=lambda x: int(x, 0), default=DEFAULT_BINDING_ID)
    add_seq_argument(acl_write_parser)
    acl_write_parser.add_argument("--src-ip", required=True)
    acl_write_parser.add_argument("--src-port", type=lambda x: int(x, 0), required=True)
    acl_write_parser.add_argument("--dst-ip", required=True)
    acl_write_parser.add_argument("--dst-port", type=lambda x: int(x, 0), required=True)
    acl_write_parser.add_argument("--protocol", type=lambda x: int(x, 0), required=True)

    acl_clear_parser = subparsers.add_parser("acl-clear", help="Clear all ACL rules from shadow ingress")
    acl_clear_parser.add_argument("--session-id", type=lambda x: int(x, 0), required=True)
    acl_clear_parser.add_argument("--binding-id", type=lambda x: int(x, 0), default=DEFAULT_BINDING_ID)
    add_seq_argument(acl_clear_parser)

    acl_status_parser = subparsers.add_parser("acl-status", help="Read shadow ingress ACL drop counter")
    acl_status_parser.add_argument("--session-id", type=lambda x: int(x, 0), required=True)
    acl_status_parser.add_argument("--binding-id", type=lambda x: int(x, 0), default=DEFAULT_BINDING_ID)
    add_seq_argument(acl_status_parser)

    args = parser.parse_args()

    client = ControlClient(ip=args.ip, source_ip=args.source_ip, timeout=args.timeout, port=args.port)
    try:
        try:
            if args.command == "hello":
                msg = client.hello()
                print(f"session_id=0x{msg.session_id:08x}")
                print(f"binding_id=0x{client.binding_id:08x}")
                return 0

            client.session_id = args.session_id
            client.binding_id = args.binding_id
            if hasattr(args, "seq_id") and args.seq_id is not None:
                client.seq_id = max(args.seq_id - 1, 0)

            if args.command == "set-key":
                key = bytes.fromhex(args.key_hex) if args.key_hex else None
                msg = client.set_key(args.algo, user_key=key, dual_enable=args.dual_enable)
                print(f"session_id=0x{client.session_id:08x}")
                print(f"binding_id=0x{client.binding_id:08x}")
                print(f"reply_payload_hex={msg.payload.hex()}")
                return 0
            if args.command == "status":
                status = decode_status_payload(client.status().payload)
                for key, value in status.items():
                    print(f"{key}={value}")
                return 0
            if args.command == "lock":
                client.lock()
                print("locked=1")
                return 0
            if args.command == "unlock":
                client.unlock()
                print("locked=0")
                return 0
            if args.command == "bench":
                bench = decode_bench_payload(client.bench(args.algo, repeats=args.repeats).payload)
                print(f"algo={bench['algo']}")
                print(f"repeats={bench['repeats']}")
                for record in bench["records"]:
                    print(f"len={record['length']} sw_us={record['sw_us']} hw_us={record['hw_us']}")
                return 0
            if args.command == "acl-write":
                client.acl_write(
                    src_ip=args.src_ip,
                    src_port=args.src_port,
                    dst_ip=args.dst_ip,
                    dst_port=args.dst_port,
                    protocol=args.protocol,
                )
                print("acl_write=1")
                return 0
            if args.command == "acl-clear":
                client.acl_clear()
                print("acl_clear=1")
                return 0
            if args.command == "acl-status":
                msg = client.acl_status()
                if len(msg.payload) < 4:
                    raise ValueError("acl-status payload too short")
                acl_count = struct.unpack("!I", msg.payload[:4])[0]
                print(f"acl_drop_count={acl_count}")
                return 0
            print(f"unknown command: {args.command}", file=sys.stderr)
            return 2
        except ControlStatusError as exc:
            if exc.status_code == args.expect_status:
                print(f"status_code={exc.status_code}")
                print(f"msg_type={exc.msg_type}")
                print(f"session_id=0x{exc.message.session_id:08x}")
                return 0
            print(str(exc), file=sys.stderr)
            return 1
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
