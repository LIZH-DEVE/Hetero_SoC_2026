#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import gc
import importlib.util
import json
import math
import socket
import sys
import time
from datetime import datetime
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BOARD_BENCH_MODULE_PATH = REPO_ROOT / "scripts" / "day21_performance_benchmark.py"
PRIMARY_CONTROL_TOOL_PATH = (
    REPO_ROOT / "HCS_SOC" / "udp_crypto_control.py"
)
FALLBACK_CONTROL_TOOL_PATH = (
    REPO_ROOT / "handoff" / "robeieda_porting_pack" / "tools" / "udp_crypto_control.py"
)
SEND_TOOL_PATH = (
    REPO_ROOT / "HCS_SOC" / "send_udp_crypto_test.py"
)
FALLBACK_SEND_TOOL_PATH = (
    REPO_ROOT / "handoff" / "robeieda_porting_pack" / "tools" / "send_udp_crypto_test.py"
)

DEFAULT_TARGET_IP = "192.168.1.20"
DEFAULT_SOURCE_IP = "192.168.1.11"
DEFAULT_CONTROL_PORT = 4662
DEFAULT_TIMEOUT = 5.0
DEFAULT_REQUESTS_PER_SCENARIO = 200
DEFAULT_BENCH_REPEATS = 1000
DEFAULT_WARMUP_PER_ALGO = 4

LOAD_MODES = ("aes_only", "sm4_only", "mixed_alt_50_50")
PAYLOAD_LENGTHS = (64, 512, 1472)
ACL_MODES = ("acl_off", "acl_on_nonmatching")

UDP_PROTOCOL = 17
ACL_NONMATCH_SRC_PORT = 54060
AES_LOCAL_PORT = 55160
SM4_LOCAL_PORT = 55161

REPORT_JSON_NAME = "bench_matrix_report.json"
REPORT_MARKDOWN_NAME = "bench_matrix_summary.md"
REPORT_CSV_NAME = "bench_matrix_results.csv"


def _load_module(module_name: str, module_path: Path):
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"unable to load module from {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def load_board_bench_module():
    return _load_module("day21_performance_benchmark", BOARD_BENCH_MODULE_PATH)


def load_control_module():
    candidates = (
        ("udp_crypto_control_matrix_primary", PRIMARY_CONTROL_TOOL_PATH),
        ("udp_crypto_control_matrix_fallback", FALLBACK_CONTROL_TOOL_PATH),
    )
    for module_name, module_path in candidates:
        if not module_path.exists():
            continue
        module = _load_module(module_name, module_path)
        client_type = getattr(module, "ControlClient", None)
        if client_type is not None and hasattr(client_type, "acl_clear") and hasattr(client_type, "acl_write"):
            return module
    raise ImportError(
        "unable to find ACL-capable udp_crypto_control.py in HCS_SOC or handoff tool paths"
    )


def load_send_tool_module():
    for module_path in (SEND_TOOL_PATH, FALLBACK_SEND_TOOL_PATH):
        if not module_path.exists():
            continue
        if str(module_path.parent) not in sys.path:
            sys.path.insert(0, str(module_path.parent))
        return _load_module("send_udp_crypto_test_matrix", module_path)
    raise ImportError(
        "unable to find send_udp_crypto_test.py in HCS_SOC or handoff tool paths"
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the Shadow Mirror host-side benchmark matrix."
    )
    parser.add_argument("--target-ip", default=DEFAULT_TARGET_IP)
    parser.add_argument("--source-ip", default=DEFAULT_SOURCE_IP)
    parser.add_argument("--control-port", type=int, default=DEFAULT_CONTROL_PORT)
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    parser.add_argument("--requests-per-scenario", type=int, default=DEFAULT_REQUESTS_PER_SCENARIO)
    parser.add_argument("--repeats", type=int, default=DEFAULT_BENCH_REPEATS)
    parser.add_argument("--output-dir", type=Path, default=Path.cwd())
    return parser.parse_args(argv)


def _round_metric(value: float) -> float:
    return float(f"{value:.6f}")


def build_matrix_scenarios() -> list[dict[str, object]]:
    scenarios = []
    for load_mode in LOAD_MODES:
        for payload_len in PAYLOAD_LENGTHS:
            for acl_mode in ACL_MODES:
                scenarios.append(
                    {
                        "load_mode": load_mode,
                        "payload_len": payload_len,
                        "acl_mode": acl_mode,
                    }
                )
    return scenarios


def build_payload_bytes(send_tool_module, algo: str, payload_len: int) -> bytes:
    if payload_len <= 0 or (payload_len % 16) != 0:
        raise ValueError("payload_len must be positive and 16-byte aligned")
    if algo == "sm4":
        block = bytes.fromhex(send_tool_module.SM4_DEFAULT_PAYLOAD_HEX)
    else:
        block = bytes.fromhex(send_tool_module.AES_DEFAULT_PAYLOAD_HEX)
    return block * (payload_len // len(block))


def build_scenario_schedule(
    load_mode: str,
    payload_by_algo: dict[str, bytes],
    request_count: int,
) -> list[dict[str, object]]:
    if request_count <= 0:
        raise ValueError("request_count must be positive")
    if load_mode == "mixed_alt_50_50" and (request_count % 2) != 0:
        raise ValueError("mixed_alt_50_50 requires an even request_count")

    schedule: list[dict[str, object]] = []
    if load_mode == "aes_only":
        algo_sequence = ["aes"] * request_count
    elif load_mode == "sm4_only":
        algo_sequence = ["sm4"] * request_count
    elif load_mode == "mixed_alt_50_50":
        algo_sequence = ["aes" if index % 2 == 0 else "sm4" for index in range(request_count)]
    else:
        raise ValueError(f"unsupported load_mode: {load_mode}")

    for algo in algo_sequence:
        schedule.append({"algo": algo, "payload": payload_by_algo[algo]})
    return schedule


def build_warmup_schedule(
    load_mode: str,
    payload_by_algo: dict[str, bytes],
    warmup_per_algo: int = DEFAULT_WARMUP_PER_ALGO,
) -> list[dict[str, object]]:
    if warmup_per_algo <= 0:
        return []
    if load_mode == "mixed_alt_50_50":
        return build_scenario_schedule(load_mode, payload_by_algo, warmup_per_algo * 2)
    return build_scenario_schedule(load_mode, payload_by_algo, warmup_per_algo)


def percentile_us(latencies_ns: list[int], percentile: float) -> float:
    if not latencies_ns:
        return 0.0
    ordered = sorted(latencies_ns)
    rank = max(1, math.ceil((percentile / 100.0) * len(ordered)))
    return _round_metric(ordered[rank - 1] / 1000.0)


def summarize_scenario_metrics(
    scenario: dict[str, object],
    latencies_ns: list[int],
    per_algo_latencies_ns: dict[str, list[int]],
    request_count: int,
    success_count: int,
    timeout_count: int,
    mismatch_count: int,
    successful_bytes: int,
) -> dict[str, object]:
    total_elapsed_ns = sum(latencies_ns)
    throughput_mb_s = 0.0
    if total_elapsed_ns > 0 and successful_bytes > 0:
        throughput_mb_s = (successful_bytes / (total_elapsed_ns / 1_000_000_000.0)) / (1024.0 * 1024.0)

    result = {
        "load_mode": str(scenario["load_mode"]),
        "payload_len": int(scenario["payload_len"]),
        "acl_mode": str(scenario["acl_mode"]),
        "request_count": request_count,
        "success_count": success_count,
        "timeout_count": timeout_count,
        "mismatch_count": mismatch_count,
        "success_rate": _round_metric(success_count / request_count if request_count else 0.0),
        "avg_latency_us": _round_metric((sum(latencies_ns) / len(latencies_ns)) / 1000.0) if latencies_ns else 0.0,
        "p50_latency_us": percentile_us(latencies_ns, 50.0),
        "p95_latency_us": percentile_us(latencies_ns, 95.0),
        "throughput_mb_s": _round_metric(throughput_mb_s),
    }

    if str(scenario["load_mode"]) == "mixed_alt_50_50":
        result["aes_request_count"] = len(per_algo_latencies_ns["aes"])
        result["sm4_request_count"] = len(per_algo_latencies_ns["sm4"])
        result["aes_avg_latency_us"] = (
            _round_metric((sum(per_algo_latencies_ns["aes"]) / len(per_algo_latencies_ns["aes"])) / 1000.0)
            if per_algo_latencies_ns["aes"]
            else 0.0
        )
        result["sm4_avg_latency_us"] = (
            _round_metric((sum(per_algo_latencies_ns["sm4"]) / len(per_algo_latencies_ns["sm4"])) / 1000.0)
            if per_algo_latencies_ns["sm4"]
            else 0.0
        )
    return result


def compute_acl_deltas(matrix_results: list[dict[str, object]]) -> list[dict[str, object]]:
    pairs: dict[tuple[str, int], dict[str, dict[str, object]]] = {}
    for result in matrix_results:
        key = (str(result["load_mode"]), int(result["payload_len"]))
        pairs.setdefault(key, {})[str(result["acl_mode"])] = result

    deltas = []
    for (load_mode, payload_len), value in sorted(pairs.items()):
        acl_off = value.get("acl_off")
        acl_on = value.get("acl_on_nonmatching")
        if acl_off is None or acl_on is None:
            continue
        deltas.append(
            {
                "load_mode": load_mode,
                "payload_len": payload_len,
                "avg_latency_delta_us": _round_metric(
                    float(acl_on["avg_latency_us"]) - float(acl_off["avg_latency_us"])
                ),
                "throughput_delta_mb_s": _round_metric(
                    float(acl_on["throughput_mb_s"]) - float(acl_off["throughput_mb_s"])
                ),
            }
        )
    return deltas


def render_bench_matrix_markdown(report: dict[str, object]) -> str:
    lines = [
        "# Phase C Board Benchmark Matrix Summary",
        "",
        "## Baseline Snapshot",
        "",
        "Existing board BENCH baseline retained for same-board SW/HW speedup.",
        "",
    ]

    baseline_snapshot = report.get("baseline_snapshot", {})
    baseline_results = baseline_snapshot.get("results", {})
    if baseline_results:
        lines.extend(
            [
                "| Algo | Avg Speedup |",
                "|---|---:|",
            ]
        )
        for algo in ("aes", "sm4"):
            summary = baseline_results.get(algo, {}).get("summary")
            if summary is None:
                continue
            lines.append(f"| {algo.upper()} | {float(summary['avg_speedup']):.6f}x |")
        lines.append("")

    lines.extend(
        [
            "## Host Matrix",
            "",
            "| Load Mode | Payload Len (B) | ACL Mode | Requests | Success | Timeouts | Mismatches | Success Rate | Avg Latency (us) | P50 (us) | P95 (us) | Throughput (MB/s) |",
            "|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
        ]
    )
    for result in report.get("matrix_results", []):
        acl_mode_label = "ACL on (non-matching rule)" if result["acl_mode"] == "acl_on_nonmatching" else "ACL off"
        row = dict(result)
        row["acl_mode_label"] = acl_mode_label
        lines.append(
            "| {load_mode} | {payload_len} | {acl_mode_label} | {request_count} | {success_count} | {timeout_count} | {mismatch_count} | {success_rate:.6f} | {avg_latency_us:.6f} | {p50_latency_us:.6f} | {p95_latency_us:.6f} | {throughput_mb_s:.6f} |".format(
                **row,
            )
        )
    lines.append("")

    lines.extend(
        [
            "## ACL Delta",
            "",
            "| Load Mode | Payload Len (B) | Avg Latency Delta (us) | Throughput Delta (MB/s) |",
            "|---|---:|---:|---:|",
        ]
    )
    for item in report.get("acl_deltas", []):
        lines.append(
            "| {load_mode} | {payload_len} | {avg_latency_delta_us:.6f} | {throughput_delta_mb_s:.6f} |".format(
                **item
            )
        )
    lines.append("")
    return "\n".join(lines)


def write_bench_matrix_artifacts(
    report: dict[str, object],
    output_dir: Path,
) -> tuple[Path, Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    json_path = output_dir / REPORT_JSON_NAME
    markdown_path = output_dir / REPORT_MARKDOWN_NAME
    csv_path = output_dir / REPORT_CSV_NAME

    json_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    markdown_path.write_text(render_bench_matrix_markdown(report), encoding="utf-8")

    fieldnames = [
        "load_mode",
        "payload_len",
        "acl_mode",
        "request_count",
        "success_count",
        "timeout_count",
        "mismatch_count",
        "success_rate",
        "avg_latency_us",
        "p50_latency_us",
        "p95_latency_us",
        "throughput_mb_s",
        "aes_request_count",
        "sm4_request_count",
        "aes_avg_latency_us",
        "sm4_avg_latency_us",
    ]
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in report.get("matrix_results", []):
            writer.writerow(row)

    return json_path, markdown_path, csv_path


def create_bound_socket(source_ip: str, local_port: int, timeout: float) -> socket.socket:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    sock.bind((source_ip, local_port))
    return sock


def build_expected_payloads(
    send_tool_module,
    binding_id: int,
    shared_user_key: bytes,
) -> dict[int, dict[str, dict[str, object]]]:
    expected_by_length: dict[int, dict[str, dict[str, object]]] = {}
    for payload_len in PAYLOAD_LENGTHS:
        aes_payload = build_payload_bytes(send_tool_module, "aes", payload_len)
        sm4_payload = build_payload_bytes(send_tool_module, "sm4", payload_len)
        expected_by_length[payload_len] = {
            "aes": {
                "payload": aes_payload,
                "expected": send_tool_module.derive_binding_aware_expected(
                    "aes", aes_payload, binding_id, shared_user_key
                ),
                "dest_port": send_tool_module.AES_PORT,
                "local_port": AES_LOCAL_PORT,
            },
            "sm4": {
                "payload": sm4_payload,
                "expected": send_tool_module.derive_binding_aware_expected(
                    "sm4", sm4_payload, binding_id, shared_user_key
                ),
                "dest_port": send_tool_module.SM4_PORT,
                "local_port": SM4_LOCAL_PORT,
            },
        }
    return expected_by_length


def reply_matches_expectation(entry: dict[str, object], target_ip: str, addr, reply: bytes) -> bool:
    if addr[0] != target_ip or addr[1] != int(entry["dest_port"]):
        return False
    payload = bytes(entry["payload"])
    expected = entry.get("expected")
    if expected is not None and reply == expected:
        return True
    return len(reply) == len(payload) and reply != payload


def apply_acl_mode(control_client, scenario: dict[str, object], target_ip: str, source_ip: str, send_tool_module) -> None:
    control_client.acl_clear()
    if str(scenario["acl_mode"]) != "acl_on_nonmatching":
        return
    for dst_port in (send_tool_module.AES_PORT, send_tool_module.SM4_PORT):
        control_client.acl_write(
            src_ip=source_ip,
            src_port=ACL_NONMATCH_SRC_PORT,
            dst_ip=target_ip,
            dst_port=dst_port,
            protocol=UDP_PROTOCOL,
        )


def build_precomputed_schedule(
    scenario: dict[str, object],
    request_count: int,
    precomputed_by_length: dict[int, dict[str, dict[str, object]]],
) -> list[dict[str, object]]:
    payload_len = int(scenario["payload_len"])
    per_algo = precomputed_by_length[payload_len]
    schedule = []
    for item in build_scenario_schedule(
        str(scenario["load_mode"]),
        {"aes": per_algo["aes"]["payload"], "sm4": per_algo["sm4"]["payload"]},
        request_count,
    ):
        algo = str(item["algo"])
        schedule.append(
            {
                "algo": algo,
                "payload": per_algo[algo]["payload"],
                "expected": per_algo[algo]["expected"],
                "dest_port": per_algo[algo]["dest_port"],
                "local_port": per_algo[algo]["local_port"],
            }
        )
    return schedule


def build_precomputed_warmup(
    scenario: dict[str, object],
    precomputed_by_length: dict[int, dict[str, dict[str, object]]],
) -> list[dict[str, object]]:
    payload_len = int(scenario["payload_len"])
    per_algo = precomputed_by_length[payload_len]
    schedule = []
    for item in build_warmup_schedule(
        str(scenario["load_mode"]),
        {"aes": per_algo["aes"]["payload"], "sm4": per_algo["sm4"]["payload"]},
    ):
        algo = str(item["algo"])
        schedule.append(
            {
                "algo": algo,
                "payload": per_algo[algo]["payload"],
                "expected": per_algo[algo]["expected"],
                "dest_port": per_algo[algo]["dest_port"],
                "local_port": per_algo[algo]["local_port"],
            }
        )
    return schedule


def precompute_scenario_assets(
    scenarios: list[dict[str, object]],
    request_count: int,
    precomputed_by_length: dict[int, dict[str, dict[str, object]]],
) -> list[dict[str, object]]:
    assets = []
    for scenario in scenarios:
        assets.append(
            {
                "scenario": dict(scenario),
                "schedule": build_precomputed_schedule(scenario, request_count, precomputed_by_length),
                "warmup_schedule": build_precomputed_warmup(scenario, precomputed_by_length),
            }
        )
    return assets


def run_warmup_sequence(
    sock_by_algo: dict[str, socket.socket],
    target_ip: str,
    warmup_schedule: list[dict[str, object]],
    send_tool_module,
) -> None:
    for entry in warmup_schedule:
        sock = sock_by_algo[str(entry["algo"])]
        send_tool_module.drain_stale_replies(sock)
        sock.sendto(entry["payload"], (target_ip, int(entry["dest_port"])))
        reply, addr = sock.recvfrom(4096)
        if not reply_matches_expectation(entry, target_ip, addr, reply):
            raise RuntimeError("warmup reply mismatch")


def run_measured_sequence(
    sock_by_algo: dict[str, socket.socket],
    target_ip: str,
    schedule: list[dict[str, object]],
    send_tool_module,
) -> tuple[list[int], dict[str, list[int]], int, int, int, int]:
    latencies_ns: list[int] = []
    per_algo_latencies_ns = {"aes": [], "sm4": []}
    success_count = 0
    timeout_count = 0
    mismatch_count = 0
    successful_bytes = 0

    gc.collect()
    gc.disable()
    try:
        for entry in schedule:
            sock = sock_by_algo[str(entry["algo"])]
            start_ns = time.perf_counter_ns()
            try:
                sock.sendto(entry["payload"], (target_ip, int(entry["dest_port"])))
                reply, addr = sock.recvfrom(4096)
            except (socket.timeout, ConnectionResetError):
                timeout_count += 1
                break
            elapsed_ns = time.perf_counter_ns() - start_ns

            if not reply_matches_expectation(entry, target_ip, addr, reply):
                mismatch_count += 1
                break

            latencies_ns.append(elapsed_ns)
            per_algo_latencies_ns[str(entry["algo"])].append(elapsed_ns)
            success_count += 1
            successful_bytes += len(entry["payload"])
    finally:
        gc.enable()
        gc.collect()

    return latencies_ns, per_algo_latencies_ns, success_count, timeout_count, mismatch_count, successful_bytes


def run_matrix_scenario(
    scenario_asset: dict[str, object],
    control_client,
    target_ip: str,
    source_ip: str,
    timeout: float,
    send_tool_module,
) -> dict[str, object]:
    scenario = dict(scenario_asset["scenario"])
    schedule = list(scenario_asset["schedule"])
    warmup_schedule = list(scenario_asset["warmup_schedule"])
    apply_acl_mode(control_client, scenario, target_ip, source_ip, send_tool_module)

    sock_by_algo = {
        "aes": create_bound_socket(source_ip, AES_LOCAL_PORT, timeout),
        "sm4": create_bound_socket(source_ip, SM4_LOCAL_PORT, timeout),
    }
    try:
        for sock in sock_by_algo.values():
            send_tool_module.drain_stale_replies(sock)
        run_warmup_sequence(sock_by_algo, target_ip, warmup_schedule, send_tool_module)
        for sock in sock_by_algo.values():
            send_tool_module.drain_stale_replies(sock)

        latencies_ns, per_algo_latencies_ns, success_count, timeout_count, mismatch_count, successful_bytes = run_measured_sequence(
            sock_by_algo,
            target_ip,
            schedule,
            send_tool_module,
        )
    finally:
        for sock in sock_by_algo.values():
            sock.close()
        control_client.acl_clear()

    return summarize_scenario_metrics(
        scenario,
        latencies_ns,
        per_algo_latencies_ns,
        len(schedule),
        success_count,
        timeout_count,
        mismatch_count,
        successful_bytes,
    )


def capture_baseline_snapshot(args, bench_module) -> dict[str, object]:
    session_info = bench_module.run_board_bench_session(
        bench_ip=args.target_ip,
        source_ip=args.source_ip,
        control_port=args.control_port,
        control_timeout=args.timeout,
        repeats=args.repeats,
        algos=["aes", "sm4"],
    )
    metrics_by_algo = {
        algo: bench_module.calculate_board_bench_metrics(payload)
        for algo, payload in session_info["results"].items()
    }
    return bench_module.build_board_bench_report(
        bench_ip=args.target_ip,
        source_ip=args.source_ip,
        control_port=args.control_port,
        repeats=args.repeats,
        target_speedup=1.0,
        session_info={
            "session_id": int(session_info["session_id"]),
            "binding_id": int(session_info["binding_id"]),
        },
        metrics_by_algo=metrics_by_algo,
    )


def build_matrix_report(
    args: argparse.Namespace,
    baseline_snapshot: dict[str, object],
    matrix_results: list[dict[str, object]],
) -> dict[str, object]:
    return {
        "timestamp": datetime.now().isoformat(),
        "mode": "board_bench_matrix",
        "target": {
            "ip": args.target_ip,
            "source_ip": args.source_ip,
            "control_port": args.control_port,
            "requests_per_scenario": args.requests_per_scenario,
            "bench_repeats": args.repeats,
        },
        "baseline_snapshot": baseline_snapshot,
        "matrix_results": matrix_results,
        "acl_deltas": compute_acl_deltas(matrix_results),
    }


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if args.requests_per_scenario <= 0:
        print("[ERROR] requests-per-scenario must be positive")
        return 1
    if (args.requests_per_scenario % 2) != 0:
        print("[ERROR] requests-per-scenario must be even for mixed_alt_50_50")
        return 1
    if args.repeats <= 0:
        print("[ERROR] repeats must be positive")
        return 1

    bench_module = load_board_bench_module()
    control_module = load_control_module()
    send_tool_module = load_send_tool_module()
    shared_user_key = control_module.default_user_key("aes")

    try:
        baseline_snapshot = capture_baseline_snapshot(args, bench_module)
        control_client = control_module.ControlClient(
            ip=args.target_ip,
            source_ip=args.source_ip,
            timeout=args.timeout,
            port=args.control_port,
        )
        control_client.hello()
        control_client.set_key("aes", user_key=shared_user_key, dual_enable=True)
    except Exception as exc:
        print(f"[ERROR] failed to initialize benchmark matrix: {exc}")
        return 1

    try:
        precomputed_by_length = build_expected_payloads(
            send_tool_module,
            control_client.binding_id,
            shared_user_key,
        )
        scenario_assets = precompute_scenario_assets(
            scenarios=build_matrix_scenarios(),
            request_count=args.requests_per_scenario,
            precomputed_by_length=precomputed_by_length,
        )
        matrix_results = []
        for scenario_asset in scenario_assets:
            result = run_matrix_scenario(
                scenario_asset=scenario_asset,
                control_client=control_client,
                target_ip=args.target_ip,
                source_ip=args.source_ip,
                timeout=args.timeout,
                send_tool_module=send_tool_module,
            )
            matrix_results.append(result)
    except Exception as exc:
        print(f"[ERROR] benchmark matrix scenario failed: {exc}")
        return 1
    finally:
        control_client.close()

    report = build_matrix_report(args, baseline_snapshot, matrix_results)
    json_path, markdown_path, csv_path = write_bench_matrix_artifacts(report, args.output_dir)

    print("=" * 72)
    print("Phase C Board Benchmark Matrix")
    print("=" * 72)
    print(f"Target board              : {args.target_ip}:{args.control_port}")
    print(f"Source IP                 : {args.source_ip}")
    print(f"Requests per scenario     : {args.requests_per_scenario}")
    print(f"BENCH repeats             : {args.repeats}")
    print(f"JSON report               : {json_path}")
    print(f"Markdown summary          : {markdown_path}")
    print(f"CSV results               : {csv_path}")

    failed = [
        item
        for item in matrix_results
        if int(item["success_count"]) != int(item["request_count"])
    ]
    if failed:
        print("[ERROR] One or more benchmark matrix scenarios did not reach 100% success.")
        for item in failed:
            print(
                "[ERROR] {load_mode} len={payload_len} acl={acl_mode} success={success_count}/{request_count} timeout={timeout_count} mismatch={mismatch_count}".format(
                    **item
                )
            )
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
