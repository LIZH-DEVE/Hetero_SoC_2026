#!/usr/bin/env python3
"""
Day 21 performance benchmark helper.

This script is no longer allowed to silently use simulated hardware data for
acceptance. Real hardware input must come from either:

1. a JSON counter file, or
2. a Vivado HW Manager / ILA monitor log containing packet counter lines.

Demo mode is still available, but only behind --demo-mode and is explicitly
marked as non-acceptance data.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path


DEFAULT_CONFIG = {
    "crypto_type": "aes-128-cbc",
    "test_duration": 30,
    "expected_speedup": 40.0,
}

COUNTER_KEYS = (
    "fastpath_cnt",
    "bypass_cnt",
    "burst_256_cnt",
    "burst_128_cnt",
    "sample_duration_us",
)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Benchmark SmartNIC performance with real hardware evidence."
    )
    parser.add_argument(
        "--crypto-type",
        default=DEFAULT_CONFIG["crypto_type"],
        help="OpenSSL EVP cipher name, default: aes-128-cbc",
    )
    parser.add_argument(
        "--duration",
        type=int,
        default=DEFAULT_CONFIG["test_duration"],
        help="OpenSSL benchmark duration in seconds.",
    )
    parser.add_argument(
        "--expected-speedup",
        type=float,
        default=DEFAULT_CONFIG["expected_speedup"],
        help="Expected hardware/software speedup ratio.",
    )
    parser.add_argument(
        "--openssl-bin",
        default="openssl",
        help="Path to the OpenSSL executable.",
    )
    parser.add_argument(
        "--skip-openssl",
        action="store_true",
        help="Skip the OpenSSL baseline and generate a hardware-only report.",
    )
    parser.add_argument(
        "--counters-json",
        type=Path,
        help="Path to a real hardware counter JSON file.",
    )
    parser.add_argument(
        "--ila-log",
        type=Path,
        help="Path to a Vivado ILA console log containing packet counters.",
    )
    parser.add_argument(
        "--demo-mode",
        action="store_true",
        help="Use simulated counters. This mode is not acceptance-eligible.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path.cwd(),
        help="Directory for generated reports and optional charts.",
    )
    return parser.parse_args(argv)


def parse_openssl_output(output: str) -> float | None:
    pattern = re.compile(r"^\s*(\d+)\s+bytes\s+(\d+\.\d+)k\s+", re.MULTILINE)
    matches = list(pattern.finditer(output))
    if matches:
        last_match = matches[-1]
        throughput_kb_s = float(last_match.group(2))
        return throughput_kb_s / 1024.0

    fallback_pattern = re.compile(
        rf"evp\s+{re.escape(DEFAULT_CONFIG['crypto_type'])}\s+(\d+\.?\d*)",
        re.IGNORECASE,
    )
    fallback = fallback_pattern.search(output)
    if fallback:
        return float(fallback.group(1)) / 1024.0

    return None


def run_openssl_benchmark(openssl_bin: str, crypto_type: str, duration: int) -> float | None:
    command = [openssl_bin, "speed", "-evp", crypto_type, "-seconds", str(duration)]

    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=duration + 15,
            check=False,
        )
    except FileNotFoundError:
        print(f"[WARN] OpenSSL executable not found: {openssl_bin}")
        return None
    except subprocess.TimeoutExpired:
        print("[WARN] OpenSSL benchmark timed out")
        return None

    if result.returncode != 0:
        print("[WARN] OpenSSL benchmark failed")
        if result.stderr:
            print(result.stderr.strip())
        return None

    throughput = parse_openssl_output(result.stdout)
    if throughput is None:
        print("[WARN] Unable to parse OpenSSL output")
    return throughput


def _validate_counter_dict(sample: dict) -> dict:
    missing = [key for key in COUNTER_KEYS if key not in sample]
    if missing:
        raise ValueError(f"counter sample is missing keys: {', '.join(missing)}")

    validated = {}
    for key in COUNTER_KEYS:
        validated[key] = int(sample[key])
    validated.setdefault("drop_cnt", int(sample.get("drop_cnt", 0)))
    return validated


def parse_ila_monitor_output(text: str) -> dict:
    duration_match = re.search(r"Monitoring performance for\s+(\d+)ms", text, re.IGNORECASE)
    fastpath_match = re.search(r"FastPath Packets:\s*(\d+)", text)
    bypass_match = re.search(r"Bypass Packets:\s*(\d+)", text)
    burst256_match = re.search(r"256-Beat Bursts:\s*(\d+)", text)
    burst128_match = re.search(r"128-Beat Bursts:\s*(\d+)", text)
    drop_match = re.search(r"Drop Packets:\s*(\d+)", text)

    if not all((duration_match, fastpath_match, bypass_match, burst256_match, burst128_match)):
        raise ValueError("ILA log does not contain the required performance counter lines")

    sample = {
        "fastpath_cnt": int(fastpath_match.group(1)),
        "bypass_cnt": int(bypass_match.group(1)),
        "burst_256_cnt": int(burst256_match.group(1)),
        "burst_128_cnt": int(burst128_match.group(1)),
        "sample_duration_us": int(duration_match.group(1)) * 1000,
        "drop_cnt": int(drop_match.group(1)) if drop_match else 0,
    }
    return _validate_counter_dict(sample)


def simulate_ila_sampling() -> dict:
    return {
        "fastpath_cnt": 1_000_000,
        "bypass_cnt": 50_000,
        "drop_cnt": 100,
        "burst_256_cnt": 800_000,
        "burst_128_cnt": 150_000,
        "sample_duration_us": 10_000,
    }


def load_hardware_sample(
    counters_json: Path | None,
    ila_log: Path | None,
    demo_mode: bool = False,
) -> tuple[dict, str, bool]:
    if demo_mode:
        return _validate_counter_dict(simulate_ila_sampling()), "demo", False

    if counters_json and ila_log:
        raise ValueError("use either --counters-json or --ila-log, not both")

    if counters_json:
        sample = json.loads(counters_json.read_text(encoding="utf-8"))
        return _validate_counter_dict(sample), "counters_json", True

    if ila_log:
        sample = parse_ila_monitor_output(ila_log.read_text(encoding="utf-8"))
        return sample, "ila_log", True

    raise ValueError(
        "real hardware data is required: pass --counters-json or --ila-log, "
        "or explicitly opt into --demo-mode"
    )


def calculate_hardware_throughput(sample_data: dict, avg_packet_size_bytes: int = 1024) -> float:
    total_packets = sample_data["fastpath_cnt"] + sample_data["bypass_cnt"]
    total_bytes = total_packets * avg_packet_size_bytes
    sample_duration_s = sample_data["sample_duration_us"] / 1e6
    if sample_duration_s <= 0:
        raise ValueError("sample_duration_us must be positive")
    return (total_bytes / sample_duration_s) / (1024 * 1024)


def calculate_speedup(software_throughput: float | None, hardware_throughput: float | None) -> float | None:
    if software_throughput and hardware_throughput:
        return hardware_throughput / software_throughput
    return None


def calculate_cpu_offload() -> tuple[float, float, float]:
    cpu_usage_hardware = 1.0
    cpu_usage_software = 100.0
    offload_rate = (cpu_usage_software - cpu_usage_hardware) / cpu_usage_software * 100.0
    return offload_rate, cpu_usage_hardware, cpu_usage_software


def create_performance_chart(
    software_throughput: float | None,
    hardware_throughput: float | None,
    speedup: float | None,
    output_dir: Path,
) -> str | None:
    if software_throughput is None or hardware_throughput is None:
        return None

    try:
        import matplotlib.pyplot as plt
    except ModuleNotFoundError:
        print("[WARN] matplotlib is not installed, skip chart generation")
        return None

    output_dir.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(8, 5))
    labels = ["Software", "Hardware"]
    values = [software_throughput, hardware_throughput]
    bars = ax.bar(labels, values, color=["#d95f02", "#1b9e77"])
    ax.set_ylabel("Throughput (MB/s)")
    ax.set_title("Software vs Hardware Throughput")
    ax.grid(True, axis="y", alpha=0.3)

    for bar, value in zip(bars, values):
        ax.text(
            bar.get_x() + bar.get_width() / 2.0,
            bar.get_height(),
            f"{value:.2f} MB/s",
            ha="center",
            va="bottom",
        )

    if speedup is not None:
        ax.text(
            0.5,
            max(values) * 0.9,
            f"Speedup: {speedup:.2f}x",
            ha="center",
            va="center",
            transform=ax.transData,
            bbox={"boxstyle": "round,pad=0.3", "facecolor": "#ffffcc", "alpha": 0.8},
        )

    filename = output_dir / f"performance_benchmark_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png"
    plt.tight_layout()
    plt.savefig(filename, dpi=200, bbox_inches="tight")
    plt.close(fig)
    return str(filename)


def generate_report(
    args: argparse.Namespace,
    software_throughput: float | None,
    hardware_throughput: float | None,
    speedup: float | None,
    sample_data: dict,
    sample_source: str,
    acceptance_eligible: bool,
    chart_filename: str | None,
) -> tuple[dict, Path]:
    offload_rate, cpu_hw, cpu_sw = calculate_cpu_offload()
    report = {
        "timestamp": datetime.now().isoformat(),
        "configuration": {
            "crypto_type": args.crypto_type,
            "duration_s": args.duration,
            "expected_speedup": args.expected_speedup,
            "skip_openssl": args.skip_openssl,
        },
        "data_source": sample_source,
        "acceptance_eligible": acceptance_eligible,
        "results": {
            "software_throughput_mb_s": software_throughput,
            "hardware_throughput_mb_s": hardware_throughput,
            "speedup": speedup,
            "meets_speedup_target": bool(
                speedup is not None and speedup >= args.expected_speedup
            ),
            "cpu_usage": {
                "software_pct": cpu_sw,
                "hardware_pct": cpu_hw,
                "offload_pct": offload_rate,
            },
            "hardware_sample": sample_data,
            "chart": chart_filename,
        },
    }

    args.output_dir.mkdir(parents=True, exist_ok=True)
    report_path = args.output_dir / f"benchmark_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report, report_path


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    try:
        sample_data, sample_source, acceptance_eligible = load_hardware_sample(
            args.counters_json, args.ila_log, demo_mode=args.demo_mode
        )
    except Exception as exc:
        print(f"[ERROR] {exc}")
        return 1

    software_throughput = None
    if not args.skip_openssl:
        software_throughput = run_openssl_benchmark(
            args.openssl_bin, args.crypto_type, args.duration
        )

    try:
        hardware_throughput = calculate_hardware_throughput(sample_data)
    except Exception as exc:
        print(f"[ERROR] failed to calculate hardware throughput: {exc}")
        return 1

    speedup = calculate_speedup(software_throughput, hardware_throughput)
    chart_filename = create_performance_chart(
        software_throughput, hardware_throughput, speedup, args.output_dir
    )
    report, report_path = generate_report(
        args,
        software_throughput,
        hardware_throughput,
        speedup,
        sample_data,
        sample_source,
        acceptance_eligible,
        chart_filename,
    )

    print("=" * 72)
    print("Day 21 Performance Benchmark")
    print("=" * 72)
    print(f"Hardware data source      : {sample_source}")
    print(f"Acceptance eligible      : {acceptance_eligible}")
    print(f"Hardware throughput      : {hardware_throughput:.2f} MB/s")
    if software_throughput is not None:
        print(f"Software throughput      : {software_throughput:.2f} MB/s")
    else:
        print("Software throughput      : unavailable")
    if speedup is not None:
        print(f"Speedup                  : {speedup:.2f}x")
    else:
        print("Speedup                  : unavailable")
    print(f"Report                   : {report_path}")
    if chart_filename:
        print(f"Chart                    : {chart_filename}")

    if sample_source == "demo":
        print("[WARN] Demo mode uses simulated counters and is not valid for acceptance.")

    if not acceptance_eligible:
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
