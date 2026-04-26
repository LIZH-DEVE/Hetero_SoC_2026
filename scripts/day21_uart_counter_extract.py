from __future__ import annotations

import argparse
import importlib.util
import json
import re
from pathlib import Path


LINE_RE = re.compile(r"shadow-counter tag=(?P<tag>\d+) (?P<key>[a-z_]+)=0x(?P<value>[0-9A-Fa-f]{16})")
META_RE = re.compile(r"shadow-counter meta tag=(?P<tag>\d+) reason=(?P<reason>\S+) rx_batches=(?P<rx_batches>\d+) rx_packets=(?P<rx_packets>\d+)")


def _load_counter_export_module():
    module_path = Path(__file__).resolve().with_name("day21_counter_snapshot_export.py")
    spec = importlib.util.spec_from_file_location("day21_counter_snapshot_export", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def parse_uart_counter_log(log_path: Path) -> dict:
    tags: dict[int, dict] = {}
    metas: dict[int, dict] = {}

    for raw_line in log_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        meta_match = META_RE.search(raw_line)
        if meta_match:
            tag = int(meta_match.group("tag"))
            metas[tag] = {
                "snapshot_tag": tag,
                "reason": meta_match.group("reason"),
                "rx_batches": int(meta_match.group("rx_batches")),
                "rx_packets": int(meta_match.group("rx_packets")),
            }
            continue

        value_match = LINE_RE.search(raw_line)
        if value_match:
            tag = int(value_match.group("tag"))
            snapshot = tags.setdefault(tag, {})
            snapshot[value_match.group("key")] = int(value_match.group("value"), 16)

    exporter = _load_counter_export_module()
    complete_tags = [tag for tag, snapshot in tags.items() if all(key in snapshot for key in exporter.REQUIRED_KEYS)]
    if not complete_tags:
        raise ValueError(f"No complete shadow-counter snapshot found in {log_path}")

    selected_tag = max(complete_tags)
    snapshot = dict(tags[selected_tag])
    snapshot.update(metas.get(selected_tag, {"snapshot_tag": selected_tag}))
    return snapshot


def write_uart_counter_artifacts(log_path: Path, output_dir: Path, clock_hz: int) -> dict[str, Path]:
    snapshot = parse_uart_counter_log(log_path)
    exporter = _load_counter_export_module()
    return exporter.write_counter_artifacts(snapshot, output_dir, clock_hz=clock_hz)


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract shadow-counter UART dumps into paper-ready counter artifacts.")
    parser.add_argument("uart_log", type=Path, help="UART log containing shadow-counter lines.")
    parser.add_argument("output_dir", type=Path, help="Directory for normalized JSON and plot-ready CSVs.")
    parser.add_argument("--clock-hz", type=int, default=50_000_000, help="Reference hardware clock in Hz.")
    args = parser.parse_args()

    paths = write_uart_counter_artifacts(args.uart_log, args.output_dir, clock_hz=args.clock_hz)
    print(json.dumps({name: str(path) for name, path in paths.items()}, indent=2))


if __name__ == "__main__":
    main()
