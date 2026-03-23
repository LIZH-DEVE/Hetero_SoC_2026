#!/usr/bin/env python3
import argparse
import binascii
import socket
import sys
import time

from Crypto.Cipher import AES
import sm4_reference
import udp_crypto_control as ctrl


DEFAULT_IP = "192.168.1.20"
DEFAULT_TIMEOUT = 3.0
DEFAULT_RETRIES = 3
DEFAULT_RETRY_DELAY = 0.5
DEFAULT_SOURCE_IP = "192.168.1.11"
DEFAULT_SEND_INTERVAL_MS = 0.0
DEFAULT_COUNT = 1
DEFAULT_HEX_PREVIEW_CHARS = 96

AES_PORT = 4660
SM4_PORT = 4661

AES_KEY_HEX = "2b7e151628aed2a6abf7158809cf4f3c"
AES_DEFAULT_PAYLOAD_HEX = "3243f6a8885a308d313198a2e0370734"
AES_EXPECTED_REPLY_HEX = "3925841d02dc09fbdc118597196a0b32"
SM4_KEY_HEX = "0123456789abcdeffedcba9876543210"
SM4_DEFAULT_PAYLOAD_HEX = "0123456789abcdeffedcba9876543210"
SM4_EXPECTED_REPLY_HEX = "681edf34d206965e86b3e94f536e4246"


def parse_hex_payload(text: str) -> bytes:
    normalized = text.replace(" ", "").replace("_", "")
    if len(normalized) == 0:
        raise ValueError("payload must not be empty")
    if len(normalized) % 2 != 0:
        raise ValueError("payload hex length must be even")
    data = binascii.unhexlify(normalized)
    if len(data) % 16 != 0:
        raise ValueError("payload length must be a multiple of 16 bytes")
    return data


def parse_hex_payload_unaligned(text: str) -> bytes:
    normalized = text.replace(" ", "").replace("_", "")
    if len(normalized) == 0:
        raise ValueError("payload must not be empty")
    if len(normalized) % 2 != 0:
        raise ValueError("payload hex length must be even")
    return binascii.unhexlify(normalized)


def resolve_profile_defaults(algo: str) -> tuple[int, str, str]:
    if algo == "sm4":
        return SM4_PORT, SM4_DEFAULT_PAYLOAD_HEX, SM4_EXPECTED_REPLY_HEX
    return AES_PORT, AES_DEFAULT_PAYLOAD_HEX, AES_EXPECTED_REPLY_HEX


def chunk_blocks(data: bytes, block_size: int = 16) -> list[bytes]:
    return [data[i:i + block_size] for i in range(0, len(data), block_size)]


def expected_aes_ecb(payload: bytes, key: bytes | None = None) -> bytes:
    resolved_key = key if key is not None else binascii.unhexlify(AES_KEY_HEX)
    cipher = AES.new(resolved_key, AES.MODE_ECB)
    return b"".join(cipher.encrypt(block) for block in chunk_blocks(payload))


def expected_sm4_repeated_default(payload: bytes) -> bytes | None:
    default_pt = binascii.unhexlify(SM4_DEFAULT_PAYLOAD_HEX)
    default_ct = binascii.unhexlify(SM4_EXPECTED_REPLY_HEX)
    blocks = chunk_blocks(payload)
    if all(block == default_pt for block in blocks):
        return default_ct * len(blocks)
    return None


def expected_sm4_ecb(payload: bytes, key: bytes) -> bytes:
    return sm4_reference.ecb_encrypt(key, payload)


def resolve_user_key_bytes(algo: str, user_key_hex: str | None) -> bytes:
    if user_key_hex is None:
        return ctrl.default_user_key(algo)
    normalized = user_key_hex.replace(" ", "").replace("_", "")
    return binascii.unhexlify(normalized)


def derive_binding_aware_expected(algo: str, payload: bytes, binding_id: int, user_key: bytes) -> bytes:
    effective_key = ctrl.derive_effective_key(user_key, binding_id, ctrl.algo_to_id(algo))
    if algo == "sm4":
        return expected_sm4_ecb(payload, key=effective_key)
    return expected_aes_ecb(payload, key=effective_key)


def render_hex(text: str, summary_only: bool, preview_chars: int) -> str:
    if not summary_only or len(text) <= preview_chars:
        return text
    if preview_chars < 16:
        preview_chars = 16
    head = preview_chars // 2
    tail = preview_chars - head
    return f"{text[:head]}...{text[-tail:]} (chars={len(text)})"


def main() -> int:
    parser = argparse.ArgumentParser(description="Send paced UDP crypto-gateway test packets to the AX7020 board.")
    parser.add_argument("--algo", choices=("aes", "sm4"), default="aes", help="Gateway algorithm profile")
    parser.add_argument("--ip", default=DEFAULT_IP, help="Board IP address")
    parser.add_argument("--port", type=int, default=None, help="Board UDP port; defaults from --algo")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT, help="Receive timeout in seconds")
    parser.add_argument("--retries", type=int, default=DEFAULT_RETRIES, help="Number of UDP send attempts before giving up")
    parser.add_argument("--retry-delay", type=float, default=DEFAULT_RETRY_DELAY, help="Delay between retries in seconds")
    parser.add_argument("--count", type=int, default=DEFAULT_COUNT, help="Number of request/response rounds")
    parser.add_argument("--send-interval-ms", type=float, default=DEFAULT_SEND_INTERVAL_MS, help="Delay between successful rounds in milliseconds")
    parser.add_argument("--source-ip", default=DEFAULT_SOURCE_IP, help="Local source IP to bind before sending")
    parser.add_argument("--broadcast", action="store_true", help="Enable SO_BROADCAST and allow sending to a subnet broadcast address")
    parser.add_argument(
        "--payload-hex",
        default=None,
        help="Hex payload to send; must be 16-byte aligned. Defaults from --algo",
    )
    parser.add_argument("--expected-reply-hex", default=None, help="Expected hex reply; defaults from --algo for the default single-block payload")
    parser.add_argument("--allow-unaligned", action="store_true", help="Allow non-16-byte-aligned payloads for negative tests")
    parser.add_argument("--expect-timeout", action="store_true", help="Treat no reply as success; fail if a reply is received")
    parser.add_argument("--summary-only", action="store_true", help="Print compact summaries instead of full hex payloads")
    parser.add_argument("--hex-preview-chars", type=int, default=DEFAULT_HEX_PREVIEW_CHARS, help="Hex preview width when --summary-only is enabled")
    parser.add_argument("--control-port", type=int, default=ctrl.CONTROL_PORT, help="Gateway control-plane UDP port")
    parser.add_argument("--skip-control-session", action="store_true", help="Skip HELLO/SET_KEY before sending data packets")
    parser.add_argument("--dual-enable", action="store_true", help="Authorize both AES and SM4 during SET_KEY")
    parser.add_argument("--user-key-hex", default=None, help="Optional 16-byte user key for control-plane SET_KEY")
    args = parser.parse_args()

    default_port, default_payload_hex, default_expected_hex = resolve_profile_defaults(args.algo)
    port = args.port if args.port is not None else default_port
    payload_hex = args.payload_hex if args.payload_hex is not None else default_payload_hex
    payload = parse_hex_payload_unaligned(payload_hex) if args.allow_unaligned else parse_hex_payload(payload_hex)
    expected = None
    expected_mode = "none"

    control_client = None
    selected_user_key = resolve_user_key_bytes(args.algo, args.user_key_hex)
    if not args.skip_control_session and not args.expect_timeout:
        try:
            control_client = ctrl.authorize_session(
                ip=args.ip,
                source_ip=args.source_ip,
                timeout=args.timeout,
                algo=args.algo,
                control_port=args.control_port,
                dual_enable=args.dual_enable,
            )
            if args.user_key_hex is not None:
                control_client.set_key(args.algo, user_key=selected_user_key, dual_enable=args.dual_enable)
            print(f"control_session=1 session_id=0x{control_client.session_id:08x} binding_id=0x{control_client.binding_id:08x}")
        except Exception as exc:
            print(f"control_session=0 error={exc}", file=sys.stderr)
            return 9

    if args.expect_timeout:
        expected_mode = "timeout"
    elif args.expected_reply_hex is not None:
        expected = binascii.unhexlify(args.expected_reply_hex)
        expected_mode = "explicit"
    elif (len(payload) % 16) == 0 and control_client is not None:
        expected = derive_binding_aware_expected(args.algo, payload, control_client.binding_id, selected_user_key)
        expected_mode = "auto_effective_key_ecb"
    elif args.algo == "aes":
        if (len(payload) % 16) == 0:
            expected = expected_aes_ecb(payload)
            expected_mode = "auto_ecb_blockmap"
    else:
        expected = expected_sm4_repeated_default(payload)
        if expected is not None:
            expected_mode = "auto_repeated_default_block"

    print(f"algo={args.algo}")
    print(f"target={args.ip}:{port}")
    print(f"source_ip={args.source_ip}")
    print(f"broadcast_mode={int(args.broadcast or args.ip.endswith('.255'))}")
    print(f"count={max(1, args.count)}")
    print(f"send_interval_ms={max(0.0, args.send_interval_ms)}")
    print(f"allow_unaligned={int(args.allow_unaligned)}")
    print(f"expect_timeout={int(args.expect_timeout)}")
    print(f"payload_len={len(payload)}")
    print(f"payload_hex={render_hex(payload.hex(), args.summary_only, args.hex_preview_chars)}")
    print(f"expected_mode={expected_mode}")
    if expected is not None:
        print(f"expected_reply_hex={render_hex(expected.hex(), args.summary_only, args.hex_preview_chars)}")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(args.timeout)
    if args.broadcast or args.ip.endswith(".255"):
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.bind((args.source_ip, 0))

    reply = None
    addr = None
    try:
        for round_index in range(1, max(1, args.count) + 1):
            if args.count > 1:
                print(f"round={round_index}")
            reply = None
            addr = None
            for attempt in range(1, max(1, args.retries) + 1):
                print(f"attempt={attempt}")
                sock.sendto(payload, (args.ip, port))
                try:
                    reply, addr = sock.recvfrom(4096)
                    break
                except socket.timeout:
                    print("attempt_result=TIMEOUT")
                    if attempt < max(1, args.retries):
                        time.sleep(max(0.0, args.retry_delay))
            if reply is None or addr is None:
                break
            if round_index < max(1, args.count):
                time.sleep(max(0.0, args.send_interval_ms) / 1000.0)
    finally:
        sock.close()
        if control_client is not None:
            control_client.close()

    if reply is None or addr is None:
        if args.expect_timeout:
            print("expected_timeout=1")
            print("result=PASS")
            return 0
        print("result=TIMEOUT")
        return 1

    print(f"reply_from={addr[0]}:{addr[1]}")
    print(f"reply_len={len(reply)}")
    print(f"reply_hex={render_hex(reply.hex(), args.summary_only, args.hex_preview_chars)}")

    if args.expect_timeout:
        print("expected_timeout=0")
        print("result=UNEXPECTED_REPLY")
        return 2

    if reply != payload:
        print("reply_differs_from_plaintext=1")
    else:
        print("reply_differs_from_plaintext=0")

    if expected is not None:
        if reply == expected:
            print("expected_match=1")
            print("result=PASS")
            return 0
        print("expected_match=0")
        print("result=UNEXPECTED_REPLY")
        return 3

    print("result=RECEIVED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
