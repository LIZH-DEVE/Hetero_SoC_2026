#!/usr/bin/env python3
import argparse
import datetime as dt
import subprocess
import sys
from pathlib import Path


def parse_acceptance_output(text: str) -> dict[str, object]:
    summary: dict[str, object] = {
        "overall": "UNKNOWN",
        "bench": {"aes": [], "sm4": []},
        "control_regression_pass": False,
        "stages": [],
    }
    current_case: str | None = None
    current_bench_algo: str | None = None

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line == "ACCEPTANCE_PASS":
            summary["overall"] = "PASS"
        elif line.startswith("ACCEPTANCE_FAILED"):
            summary["overall"] = "FAIL"
        elif line == "CONTROL_REGRESSION_PASS":
            summary["control_regression_pass"] = True
        elif line.startswith("=== ") and line.endswith(" ==="):
            current_case = line[4:-4]
            current_bench_algo = None
            summary["stages"].append(current_case)
        elif line.startswith("CASE bench "):
            current_bench_algo = line.split()[-1]
        elif line.startswith("algo=") and "repeats=" in line and current_case == "CONTROL_REGRESSION":
            parts = dict(item.split("=", 1) for item in line.split())
            current_bench_algo = parts.get("algo")
        elif line.startswith("len=") and "sw_us=" in line and "hw_us=" in line and current_bench_algo in ("aes", "sm4"):
            parts = dict(item.split("=", 1) for item in line.split())
            summary["bench"][current_bench_algo].append(
                {
                    "length": int(parts["len"]),
                    "sw_us": int(parts["sw_us"]),
                    "hw_us": int(parts["hw_us"]),
                    "speedup": round(int(parts["sw_us"]) / int(parts["hw_us"]), 2) if int(parts["hw_us"]) != 0 else 0.0,
                }
            )
    return summary


def render_markdown(summary: dict[str, object], command: list[str], raw_log_path: Path) -> str:
    timestamp = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    lines = [
        "# AX7020 UDP Crypto Acceptance Report",
        "",
        f"- Time: `{timestamp}`",
        f"- Command: `{' '.join(command)}`",
        f"- Overall: `{summary['overall']}`",
        f"- Control regression: `{'PASS' if summary['control_regression_pass'] else 'FAIL/UNKNOWN'}`",
        f"- Raw log: `{raw_log_path}`",
        "",
        "## Stages",
    ]
    for stage in summary["stages"]:
        lines.append(f"- `{stage}`")

    for algo in ("aes", "sm4"):
        records = summary["bench"][algo]
        lines.extend([
            "",
            f"## BENCH {algo.upper()}",
            "",
            "| Len | sw_us | hw_us | Speedup |",
            "| --- | ---: | ---: | ---: |",
        ])
        if records:
            for record in records:
                lines.append(
                    f"| {record['length']} | {record['sw_us']} | {record['hw_us']} | {record['speedup']:.2f}x |"
                )
        else:
            lines.append("| n/a | n/a | n/a | n/a |")

    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Run acceptance and emit a Markdown summary plus raw log.")
    parser.add_argument("--output-dir", default=None, help="Directory for generated report files")
    args, forwarded = parser.parse_known_args()

    root = Path(__file__).resolve().parent
    acceptance_script = root / "run_udp_crypto_acceptance.py"
    if not acceptance_script.exists():
        print(f"missing acceptance script: {acceptance_script}", file=sys.stderr)
        return 2

    output_dir = Path(args.output_dir) if args.output_dir else (root.parent / "logs" / "udp_crypto_acceptance")
    output_dir.mkdir(parents=True, exist_ok=True)

    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    raw_log_path = output_dir / f"acceptance_{timestamp}.log"
    report_path = output_dir / f"acceptance_{timestamp}.md"

    command = [sys.executable, str(acceptance_script), *forwarded]
    completed = subprocess.run(command, check=False, capture_output=True, text=True)
    combined_output = completed.stdout
    if completed.stderr:
        combined_output = combined_output + ("\n" if combined_output and not combined_output.endswith("\n") else "") + completed.stderr

    raw_log_path.write_text(combined_output, encoding="utf-8")
    summary = parse_acceptance_output(combined_output)
    report_path.write_text(render_markdown(summary, command, raw_log_path), encoding="utf-8")

    print(f"raw_log={raw_log_path}")
    print(f"report_md={report_path}")
    print(f"overall={summary['overall']}")
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
