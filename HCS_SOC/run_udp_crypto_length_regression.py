#!/usr/bin/env python3
import argparse
import subprocess
import sys
from pathlib import Path


AES_BLOCK_HEX = "3243f6a8885a308d313198a2e0370734"
SM4_BLOCK_HEX = "0123456789abcdeffedcba9876543210"
FUNCTIONAL_LENGTHS = (48, 64, 128, 256, 512, 1472)
INVALID_LENGTHS = (15, 17, 1473)


def build_repeated_payload(block_hex: str, total_len: int) -> str:
    block = bytes.fromhex(block_hex)
    if total_len % len(block) != 0:
        raise ValueError(f"length {total_len} is not an integer multiple of block size {len(block)}")
    return (block * (total_len // len(block))).hex()


def build_invalid_payload(length_bytes: int) -> str:
    return bytes((i & 0xFF for i in range(length_bytes))).hex()


def run_case(sender: Path, args: list[str]) -> int:
    cmd = [sys.executable, str(sender), *args]
    print("$ " + " ".join(cmd))
    completed = subprocess.run(cmd, check=False)
    print(f"exit_code={completed.returncode}")
    print()
    return completed.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description="Run paced AX7020 UDP crypto length regression cases.")
    parser.add_argument("--ip", default="192.168.1.20", help="Board IP address")
    parser.add_argument("--source-ip", default="192.168.1.11", help="Local source IP to bind before sending")
    parser.add_argument("--timeout", type=float, default=3.0, help="Receive timeout in seconds")
    parser.add_argument("--retries", type=int, default=3, help="Retries per case")
    parser.add_argument("--retry-delay", type=float, default=0.5, help="Retry delay in seconds")
    parser.add_argument("--send-interval-ms", type=float, default=1.0, help="Gap between successful paced sends")
    parser.add_argument("--stress-count", type=int, default=20, help="Round count for paced stress")
    parser.add_argument("--hex-preview-chars", type=int, default=96, help="Hex preview width for sender summary output")
    parser.add_argument("--algo", choices=("aes", "sm4", "both"), default="both", help="Which algorithm set to run")
    parser.add_argument("--lengths", default=None, help="Comma-separated functional lengths to run, e.g. 1472 or 48,64,128")
    parser.add_argument("--skip-functional", action="store_true", help="Skip functional length cases")
    parser.add_argument("--skip-invalid", action="store_true", help="Skip invalid-length negative cases")
    parser.add_argument("--skip-stress", action="store_true", help="Skip paced stress cases")
    parser.add_argument("--sender-script", default=None, help="Path to send_udp_crypto_test.py")
    args = parser.parse_args()

    sender = Path(args.sender_script) if args.sender_script else Path(__file__).with_name("send_udp_crypto_test.py")
    if not sender.exists():
        print(f"sender script not found: {sender}", file=sys.stderr)
        return 2

    failures = 0
    selected_algos = ("aes", "sm4") if args.algo == "both" else (args.algo,)
    functional_lengths = FUNCTIONAL_LENGTHS
    if args.lengths:
        functional_lengths = tuple(int(part.strip()) for part in args.lengths.split(",") if part.strip())
        for total_len in functional_lengths:
            if total_len <= 0 or total_len > 1472 or (total_len % 16) != 0:
                print(f"invalid functional length selection: {total_len}", file=sys.stderr)
                return 2

    if not args.skip_functional:
        for algo, block_hex in (("aes", AES_BLOCK_HEX), ("sm4", SM4_BLOCK_HEX)):
            if algo not in selected_algos:
                continue
            print(f"=== FUNCTIONAL {algo.upper()} ===")
            for total_len in functional_lengths:
                payload_hex = build_repeated_payload(block_hex, total_len)
                print(f"CASE functional algo={algo} len={total_len}")
                case_args = [
                    "--algo", algo,
                    "--ip", args.ip,
                    "--source-ip", args.source_ip,
                    "--timeout", str(args.timeout),
                    "--retries", str(args.retries),
                    "--retry-delay", str(args.retry_delay),
                    "--count", "1",
                    "--send-interval-ms", str(args.send_interval_ms),
                    "--summary-only",
                    "--hex-preview-chars", str(args.hex_preview_chars),
                    "--payload-hex", payload_hex,
                ]
                if run_case(sender, case_args) != 0:
                    failures += 1

    if not args.skip_invalid:
        print("=== INVALID LENGTHS ===")
        for algo in selected_algos:
            for total_len in INVALID_LENGTHS:
                payload_hex = build_invalid_payload(total_len)
                print(f"CASE invalid algo={algo} len={total_len}")
                case_args = [
                    "--algo", algo,
                    "--ip", args.ip,
                    "--source-ip", args.source_ip,
                    "--timeout", str(args.timeout),
                    "--retries", str(args.retries),
                    "--retry-delay", str(args.retry_delay),
                    "--count", "1",
                    "--send-interval-ms", str(args.send_interval_ms),
                    "--summary-only",
                    "--hex-preview-chars", str(args.hex_preview_chars),
                    "--payload-hex", payload_hex,
                    "--allow-unaligned",
                    "--expect-timeout",
                ]
                if run_case(sender, case_args) != 0:
                    failures += 1

    if not args.skip_stress:
        for algo, block_hex in (("aes", AES_BLOCK_HEX), ("sm4", SM4_BLOCK_HEX)):
            if algo not in selected_algos:
                continue
            print(f"=== PACED STRESS {algo.upper()} 1472 ===")
            payload_hex = build_repeated_payload(block_hex, 1472)
            print(f"CASE stress algo={algo} len=1472 count={args.stress_count}")
            case_args = [
                "--algo", algo,
                "--ip", args.ip,
                "--source-ip", args.source_ip,
                "--timeout", str(args.timeout),
                "--retries", str(args.retries),
                "--retry-delay", str(args.retry_delay),
                "--send-interval-ms", str(args.send_interval_ms),
                "--count", str(args.stress_count),
                "--summary-only",
                "--hex-preview-chars", str(args.hex_preview_chars),
                "--payload-hex", payload_hex,
            ]
            if run_case(sender, case_args) != 0:
                failures += 1

    if failures != 0:
        print(f"REGRESSION_FAILED cases={failures}")
        return 1

    print("REGRESSION_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
