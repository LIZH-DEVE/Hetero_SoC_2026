import argparse
import binascii
import socket
import sys


DEFAULT_IP = "192.168.1.20"
DEFAULT_PORT = 4660
DEFAULT_TIMEOUT = 3.0

# AES-128 ECB with key 2b7e151628aed2a6abf7158809cf4f3c
DEFAULT_PLAINTEXT = bytes.fromhex("6bc1bee22e409f96e93d7e117393172a")
EXPECTED_CIPHERTEXT = bytes.fromhex("3ad77bb40d7a3660a89ecaf32466ef97")


def main() -> int:
    parser = argparse.ArgumentParser(description="Send a fixed UDP AES test vector to the AX7020 Stage A gateway.")
    parser.add_argument("--ip", default=DEFAULT_IP, help="Board IPv4 address")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Board UDP port")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT, help="Receive timeout in seconds")
    parser.add_argument(
        "--payload-hex",
        default=DEFAULT_PLAINTEXT.hex(),
        help="Hex payload to send. Must be 16-byte aligned.",
    )
    args = parser.parse_args()

    payload = bytes.fromhex(args.payload_hex)
    if len(payload) == 0 or (len(payload) % 16) != 0:
        print("payload must be non-empty and 16-byte aligned", file=sys.stderr)
        return 2

    print(f"target={args.ip}:{args.port}")
    print(f"payload_len={len(payload)}")
    print(f"payload_hex={payload.hex()}")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(args.timeout)

    try:
        sock.sendto(payload, (args.ip, args.port))
        data, addr = sock.recvfrom(4096)
    except socket.timeout:
        print("ERROR: no UDP reply before timeout", file=sys.stderr)
        return 3
    finally:
        sock.close()

    print(f"reply_from={addr[0]}:{addr[1]}")
    print(f"reply_len={len(data)}")
    print(f"reply_hex={binascii.hexlify(data).decode('ascii')}")

    if payload == DEFAULT_PLAINTEXT and len(payload) == 16:
        if data == EXPECTED_CIPHERTEXT:
            print("PASS: reply matches expected AES-128 ECB ciphertext")
            return 0
        print("FAIL: reply does not match expected AES-128 ECB ciphertext", file=sys.stderr)
        print(f"expected_hex={EXPECTED_CIPHERTEXT.hex()}", file=sys.stderr)
        return 4

    if len(data) != len(payload):
        print("FAIL: reply length does not match request length", file=sys.stderr)
        return 5

    print("PASS: reply received")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
