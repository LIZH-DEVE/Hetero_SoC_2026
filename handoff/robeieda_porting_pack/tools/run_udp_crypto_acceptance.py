#!/usr/bin/env python3
import argparse
import datetime as dt
import subprocess
import sys
from pathlib import Path
from typing import Callable

from run_udp_crypto_acceptance_report import parse_acceptance_output, render_markdown


Runner = Callable[..., subprocess.CompletedProcess[str]]


def run_case(
    label: str,
    cmd: list[str],
    emit: Callable[[str], None] = print,
    runner: Runner | None = None,
) -> tuple[int, str]:
    active_runner = runner or subprocess.run
    emit(f"=== {label} ===")
    emit("$ " + " ".join(cmd))
    completed = active_runner(cmd, check=False, capture_output=True, text=True)
    combined = completed.stdout or ""
    if completed.stderr:
        combined += ("\n" if combined and not combined.endswith("\n") else "") + completed.stderr
    if combined:
        for line in combined.rstrip("\n").splitlines():
            emit(line)
    emit(f"exit_code={completed.returncode}")
    emit("")
    return completed.returncode, combined


def _write_reports(
    report_dir: Path,
    transcript: str,
    command: list[str],
) -> dict[str, Path]:
    report_dir.mkdir(parents=True, exist_ok=True)
    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    raw_log_path = report_dir / f"acceptance_{timestamp}.log"
    report_path = report_dir / f"acceptance_{timestamp}.md"
    raw_log_path.write_text(transcript, encoding="utf-8")
    summary = parse_acceptance_output(transcript)
    report_path.write_text(render_markdown(summary, command, raw_log_path), encoding="utf-8")
    return {"raw_log": raw_log_path, "report_md": report_path}


def _parse_key_value(output: str, name: str) -> int:
    prefix = f"{name}="
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if line.startswith(prefix):
            return int(line[len(prefix):], 0)
    raise ValueError(f"missing {name} in output")


def execute_acceptance(
    *,
    ip: str,
    source_ip: str,
    timeout: float,
    bench_timeout: float,
    length_timeout: float,
    retries: int,
    retry_delay: float,
    send_interval_ms: float,
    bench_repeats: int,
    hex_preview_chars: int,
    skip_ping: bool,
    host_python: str,
    report_dir: Path | None = None,
    runner: Runner | None = None,
    emit: Callable[[str], None] = print,
    command: list[str] | None = None,
) -> tuple[int, str, dict[str, Path]]:
    root = Path(__file__).resolve().parent
    control_script = root / "udp_crypto_control.py"
    sender_script = root / "send_udp_crypto_test.py"
    length_script = root / "run_udp_crypto_length_regression.py"
    control_regression_script = root / "run_udp_crypto_control_regression.py"

    transcript_lines: list[str] = []

    def emit_and_capture(line: str) -> None:
        transcript_lines.append(line)
        emit(line)

    for script in (control_script, sender_script, length_script, control_regression_script):
        if not script.exists():
            emit_and_capture(f"missing script: {script}")
            emit_and_capture("ACCEPTANCE_FAILED stage=SETUP exit_code=2")
            transcript = "\n".join(transcript_lines) + "\n"
            outputs = _write_reports(
                report_dir or (root.parent / "logs" / "udp_crypto_acceptance"),
                transcript,
                command or [host_python, str(Path(__file__).resolve())],
            )
            return 2, transcript, outputs

    def run_stage(stage_label: str, case_label: str, cmd: list[str]) -> tuple[bool, str]:
        rc, combined = run_case(case_label, cmd, emit=emit_and_capture, runner=runner)
        if rc != 0:
            emit_and_capture(f"ACCEPTANCE_FAILED stage={stage_label} exit_code={rc}")
            return False, combined
        return True, combined

    if not skip_ping:
        ok, _ = run_stage("PING", "PING", ["ping", ip, "-n", "4"])
        if not ok:
            transcript = "\n".join(transcript_lines) + "\n"
            outputs = _write_reports(
                report_dir or (root.parent / "logs" / "udp_crypto_acceptance"),
                transcript,
                command or [host_python, str(Path(__file__).resolve())],
            )
            return 1, transcript, outputs

    for algo in ("aes", "sm4"):
        ok, _ = run_stage(
            "ABSOLUTE_DENIAL",
            f"ABSOLUTE_DENIAL_{algo.upper()}",
            [
                host_python,
                str(sender_script),
                "--algo",
                algo,
                "--ip",
                ip,
                "--source-ip",
                source_ip,
                "--timeout",
                str(timeout),
                "--retries",
                str(retries),
                "--retry-delay",
                str(retry_delay),
                "--skip-control-session",
                "--expect-timeout",
            ],
        )
        if not ok:
            transcript = "\n".join(transcript_lines) + "\n"
            outputs = _write_reports(
                report_dir or (root.parent / "logs" / "udp_crypto_acceptance"),
                transcript,
                command or [host_python, str(Path(__file__).resolve())],
            )
            return 1, transcript, outputs

    ok, hello_output = run_stage(
        "HELLO_AND_SET_KEY",
        "HELLO",
        [
            host_python,
            str(control_script),
            "--ip",
            ip,
            "--source-ip",
            source_ip,
            "--timeout",
            str(timeout),
            "hello",
        ],
    )
    if not ok:
        transcript = "\n".join(transcript_lines) + "\n"
        outputs = _write_reports(
            report_dir or (root.parent / "logs" / "udp_crypto_acceptance"),
            transcript,
            command or [host_python, str(Path(__file__).resolve())],
        )
        return 1, transcript, outputs

    session_id = _parse_key_value(hello_output, "session_id")
    binding_id = _parse_key_value(hello_output, "binding_id")

    ok, _ = run_stage(
        "HELLO_AND_SET_KEY",
        "SET_KEY_DUAL",
        [
            host_python,
            str(control_script),
            "--ip",
            ip,
            "--source-ip",
            source_ip,
            "--timeout",
            str(timeout),
            "set-key",
            "--session-id",
            hex(session_id),
            "--binding-id",
            hex(binding_id),
            "--algo",
            "aes",
            "--dual-enable",
        ],
    )
    if not ok:
        transcript = "\n".join(transcript_lines) + "\n"
        outputs = _write_reports(
            report_dir or (root.parent / "logs" / "udp_crypto_acceptance"),
            transcript,
            command or [host_python, str(Path(__file__).resolve())],
        )
        return 1, transcript, outputs

    for algo in ("aes", "sm4"):
        ok, _ = run_stage(
            "SINGLE_BLOCK",
            f"SINGLE_BLOCK_{algo.upper()}",
            [
                host_python,
                str(sender_script),
                "--algo",
                algo,
                "--ip",
                ip,
                "--source-ip",
                source_ip,
                "--timeout",
                str(timeout),
            ],
        )
        if not ok:
            transcript = "\n".join(transcript_lines) + "\n"
            outputs = _write_reports(
                report_dir or (root.parent / "logs" / "udp_crypto_acceptance"),
                transcript,
                command or [host_python, str(Path(__file__).resolve())],
            )
            return 1, transcript, outputs

    for algo in ("aes", "sm4"):
        ok, _ = run_stage(
            "LENGTH_1472",
            f"LENGTH_1472_{algo.upper()}",
            [
                host_python,
                str(length_script),
                "--ip",
                ip,
                "--source-ip",
                source_ip,
                "--algo",
                algo,
                "--lengths",
                "1472",
                "--skip-invalid",
                "--skip-stress",
                "--timeout",
                str(length_timeout),
                "--retries",
                str(retries),
                "--retry-delay",
                str(retry_delay),
                "--send-interval-ms",
                str(send_interval_ms),
                "--hex-preview-chars",
                str(hex_preview_chars),
            ],
        )
        if not ok:
            transcript = "\n".join(transcript_lines) + "\n"
            outputs = _write_reports(
                report_dir or (root.parent / "logs" / "udp_crypto_acceptance"),
                transcript,
                command or [host_python, str(Path(__file__).resolve())],
            )
            return 1, transcript, outputs

    ok, _ = run_stage(
        "CONTROL_REGRESSION",
        "CONTROL_REGRESSION",
        [
            host_python,
            str(control_regression_script),
            "--ip",
            ip,
            "--source-ip",
            source_ip,
            "--timeout",
            str(timeout),
            "--bench-timeout",
            str(bench_timeout),
            "--bench-repeats",
            str(bench_repeats),
        ],
    )
    if not ok:
        transcript = "\n".join(transcript_lines) + "\n"
        outputs = _write_reports(
            report_dir or (root.parent / "logs" / "udp_crypto_acceptance"),
            transcript,
            command or [host_python, str(Path(__file__).resolve())],
        )
        return 1, transcript, outputs

    emit_and_capture("ACCEPTANCE_PASS")
    transcript = "\n".join(transcript_lines) + "\n"
    outputs = _write_reports(
        report_dir or (root.parent / "logs" / "udp_crypto_acceptance"),
        transcript,
        command or [host_python, str(Path(__file__).resolve())],
    )
    return 0, transcript, outputs


def main() -> int:
    parser = argparse.ArgumentParser(description="Run end-to-end AX7020 UDP crypto acceptance.")
    parser.add_argument("--ip", default="192.168.1.20", help="Board IP address")
    parser.add_argument("--source-ip", default="192.168.1.11", help="Local source IP to bind before sending")
    parser.add_argument("--timeout", type=float, default=3.0, help="Default control/data timeout in seconds")
    parser.add_argument("--bench-timeout", type=float, default=10.0, help="BENCH timeout in seconds")
    parser.add_argument("--length-timeout", type=float, default=6.0, help="1472-byte regression timeout in seconds")
    parser.add_argument("--retries", type=int, default=3, help="Retries per sender case")
    parser.add_argument("--retry-delay", type=float, default=0.5, help="Retry delay in seconds")
    parser.add_argument("--send-interval-ms", type=float, default=1.0, help="Gap between paced sends")
    parser.add_argument("--bench-repeats", type=int, default=8, help="Repeat count for BENCH")
    parser.add_argument("--hex-preview-chars", type=int, default=48, help="Hex preview width for sender summary output")
    parser.add_argument("--skip-ping", action="store_true", help="Skip ICMP connectivity check")
    parser.add_argument("--host-python", default=sys.executable, help="Python executable for subcommands")
    parser.add_argument("--report-dir", default=None, help="Directory for raw log and Markdown report")
    args = parser.parse_args()
    rc, _transcript, outputs = execute_acceptance(
        ip=args.ip,
        source_ip=args.source_ip,
        timeout=args.timeout,
        bench_timeout=args.bench_timeout,
        length_timeout=args.length_timeout,
        retries=args.retries,
        retry_delay=args.retry_delay,
        send_interval_ms=args.send_interval_ms,
        bench_repeats=args.bench_repeats,
        hex_preview_chars=args.hex_preview_chars,
        skip_ping=args.skip_ping,
        host_python=args.host_python,
        report_dir=Path(args.report_dir) if args.report_dir else None,
        command=[sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]],
    )
    print(f"raw_log={outputs['raw_log']}")
    print(f"report_md={outputs['report_md']}")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
