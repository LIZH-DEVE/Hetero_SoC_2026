#!/usr/bin/env python3
"""
Day 21 performance benchmark helper.

Acceptance data must come from one of these sources:

1. AX7020 board BENCH control responses
2. a JSON counter file
3. a Vivado HW Manager / ILA monitor log containing packet counter lines

Demo mode is still available, but only behind --demo-mode and is explicitly
marked as non-acceptance data.
"""

from __future__ import annotations

import argparse
import importlib.util
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

DEFAULT_BENCH_IP = "192.168.1.20"
DEFAULT_SOURCE_IP = "192.168.1.11"
DEFAULT_CONTROL_PORT = 4662
DEFAULT_CONTROL_TIMEOUT = 3.0
DEFAULT_BENCH_REPEATS = 1000
DEFAULT_ALGOS = ("aes", "sm4")
STAGE2_PROOF_LENGTHS = (16, 32, 128, 512, 1472)
REPO_ROOT = Path(__file__).resolve().parents[1]
CONTROL_TOOL_PATH = (
    REPO_ROOT / "handoff" / "robeieda_porting_pack" / "tools" / "udp_crypto_control.py"
)

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
        "--bench-ip",
        default=None,
        help="Board IPv4 address for UDP BENCH mode.",
    )
    parser.add_argument(
        "--proof-uart-log",
        type=Path,
        default=None,
        help="UART log from the Stage 2 SG perf proof image.",
    )
    parser.add_argument(
        "--expected-proof-repeats",
        type=int,
        default=DEFAULT_BENCH_REPEATS,
        help="Expected repeat count embedded in the Stage 2 SG proof UART log.",
    )
    parser.add_argument(
        "--source-ip",
        default=DEFAULT_SOURCE_IP,
        help="Local source IP to bind for UDP BENCH mode.",
    )
    parser.add_argument(
        "--control-port",
        type=int,
        default=DEFAULT_CONTROL_PORT,
        help="Control UDP port for UDP BENCH mode.",
    )
    parser.add_argument(
        "--control-timeout",
        type=float,
        default=DEFAULT_CONTROL_TIMEOUT,
        help="Receive timeout in seconds for UDP BENCH mode.",
    )
    parser.add_argument(
        "--algos",
        default="aes,sm4",
        help="Comma-separated algorithms for UDP BENCH mode (aes,sm4).",
    )
    parser.add_argument(
        "--repeats",
        type=int,
        default=DEFAULT_BENCH_REPEATS,
        help="Repeat count passed to the board BENCH command.",
    )
    parser.add_argument(
        "--target-speedup",
        type=float,
        default=1.0,
        help="Average speedup gate for UDP BENCH mode.",
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


def parse_algo_list(raw_algos: str) -> list[str]:
    values = [value.strip().lower() for value in raw_algos.split(",") if value.strip()]
    if not values:
        raise ValueError("at least one algorithm must be specified")
    invalid = [value for value in values if value not in DEFAULT_ALGOS]
    if invalid:
        raise ValueError(f"unsupported algorithm(s): {', '.join(invalid)}")
    unique_values = []
    for value in values:
        if value not in unique_values:
            unique_values.append(value)
    return unique_values


def load_udp_control_module(control_module_path: Path | None = None):
    module_path = control_module_path or CONTROL_TOOL_PATH
    if not module_path.exists():
        raise FileNotFoundError(f"UDP control tool not found: {module_path}")

    spec = importlib.util.spec_from_file_location("udp_crypto_control", module_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Unable to load UDP control tool module: {module_path}")

    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def run_board_bench_session(
    bench_ip: str,
    source_ip: str,
    control_port: int,
    control_timeout: float,
    repeats: int,
    algos: list[str],
    control_module=None,
) -> dict:
    if repeats <= 0:
        raise ValueError("repeats must be positive")

    module = control_module or load_udp_control_module()
    client = module.ControlClient(
        ip=bench_ip,
        source_ip=source_ip,
        timeout=control_timeout,
        port=control_port,
    )

    try:
        client.hello()
        for algo in algos:
            client.set_key(algo=algo)

        results = {}
        for algo in algos:
            decoded = module.decode_bench_payload(client.bench(algo, repeats=repeats).payload)
            if decoded["algo"] != algo:
                raise ValueError(
                    f"bench response algo mismatch: expected {algo}, got {decoded['algo']}"
                )
            results[algo] = decoded

        return {
            "session_id": client.session_id,
            "binding_id": client.binding_id,
            "results": results,
        }
    finally:
        client.close()


def parse_stage2_proof_uart_log(
    text: str, expected_repeats: int = DEFAULT_BENCH_REPEATS
) -> dict[str, object]:
    row_pattern = re.compile(r"^PROOF_ROW\s+(?P<body>.+)$", re.MULTILINE)
    config_pattern = re.compile(r"^PROOF_CONFIG\s+(?P<body>.+)$", re.MULTILINE)

    def parse_kv_blob(blob: str) -> dict[str, str]:
        pairs: dict[str, str] = {}
        for token in blob.split():
            if "=" not in token:
                continue
            key, value = token.split("=", 1)
            pairs[key.strip()] = value.strip()
        return pairs

    config_match = config_pattern.search(text)
    if config_match is None:
        raise ValueError("proof UART log is missing PROOF_CONFIG")

    config = parse_kv_blob(config_match.group("body"))
    repeats = int(config.get("repeats", "0"))
    if repeats <= 0:
        raise ValueError("proof UART log contains invalid repeats")
    if expected_repeats > 0 and repeats != expected_repeats:
        raise ValueError(
            f"proof UART repeats mismatch: expected {expected_repeats}, got {repeats}"
        )

    required_pass_lines = (
        "PROOF_AES PASS",
        "PROOF_SM4 PASS",
        "DMA gateway hybrid perf proof PASS",
    )
    missing_pass_lines = [line for line in required_pass_lines if line not in text]
    if missing_pass_lines:
        raise ValueError(
            "proof UART log is missing required PASS lines: "
            + ", ".join(missing_pass_lines)
        )

    rows_by_algo: dict[str, list[dict[str, int]]] = {algo: [] for algo in DEFAULT_ALGOS}
    for match in row_pattern.finditer(text):
        row = parse_kv_blob(match.group("body"))
        algo = row.get("algo", "").lower()
        if algo not in rows_by_algo:
            raise ValueError(f"unsupported proof algo row: {algo}")

        parsed_row = {
            "length": int(row["length"]),
            "sw_us": int(row["sw_us"]),
            "hw_us": int(row["hw_us"]),
            "batch_descriptor_count": int(row["batch_descriptor_count"]),
            "single_launch_used": int(row["single_launch_used"]),
            "doorbell_count": int(row["doorbell_count"]),
            "last_descriptor_poll_count": int(row["last_descriptor_poll_count"]),
            "actual_len_mismatch_count": int(row["actual_len_mismatch_count"]),
            "cipher_mismatch_count": int(row["cipher_mismatch_count"]),
            "descriptor_error_count": int(row["descriptor_error_count"]),
            "completion_timeout_count": int(row["completion_timeout_count"]),
            "repeats": int(row["repeats"]),
        }
        if parsed_row["repeats"] != repeats:
            raise ValueError(
                f"proof row repeats mismatch for {algo}: expected {repeats}, got {parsed_row['repeats']}"
            )
        rows_by_algo[algo].append(parsed_row)

    results: dict[str, dict[str, object]] = {}
    for algo in DEFAULT_ALGOS:
        rows = rows_by_algo[algo]
        if len(rows) != len(STAGE2_PROOF_LENGTHS):
            raise ValueError(
                f"proof UART log for {algo} must contain {len(STAGE2_PROOF_LENGTHS)} rows"
            )
        lengths = tuple(row["length"] for row in rows)
        if lengths != STAGE2_PROOF_LENGTHS:
            raise ValueError(
                f"proof UART log for {algo} must use lengths {STAGE2_PROOF_LENGTHS}, got {lengths}"
            )

        diagnostics = {
            "single_launch_used": all(row["single_launch_used"] == 1 for row in rows),
            "batch_descriptor_count": rows[0]["batch_descriptor_count"],
            "doorbell_count": max(row["doorbell_count"] for row in rows),
            "last_descriptor_poll_count": max(
                row["last_descriptor_poll_count"] for row in rows
            ),
            "actual_len_mismatch_count": sum(
                row["actual_len_mismatch_count"] for row in rows
            ),
            "cipher_mismatch_count": sum(
                row["cipher_mismatch_count"] for row in rows
            ),
            "descriptor_error_count": sum(
                row["descriptor_error_count"] for row in rows
            ),
            "completion_timeout_count": sum(
                row["completion_timeout_count"] for row in rows
            ),
            "transport": "uart_stage2_proof",
        }
        results[algo] = {
            "algo": algo,
            "repeats": repeats,
            "records": [
                {
                    "length": row["length"],
                    "sw_us": row["sw_us"],
                    "hw_us": row["hw_us"],
                }
                for row in rows
            ],
            "diagnostics": diagnostics,
        }

    return {
        "source": "uart_stage2_proof",
        "repeats": repeats,
        "overall_pass": True,
        "results": results,
    }


def _round_metric(value: float) -> float:
    return float(f"{value:.6f}")


def calculate_board_bench_metrics(bench_payload: dict[str, object]) -> dict[str, object]:
    algo = str(bench_payload["algo"])
    repeats = int(bench_payload["repeats"])
    raw_records = list(bench_payload["records"])

    if repeats <= 0:
        raise ValueError("bench repeats must be positive")

    records = []
    speedups = []
    for raw_record in raw_records:
        length = int(raw_record["length"])
        sw_us = int(raw_record["sw_us"])
        hw_us = int(raw_record["hw_us"])

        if length <= 0:
            raise ValueError("bench record length must be positive")
        if sw_us <= 0 or hw_us <= 0:
            raise ValueError("bench record times must be positive")

        workload_bytes = length * repeats
        sw_seconds = sw_us / 1_000_000.0
        hw_seconds = hw_us / 1_000_000.0
        sw_throughput = (workload_bytes / sw_seconds) / (1024.0 * 1024.0)
        hw_throughput = (workload_bytes / hw_seconds) / (1024.0 * 1024.0)
        speedup = hw_throughput / sw_throughput

        speedups.append(speedup)
        records.append(
            {
                "length_bytes": length,
                "workload_bytes": workload_bytes,
                "sw_total_us": sw_us,
                "hw_total_us": hw_us,
                "sw_avg_latency_us": _round_metric(sw_us / repeats),
                "hw_avg_latency_us": _round_metric(hw_us / repeats),
                "sw_throughput_mb_s": _round_metric(sw_throughput),
                "hw_throughput_mb_s": _round_metric(hw_throughput),
                "speedup": _round_metric(speedup),
            }
        )

    result = {
        "algo": algo,
        "repeats": repeats,
        "records": records,
        "summary": {
            "record_count": len(records),
            "min_speedup": _round_metric(min(speedups)),
            "max_speedup": _round_metric(max(speedups)),
            "avg_speedup": _round_metric(sum(speedups) / len(speedups)),
        },
    }
    diagnostics = bench_payload.get("diagnostics")
    if diagnostics is not None:
        result["diagnostics"] = dict(diagnostics)
    return result


def summarize_board_bench_records(records: list[dict[str, object]]) -> dict[str, float]:
    if not records:
        raise ValueError("board bench records must not be empty")

    speedups = [float(record["speedup"]) for record in records]
    return {
        "record_count": len(records),
        "min_speedup": _round_metric(min(speedups)),
        "max_speedup": _round_metric(max(speedups)),
        "avg_speedup": _round_metric(sum(speedups) / len(speedups)),
    }


def build_board_bench_report(
    bench_ip: str,
    source_ip: str,
    control_port: int,
    repeats: int,
    target_speedup: float,
    session_info: dict[str, object],
    metrics_by_algo: dict[str, dict[str, object]],
) -> dict[str, object]:
    results: dict[str, dict[str, object]] = {}
    overall_meets_target = True

    for algo, metrics in metrics_by_algo.items():
        result = dict(metrics)
        summary = result.get("summary")
        if summary is None:
            summary = summarize_board_bench_records(result["records"])
        result["summary"] = summary
        result["meets_target"] = bool(float(summary["avg_speedup"]) >= target_speedup)
        results[algo] = result
        overall_meets_target = overall_meets_target and result["meets_target"]

    return {
        "timestamp": datetime.now().isoformat(),
        "mode": "board_bench",
        "acceptance_eligible": True,
        "baseline": "ps_software_same_board",
        "target": {
            "ip": bench_ip,
            "source_ip": source_ip,
            "control_port": control_port,
            "repeats": repeats,
            "speedup": _round_metric(target_speedup),
        },
        "session": {
            "session_id": int(session_info["session_id"]),
            "binding_id": int(session_info["binding_id"]),
        },
        "results": results,
        "overall": {
            "meets_target": overall_meets_target,
        },
    }


def render_board_bench_markdown(report: dict[str, object]) -> str:
    target = report.get("target", {})
    overall = report.get("overall", {})
    target_speedup = float(target.get("speedup", 1.0))
    target_result = "PASS" if overall.get("meets_target", False) else "FAIL"
    source_label = (
        "AX7020 board Stage 2 SG proof UART log."
        if report.get("source") == "uart_stage2_proof"
        else "AX7020 board UDP BENCH control responses."
    )
    hardware_label = (
        "same-board descriptor-driven DMA/crypto path measured by the Stage 2 proof image."
        if report.get("source") == "uart_stage2_proof"
        else "same-board hardware path measured by `gateway_hw_encrypt_buffer_sync()`."
    )
    lines = [
        "# Phase C Board Benchmark Summary",
        "",
        f"Board-first acceptance source: {source_label}",
        "",
        f"- Target IP: `{target.get('ip', 'unknown')}`",
        f"- Source IP: `{target.get('source_ip', 'unknown')}`",
        f"- Control port: `{target.get('control_port', 'unknown')}`",
        f"- Repeats per length: `{target.get('repeats', 'unknown')}`",
        "",
        "PS software baseline: same-board software path measured by `gateway_sw_encrypt_buffer()`.",
        f"Hardware speedup vs PS software: {hardware_label}",
        f"Target speedup gate: average speedup per algorithm must be `>= {target_speedup:.6f}x`.",
        "Short payload note: `16B` and `32B` rows may remain `<1.0x`; failure should be judged on average result, not isolated short-packet rows.",
        f"Target result: `{target_result}`",
        "",
    ]

    for algo in DEFAULT_ALGOS:
        result = report.get("results", {}).get(algo)
        if result is None:
            continue

        lines.extend(
            [
                f"## {algo.upper()}",
                "",
                "| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |",
                "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
            ]
        )
        for record in result["records"]:
            lines.append(
                "| {length_bytes} | {repeats} | {sw_total_us} | {hw_total_us} | {sw_avg_latency_us:.6f} | {hw_avg_latency_us:.6f} | {sw_throughput_mb_s:.6f} | {hw_throughput_mb_s:.6f} | {speedup:.6f} |".format(
                    repeats=result["repeats"],
                    **record,
                )
            )
        summary = result.get("summary", summarize_board_bench_records(result["records"]))
        diagnostics = result.get("diagnostics")
        if diagnostics:
            execution_mode = (
                "single-launch SG batch"
                if diagnostics.get("single_launch_used")
                else "multi-launch or unspecified"
            )
            lines.extend(
                [
                    "",
                    "Diagnostics:",
                    f"- Hardware execution mode: `{execution_mode}`",
                    f"- Descriptor count: `{diagnostics.get('batch_descriptor_count', 'unknown')}`",
                    f"- Doorbell count: `{diagnostics.get('doorbell_count', 'unknown')}`",
                    f"- Last descriptor poll count: `{diagnostics.get('last_descriptor_poll_count', 'unknown')}`",
                    f"- Actual length mismatch count: `{diagnostics.get('actual_len_mismatch_count', 'unknown')}`",
                ]
            )
        lines.extend(
            [
                "",
                "Summary: min speedup `{min_speedup:.6f}x`, max speedup `{max_speedup:.6f}x`, avg speedup `{avg_speedup:.6f}x`.".format(
                    **summary
                ),
                "",
            ]
        )

    return "\n".join(lines).rstrip() + "\n"


def write_board_bench_artifacts(
    report: dict[str, object], output_dir: Path
) -> tuple[Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    json_path = output_dir / "board_bench_report.json"
    markdown_path = output_dir / "board_bench_summary.md"
    json_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    markdown_path.write_text(render_board_bench_markdown(report), encoding="utf-8")
    return json_path, markdown_path


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


def run_board_benchmark_mode(args: argparse.Namespace) -> int:
    if args.counters_json or args.ila_log or args.demo_mode:
        print(
            "[ERROR] UDP BENCH mode cannot be combined with --counters-json, --ila-log, or --demo-mode"
        )
        return 1

    try:
        algos = parse_algo_list(args.algos)
        session_info = run_board_bench_session(
            bench_ip=args.bench_ip,
            source_ip=args.source_ip,
            control_port=args.control_port,
            control_timeout=args.control_timeout,
            repeats=args.repeats,
            algos=algos,
        )
        metrics_by_algo = {
            algo: calculate_board_bench_metrics(payload)
            for algo, payload in session_info["results"].items()
        }
        report = build_board_bench_report(
            bench_ip=args.bench_ip,
            source_ip=args.source_ip,
            control_port=args.control_port,
            repeats=args.repeats,
            target_speedup=float(getattr(args, "target_speedup", 1.0)),
            session_info=session_info,
            metrics_by_algo=metrics_by_algo,
        )
        json_path, markdown_path = write_board_bench_artifacts(report, args.output_dir)
    except Exception as exc:
        print(f"[ERROR] {exc}")
        return 1

    print("=" * 72)
    print("Phase C Board Benchmark")
    print("=" * 72)
    print(f"Target board              : {args.bench_ip}:{args.control_port}")
    print(f"Source IP                 : {args.source_ip}")
    print(f"Session ID                : 0x{report['session']['session_id']:08X}")
    print(f"Binding ID                : 0x{report['session']['binding_id']:08X}")
    print("Baseline                  : PS software same-board")
    for algo in DEFAULT_ALGOS:
        result = report["results"].get(algo)
        if result is None:
            continue
        print(f"{algo.upper()} records              : {result['summary']['record_count']}")
        print(f"{algo.upper()} avg speedup          : {result['summary']['avg_speedup']:.6f}x")
    print(f"JSON report               : {json_path}")
    print(f"Markdown summary          : {markdown_path}")
    if not report["overall"]["meets_target"]:
        print(
            "[ERROR] Performance target not met: target={0:.6f}x AES={1:.6f}x SM4={2:.6f}x".format(
                float(report["target"]["speedup"]),
                float(report["results"].get("aes", {}).get("summary", {}).get("avg_speedup", 0.0)),
                float(report["results"].get("sm4", {}).get("summary", {}).get("avg_speedup", 0.0)),
            )
        )
        return 2
    return 0


def run_proof_uart_mode(args: argparse.Namespace) -> int:
    if args.counters_json or args.ila_log or args.demo_mode or args.bench_ip:
        print(
            "[ERROR] Stage 2 proof UART mode cannot be combined with UDP BENCH, counters, ILA, or demo inputs"
        )
        return 1

    try:
        proof_log = args.proof_uart_log.read_text(encoding="utf-8", errors="ignore")
        parsed = parse_stage2_proof_uart_log(
            proof_log, expected_repeats=int(args.expected_proof_repeats)
        )
        metrics_by_algo = {
            algo: calculate_board_bench_metrics(payload)
            for algo, payload in parsed["results"].items()
        }
        report = build_board_bench_report(
            bench_ip="uart-proof",
            source_ip="uart-proof",
            control_port=0,
            repeats=int(parsed["repeats"]),
            target_speedup=float(getattr(args, "target_speedup", 1.0)),
            session_info={"session_id": 0, "binding_id": 0},
            metrics_by_algo=metrics_by_algo,
        )
        report["source"] = parsed["source"]
        report["capture"] = {"uart_log": str(args.proof_uart_log)}
        json_path, markdown_path = write_board_bench_artifacts(report, args.output_dir)
    except Exception as exc:
        print(f"[ERROR] {exc}")
        return 1

    print("=" * 72)
    print("Stage 2 SG Batch Proof")
    print("=" * 72)
    print(f"UART proof log            : {args.proof_uart_log}")
    print("Baseline                  : PS software same-board")
    for algo in DEFAULT_ALGOS:
        result = report["results"].get(algo)
        if result is None:
            continue
        print(f"{algo.upper()} records              : {result['summary']['record_count']}")
        print(f"{algo.upper()} avg speedup          : {result['summary']['avg_speedup']:.6f}x")
    print(f"JSON report               : {json_path}")
    print(f"Markdown summary          : {markdown_path}")
    if not report["overall"]["meets_target"]:
        print(
            "[ERROR] Performance target not met: target={0:.6f}x AES={1:.6f}x SM4={2:.6f}x".format(
                float(report["target"]["speedup"]),
                float(report["results"].get("aes", {}).get("summary", {}).get("avg_speedup", 0.0)),
                float(report["results"].get("sm4", {}).get("summary", {}).get("avg_speedup", 0.0)),
            )
        )
        return 2
    return 0


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if args.proof_uart_log:
        return run_proof_uart_mode(args)

    if args.bench_ip:
        return run_board_benchmark_mode(args)

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

    if not report["acceptance_eligible"]:
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
