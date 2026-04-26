from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


REQUIRED_KEYS = (
    "rollback_event_count",
    "recovery_active_cycles",
    "recovery_last_window_cycles",
    "recovery_max_window_cycles",
    "error_qualified_packet_count",
    "backend_total_cycles",
    "backend_accept_cycles",
    "backend_starvation_cycles",
    "high_water_count",
    "drop_pulse_count",
)


def _require_keys(snapshot: dict) -> None:
    missing = [key for key in REQUIRED_KEYS if key not in snapshot]
    if missing:
        raise ValueError(f"Missing required counter keys: {', '.join(missing)}")


def normalize_counter_snapshot(snapshot: dict, clock_hz: int) -> dict:
    normalized = dict(snapshot)

    _require_keys(normalized)
    if clock_hz <= 0:
        raise ValueError("clock_hz must be positive")

    backend_total = float(normalized["backend_total_cycles"])
    normalized["recovery_active_us"] = (float(normalized["recovery_active_cycles"]) * 1_000_000.0) / float(clock_hz)
    normalized["recovery_last_window_us"] = (
        float(normalized["recovery_last_window_cycles"]) * 1_000_000.0
    ) / float(clock_hz)
    normalized["recovery_max_window_us"] = (
        float(normalized["recovery_max_window_cycles"]) * 1_000_000.0
    ) / float(clock_hz)
    normalized["backend_utilization_ratio"] = (
        float(normalized["backend_accept_cycles"]) / backend_total if backend_total > 0.0 else 0.0
    )
    normalized["backend_starvation_ratio"] = (
        float(normalized["backend_starvation_cycles"]) / backend_total if backend_total > 0.0 else 0.0
    )
    normalized["clock_hz"] = int(clock_hz)
    return normalized


def _write_csv(path: Path, fieldnames: list[str], row: dict) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerow({name: row.get(name) for name in fieldnames})


def write_counter_artifacts(snapshot: dict, output_dir: Path, clock_hz: int) -> dict[str, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    normalized = normalize_counter_snapshot(snapshot, clock_hz=clock_hz)

    snapshot_json = output_dir / "hardware_counters_snapshot.json"
    fig5_csv = output_dir / "fig5_recovery_counters.csv"
    fig7_csv = output_dir / "fig7_backend_utilization.csv"

    snapshot_json.write_text(json.dumps(normalized, indent=2, sort_keys=True), encoding="utf-8")
    _write_csv(
        fig5_csv,
        [
            "rollback_event_count",
            "error_qualified_packet_count",
            "recovery_active_cycles",
            "recovery_last_window_cycles",
            "recovery_max_window_cycles",
            "recovery_active_us",
            "recovery_last_window_us",
            "recovery_max_window_us",
            "high_water_count",
            "drop_pulse_count",
        ],
        normalized,
    )
    _write_csv(
        fig7_csv,
        [
            "backend_total_cycles",
            "backend_accept_cycles",
            "backend_starvation_cycles",
            "backend_utilization_ratio",
            "backend_starvation_ratio",
        ],
        normalized,
    )

    return {
        "snapshot_json": snapshot_json,
        "fig5_csv": fig5_csv,
        "fig7_csv": fig7_csv,
    }


def load_snapshot_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Normalize AXI-Lite hardware counter snapshots into paper-ready artifacts.")
    parser.add_argument("snapshot_json", type=Path, help="Input JSON containing raw hardware counters.")
    parser.add_argument("output_dir", type=Path, help="Directory for normalized JSON and plot-ready CSVs.")
    parser.add_argument("--clock-hz", type=int, default=50_000_000, help="Reference hardware clock in Hz.")
    args = parser.parse_args()

    snapshot = load_snapshot_json(args.snapshot_json)
    paths = write_counter_artifacts(snapshot, args.output_dir, clock_hz=args.clock_hz)
    print(json.dumps({name: str(path) for name, path in paths.items()}, indent=2))


if __name__ == "__main__":
    main()
