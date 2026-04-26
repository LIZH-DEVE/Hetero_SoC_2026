#!/usr/bin/env python3
"""Post-process shadow recovery probe runs into reproducible evidence packs."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import math
import os
import platform
import random
import re
import statistics
import struct
import subprocess
import sys
import zlib
from pathlib import Path
from typing import Any


MANIFEST_SCHEMA_VERSION = "1.0.0"
STATS_SCHEMA_VERSION = "1.0.0"
PLOT_SCHEMA_VERSION = "1.0.0"
METRICS_SEMANTICS_VERSION = "1.0.0"
EXPERIMENT_PLAN_VERSION = "shadow-recovery-experiment-infra-v1"
TRAFFIC_GENERATOR_VERSION = "shadow-recovery-traffic-v1"
PBM_DIAG_CSR_MAP_VERSION = "stage1a8-pbm-diag-v1"
CRYPTO_INGRESS_DIAG_CSR_MAP_VERSION = "stage1a9-crypto-ingress-diag-v1"
CRYPTO_DMA_HANDOFF_DIAG_CSR_MAP_VERSION = "stage1a10-crypto-dma-handoff-diag-v1"
PBM_READ_SIDE_DIAG_CSR_MAP_VERSION = "stage1a11-pbm-read-side-diag-v1"
BRIDGE_OUTPUT_FIFO_DIAG_CSR_MAP_VERSION = "stage1a12-bridge-output-fifo-diag-v1"
DMA_START_PATH_DIAG_CSR_MAP_VERSION = "stage1a13-dma-start-path-diag-v1"
START_PULSE_INJECTION_DIAG_CSR_MAP_VERSION = "stage1a14-start-pulse-injection-diag-v1"
EXPLICIT_START_BRIDGE_HANDOFF_DIAG_CSR_MAP_VERSION = "stage1a15-explicit-start-bridge-handoff-v1"
BRIDGE_DATA_PRODUCTION_DIAG_CSR_MAP_VERSION = "stage1a16-bridge-data-production-v1"
INJECTION_SOURCE_ARMING_DIAG_CSR_MAP_VERSION = "stage1a20-injection-source-arming-v1"
PBM_RESET_DOMAIN_SCOPE_DIAG_VERSION = "stage1a24-pbm-reset-domain-scope-v1"

ALLOWED_FAULT_SEVERITY_UNITS = {
    "bytes",
    "ratio",
    "offset_bytes",
    "length_delta_bytes",
    "pattern_code",
    "null",
}

NEGATIVE_RESULT_TYPES = {
    "negative_no_backend_activity",
    "negative_backend_activity_only",
    "negative_fault_observed_no_recovery",
    "negative_inconclusive_due_to_log_gap",
    "negative_diagnostic_only",
}

SANITY_CASE0_MIN_PASS = 4
SANITY_CASE1_MIN_PASS = 4
SANITY_CASE2_MIN_PASS = 3
ACTIVITY_GAIN_EPSILON = 0.01
STARVATION_GAIN_EPSILON = 0.005
ABSOLUTE_ACTIVITY_FLOOR = 16
RATIO_GAIN_EPSILON = 0.01

ROLLBACK_RECOVERY_COUNTERS = (
    "rollback_event_count",
    "recovery_active_cycles",
    "recovery_last_window_cycles",
    "recovery_max_window_cycles",
)

FRONTEND_PRESSURE_COUNTERS = (
    "high_water_count",
    "drop_pulse_count",
)

BACKEND_SERVICE_COUNTERS = (
    "backend_accept_cycles",
    "backend_starvation_cycles",
)

PRIOR_DROP_PULSE_CONFIG_ORDER = (
    ("BF1_SM500", 1, 500),
    ("BF8_SM500", 8, 500),
    ("BF64_SM500", 64, 500),
)

PRIOR_DROP_PULSE_CONFIG_BY_BURST = {
    burst_frames: config_name for config_name, burst_frames, _ in PRIOR_DROP_PULSE_CONFIG_ORDER
}

STAGE1A7_CONFIG_ORDER = (
    ("BF8_SM500", 8, 500, "standard"),
    ("BF64_SM500", 64, 500, "standard"),
    ("BF64_SM100", 64, 100, "standard"),
    ("BF64_SM500_ExtraSnapshots", 64, 500, "extra_snapshots"),
)

STAGE1A8_CONFIG_ORDER = (
    ("IdleControl", 0, 500, "standard"),
    ("BF8_SM500", 8, 500, "standard"),
    ("BF64_SM500", 64, 500, "standard"),
    ("BF8_SM500_ExtraSnapshots", 8, 500, "extra_snapshots"),
    ("BF64_SM500_ExtraSnapshots", 64, 500, "extra_snapshots"),
)

STAGE1A9_CONFIG_ORDER = STAGE1A8_CONFIG_ORDER
STAGE1A10_CONFIG_ORDER = STAGE1A8_CONFIG_ORDER
STAGE1A11_CONFIG_ORDER = STAGE1A8_CONFIG_ORDER
STAGE1A12_CONFIG_ORDER = STAGE1A8_CONFIG_ORDER
STAGE1A13_CONFIG_ORDER = (
    ("Current_Bypass_NoExplicitStart", 64, 500),
    ("Bypass_WithExplicitCSRStart", 64, 500),
)
STAGE1A14_CONFIG_ORDER = (
    ("ExplicitStartWrite_Readback", 64, 500),
)
STAGE1A15_CONFIG_ORDER = (
    ("Current_Bypass_NoExplicitStart", 64, 500, "none", 0),
    ("Bypass_ExplicitStart_BeforeWorkload", 64, 500, "before_workload", 0),
    ("Bypass_ExplicitStart_AfterWorkload", 64, 500, "after_workload_50ms", 50),
)
STAGE1A16_CONFIG_ORDER = (
    ("A12_NoStart_Replay", 64, 500, "none", 0),
    ("A15_AfterWorkloadStart_Replay", 64, 500, "after_workload_50ms", 50),
)
STAGE1A20_CONFIG_ORDER = (
    ("InjectionArmOnly", 64, 500, "arm_only"),
    ("InjectionArmWithReadback", 64, 500, "with_readback"),
)

PBM_DIAG_CSR_OFFSETS = {
    "pbm_wr_valid_cycles": 0x154,
    "pbm_wr_ready_high_cycles": 0x158,
    "pbm_valid_not_ready_cycles": 0x15C,
    "pbm_wr_accept_cycles": 0x160,
    "pbm_wr_last_accepted_count": 0x164,
    "pbm_wr_error_accepted_count": 0x168,
    "pbm_wr_last_error_accepted_count": 0x16C,
    "pbm_alloc_meta_entry_count": 0x170,
    "pbm_alloc_pbm_entry_count": 0x174,
    "pbm_commit_entry_count": 0x178,
    "pbm_rollback_entry_count": 0x17C,
    "pbm_state_raw": 0x180,
    "pbm_ptr_head_reserve": 0x184,
    "pbm_ptr_head_commit": 0x188,
    "pbm_ptr_tail": 0x18C,
    "pbm_buffer_usage": 0x190,
}

CRYPTO_INGRESS_DIAG_CSR_OFFSETS = {
    "crypto_rx_valid_cycles": 0x194,
    "crypto_rx_ready_high_cycles": 0x198,
    "crypto_rx_valid_not_ready_cycles": 0x19C,
    "crypto_rx_accept_cycles": 0x1A0,
    "crypto_rx_last_accepted_count": 0x1A4,
    "crypto_rx_error_accepted_count": 0x1A8,
    "crypto_rx_last_error_accepted_count": 0x1AC,
    "crypto_rx_pkt_end_accepted_count": 0x1B0,
}

CRYPTO_DMA_HANDOFF_DIAG_CSR_OFFSETS = {
    "pbm_committed_available_cycles": 0x1B4,
    "pbm_rd_empty_cycles": 0x1B8,
    "pbm_rd_nonempty_cycles": 0x1BC,
    "pbm_rd_en_cycles": 0x1C0,
    "pbm_rd_accept_cycles": 0x1C4,
    "crypto_dma_in_valid_cycles": 0x1C8,
    "crypto_dma_in_ready_cycles": 0x1CC,
    "crypto_dma_in_accept_cycles": 0x1D0,
    "crypto_dma_backpressure_cycles": 0x1D4,
    "crypto_dma_in_last_seen_count": 0x1D8,
    "crypto_dma_completion_count": 0x1DC,
}

PBM_READ_SIDE_DIAG_CSR_OFFSETS = {
    "bridge_pbm_rd_en_cycles": 0x1E0,
    "bridge_pbm_fire_count": 0x1E4,
    "bridge_inst_available_cycles": 0x1E8,
    "bridge_data_available_no_inst_available_cycles": 0x1EC,
    "bridge_mid_fifo_full_cycles": 0x1F0,
    "bridge_out_fifo_full_cycles": 0x1F4,
    "bridge_input_state_raw": 0x1F8,
    "dma_start_seen_count": 0x1FC,
    "dma_addr_cycles": 0x200,
    "dma_data_cycles": 0x204,
    "dma_resp_cycles": 0x208,
    "dma_aw_handshake_count": 0x20C,
    "dma_w_handshake_count": 0x210,
    "dma_b_handshake_count": 0x214,
    "dma_wready_low_cycles": 0x218,
    "dma_state_raw": 0x21C,
}

BRIDGE_OUTPUT_FIFO_DIAG_CSR_OFFSETS = {
    "bridge_tx_nonempty_cycles": 0x220,
    "bridge_tx_rd_en_cycles": 0x224,
    "bridge_tx_accept_cycles": 0x228,
    "bridge_tx_last_seen_count": 0x22C,
}

DMA_START_PATH_DIAG_CSR_OFFSETS = {
    "csr_start_pulse_count": 0x230,
    "ring_doorbell_pulse_count": 0x234,
    "fetcher_start_pulse_count": 0x238,
    "final_start_pulse_count": 0x23C,
    "source_reader_start_pulse_count": 0x240,
    "dma_busy_cycles": 0x244,
    "source_reader_busy_cycles": 0x248,
}

START_PULSE_INJECTION_DIAG_CSR_OFFSETS = {
    "axil_write_hit_control_count": 0x24C,
    "axil_write_hit_start_count": 0x250,
    "axil_write_hit_doorbell_count": 0x254,
}

BRIDGE_DATA_PRODUCTION_DIAG_CSR_OFFSETS = {
    "bridge_tx_wr_en_cycles": 0x258,
    "bridge_tx_fifo_level": 0x25C,
    "bridge_tx_fifo_level_max": 0x260,
    "bridge_tx_empty_cycles": 0x264,
    "bridge_tx_full_cycles": 0x268,
    "bridge_tx_overflow_count": 0x26C,
}

DMA_RD_EN_EQUATION_DIAG_CSR_OFFSETS = {
    "dma_rd_en_loopback_mode_raw": 0x280,
    "dma_rd_en_tx_axis_tready_cycles": 0x284,
    "dma_rd_en_crypto_to_dma_nonempty_cycles": 0x288,
    "dma_rd_en_tx_ready_when_nonempty_cycles": 0x28C,
    "dma_rd_en_dma_req_rd_cycles": 0x290,
    "dma_rd_en_loopback_branch_selected_cycles": 0x294,
    "dma_rd_en_normal_branch_selected_cycles": 0x298,
    "dma_rd_en_loopback_branch_candidate_cycles": 0x29C,
    "dma_rd_en_equation_true_but_rd_en_low_cycles": 0x2A0,
}

NUMERIC_FIELDS = (
    "backend_total_cycles",
    "backend_accept_cycles",
    "backend_starvation_cycles",
    "rollback_event_count",
    "recovery_active_cycles",
    "recovery_last_window_cycles",
    "recovery_max_window_cycles",
    "high_water_count",
    "drop_pulse_count",
)


def build_fault_sequence(
    repeat_count: int,
    fault_ratio: float,
    fault_mode: str,
    noise_pattern: str,
    seed: int,
) -> list[dict[str, Any]]:
    """Build a deterministic fault schedule for reproducible noise traffic."""

    rng = random.Random(seed)
    fault_ratio = max(0.0, min(1.0, float(fault_ratio)))
    sequence: list[dict[str, Any]] = []

    if noise_pattern == "periodic" and fault_ratio > 0:
        period = max(1, round(1.0 / fault_ratio))
        for index in range(repeat_count):
            is_fault = (index % period) == 0
            sequence.append(
                {
                    "index": index,
                    "is_fault": is_fault,
                    "fault_mode": fault_mode if is_fault else "none",
                    "noise_pattern": noise_pattern,
                }
            )
        return sequence

    if noise_pattern == "bursty_fault_cluster" and fault_ratio > 0:
        cluster_len = max(1, round(repeat_count * fault_ratio))
        start = rng.randrange(0, max(1, repeat_count - cluster_len + 1))
        for index in range(repeat_count):
            is_fault = start <= index < start + cluster_len
            sequence.append(
                {
                    "index": index,
                    "is_fault": is_fault,
                    "fault_mode": fault_mode if is_fault else "none",
                    "noise_pattern": noise_pattern,
                }
            )
        return sequence

    for index in range(repeat_count):
        is_fault = rng.random() < fault_ratio
        sequence.append(
            {
                "index": index,
                "is_fault": is_fault,
                "fault_mode": fault_mode if is_fault else "none",
                "noise_pattern": noise_pattern,
            }
        )
    return sequence


def digest_fault_sequence(sequence: list[dict[str, Any]]) -> str:
    payload = json.dumps(sequence, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str | None:
    if not path.exists() or not path.is_file():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def iso_timestamp(path: Path) -> str | None:
    if not path.exists():
        return None
    return dt.datetime.fromtimestamp(path.stat().st_mtime, tz=dt.timezone.utc).isoformat()


def file_record(path: Path, root: Path) -> dict[str, Any]:
    try:
        relative_path = path.relative_to(root).as_posix() if path.exists() else str(path)
    except ValueError:
        relative_path = str(path)
    return {
        "relative_path": relative_path,
        "sha256": sha256_file(path),
        "size_bytes": path.stat().st_size if path.exists() else None,
        "created_at": iso_timestamp(path),
    }


def load_json_if_exists(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8-sig"))


def load_csv_rows_if_exists(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def reference_run_payload(path_str: str) -> dict[str, Any]:
    if not path_str:
        return {"dir": None, "manifest": {}, "stats": {}, "rows": []}
    path = Path(path_str)
    return {
        "dir": str(path),
        "manifest": load_json_if_exists(path / "run_manifest.json"),
        "stats": load_json_if_exists(path / "summary_stats.json"),
        "rows": load_csv_rows_if_exists(path / "case_results.csv"),
    }


def command_output(command: list[str], cwd: Path) -> str:
    try:
        completed = subprocess.run(
            command,
            cwd=str(cwd),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=15,
            check=False,
        )
        return completed.stdout.strip()
    except Exception as exc:  # pragma: no cover - defensive environment capture
        return f"unavailable: {exc}"


def script_commit_hash(repo_root: Path) -> dict[str, str]:
    output = command_output(["git", "rev-parse", "HEAD"], repo_root)
    if output and "fatal:" not in output.lower() and "unavailable:" not in output.lower():
        return {"script_commit_hash": output.splitlines()[-1].strip(), "script_commit_hash_source": "git"}
    return {"script_commit_hash": "unavailable", "script_commit_hash_source": output or "not a git repository"}


def safe_ratio(numerator: float, denominator: float) -> float | None:
    if denominator == 0:
        return None
    return numerator / denominator


def int_value(value: Any) -> int:
    if value in (None, ""):
        return 0
    if isinstance(value, str):
        text = value.strip()
        if text.lower().startswith("0x"):
            return int(text, 16)
    return int(float(value))


def any_nonzero(row: dict[str, Any], fields: tuple[str, ...] | list[str]) -> bool:
    return any(int_value(row.get(field, 0)) > 0 for field in fields)


def any_nonzero_rows(rows: list[dict[str, Any]], fields: tuple[str, ...] | list[str]) -> bool:
    return any(any_nonzero(row, fields) for row in rows)


def max_counter(rows: list[dict[str, Any]], field: str) -> int:
    return max([int_value(row.get(field, 0)) for row in rows] + [0])


def bool_majority(rows: list[dict[str, Any]], predicate) -> bool:
    if not rows:
        return False
    matches = sum(1 for row in rows if predicate(row))
    return matches >= max(1, math.ceil(len(rows) / 2))


def invocation_digest(args: argparse.Namespace, argv: list[str]) -> str:
    payload = {
        "argv": argv,
        "args": vars(args),
        "default_versions": {
            "manifest_schema_version": MANIFEST_SCHEMA_VERSION,
            "stats_schema_version": STATS_SCHEMA_VERSION,
            "plot_schema_version": PLOT_SCHEMA_VERSION,
            "metrics_semantics_version": METRICS_SEMANTICS_VERSION,
            "experiment_plan_version": args.experiment_plan_version,
        },
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def normalize_fault_severity(value: str, unit: str) -> float | None:
    if unit == "null" or value == "":
        return None
    try:
        return float(value)
    except ValueError:
        return None


def hex32(value: Any) -> str:
    return f"0x{int_value(value) & 0xFFFFFFFF:08X}"


def hex32_or_none(value: Any) -> str | None:
    if value in (None, ""):
        return None
    return hex32(value)


def set_bits_32(value: Any) -> list[int]:
    raw = int_value(value) & 0xFFFFFFFF
    return [bit for bit in range(32) if raw & (1 << bit)]


def decode_inj_status(raw_value: Any) -> dict[str, Any]:
    raw = int_value(raw_value) & 0xFFFFFFFF
    return {
        "inj_status_raw_decimal": raw,
        "inj_status_hex": f"0x{raw:08X}",
        "inj_status_set_bits": set_bits_32(raw),
        "inj_status_decode_source": "current RTL/CSR definition",
        "inj_overflow": 1 if (raw & (1 << 18)) else 0,
        "inj_done": 1 if (raw & (1 << 17)) else 0,
        "inj_fifo_nonempty": 1 if (raw & (1 << 16)) else 0,
        "inj_fifo_count": raw & 0xFFFF,
    }


INJECTION_SOURCE_STATE_NAMES = {
    0: "IDLE",
    1: "ARMED",
    2: "ACTIVE",
    3: "EMITTING",
}


def decode_injection_source_state(raw_value: Any) -> dict[str, Any]:
    raw = int_value(raw_value) & 0xFFFFFFFF
    return {
        "inj_source_state_raw": raw,
        "inj_source_state_decoded": INJECTION_SOURCE_STATE_NAMES.get(raw, f"UNKNOWN_{raw}"),
    }


ROUTE_STATE_NAMES = {
    0: "FASTPATH_ROUTE_IDLE",
    1: "FASTPATH_ROUTE_HEADER",
    2: "FASTPATH_ROUTE_REPLAY",
    3: "FASTPATH_ROUTE_DMA",
    4: "FASTPATH_ROUTE_EGRESS_REPLAY",
    5: "FASTPATH_ROUTE_EGRESS_DMA",
}


def decode_netdbg_status(raw_value: Any) -> dict[str, Any]:
    raw = int_value(raw_value) & 0xFFFFFFFF
    route_state = (raw >> 14) & 0x7
    return {
        "netdbg_status_raw_decimal": raw,
        "netdbg_status_hex": f"0x{raw:08X}",
        "netdbg_status_set_bits": set_bits_32(raw),
        "netdbg_classifier_dma_idle": 1 if (raw & (1 << 18)) else 0,
        "netdbg_acl_drop_pulse": 1 if (raw & (1 << 17)) else 0,
        "netdbg_route_state": route_state,
        "netdbg_route_state_name": ROUTE_STATE_NAMES.get(route_state, f"UNKNOWN_{route_state}"),
        "netdbg_classifier_dma_ready_seen": 1 if (raw & (1 << 13)) else 0,
        "netdbg_classifier_dma_fire_seen": 1 if (raw & (1 << 12)) else 0,
        "netdbg_classifier_dma_valid_seen": 1 if (raw & (1 << 11)) else 0,
        "netdbg_classifier_in_fire_seen": 1 if (raw & (1 << 10)) else 0,
        "netdbg_acl_fire_seen": 1 if (raw & (1 << 9)) else 0,
        "netdbg_stage1_fire_seen": 1 if (raw & (1 << 8)) else 0,
        "classifier_dma_tready": 1 if (raw & (1 << 7)) else 0,
        "classifier_dma_tvalid": 1 if (raw & (1 << 6)) else 0,
        "classifier_s_tready": 1 if (raw & (1 << 5)) else 0,
        "classifier_s_tvalid": 1 if (raw & (1 << 4)) else 0,
        "aclf_tready": 1 if (raw & (1 << 3)) else 0,
        "aclf_tvalid": 1 if (raw & (1 << 2)) else 0,
        "stage1_inject_tready": 1 if (raw & (1 << 1)) else 0,
        "stage1_inject_tvalid": 1 if (raw & (1 << 0)) else 0,
    }


def load_pbm_state_decode_map(repo_root: Path) -> dict[int, str]:
    rtl_path = repo_root / "rtl" / "core" / "pbm" / "pbm_controller.sv"
    if not rtl_path.exists():
        return {}
    text = rtl_path.read_text(encoding="utf-8", errors="ignore")
    match = re.search(r"typedef\s+enum\s+logic\s*\[[^\]]+\]\s*\{(?P<body>.*?)\}\s*state_t\s*;", text, re.S)
    if not match:
        return {}
    body = match.group("body")
    entries: list[str] = []
    for raw_entry in body.split(","):
        cleaned = re.sub(r"//.*", "", raw_entry)
        cleaned = re.sub(r"/\*.*?\*/", "", cleaned, flags=re.S).strip()
        if not cleaned:
            continue
        entries.append(cleaned.split("=", 1)[0].strip())
    return {index: name for index, name in enumerate(entries)}


def decode_pbm_state(raw_value: Any, repo_root: Path) -> dict[str, Any]:
    raw = int_value(raw_value) & 0xFFFFFFFF
    decode_map = load_pbm_state_decode_map(repo_root)
    return {
        "pbm_state_raw": raw,
        "pbm_state_decoded": decode_map.get(raw, f"unknown_state_{raw}"),
    }


def parse_pbm_depth(repo_root: Path) -> int | None:
    rtl_path = repo_root / "rtl" / "core" / "pbm" / "pbm_controller.sv"
    if not rtl_path.exists():
        return None
    text = rtl_path.read_text(encoding="utf-8", errors="ignore")
    match = re.search(r"parameter\s+PBM_ADDR_WIDTH\s*=\s*(\d+)", text)
    if not match:
        return None
    addr_width = int(match.group(1))
    if addr_width < 3:
        return None
    return 1 << (addr_width - 2)


def pointer_delta_mod(pre_value: Any, post_value: Any, depth: int | None) -> int | None:
    if depth is None:
        return None
    return (int_value(post_value) - int_value(pre_value)) % depth


def pbm_diag_csr_collision(repo_root: Path) -> bool:
    rtl_path = repo_root / "rtl" / "core" / "axil_csr.sv"
    if not rtl_path.exists():
        return True
    text = rtl_path.read_text(encoding="utf-8", errors="ignore")
    for offset in PBM_DIAG_CSR_OFFSETS.values():
        token = f"10'h{offset:03X}:"
        if text.count(token) != 1:
            return True
    return False


def sv_instance_block(text: str, marker: str) -> str:
    start = text.find(marker)
    if start < 0:
        return ""
    end = text.find("\n    );", start)
    if end < 0:
        end = text.find(");", start)
    return text[start : end + 4] if end >= 0 else text[start:]


def pbm_reset_domain_static_scope(repo_root: Path) -> dict[str, Any]:
    pbm_path = repo_root / "rtl" / "core" / "pbm" / "pbm_controller.sv"
    crypto_path = repo_root / "rtl" / "top" / "crypto_dma_subsystem.sv"
    axil_path = repo_root / "rtl" / "core" / "axil_csr.sv"
    missing = [str(path) for path in (pbm_path, crypto_path, axil_path) if not path.exists()]
    if missing:
        return {
            "pbm_reset_domain_scope_version": PBM_RESET_DOMAIN_SCOPE_DIAG_VERSION,
            "static_scope_parse_ok": False,
            "static_scope_parse_error": "missing RTL files: " + ", ".join(missing),
        }

    pbm_text = pbm_path.read_text(encoding="utf-8", errors="ignore")
    crypto_text = crypto_path.read_text(encoding="utf-8", errors="ignore")
    axil_text = axil_path.read_text(encoding="utf-8", errors="ignore")
    header_end = pbm_text.find(");")
    pbm_header = pbm_text[: header_end if header_end >= 0 else min(len(pbm_text), 4096)]
    u_pbm_block = sv_instance_block(
        crypto_text,
        "pbm_controller #(.PBM_ADDR_WIDTH(14), .DATA_WIDTH(DATA_WIDTH)) u_pbm",
    )
    fetcher_block = sv_instance_block(crypto_text, "dma_desc_fetcher #(.ADDR_WIDTH(ADDR_WIDTH)) u_fetcher")
    source_reader_block = sv_instance_block(
        crypto_text,
        "dma_crypto_source_reader #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_dma_crypto_source_reader",
    )
    diag_clear_start = pbm_text.find("end else if (i_diag_clear) begin")
    diag_clear_end = pbm_text.find("end else begin", diag_clear_start)
    diag_clear_block = (
        pbm_text[diag_clear_start:diag_clear_end]
        if diag_clear_start >= 0 and diag_clear_end > diag_clear_start
        else ""
    )

    return {
        "pbm_reset_domain_scope_version": PBM_RESET_DOMAIN_SCOPE_DIAG_VERSION,
        "static_scope_parse_ok": bool(u_pbm_block and fetcher_block and source_reader_block),
        "static_scope_parse_error": "",
        "dma_soft_reset_generated_by_axil_csr": "s_axil_wdata[10]" in axil_text
        and "o_soft_reset <= 1'b1" in axil_text,
        "pbm_controller_has_soft_reset_port": "i_soft_reset" in pbm_header,
        "dma_soft_reset_connected_to_pbm": "csr_soft_reset" in u_pbm_block or ".i_soft_reset" in u_pbm_block,
        "dma_soft_reset_connected_to_fetcher": ".i_soft_reset(csr_soft_reset)" in fetcher_block,
        "dma_soft_reset_connected_to_source_reader": ".i_soft_reset(csr_soft_reset)" in source_reader_block,
        "pbm_diag_clear_resets_diag_counters_only": bool(diag_clear_block)
        and "diag_wr_valid_cycles_q <= 32'd0" in diag_clear_block
        and "ptr_head_commit <=" not in diag_clear_block
        and "ptr_head_reserve <=" not in diag_clear_block
        and "ptr_tail <=" not in diag_clear_block
        and "state <=" not in diag_clear_block,
        "pbm_state_pointer_reset_requires_global_rst_n": "if (!rst_n) begin" in pbm_text
        and "state <= ALLOC_META" in pbm_text
        and "ptr_head_commit <= '0" in pbm_text
        and "ptr_head_reserve <= '0" in pbm_text
        and "ptr_tail <= '0" in pbm_text
        and "i_soft_reset" not in pbm_text,
        "pbm_memory_reset_requires_global_rst_n": ".rstb(!rst_n)" in pbm_text,
    }


def crypto_ingress_diag_csr_collision(repo_root: Path) -> bool:
    rtl_path = repo_root / "rtl" / "core" / "axil_csr.sv"
    if not rtl_path.exists():
        return True
    text = rtl_path.read_text(encoding="utf-8", errors="ignore")
    for offset in CRYPTO_INGRESS_DIAG_CSR_OFFSETS.values():
        token = f"10'h{offset:03X}:"
        if text.count(token) != 1:
            return True
    return False


def crypto_dma_handoff_diag_csr_collision(repo_root: Path) -> bool:
    rtl_path = repo_root / "rtl" / "core" / "axil_csr.sv"
    if not rtl_path.exists():
        return True
    text = rtl_path.read_text(encoding="utf-8", errors="ignore")
    for offset in CRYPTO_DMA_HANDOFF_DIAG_CSR_OFFSETS.values():
        token = f"10'h{offset:03X}:"
        if text.count(token) != 1:
            return True
    return False


def pbm_read_side_diag_csr_collision(repo_root: Path) -> bool:
    rtl_path = repo_root / "rtl" / "core" / "axil_csr.sv"
    if not rtl_path.exists():
        return True
    text = rtl_path.read_text(encoding="utf-8", errors="ignore")
    for offset in PBM_READ_SIDE_DIAG_CSR_OFFSETS.values():
        token = f"10'h{offset:03X}:"
        if text.count(token) != 1:
            return True
    return False


def bridge_output_fifo_diag_csr_collision(repo_root: Path) -> bool:
    rtl_path = repo_root / "rtl" / "core" / "axil_csr.sv"
    if not rtl_path.exists():
        return True
    text = rtl_path.read_text(encoding="utf-8", errors="ignore")
    for offset in BRIDGE_OUTPUT_FIFO_DIAG_CSR_OFFSETS.values():
        token = f"10'h{offset:03X}:"
        if text.count(token) != 1:
            return True
    return False


def dma_start_path_diag_csr_collision(repo_root: Path) -> bool:
    rtl_path = repo_root / "rtl" / "core" / "axil_csr.sv"
    if not rtl_path.exists():
        return True
    text = rtl_path.read_text(encoding="utf-8", errors="ignore")
    for offset in DMA_START_PATH_DIAG_CSR_OFFSETS.values():
        token = f"10'h{offset:03X}:"
        if text.count(token) != 1:
            return True
    return False


def start_pulse_injection_diag_csr_collision(repo_root: Path) -> bool:
    rtl_path = repo_root / "rtl" / "core" / "axil_csr.sv"
    if not rtl_path.exists():
        return True
    text = rtl_path.read_text(encoding="utf-8", errors="ignore")
    for offset in START_PULSE_INJECTION_DIAG_CSR_OFFSETS.values():
        token = f"10'h{offset:03X}:"
        if text.count(token) != 1:
            return True
    return False


def dma_rd_en_equation_diag_csr_collision(repo_root: Path) -> bool:
    rtl_path = repo_root / "rtl" / "core" / "axil_csr.sv"
    if not rtl_path.exists():
        return True
    text = rtl_path.read_text(encoding="utf-8", errors="ignore")
    for offset in DMA_RD_EN_EQUATION_DIAG_CSR_OFFSETS.values():
        token = f"10'h{offset:03X}:"
        if text.count(token) != 1:
            return True
    return False


def row_stage_status(case_name: str, case: dict[str, Any], validation_status: str, negative_result_type: str | None) -> str:
    delta = case.get("delta", {})
    if case_name == "Case0_OriginalWrongPort":
        wrong_port = int(delta.get("drop_wrong_port_count", 0) or 0)
        backend_accept = int(delta.get("backend_accept_cycles", 0) or 0)
        return "pass" if wrong_port == 1 and backend_accept == 0 else "fail"
    if case_name == "Case1_HeaderAccepted":
        wrong_port = int(delta.get("drop_wrong_port_count", 0) or 0)
        unaligned = int(delta.get("drop_unaligned_count", 0) or 0)
        return "pass" if wrong_port == 0 and unaligned == 0 else "fail"
    if case_name == "Case2_RuntimeRingBypass":
        backend_accept = int(delta.get("backend_accept_cycles", 0) or 0)
        backend_starvation = int(delta.get("backend_starvation_cycles", 0) or 0)
        return "pass" if backend_accept > 0 or backend_starvation > 0 else "fail"
    if validation_status == "valid_positive_recovery":
        return "pass"
    if negative_result_type == "negative_backend_activity_only":
        return "partial"
    return "fail"


def stage1a7_row_status(row: dict[str, Any]) -> str:
    config_name = str(row.get("condition_diff_config") or "")
    drop_pulse_count = int_value(row.get("drop_pulse_count", 0))
    if config_name == "BF8_SM500":
        return "negative_control_pass" if drop_pulse_count == 0 else "negative_control_unexpected_activity"
    if config_name == "BF64_SM500":
        return "positive_reproduction_condition" if drop_pulse_count > 0 else "not_reproduced_condition"
    if config_name == "BF64_SM100":
        return "window_short_no_trigger" if drop_pulse_count == 0 else "window_scaled_trigger"
    if config_name == "BF64_SM500_ExtraSnapshots":
        return "extra_snapshot_observation"
    return "partial"


def stage1a8_row_status(row: dict[str, Any]) -> str:
    config_name = str(row.get("pbm_visibility_config") or "")
    idle_residual_activity_seen = truthy(row.get("idle_residual_activity_seen"))
    pbm_wr_accept_cycles = int_value(row.get("pbm_wr_accept_cycles", 0))
    pbm_valid_not_ready_cycles = int_value(row.get("pbm_valid_not_ready_cycles", 0))
    pbm_wr_last_accepted_count = int_value(row.get("pbm_wr_last_accepted_count", 0))
    pbm_wr_last_error_accepted_count = int_value(row.get("pbm_wr_last_error_accepted_count", 0))
    pbm_commit_entry_count = int_value(row.get("pbm_commit_entry_count", 0))
    rollback_path_observed = (
        int_value(row.get("pbm_rollback_entry_count", 0)) > 0 or any_nonzero(row, ROLLBACK_RECOVERY_COUNTERS)
    )
    if config_name == "IdleControl":
        return "negative_control_pass" if not idle_residual_activity_seen else "negative_control_unstable"
    if rollback_path_observed or pbm_wr_last_error_accepted_count > 0:
        return "rollback_trigger_candidate_observed"
    if pbm_commit_entry_count > 0 or int_value(row.get("pbm_ptr_head_commit_delta_mod", 0)) > 0:
        return "commit_without_backend_service_observed"
    if (
        pbm_wr_accept_cycles > 0
        and pbm_wr_last_accepted_count == 0
        and int_value(row.get("pbm_ptr_head_reserve_delta_mod", 0)) > 0
        and int_value(row.get("pbm_ptr_head_commit_delta_mod", 0)) == 0
    ):
        return "accept_without_packet_end_observed"
    if pbm_valid_not_ready_cycles > 0 and pbm_wr_accept_cycles == 0:
        return "ingress_ready_gating_observed"
    return "pbm_visibility_observation"


def stage1a21_row_status(row: dict[str, Any]) -> str:
    config_name = str(row.get("pbm_ready_gating_config") or "")
    state_name = str(row.get("pbm_state_decoded") or "")
    pbm_valid = int_value(row.get("pbm_wr_valid_cycles", 0))
    pbm_ready = int_value(row.get("pbm_wr_ready_high_cycles", 0))
    pbm_accept = int_value(row.get("pbm_wr_accept_cycles", 0))
    pbm_vnr = int_value(row.get("pbm_valid_not_ready_cycles", 0))
    if config_name == "IdleControl":
        tail_pre = int_value(row.get("pbm_ptr_tail_pre", 0))
        commit_pre = int_value(row.get("pbm_ptr_head_commit_pre", 0))
        rd_nonempty = int_value(row.get("pbm_rd_nonempty_cycles", 0))
        committed_available = int_value(row.get("pbm_committed_available_cycles", 0))
        return (
            "idle_pointer_gap_preexisting"
            if (tail_pre != commit_pre and (rd_nonempty > 0 or committed_available > 0))
            else "negative_control_pass"
        )
    if state_name in {"ALLOC_META", "ALLOC_PBM"} and pbm_valid > 0 and pbm_ready == 0 and pbm_vnr > 0 and pbm_accept == 0:
        return "ready_low_due_to_full_inferred"
    if state_name not in {"ALLOC_META", "ALLOC_PBM"} and pbm_valid > 0 and pbm_ready == 0 and pbm_vnr > 0 and pbm_accept == 0:
        return "ready_low_due_to_state_inferred"
    return "pbm_ready_gating_observation"


def stage1a22_row_status(row: dict[str, Any]) -> str:
    config_name = str(row.get("pbm_pointer_reset_or_drain_config") or "")
    commit_pre = int_value(row.get("pbm_ptr_head_commit_pre", 0))
    reserve_pre = int_value(row.get("pbm_ptr_head_reserve_pre", 0))
    tail_pre = int_value(row.get("pbm_ptr_tail_pre", 0))
    rd_nonempty = int_value(row.get("pbm_rd_nonempty_cycles", 0))
    committed_available = int_value(row.get("pbm_committed_available_cycles", 0))
    rd_en = int_value(row.get("pbm_rd_en_cycles", 0))
    rd_accept = int_value(row.get("pbm_rd_accept_cycles", 0))
    wr_ready = int_value(row.get("pbm_wr_ready_high_cycles", 0))
    wr_accept = int_value(row.get("pbm_wr_accept_cycles", 0))
    pointer_gap_seen = tail_pre != commit_pre and commit_pre == reserve_pre and (rd_nonempty > 0 or committed_available > 0)
    gap_cleared = tail_pre == commit_pre == reserve_pre and rd_nonempty == 0 and committed_available == 0

    if config_name == "IdleControl_NoReset":
        return "idle_pointer_gap_preexisting" if pointer_gap_seen else "idle_pointer_gap_not_seen"
    if config_name == "IdleControl_AfterSoftReset":
        if gap_cleared:
            return "soft_reset_gap_cleared"
        if pointer_gap_seen and (rd_en > 0 or rd_accept > 0):
            return "soft_reset_read_drain_seen"
        if pointer_gap_seen:
            return "soft_reset_gap_persisted"
        if rd_nonempty > 0 or committed_available > 0:
            return "soft_reset_read_side_nonempty_persisted"
        return "soft_reset_idle_observation"
    if config_name == "BF64_SM500_AfterSoftReset":
        if wr_accept > 0:
            return "ready_recovered_accept_seen"
        if wr_ready > 0:
            return "ready_recovered_no_accept"
        return "ready_still_low_after_soft_reset"
    return "pbm_pointer_reset_or_drain_observation"


def stage1a23_row_status(row: dict[str, Any]) -> str:
    config_name = str(row.get("pbm_commit_tail_invariant_config") or "")
    commit_pre = int_value(row.get("pbm_ptr_head_commit_pre", 0))
    reserve_pre = int_value(row.get("pbm_ptr_head_reserve_pre", 0))
    tail_pre = int_value(row.get("pbm_ptr_tail_pre", 0))
    rd_nonempty = int_value(row.get("pbm_rd_nonempty_cycles", 0))
    committed_available = int_value(row.get("pbm_committed_available_cycles", 0))
    rd_en = int_value(row.get("pbm_rd_en_cycles", 0))
    rd_accept = int_value(row.get("pbm_rd_accept_cycles", 0))
    pointer_gap_seen = tail_pre != commit_pre and commit_pre == reserve_pre and (rd_nonempty > 0 or committed_available > 0)

    if config_name == "IdleControl_NoReset":
        return "idle_pointer_gap_preexisting" if pointer_gap_seen else "idle_pointer_gap_not_seen"
    if config_name == "IdleControl_AfterSoftReset":
        return "soft_reset_gap_persisted" if pointer_gap_seen else "soft_reset_idle_observation"
    if config_name == "IdleControl_AfterSoftReset_ExtraSnapshots":
        state_values = [
            row.get("pbm_state_raw_at_post_workload"),
            row.get("pbm_state_raw_at_050ms"),
            row.get("pbm_state_raw_at_250ms"),
            row.get("pbm_state_raw_at_500ms"),
        ]
        commit_values = [
            row.get("pbm_ptr_head_commit_at_post_workload"),
            row.get("pbm_ptr_head_commit_at_050ms"),
            row.get("pbm_ptr_head_commit_at_250ms"),
            row.get("pbm_ptr_head_commit_at_500ms"),
        ]
        tail_values = [
            row.get("pbm_ptr_tail_at_post_workload"),
            row.get("pbm_ptr_tail_at_050ms"),
            row.get("pbm_ptr_tail_at_250ms"),
            row.get("pbm_ptr_tail_at_500ms"),
        ]
        deltas = [
            row.get("pbm_rd_nonempty_cycles_delta_at_post_workload"),
            row.get("pbm_rd_nonempty_cycles_delta_at_050ms"),
            row.get("pbm_rd_nonempty_cycles_delta_at_250ms"),
            row.get("pbm_rd_nonempty_cycles_delta_at_500ms"),
        ]
        drain_seen = any(int_value(value or 0) > 0 for value in (
            row.get("pbm_rd_en_cycles_delta_at_post_workload"),
            row.get("pbm_rd_en_cycles_delta_at_050ms"),
            row.get("pbm_rd_en_cycles_delta_at_250ms"),
            row.get("pbm_rd_en_cycles_delta_at_500ms"),
            row.get("pbm_rd_accept_cycles_delta_at_post_workload"),
            row.get("pbm_rd_accept_cycles_delta_at_050ms"),
            row.get("pbm_rd_accept_cycles_delta_at_250ms"),
            row.get("pbm_rd_accept_cycles_delta_at_500ms"),
        ))
        state_constant = len({value for value in state_values if value is not None}) <= 1
        pointer_constant = len({value for value in commit_values if value is not None}) <= 1 and len(
            {value for value in tail_values if value is not None}
        ) <= 1
        deltas_numeric = [int_value(value or 0) for value in deltas if value is not None]
        accumulates = len(deltas_numeric) == 4 and deltas_numeric == sorted(deltas_numeric) and len(set(deltas_numeric)) > 1
        if state_constant and pointer_constant and accumulates and not drain_seen:
            return "persistent_invariant_timeseries"
        if (not state_constant) or (not pointer_constant) or drain_seen:
            return "state_or_pointer_changed_across_idle_snapshots"
    return "pbm_commit_tail_invariant_observation"


def stage1a9_row_status(row: dict[str, Any]) -> str:
    config_name = str(row.get("crypto_ingress_config") or "")
    idle_residual_activity_seen = truthy(row.get("idle_residual_activity_seen"))
    crypto_valid = int_value(row.get("crypto_rx_valid_cycles", 0))
    crypto_vnr = int_value(row.get("crypto_rx_valid_not_ready_cycles", 0))
    crypto_accept = int_value(row.get("crypto_rx_accept_cycles", 0))
    pbm_activity = (
        int_value(row.get("pbm_wr_valid_cycles", 0)) > 0
        or int_value(row.get("pbm_valid_not_ready_cycles", 0)) > 0
        or int_value(row.get("pbm_wr_accept_cycles", 0)) > 0
    )
    if config_name == "IdleControl":
        return "negative_control_pass" if not idle_residual_activity_seen else "negative_control_unstable"
    if crypto_vnr > 0 and not pbm_activity:
        return "crypto_rx_without_pbm_activity_observed"
    if crypto_accept > 0 and int_value(row.get("pbm_wr_accept_cycles", 0)) == 0:
        return "crypto_rx_accept_without_pbm_accept_observed"
    if (
        int_value(row.get("pbm_commit_entry_count", 0)) > 0
        and int_value(row.get("backend_accept_cycles", 0)) == 0
        and int_value(row.get("backend_starvation_cycles", 0)) == 0
    ):
        return "pbm_commit_without_backend_service_observed"
    if int_value(row.get("pbm_commit_entry_count", 0)) > 0:
        return "pbm_commit_observed"
    if crypto_valid == 0:
        return "wrapper_classifier_dma_boundary_observation"
    return "crypto_ingress_observation"


def stage1a10_row_status(row: dict[str, Any]) -> str:
    config_name = str(row.get("crypto_dma_handoff_config") or "")
    idle_residual_activity_seen = truthy(row.get("idle_residual_activity_seen"))
    pbm_commit_seen = (
        int_value(row.get("pbm_commit_entry_count", 0)) > 0
        or int_value(row.get("pbm_ptr_head_commit_delta_mod", 0)) > 0
    )
    pbm_tail_moved = int_value(row.get("pbm_ptr_tail_delta_mod", 0)) > 0
    crypto_dma_accept = int_value(row.get("crypto_dma_in_accept_cycles", 0))
    backend_seen = any_nonzero(row, BACKEND_SERVICE_COUNTERS)
    rollback_path_observed = (
        int_value(row.get("pbm_rollback_entry_count", 0)) > 0 or any_nonzero(row, ROLLBACK_RECOVERY_COUNTERS)
    )
    rollback_trigger_candidate = int_value(row.get("pbm_wr_last_error_accepted_count", 0)) > 0
    completion_seen = int_value(row.get("crypto_dma_completion_count", 0)) > 0
    idle_counter_activity_seen = (
        int_value(row.get("pbm_committed_available_cycles", 0)) > 0
        or int_value(row.get("pbm_rd_accept_cycles", 0)) > 0
        or int_value(row.get("crypto_dma_in_valid_cycles", 0)) > 0
        or int_value(row.get("crypto_dma_in_accept_cycles", 0)) > 0
        or backend_seen
    )
    if config_name == "IdleControl":
        return (
            "negative_control_pass"
            if not (idle_residual_activity_seen or idle_counter_activity_seen)
            else "negative_control_unstable"
        )
    if rollback_path_observed or rollback_trigger_candidate:
        return "rollback_trigger_candidate_observed"
    if pbm_commit_seen and not pbm_tail_moved:
        return "pbm_read_visibility_gap_observed"
    if pbm_tail_moved and crypto_dma_accept == 0:
        return "crypto_dma_ingress_backpressure_observed"
    if crypto_dma_accept > 0 and not backend_seen:
        return "backend_input_gating_observed"
    if crypto_dma_accept > 0 and backend_seen and not completion_seen:
        return "backend_input_gating_observed"
    if completion_seen:
        return "completion_writeback_observed"
    if pbm_commit_seen:
        return "crypto_dma_handoff_observation"
    return "crypto_dma_handoff_inconclusive"


def stage1a11_row_status(row: dict[str, Any]) -> str:
    config_name = str(row.get("pbm_read_side_config") or "")
    idle_residual_activity_seen = truthy(row.get("idle_residual_activity_seen"))
    pbm_commit_seen = (
        int_value(row.get("pbm_commit_entry_count", 0)) > 0
        or int_value(row.get("pbm_ptr_head_commit_delta_mod", 0)) > 0
    )
    bridge_rd_en_seen = int_value(row.get("bridge_pbm_rd_en_cycles", 0)) > 0
    bridge_fire_seen = int_value(row.get("bridge_pbm_fire_count", 0)) > 0
    data_without_inst_available = int_value(row.get("bridge_data_available_no_inst_available_cycles", 0)) > 0
    dma_start_seen = int_value(row.get("dma_start_seen_count", 0)) > 0
    dma_progress_seen = (
        dma_start_seen
        or int_value(row.get("dma_addr_cycles", 0)) > 0
        or int_value(row.get("dma_data_cycles", 0)) > 0
    )
    dma_w_handshake_seen = int_value(row.get("dma_w_handshake_count", 0)) > 0
    dma_wready_backpressure_seen = int_value(row.get("dma_wready_low_cycles", 0)) > 0
    rollback_path_observed = (
        int_value(row.get("pbm_rollback_entry_count", 0)) > 0 or any_nonzero(row, ROLLBACK_RECOVERY_COUNTERS)
    )
    rollback_trigger_candidate = int_value(row.get("pbm_wr_last_error_accepted_count", 0)) > 0
    if config_name == "IdleControl":
        return "negative_control_pass" if not idle_residual_activity_seen else "negative_control_unstable"
    if rollback_path_observed or rollback_trigger_candidate:
        return "rollback_trigger_candidate_observed"
    if pbm_commit_seen and not bridge_rd_en_seen and data_without_inst_available:
        return "crypto_bridge_availability_gap_observed"
    if bridge_fire_seen and not dma_progress_seen:
        return "dma_transfer_start_gap_observed"
    if dma_progress_seen and not dma_w_handshake_seen and dma_wready_backpressure_seen:
        return "dma_write_channel_backpressure_observed"
    if dma_w_handshake_seen:
        return "dma_write_progress_observed"
    return "pbm_read_side_inconclusive"


def stage1a12_row_status(row: dict[str, Any]) -> str:
    config_name = str(row.get("bridge_output_fifo_config") or "")
    bridge_nonempty_seen = int_value(row.get("bridge_tx_nonempty_cycles", 0)) > 0
    bridge_rd_en_seen = int_value(row.get("bridge_tx_rd_en_cycles", 0)) > 0
    bridge_accept_seen = int_value(row.get("bridge_tx_accept_cycles", 0)) > 0
    bridge_last_seen = int_value(row.get("bridge_tx_last_seen_count", 0)) > 0
    dma_start_seen = int_value(row.get("dma_start_seen_count", 0)) > 0
    backend_seen = any_nonzero(row, BACKEND_SERVICE_COUNTERS)
    idle_residual_activity_seen = (
        truthy(row.get("idle_residual_activity_seen"))
        or bridge_nonempty_seen
        or bridge_rd_en_seen
        or bridge_accept_seen
        or bridge_last_seen
    )
    if config_name == "IdleControl":
        return "negative_control_pass" if not idle_residual_activity_seen else "negative_control_unstable"
    if bridge_accept_seen and backend_seen:
        return "bridge_accept_with_backend_service_observed"
    if bridge_accept_seen:
        return "bridge_accept_without_backend_service_observed"
    if bridge_rd_en_seen and not bridge_accept_seen:
        return "bridge_rd_en_without_accept_observed"
    if bridge_nonempty_seen and not dma_start_seen:
        return "dma_start_path_absent_observed"
    if bridge_nonempty_seen and not bridge_rd_en_seen:
        return "dma_rd_enable_gating_observed"
    return "bridge_output_fifo_observation"


def stage1a13_row_status(row: dict[str, Any]) -> str:
    config_name = str(row.get("dma_start_path_config") or "")
    bridge_nonempty_seen = int_value(row.get("bridge_tx_nonempty_cycles", 0)) > 0
    csr_start_seen = int_value(row.get("csr_start_pulse_count", 0)) > 0
    final_start_seen = int_value(row.get("final_start_pulse_count", 0)) > 0
    dma_start_seen = int_value(row.get("dma_start_seen_count", 0)) > 0
    dma_busy_seen = int_value(row.get("dma_busy_cycles", 0)) > 0
    bridge_rd_en_seen = int_value(row.get("bridge_tx_rd_en_cycles", 0)) > 0
    bridge_accept_seen = int_value(row.get("bridge_tx_accept_cycles", 0)) > 0
    if config_name == "Current_Bypass_NoExplicitStart":
        if bridge_nonempty_seen and not csr_start_seen and not final_start_seen and not dma_start_seen:
            return "start_source_absent_observed"
        return "dma_start_path_observation"
    if csr_start_seen and not final_start_seen:
        return "csr_start_without_final_start_observed"
    if final_start_seen and not dma_start_seen and not dma_busy_seen:
        return "final_start_without_dma_activation_observed"
    if (dma_start_seen or dma_busy_seen) and not bridge_rd_en_seen:
        return "dma_active_but_no_rd_en_observed"
    if bridge_rd_en_seen and not bridge_accept_seen:
        return "rd_en_without_accept_observed"
    if bridge_accept_seen:
        return "explicit_start_chain_observed"
    return "dma_start_path_observation"


def stage1a14_row_status(row: dict[str, Any]) -> str:
    axil_control_seen = int_value(row.get("axil_write_hit_control_count", 0)) > 0
    axil_start_seen = int_value(row.get("axil_write_hit_start_count", 0)) > 0
    csr_start_seen = int_value(row.get("csr_start_pulse_count", 0)) > 0
    final_start_seen = int_value(row.get("final_start_pulse_count", 0)) > 0
    dma_start_seen = int_value(row.get("dma_start_seen_count", 0)) > 0
    bridge_rd_en_seen = int_value(row.get("bridge_tx_rd_en_cycles", 0)) > 0
    if axil_control_seen and not axil_start_seen and not csr_start_seen:
        return "probe_write_observed_but_no_csr_start"
    if csr_start_seen and not final_start_seen:
        return "csr_start_seen_but_no_final_start"
    if final_start_seen and not dma_start_seen:
        return "final_start_seen_but_no_dma_start"
    if dma_start_seen and not bridge_rd_en_seen:
        return "dma_start_seen_then_rd_en_absent"
    if dma_start_seen and bridge_rd_en_seen:
        return "start_chain_alive"
    return "start_pulse_injection_observation"


def stage1a15_row_status(row: dict[str, Any]) -> str:
    explicit_timing = str(row.get("explicit_start_timing") or "none")
    explicit_expected = explicit_timing != "none"
    axil_start_seen = int_value(row.get("axil_write_hit_start_count", 0)) > 0
    csr_start_seen = int_value(row.get("csr_start_pulse_count", 0)) > 0
    final_start_seen = int_value(row.get("final_start_pulse_count", 0)) > 0
    dma_start_seen = int_value(row.get("dma_start_seen_count", 0)) > 0
    dma_busy_seen = int_value(row.get("dma_busy_cycles", 0)) > 0
    source_reader_busy_seen = int_value(row.get("source_reader_busy_cycles", 0)) > 0
    bridge_nonempty_seen = int_value(row.get("bridge_tx_nonempty_cycles", 0)) > 0
    bridge_rd_en_seen = int_value(row.get("bridge_tx_rd_en_cycles", 0)) > 0
    bridge_accept_seen = int_value(row.get("bridge_tx_accept_cycles", 0)) > 0
    crypto_accept_seen = int_value(row.get("crypto_dma_in_accept_cycles", 0)) > 0
    backend_seen = any_nonzero(row, BACKEND_SERVICE_COUNTERS)
    if not explicit_expected:
        if bridge_nonempty_seen and not dma_start_seen and not bridge_rd_en_seen:
            return "no_start_baseline_bridge_nonempty_observed"
        return "no_start_baseline_observation"
    if not axil_start_seen or not csr_start_seen:
        return "explicit_start_not_verified_by_hardware"
    if dma_start_seen and not bridge_nonempty_seen:
        return "explicit_start_without_bridge_data_observed"
    if dma_start_seen and bridge_nonempty_seen and (dma_busy_seen or source_reader_busy_seen) and not bridge_rd_en_seen:
        return "dma_rd_enable_gating_observed"
    if bridge_rd_en_seen and not bridge_accept_seen:
        return "rd_en_without_bridge_accept_observed"
    if bridge_accept_seen and not crypto_accept_seen:
        return "bridge_accept_without_crypto_dma_accept_observed"
    if crypto_accept_seen and not backend_seen:
        return "crypto_dma_accept_without_backend_service_observed"
    if crypto_accept_seen and backend_seen:
        return "backend_input_progress_observed"
    return "explicit_start_bridge_handoff_observation"


def stage1a26_row_status(row: dict[str, Any]) -> str:
    loopback_mode = int_value(row.get("dma_rd_en_loopback_mode_raw", 0))
    runtime_bypass = truthy(row.get("runtime_ring_bypass_enabled"))
    tx_ready = int_value(row.get("dma_rd_en_tx_axis_tready_cycles", 0)) > 0
    nonempty = int_value(row.get("dma_rd_en_crypto_to_dma_nonempty_cycles", 0)) > 0
    tx_ready_when_nonempty = int_value(row.get("dma_rd_en_tx_ready_when_nonempty_cycles", 0)) > 0
    dma_req_rd = int_value(row.get("dma_rd_en_dma_req_rd_cycles", 0)) > 0
    loopback_candidate = int_value(row.get("dma_rd_en_loopback_branch_candidate_cycles", 0)) > 0
    bridge_rd_en = int_value(row.get("bridge_tx_rd_en_cycles", 0)) > 0
    bridge_accept = int_value(row.get("bridge_tx_accept_cycles", 0)) > 0
    if runtime_bypass and loopback_mode != 2:
        return "loopback_mode_control_mismatch_observed"
    if loopback_mode == 2 and not tx_ready:
        return "tx_axis_tready_absent_observed"
    if loopback_mode == 2 and nonempty and not tx_ready_when_nonempty:
        return "tx_ready_absent_while_nonempty_observed"
    if loopback_mode != 2 and not dma_req_rd:
        return "normal_branch_dma_req_rd_absent_observed"
    if loopback_candidate and not bridge_rd_en:
        return "equation_true_but_rd_en_low_observed"
    if bridge_rd_en and not bridge_accept:
        return "rd_en_without_bridge_accept_observed"
    if bridge_rd_en and bridge_accept:
        return "rd_en_and_bridge_accept_observed"
    return "dma_rd_en_equation_observation"


def percentile(values: list[float], pct: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = (len(ordered) - 1) * pct
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return ordered[int(rank)]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (rank - lower)


def summarize_values(values: list[float]) -> dict[str, Any]:
    values = [float(value) for value in values if value is not None]
    if not values:
        return {
            "count": 0,
            "mean": None,
            "std": None,
            "min": None,
            "max": None,
            "p50": None,
            "p95": None,
            "p99": None,
            "IQR": None,
            "p95_minus_p50": None,
            "bootstrap_95_ci": [None, None],
        }

    p50 = percentile(values, 0.50)
    p25 = percentile(values, 0.25)
    p75 = percentile(values, 0.75)
    p95 = percentile(values, 0.95)
    p99 = percentile(values, 0.99)
    return {
        "count": len(values),
        "mean": statistics.fmean(values),
        "std": statistics.stdev(values) if len(values) > 1 else 0.0,
        "min": min(values),
        "max": max(values),
        "p50": p50,
        "p95": p95,
        "p99": p99,
        "IQR": None if p25 is None or p75 is None else p75 - p25,
        "p95_minus_p50": None if p95 is None or p50 is None else p95 - p50,
        "bootstrap_95_ci": bootstrap_mean_ci(values),
    }


def bootstrap_mean_ci(values: list[float], samples: int = 200, seed: int = 20260423) -> list[float | None]:
    if not values:
        return [None, None]
    rng = random.Random(seed)
    means = []
    for _ in range(samples):
        draw = [values[rng.randrange(0, len(values))] for _ in values]
        means.append(statistics.fmean(draw))
    return [percentile(means, 0.025), percentile(means, 0.975)]


def classify_row(case: dict[str, Any], row: dict[str, Any]) -> tuple[str, str | None]:
    delta = case.get("delta", {})
    recovery_seen = any(int(delta.get(field, 0) or 0) > 0 for field in ROLLBACK_RECOVERY_COUNTERS)
    backend_seen = any(int(delta.get(field, 0) or 0) > 0 for field in BACKEND_SERVICE_COUNTERS)
    fault_seen = int(delta.get("drop_wrong_port_count", 0) or 0) > 0 or int(
        delta.get("drop_unaligned_count", 0) or 0
    ) > 0

    if recovery_seen:
        return "valid_positive_recovery", None
    if fault_seen:
        return "valid_negative", "negative_fault_observed_no_recovery"
    if backend_seen:
        return "valid_negative", "negative_backend_activity_only"
    return "valid_negative", "negative_no_backend_activity"


def make_case_rows(summary: dict[str, Any], args: argparse.Namespace) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    cases = summary.get("cases", [])
    repo_root = Path(args.repo_root)
    pbm_depth = parse_pbm_depth(repo_root)
    fault_sequence = build_fault_sequence(
        repeat_count=max(1, int(args.repeat_count)),
        fault_ratio=float(args.fault_ratio),
        fault_mode=args.fault_mode,
        noise_pattern=args.noise_pattern,
        seed=int(args.fault_schedule_seed),
    )
    sequence_digest = digest_fault_sequence(fault_sequence)

    for case_index, case in enumerate(cases):
        case_instance_name = case.get("name", "case")
        case_base_name = case.get("base_name") or str(case_instance_name).split(".", 1)[-1]
        case_repeat = int(case.get("repeat", 1) or 1)
        case_burst_frames = case.get("burst_frames", args.burst_frames)
        case_burst_gap_us = case.get("burst_gap_us", args.burst_gap_us)
        case_settle_ms = case.get("settle_ms", args.settle_ms)
        row_burst_frames = int(args.burst_frames if case_burst_frames in (None, "") else case_burst_frames)
        row_burst_gap_us = float(args.burst_gap_us if case_burst_gap_us in (None, "") else case_burst_gap_us)
        row_settle_ms = float(args.settle_ms if case_settle_ms in (None, "") else case_settle_ms)
        delta = case.get("delta", {})
        pre = case.get("pre", {})
        post = case.get("post", {})
        backend_total = int(delta.get("backend_total_cycles", 0) or 0)
        backend_accept = int(delta.get("backend_accept_cycles", 0) or 0)
        backend_starvation = int(delta.get("backend_starvation_cycles", 0) or 0)
        recovery_active = int(delta.get("recovery_active_cycles", 0) or 0)
        recovery_last = int(delta.get("recovery_last_window_cycles", 0) or 0)
        effective_denominator = backend_accept + backend_starvation
        configured_frames_per_s = configured_injection_intensity(args, row_burst_frames, row_burst_gap_us, row_settle_ms)
        observed_frames_per_window = case.get("observed_injection_intensity_frames_per_probe_window", backend_accept)
        validation_status, negative_result_type = classify_row(case, {})
        if args.stage == "Stage1A_DropPulseAudit":
            validation_status = "valid_negative"
            negative_result_type = "negative_diagnostic_only"
        if args.stage == "Stage1A6_PriorDropPulseReproduction":
            validation_status = "valid_negative"
            negative_result_type = "negative_diagnostic_only"
        if args.stage == "Stage1A7_DropPulseConditionDiffDiagnosis":
            validation_status = "valid_negative"
            negative_result_type = "negative_diagnostic_only"
        if args.stage == "Stage1A8_PBMIngressVisibilityDiagnosis":
            validation_status = "valid_negative"
            negative_result_type = "negative_diagnostic_only"
        if args.stage == "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis":
            validation_status = "valid_negative"
            negative_result_type = "negative_diagnostic_only"
        if args.stage == "Stage1A10_CryptoDMAHandoffDiagnosis":
            validation_status = "valid_negative"
            negative_result_type = "negative_diagnostic_only"
        if args.stage == "Stage1A11_PBMReadSideVisibilityDiagnosis":
            validation_status = "valid_negative"
            negative_result_type = "negative_diagnostic_only"
        if args.stage == "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis":
            validation_status = "valid_negative"
            negative_result_type = "negative_diagnostic_only"
        if args.stage == "Stage1A13_DMAStartPathDiagnosis":
            validation_status = "valid_negative"
            negative_result_type = "negative_diagnostic_only"
        if args.stage == "Stage1A14_StartPulseInjectionOrProbeControlFix":
            validation_status = "valid_negative"
            negative_result_type = "negative_diagnostic_only"
        if args.stage == "Stage1A21_PBMReadyGatingDiagnosis":
            validation_status = "valid_negative"
            negative_result_type = "negative_diagnostic_only"
        stage_status = row_stage_status(case_base_name, case, validation_status, negative_result_type)
        probe_window_id = case.get("probe_window_id")
        if not probe_window_id:
            if args.stage == "Stage1A_DropPulseAudit":
                audit_config = case.get("audit_config", "UnknownAuditConfig")
                probe_window_id = (
                    f"Stage1A_DropPulseAudit:{audit_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A6_PriorDropPulseReproduction":
                reproduction_config = case.get("reproduction_config", "UnknownReplayConfig")
                probe_window_id = (
                    f"Stage1A6_PriorDropPulseReproduction:{reproduction_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A7_DropPulseConditionDiffDiagnosis":
                condition_config = case.get("condition_diff_config", "UnknownConditionConfig")
                probe_window_id = (
                    f"Stage1A7_DropPulseConditionDiffDiagnosis:{condition_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A8_PBMIngressVisibilityDiagnosis":
                visibility_config = case.get("pbm_visibility_config", "UnknownVisibilityConfig")
                probe_window_id = (
                    f"Stage1A8_PBMIngressVisibilityDiagnosis:{visibility_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis":
                crypto_ingress_config = case.get("crypto_ingress_config", "UnknownCryptoIngressConfig")
                probe_window_id = (
                    f"Stage1A9_CryptoIngressHandoffVisibilityDiagnosis:{crypto_ingress_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A10_CryptoDMAHandoffDiagnosis":
                crypto_dma_handoff_config = case.get("crypto_dma_handoff_config", "UnknownCryptoDMAHandoffConfig")
                probe_window_id = (
                    f"Stage1A10_CryptoDMAHandoffDiagnosis:{crypto_dma_handoff_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A11_PBMReadSideVisibilityDiagnosis":
                pbm_read_side_config = case.get("pbm_read_side_config", "UnknownPBMReadSideConfig")
                probe_window_id = (
                    f"Stage1A11_PBMReadSideVisibilityDiagnosis:{pbm_read_side_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis":
                bridge_output_fifo_config = case.get("bridge_output_fifo_config", "UnknownBridgeOutputFIFOConfig")
                probe_window_id = (
                    f"Stage1A12_BridgeOutputFIFOVisibilityDiagnosis:{bridge_output_fifo_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A13_DMAStartPathDiagnosis":
                dma_start_path_config = case.get("dma_start_path_config", "UnknownDMAStartPathConfig")
                probe_window_id = (
                    f"Stage1A13_DMAStartPathDiagnosis:{dma_start_path_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A14_StartPulseInjectionOrProbeControlFix":
                start_pulse_config = case.get("start_pulse_injection_config", "UnknownStartPulseConfig")
                probe_window_id = (
                    f"Stage1A14_StartPulseInjectionOrProbeControlFix:{start_pulse_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A15_ExplicitStartBridgeHandoffDiagnosis":
                bridge_handoff_config = case.get(
                    "explicit_start_bridge_handoff_config", "UnknownBridgeHandoffConfig"
                )
                probe_window_id = (
                    f"Stage1A15_ExplicitStartBridgeHandoffDiagnosis:{bridge_handoff_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A16_BridgeDataProductionDiagnosis":
                bridge_data_config = case.get(
                    "bridge_data_production_config", "UnknownBridgeDataProductionConfig"
                )
                probe_window_id = (
                    f"Stage1A16_BridgeDataProductionDiagnosis:{bridge_data_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A17_PBMCommitReproductionDiagnosis":
                pbm_commit_config = case.get(
                    "pbm_commit_reproduction_config", "UnknownPBMCommitReproductionConfig"
                )
                probe_window_id = (
                    f"Stage1A17_PBMCommitReproductionDiagnosis:{pbm_commit_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A26_DMARdEnableEquationDiagnosis":
                dma_rd_en_equation_config = case.get(
                    "dma_rd_en_equation_config", "UnknownDMARdEnEquationConfig"
                )
                probe_window_id = (
                    f"Stage1A26_DMARdEnableEquationDiagnosis:{dma_rd_en_equation_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis":
                upstream_ingress_config = case.get(
                    "upstream_ingress_to_pbm_visibility_config",
                    "UnknownUpstreamIngressToPBMConfig",
                )
                probe_window_id = (
                    f"Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis:{upstream_ingress_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A19_InjectionSourceEmissionDiagnosis":
                injection_source_config = case.get(
                    "injection_source_emission_config",
                    "UnknownInjectionSourceEmissionConfig",
                )
                probe_window_id = (
                    f"Stage1A19_InjectionSourceEmissionDiagnosis:{injection_source_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A20_InjectionSourceArmingDiagnosis":
                injection_arming_config = case.get(
                    "injection_source_arming_config",
                    "UnknownInjectionSourceArmingConfig",
                )
                probe_window_id = (
                    f"Stage1A20_InjectionSourceArmingDiagnosis:{injection_arming_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A21_PBMReadyGatingDiagnosis":
                pbm_ready_gating_config = case.get(
                    "pbm_ready_gating_config",
                    "UnknownPBMReadyGatingConfig",
                )
                probe_window_id = (
                    f"Stage1A21_PBMReadyGatingDiagnosis:{pbm_ready_gating_config}:"
                    f"bf{row_burst_frames:04d}:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            elif args.stage == "Stage1A_BurstSweep":
                probe_window_id = (
                    f"Stage1A_BurstSweep:bf{row_burst_frames:04d}:"
                    f"bg{int(round(row_burst_gap_us)):04d}us:"
                    f"sm{int(round(row_settle_ms)):04d}ms:"
                    f"r{case_repeat:02d}:{case_base_name}"
                )
            else:
                probe_window_id = f"{args.stage}:r{case_repeat:02d}:{case_base_name}"
        inj_status_raw = case.get("inj_status_active")
        netdbg_status_raw = post.get("netdbg_status")
        inj_status_decoded = decode_inj_status(inj_status_raw)
        inj_source_state_decoded = decode_injection_source_state(
            case.get("inj_source_state_raw", post.get("inj_source_state_raw", 0))
        )
        netdbg_decoded = decode_netdbg_status(netdbg_status_raw)
        pbm_state_raw = case.get("pbm_state_raw", post.get("pbm_state_raw", 0))
        pbm_state_decoded = decode_pbm_state(pbm_state_raw, repo_root)
        pbm_ptr_head_reserve_pre = case.get("pbm_ptr_head_reserve_pre", pre.get("pbm_ptr_head_reserve"))
        pbm_ptr_head_reserve_post = case.get("pbm_ptr_head_reserve", post.get("pbm_ptr_head_reserve"))
        pbm_ptr_head_commit_pre = case.get("pbm_ptr_head_commit_pre", pre.get("pbm_ptr_head_commit"))
        pbm_ptr_head_commit_post = case.get("pbm_ptr_head_commit", post.get("pbm_ptr_head_commit"))
        pbm_ptr_tail_pre = case.get("pbm_ptr_tail_pre", pre.get("pbm_ptr_tail"))
        pbm_ptr_tail_post = case.get("pbm_ptr_tail", post.get("pbm_ptr_tail"))
        pbm_buffer_usage_pre = case.get("pbm_buffer_usage_pre", pre.get("pbm_buffer_usage"))
        pbm_buffer_usage_post = case.get("pbm_buffer_usage", post.get("pbm_buffer_usage"))
        def case_or_snapshot_delta(field: str) -> Any:
            if case.get(field) not in (None, ""):
                return case.get(field)
            if pre.get(field) not in (None, "") and post.get(field) not in (None, ""):
                return int_value(post.get(field)) - int_value(pre.get(field))
            return post.get(field)

        row = {
            "probe_window_id": probe_window_id,
            "stage": args.stage,
            "stage_status": stage_status,
            "case": case_base_name,
            "case_instance": case_instance_name,
            "audit_config": case.get("audit_config", ""),
            "reproduction_config": case.get("reproduction_config", ""),
            "condition_diff_config": case.get("condition_diff_config", ""),
            "pbm_visibility_config": case.get("pbm_visibility_config", ""),
            "crypto_ingress_config": case.get("crypto_ingress_config", ""),
            "crypto_dma_handoff_config": case.get("crypto_dma_handoff_config", ""),
            "pbm_read_side_config": case.get("pbm_read_side_config", ""),
            "bridge_output_fifo_config": case.get("bridge_output_fifo_config", ""),
            "dma_start_path_config": case.get("dma_start_path_config", ""),
            "explicit_start_bridge_handoff_config": case.get("explicit_start_bridge_handoff_config", ""),
            "bridge_data_production_config": case.get("bridge_data_production_config", ""),
            "pbm_commit_reproduction_config": case.get("pbm_commit_reproduction_config", ""),
            "dma_rd_en_equation_config": case.get("dma_rd_en_equation_config", ""),
            "upstream_ingress_to_pbm_visibility_config": case.get(
                "upstream_ingress_to_pbm_visibility_config", ""
            ),
            "injection_source_emission_config": case.get("injection_source_emission_config", ""),
            "injection_source_arming_config": case.get("injection_source_arming_config", ""),
            "pbm_ready_gating_config": case.get("pbm_ready_gating_config", ""),
            "pbm_pointer_reset_or_drain_config": case.get("pbm_pointer_reset_or_drain_config", ""),
            "pbm_commit_tail_invariant_config": case.get("pbm_commit_tail_invariant_config", ""),
            "stage1a8_snapshot_mode": case.get("stage1a8_snapshot_mode", ""),
            "stage1a9_snapshot_mode": case.get("stage1a9_snapshot_mode", ""),
            "stage1a10_snapshot_mode": case.get("stage1a10_snapshot_mode", ""),
            "stage1a11_snapshot_mode": case.get("stage1a11_snapshot_mode", ""),
            "stage1a12_snapshot_mode": case.get("stage1a12_snapshot_mode", ""),
            "stage1a17_snapshot_mode": case.get("stage1a17_snapshot_mode", ""),
            "stage1a18_snapshot_mode": case.get("stage1a18_snapshot_mode", ""),
            "stage1a19_snapshot_mode": case.get("stage1a19_snapshot_mode", ""),
            "stage1a21_snapshot_mode": case.get("stage1a21_snapshot_mode", ""),
            "stage1a22_reset_mode": case.get("stage1a22_reset_mode", ""),
            "stage1a23_reset_mode": case.get("stage1a23_reset_mode", ""),
            "stage1a23_snapshot_mode": case.get("stage1a23_snapshot_mode", ""),
            "configured_burst_frames": case.get("configured_burst_frames"),
            "configured_frame_word_count": case.get("configured_frame_word_count"),
            "inj_ctrl_read_before": hex32_or_none(case.get("inj_ctrl_read_before")),
            "inj_ctrl_read_after": hex32_or_none(case.get("inj_ctrl_read_after")),
            "inj_frame_length_readback": case.get("inj_frame_length_readback"),
            "inj_config_valid": case.get("inj_config_valid"),
            "reproduction_mode": case.get("reproduction_mode", args.reproduction_mode),
            "repeat": case_repeat,
            "TrafficMode": args.traffic_mode,
            "FaultMode": args.fault_mode,
            "FaultRatio": args.fault_ratio,
            "noise_pattern": args.noise_pattern,
            "BurstFrames": row_burst_frames,
            "BurstGapUs": row_burst_gap_us,
            "SettleMs": row_settle_ms,
            "frame_size": args.frame_size,
            "load_class": args.load_class,
            "random_seed": args.random_seed,
            "fault_schedule_seed": args.fault_schedule_seed,
            "fault_sequence_digest": sequence_digest,
            "fault_severity_value": args.fault_severity_value,
            "fault_severity_unit": args.fault_severity_unit,
            "fault_severity_note": args.fault_severity_note,
            "fault_severity_normalized": normalize_fault_severity(
                args.fault_severity_value,
                args.fault_severity_unit,
            ),
            "validation_status": validation_status,
            "negative_result_type": negative_result_type,
            "candidate_for_paper_evidence": "no",
            "why_it_is_or_is_not_candidate": "recovery/high-water/drop/rollback counters did not meet paper-ready recovery gate",
            "evidence_risk": "high" if negative_result_type else "medium",
            "inj_status_active": inj_status_raw,
            "netdbg_status": netdbg_status_raw,
            "inj_ctrl_write_hit_count": case_or_snapshot_delta("inj_ctrl_write_hit_count"),
            "inj_clear_write_hit_count": case_or_snapshot_delta("inj_clear_write_hit_count"),
            "inj_frame_word_write_hit_count": case_or_snapshot_delta("inj_frame_word_write_hit_count"),
            "inj_expected_words_write_hit_count": case_or_snapshot_delta("inj_expected_words_write_hit_count"),
            "inj_source_state_raw": inj_source_state_decoded["inj_source_state_raw"],
            "inj_source_state_decoded": inj_source_state_decoded["inj_source_state_decoded"],
            "inj_fifo_write_count": case_or_snapshot_delta("inj_fifo_write_count"),
            "inj_fifo_level_pre": case.get("inj_fifo_level_pre", pre.get("inj_fifo_level")),
            "inj_fifo_level_post": case.get("inj_fifo_level_post", post.get("inj_fifo_level")),
            "inj_fifo_level_max": case.get("inj_fifo_level_max", post.get("inj_fifo_level_max")),
            "inj_source_idle_cycles": case_or_snapshot_delta("inj_source_idle_cycles"),
            "inj_source_armed_cycles": case_or_snapshot_delta("inj_source_armed_cycles"),
            "inj_source_active_cycles": case_or_snapshot_delta("inj_source_active_cycles"),
            "inj_source_done_count": case_or_snapshot_delta("inj_source_done_count"),
            "inj_source_emitting_cycles": case_or_snapshot_delta("inj_source_emitting_cycles"),
            "stage1_inject_tvalid_cycles": case_or_snapshot_delta("stage1_inject_tvalid_cycles"),
            "stage1_inject_tready_cycles": case_or_snapshot_delta("stage1_inject_tready_cycles"),
            "stage1_inject_fire_cycles": case_or_snapshot_delta("stage1_inject_fire_cycles"),
            "stage1_inject_last_seen_count": case_or_snapshot_delta("stage1_inject_last_seen_count"),
            "audit_pre_snapshot_after_clear_nonzero": case.get("audit_pre_snapshot_after_clear_nonzero"),
            "repro_pre_snapshot_after_clear_nonzero": case.get("repro_pre_snapshot_after_clear_nonzero"),
            "audit_idle_no_frame_injection": case.get("audit_idle_no_frame_injection"),
            "source_progress_pre": case.get("source_progress_pre"),
            "source_progress_post": case.get("source_progress_post"),
            "sink_progress_pre": case.get("sink_progress_pre"),
            "sink_progress_post": case.get("sink_progress_post"),
            "runtime_ring_bypass_enabled": case.get("runtime_ring_bypass_enabled"),
            "fastpath_enabled": case.get("fastpath_enabled"),
            "ring_size_zero": case.get("ring_size_zero"),
            "stage1a13_explicit_csr_start": case.get("stage1a13_explicit_csr_start"),
            "csr_start_pulsed_by_probe": case.get("csr_start_pulsed_by_probe"),
            "start_pulse_injection_config": case.get("start_pulse_injection_config"),
            "explicit_start_timing": case.get("explicit_start_timing", ""),
            "start_delay_ms": case.get("start_delay_ms"),
            "shadow_control_base": hex32_or_none(case.get("shadow_control_base")),
            "dma_csr_base": hex32_or_none(case.get("dma_csr_base")),
            "explicit_csr_start_pulsed_by_probe": case.get(
                "explicit_csr_start_pulsed_by_probe", case.get("csr_start_pulsed_by_probe")
            ),
            "explicit_start_write_addr": hex32_or_none(case.get("explicit_start_write_addr")),
            "explicit_start_write_value": hex32_or_none(case.get("explicit_start_write_value")),
            "explicit_start_write_mask_or_wstrb": hex32_or_none(case.get("explicit_start_write_mask_or_wstrb")),
            "explicit_start_readback_before": hex32_or_none(case.get("explicit_start_readback_before")),
            "explicit_start_readback_after": hex32_or_none(case.get("explicit_start_readback_after")),
            "explicit_start_readback_after_clear": hex32_or_none(case.get("explicit_start_readback_after_clear")),
            "dma_ctrl_read_before": hex32_or_none(case.get("dma_ctrl_read_before")),
            "dma_ctrl_read_after": hex32_or_none(case.get("dma_ctrl_read_after")),
            "dma_ctrl_changed_bits": hex32_or_none(case.get("dma_ctrl_changed_bits")),
            "start_bit_mask": hex32_or_none(case.get("start_bit_mask", 1)),
            "explicit_start_changed_control_state": None,
            "explicit_start_write_addr_matches_dma_csr_base": case.get("explicit_start_write_addr_matches_dma_csr_base"),
            "explicit_start_verified_by_hardware": None,
            "row_level_start_and_bridge_nonempty_seen": None,
            "dma_or_source_reader_busy_seen": None,
            "a15_after_start_bridge_nonempty_seen": None,
            "a15_after_start_explicit_start_verified": None,
            "a15_after_start_dma_start_seen": None,
            "explicit_start_and_bridge_nonempty_same_row_seen": None,
            "csr_control_reg_addr_expected": hex32_or_none(case.get("csr_control_reg_addr_expected")),
            "csr_start_bit_expected": case.get("csr_start_bit_expected"),
            "start_path_expected_source": case.get("start_path_expected_source"),
            "idle_control_quiesce_guard_ms": case.get("idle_control_quiesce_guard_ms"),
            "idle_pre_after_clear_zero": case.get("idle_pre_after_clear_zero"),
            "idle_residual_activity_seen": case.get("idle_residual_activity_seen"),
            "dma_soft_reset_pulsed": case.get("dma_soft_reset_pulsed"),
            "backend_window_cycles": backend_total,
            "backend_accept_cycles_numerator": backend_accept,
            "backend_total_cycles_denominator": backend_total,
            "backend_accept_ratio": safe_ratio(backend_accept, backend_total),
            "backend_starvation_cycles_numerator": backend_starvation,
            "backend_starvation_ratio": safe_ratio(backend_starvation, backend_total),
            "effective_work_numerator": backend_accept,
            "effective_work_denominator": effective_denominator,
            "effective_work_ratio": safe_ratio(backend_accept, effective_denominator),
            "recovery_time_ms": recovery_active / float(args.clock_hz) * 1000.0,
            "recovery_window_ms": recovery_last / float(args.clock_hz) * 1000.0,
            "configured_injection_intensity_frames_per_s": configured_frames_per_s,
            "configured_injection_intensity_bytes_per_s": configured_frames_per_s * int(args.frame_size),
            "configured_injection_intensity_frames_per_probe_window": row_burst_frames,
            "observed_injection_intensity_frames_per_probe_window": observed_frames_per_window,
            "drop_wrong_port_count": delta.get("drop_wrong_port_count", 0),
            "drop_unaligned_count": delta.get("drop_unaligned_count", 0),
            "pbm_wr_valid_cycles": case.get("pbm_wr_valid_cycles", post.get("pbm_wr_valid_cycles", 0)),
            "pbm_wr_ready_high_cycles": case.get("pbm_wr_ready_high_cycles", post.get("pbm_wr_ready_high_cycles", 0)),
            "pbm_valid_not_ready_cycles": case.get("pbm_valid_not_ready_cycles", post.get("pbm_valid_not_ready_cycles", 0)),
            "pbm_wr_accept_cycles": case.get("pbm_wr_accept_cycles", post.get("pbm_wr_accept_cycles", 0)),
            "pbm_wr_last_accepted_count": case.get("pbm_wr_last_accepted_count", post.get("pbm_wr_last_accepted_count", 0)),
            "pbm_wr_error_accepted_count": case.get("pbm_wr_error_accepted_count", post.get("pbm_wr_error_accepted_count", 0)),
            "pbm_wr_last_error_accepted_count": case.get("pbm_wr_last_error_accepted_count", post.get("pbm_wr_last_error_accepted_count", 0)),
            "pbm_alloc_meta_entry_count": case.get("pbm_alloc_meta_entry_count", post.get("pbm_alloc_meta_entry_count", 0)),
            "pbm_alloc_pbm_entry_count": case.get("pbm_alloc_pbm_entry_count", post.get("pbm_alloc_pbm_entry_count", 0)),
            "pbm_commit_entry_count": case.get("pbm_commit_entry_count", post.get("pbm_commit_entry_count", 0)),
            "pbm_rollback_entry_count": case.get("pbm_rollback_entry_count", post.get("pbm_rollback_entry_count", 0)),
            "pbm_ptr_head_reserve_pre": pbm_ptr_head_reserve_pre,
            "pbm_ptr_head_reserve_post": pbm_ptr_head_reserve_post,
            "pbm_ptr_head_reserve_delta_mod": pointer_delta_mod(pbm_ptr_head_reserve_pre, pbm_ptr_head_reserve_post, pbm_depth),
            "pbm_ptr_head_commit_pre": pbm_ptr_head_commit_pre,
            "pbm_ptr_head_commit_post": pbm_ptr_head_commit_post,
            "pbm_ptr_head_commit_delta_mod": pointer_delta_mod(pbm_ptr_head_commit_pre, pbm_ptr_head_commit_post, pbm_depth),
            "pbm_ptr_tail_pre": pbm_ptr_tail_pre,
            "pbm_ptr_tail_post": pbm_ptr_tail_post,
            "pbm_ptr_tail_delta_mod": pointer_delta_mod(pbm_ptr_tail_pre, pbm_ptr_tail_post, pbm_depth),
            "pbm_buffer_usage_pre": pbm_buffer_usage_pre,
            "pbm_buffer_usage_post": pbm_buffer_usage_post,
            "pbm_buffer_usage_delta": (
                None
                if pbm_buffer_usage_pre is None or pbm_buffer_usage_post is None
                else int_value(pbm_buffer_usage_post) - int_value(pbm_buffer_usage_pre)
            ),
            "pbm_committed_available_cycles": case.get(
                "pbm_committed_available_cycles", post.get("pbm_committed_available_cycles", 0)
            ),
            "pbm_rd_empty_cycles": case.get("pbm_rd_empty_cycles", post.get("pbm_rd_empty_cycles", 0)),
            "pbm_rd_nonempty_cycles": case.get("pbm_rd_nonempty_cycles", post.get("pbm_rd_nonempty_cycles", 0)),
            "pbm_rd_en_cycles": case.get("pbm_rd_en_cycles", post.get("pbm_rd_en_cycles", 0)),
            "pbm_rd_accept_cycles": case.get("pbm_rd_accept_cycles", post.get("pbm_rd_accept_cycles", 0)),
            "crypto_rx_valid_cycles": case.get("crypto_rx_valid_cycles", post.get("crypto_rx_valid_cycles", 0)),
            "crypto_rx_ready_high_cycles": case.get(
                "crypto_rx_ready_high_cycles", post.get("crypto_rx_ready_high_cycles", 0)
            ),
            "crypto_rx_valid_not_ready_cycles": case.get(
                "crypto_rx_valid_not_ready_cycles", post.get("crypto_rx_valid_not_ready_cycles", 0)
            ),
            "crypto_rx_accept_cycles": case.get("crypto_rx_accept_cycles", post.get("crypto_rx_accept_cycles", 0)),
            "crypto_rx_last_accepted_count": case.get(
                "crypto_rx_last_accepted_count", post.get("crypto_rx_last_accepted_count", 0)
            ),
            "crypto_rx_error_accepted_count": case.get(
                "crypto_rx_error_accepted_count", post.get("crypto_rx_error_accepted_count", 0)
            ),
            "crypto_rx_last_error_accepted_count": case.get(
                "crypto_rx_last_error_accepted_count", post.get("crypto_rx_last_error_accepted_count", 0)
            ),
            "crypto_rx_pkt_end_accepted_count": case.get(
                "crypto_rx_pkt_end_accepted_count", post.get("crypto_rx_pkt_end_accepted_count", 0)
            ),
            "crypto_dma_in_valid_cycles": case.get(
                "crypto_dma_in_valid_cycles", post.get("crypto_dma_in_valid_cycles", 0)
            ),
            "crypto_dma_in_ready_cycles": case.get(
                "crypto_dma_in_ready_cycles", post.get("crypto_dma_in_ready_cycles", 0)
            ),
            "crypto_dma_in_accept_cycles": case.get(
                "crypto_dma_in_accept_cycles", post.get("crypto_dma_in_accept_cycles", 0)
            ),
            "crypto_dma_backpressure_cycles": case.get(
                "crypto_dma_backpressure_cycles", post.get("crypto_dma_backpressure_cycles", 0)
            ),
            "crypto_dma_in_last_seen_count": case.get(
                "crypto_dma_in_last_seen_count", post.get("crypto_dma_in_last_seen_count", 0)
            ),
            "crypto_dma_completion_count": case.get(
                "crypto_dma_completion_count", post.get("crypto_dma_completion_count", 0)
            ),
            "bridge_pbm_rd_en_cycles": case.get("bridge_pbm_rd_en_cycles", post.get("bridge_pbm_rd_en_cycles", 0)),
            "bridge_pbm_fire_count": case.get("bridge_pbm_fire_count", post.get("bridge_pbm_fire_count", 0)),
            "bridge_inst_available_cycles": case.get(
                "bridge_inst_available_cycles", post.get("bridge_inst_available_cycles", 0)
            ),
            "bridge_data_available_no_inst_available_cycles": case.get(
                "bridge_data_available_no_inst_available_cycles",
                post.get("bridge_data_available_no_inst_available_cycles", 0),
            ),
            "bridge_mid_fifo_full_cycles": case.get(
                "bridge_mid_fifo_full_cycles", post.get("bridge_mid_fifo_full_cycles", 0)
            ),
            "bridge_out_fifo_full_cycles": case.get(
                "bridge_out_fifo_full_cycles", post.get("bridge_out_fifo_full_cycles", 0)
            ),
            "bridge_input_state_raw": case.get("bridge_input_state_raw", post.get("bridge_input_state_raw", 0)),
            "dma_start_seen_count": case.get("dma_start_seen_count", post.get("dma_start_seen_count", 0)),
            "dma_addr_cycles": case.get("dma_addr_cycles", post.get("dma_addr_cycles", 0)),
            "dma_data_cycles": case.get("dma_data_cycles", post.get("dma_data_cycles", 0)),
            "dma_resp_cycles": case.get("dma_resp_cycles", post.get("dma_resp_cycles", 0)),
            "dma_aw_handshake_count": case.get(
                "dma_aw_handshake_count", post.get("dma_aw_handshake_count", 0)
            ),
            "dma_w_handshake_count": case.get(
                "dma_w_handshake_count", post.get("dma_w_handshake_count", 0)
            ),
            "dma_b_handshake_count": case.get(
                "dma_b_handshake_count", post.get("dma_b_handshake_count", 0)
            ),
            "dma_wready_low_cycles": case.get(
                "dma_wready_low_cycles", post.get("dma_wready_low_cycles", 0)
            ),
            "dma_state_raw": case.get("dma_state_raw", post.get("dma_state_raw", 0)),
            "bridge_tx_nonempty_cycles": case.get(
                "bridge_tx_nonempty_cycles", post.get("bridge_tx_nonempty_cycles", 0)
            ),
            "bridge_tx_rd_en_cycles": case.get(
                "bridge_tx_rd_en_cycles", post.get("bridge_tx_rd_en_cycles", 0)
            ),
            "bridge_tx_accept_cycles": case.get(
                "bridge_tx_accept_cycles", post.get("bridge_tx_accept_cycles", 0)
            ),
            "bridge_tx_last_seen_count": case.get(
                "bridge_tx_last_seen_count", post.get("bridge_tx_last_seen_count", 0)
            ),
            "bridge_tx_wr_en_cycles": case.get(
                "bridge_tx_wr_en_cycles", post.get("bridge_tx_wr_en_cycles", 0)
            ),
            "bridge_tx_fifo_level_pre": case.get(
                "bridge_tx_fifo_level_pre", pre.get("bridge_tx_fifo_level", 0)
            ),
            "bridge_tx_fifo_level_post": case.get(
                "bridge_tx_fifo_level", post.get("bridge_tx_fifo_level", 0)
            ),
            "bridge_tx_fifo_level_max": case.get(
                "bridge_tx_fifo_level_max", post.get("bridge_tx_fifo_level_max", 0)
            ),
            "bridge_tx_empty_cycles": case.get(
                "bridge_tx_empty_cycles", post.get("bridge_tx_empty_cycles", 0)
            ),
            "bridge_tx_full_cycles": case.get(
                "bridge_tx_full_cycles", post.get("bridge_tx_full_cycles", 0)
            ),
            "bridge_tx_overflow_count": case.get(
                "bridge_tx_overflow_count", post.get("bridge_tx_overflow_count", 0)
            ),
            "csr_start_pulse_count": case.get("csr_start_pulse_count", post.get("csr_start_pulse_count", 0)),
            "ring_doorbell_pulse_count": case.get(
                "ring_doorbell_pulse_count", post.get("ring_doorbell_pulse_count", 0)
            ),
            "fetcher_start_pulse_count": case.get(
                "fetcher_start_pulse_count", post.get("fetcher_start_pulse_count", 0)
            ),
            "final_start_pulse_count": case.get(
                "final_start_pulse_count", post.get("final_start_pulse_count", 0)
            ),
            "source_reader_start_pulse_count": case.get(
                "source_reader_start_pulse_count", post.get("source_reader_start_pulse_count", 0)
            ),
            "dma_busy_cycles": case.get("dma_busy_cycles", post.get("dma_busy_cycles", 0)),
            "source_reader_busy_cycles": case.get(
                "source_reader_busy_cycles", post.get("source_reader_busy_cycles", 0)
            ),
            "axil_write_hit_control_count": case.get(
                "axil_write_hit_control_count", post.get("axil_write_hit_control_count", 0)
            ),
            "axil_write_hit_start_count": case.get(
                "axil_write_hit_start_count", post.get("axil_write_hit_start_count", 0)
            ),
            "axil_write_hit_doorbell_count": case.get(
                "axil_write_hit_doorbell_count", post.get("axil_write_hit_doorbell_count", 0)
            ),
            "dma_rd_en_loopback_mode_raw": case.get(
                "dma_rd_en_loopback_mode_raw", post.get("dma_rd_en_loopback_mode_raw", 0)
            ),
            "dma_rd_en_tx_axis_tready_cycles": case.get(
                "dma_rd_en_tx_axis_tready_cycles", post.get("dma_rd_en_tx_axis_tready_cycles", 0)
            ),
            "dma_rd_en_crypto_to_dma_nonempty_cycles": case.get(
                "dma_rd_en_crypto_to_dma_nonempty_cycles",
                post.get("dma_rd_en_crypto_to_dma_nonempty_cycles", 0),
            ),
            "dma_rd_en_tx_ready_when_nonempty_cycles": case.get(
                "dma_rd_en_tx_ready_when_nonempty_cycles",
                post.get("dma_rd_en_tx_ready_when_nonempty_cycles", 0),
            ),
            "dma_rd_en_dma_req_rd_cycles": case.get(
                "dma_rd_en_dma_req_rd_cycles", post.get("dma_rd_en_dma_req_rd_cycles", 0)
            ),
            "dma_rd_en_loopback_branch_selected_cycles": case.get(
                "dma_rd_en_loopback_branch_selected_cycles",
                post.get("dma_rd_en_loopback_branch_selected_cycles", 0),
            ),
            "dma_rd_en_normal_branch_selected_cycles": case.get(
                "dma_rd_en_normal_branch_selected_cycles",
                post.get("dma_rd_en_normal_branch_selected_cycles", 0),
            ),
            "dma_rd_en_loopback_branch_candidate_cycles": case.get(
                "dma_rd_en_loopback_branch_candidate_cycles",
                post.get("dma_rd_en_loopback_branch_candidate_cycles", 0),
            ),
            "dma_rd_en_equation_true_but_rd_en_low_cycles": case.get(
                "dma_rd_en_equation_true_but_rd_en_low_cycles",
                post.get("dma_rd_en_equation_true_but_rd_en_low_cycles", 0),
            ),
        }
        row.update(inj_status_decoded)
        row.update(inj_source_state_decoded)
        row.update(netdbg_decoded)
        row.update(pbm_state_decoded)
        row["netdbg_status_xor_vs_bf8_baseline_hex"] = None
        if args.stage == "Stage1A6_PriorDropPulseReproduction":
            if truthy(row.get("repro_pre_snapshot_after_clear_nonzero")):
                row["stage_status"] = "fail"
            elif int(delta.get("drop_pulse_count", 0) or 0) > 0:
                row["stage_status"] = "partial"
            else:
                row["stage_status"] = "fail"
        for field in NUMERIC_FIELDS:
            row[field] = delta.get(field, 0)
        if args.stage == "Stage1A7_DropPulseConditionDiffDiagnosis":
            row["stage_status"] = stage1a7_row_status(row)
            extra_deltas = case.get("extra_snapshot_deltas") or {}
            for name in (
                "drop_pulse_delta_at_post_injection",
                "drop_pulse_delta_at_050ms",
                "drop_pulse_delta_at_250ms",
                "drop_pulse_delta_at_500ms",
            ):
                row[name] = extra_deltas.get(name)
        if args.stage == "Stage1A8_PBMIngressVisibilityDiagnosis":
            extra_deltas = case.get("extra_snapshot_deltas") or {}
            for name in (
                "drop_pulse_delta_at_post_injection",
                "drop_pulse_delta_at_050ms",
                "drop_pulse_delta_at_250ms",
                "drop_pulse_delta_at_500ms",
                "pbm_wr_valid_cycles_delta_at_post_injection",
                "pbm_wr_valid_cycles_delta_at_050ms",
                "pbm_wr_valid_cycles_delta_at_250ms",
                "pbm_wr_valid_cycles_delta_at_500ms",
                "pbm_valid_not_ready_cycles_delta_at_post_injection",
                "pbm_valid_not_ready_cycles_delta_at_050ms",
                "pbm_valid_not_ready_cycles_delta_at_250ms",
                "pbm_valid_not_ready_cycles_delta_at_500ms",
                "pbm_wr_accept_cycles_delta_at_post_injection",
                "pbm_wr_accept_cycles_delta_at_050ms",
                "pbm_wr_accept_cycles_delta_at_250ms",
                "pbm_wr_accept_cycles_delta_at_500ms",
                "pbm_state_raw_at_post_injection",
                "pbm_state_raw_at_050ms",
                "pbm_state_raw_at_250ms",
                "pbm_state_raw_at_500ms",
                "pbm_ptr_head_reserve_at_post_injection",
                "pbm_ptr_head_reserve_at_050ms",
                "pbm_ptr_head_reserve_at_250ms",
                "pbm_ptr_head_reserve_at_500ms",
                "pbm_ptr_head_commit_at_post_injection",
                "pbm_ptr_head_commit_at_050ms",
                "pbm_ptr_head_commit_at_250ms",
                "pbm_ptr_head_commit_at_500ms",
                "pbm_ptr_tail_at_post_injection",
                "pbm_ptr_tail_at_050ms",
                "pbm_ptr_tail_at_250ms",
                "pbm_ptr_tail_at_500ms",
                "pbm_buffer_usage_at_post_injection",
                "pbm_buffer_usage_at_050ms",
                "pbm_buffer_usage_at_250ms",
                "pbm_buffer_usage_at_500ms",
            ):
                row[name] = extra_deltas.get(name)
            row["stage_status"] = stage1a8_row_status(row)
        if args.stage == "Stage1A21_PBMReadyGatingDiagnosis":
            extra_deltas = case.get("extra_snapshot_deltas") or {}
            for name in (
                "drop_pulse_delta_at_post_injection",
                "drop_pulse_delta_at_050ms",
                "drop_pulse_delta_at_250ms",
                "drop_pulse_delta_at_500ms",
                "pbm_wr_valid_cycles_delta_at_post_injection",
                "pbm_wr_valid_cycles_delta_at_050ms",
                "pbm_wr_valid_cycles_delta_at_250ms",
                "pbm_wr_valid_cycles_delta_at_500ms",
                "pbm_valid_not_ready_cycles_delta_at_post_injection",
                "pbm_valid_not_ready_cycles_delta_at_050ms",
                "pbm_valid_not_ready_cycles_delta_at_250ms",
                "pbm_valid_not_ready_cycles_delta_at_500ms",
                "pbm_wr_accept_cycles_delta_at_post_injection",
                "pbm_wr_accept_cycles_delta_at_050ms",
                "pbm_wr_accept_cycles_delta_at_250ms",
                "pbm_wr_accept_cycles_delta_at_500ms",
                "pbm_state_raw_at_post_injection",
                "pbm_state_raw_at_050ms",
                "pbm_state_raw_at_250ms",
                "pbm_state_raw_at_500ms",
            ):
                row[name] = extra_deltas.get(name)
            row["stage_status"] = stage1a21_row_status(row)
        if args.stage == "Stage1A22_PBMPointerResetOrDrainDiagnosis":
            row["stage_status"] = stage1a22_row_status(row)
        if args.stage in {
            "Stage1A23_PBMCommitTailPointerInvariantDiagnosis",
            "Stage1A24_PBMResetDomainScopeDiagnosis",
            "Stage1A25_PBMResetDomainRemediationPlan",
        }:
            extra_deltas = case.get("extra_snapshot_deltas") or {}
            for name in (
                "pbm_state_raw_at_post_workload",
                "pbm_state_raw_at_050ms",
                "pbm_state_raw_at_250ms",
                "pbm_state_raw_at_500ms",
                "pbm_ptr_head_commit_at_post_workload",
                "pbm_ptr_head_commit_at_050ms",
                "pbm_ptr_head_commit_at_250ms",
                "pbm_ptr_head_commit_at_500ms",
                "pbm_ptr_tail_at_post_workload",
                "pbm_ptr_tail_at_050ms",
                "pbm_ptr_tail_at_250ms",
                "pbm_ptr_tail_at_500ms",
                "pbm_rd_nonempty_cycles_delta_at_post_workload",
                "pbm_rd_nonempty_cycles_delta_at_050ms",
                "pbm_rd_nonempty_cycles_delta_at_250ms",
                "pbm_rd_nonempty_cycles_delta_at_500ms",
                "pbm_committed_available_cycles_delta_at_post_workload",
                "pbm_committed_available_cycles_delta_at_050ms",
                "pbm_committed_available_cycles_delta_at_250ms",
                "pbm_committed_available_cycles_delta_at_500ms",
                "pbm_rd_en_cycles_delta_at_post_workload",
                "pbm_rd_en_cycles_delta_at_050ms",
                "pbm_rd_en_cycles_delta_at_250ms",
                "pbm_rd_en_cycles_delta_at_500ms",
                "pbm_rd_accept_cycles_delta_at_post_workload",
                "pbm_rd_accept_cycles_delta_at_050ms",
                "pbm_rd_accept_cycles_delta_at_250ms",
                "pbm_rd_accept_cycles_delta_at_500ms",
            ):
                row[name] = extra_deltas.get(name)
            row["stage1a23_extra_snapshots_present"] = case.get("stage1a23_extra_snapshots_present")
            row["stage_status"] = stage1a23_row_status(row)
        if args.stage == "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis":
            extra_deltas = case.get("extra_snapshot_deltas") or {}
            for name in (
                "drop_pulse_delta_at_post_injection",
                "drop_pulse_delta_at_050ms",
                "drop_pulse_delta_at_250ms",
                "drop_pulse_delta_at_500ms",
                "crypto_rx_valid_cycles_delta_at_post_injection",
                "crypto_rx_valid_cycles_delta_at_050ms",
                "crypto_rx_valid_cycles_delta_at_250ms",
                "crypto_rx_valid_cycles_delta_at_500ms",
                "crypto_rx_valid_not_ready_cycles_delta_at_post_injection",
                "crypto_rx_valid_not_ready_cycles_delta_at_050ms",
                "crypto_rx_valid_not_ready_cycles_delta_at_250ms",
                "crypto_rx_valid_not_ready_cycles_delta_at_500ms",
                "crypto_rx_accept_cycles_delta_at_post_injection",
                "crypto_rx_accept_cycles_delta_at_050ms",
                "crypto_rx_accept_cycles_delta_at_250ms",
                "crypto_rx_accept_cycles_delta_at_500ms",
            ):
                row[name] = extra_deltas.get(name)
            row["stage_status"] = stage1a9_row_status(row)
        if args.stage == "Stage1A10_CryptoDMAHandoffDiagnosis":
            extra_deltas = case.get("extra_snapshot_deltas") or {}
            for name in (
                "pbm_rd_accept_cycles_delta_at_post_injection",
                "pbm_rd_accept_cycles_delta_at_050ms",
                "pbm_rd_accept_cycles_delta_at_250ms",
                "pbm_rd_accept_cycles_delta_at_500ms",
                "crypto_dma_in_accept_cycles_delta_at_post_injection",
                "crypto_dma_in_accept_cycles_delta_at_050ms",
                "crypto_dma_in_accept_cycles_delta_at_250ms",
                "crypto_dma_in_accept_cycles_delta_at_500ms",
                "crypto_dma_backpressure_cycles_delta_at_post_injection",
                "crypto_dma_backpressure_cycles_delta_at_050ms",
                "crypto_dma_backpressure_cycles_delta_at_250ms",
                "crypto_dma_backpressure_cycles_delta_at_500ms",
            ):
                row[name] = extra_deltas.get(name)
            row["stage_status"] = stage1a10_row_status(row)
        if args.stage == "Stage1A11_PBMReadSideVisibilityDiagnosis":
            extra_deltas = case.get("extra_snapshot_deltas") or {}
            for name in (
                "bridge_pbm_rd_en_cycles_delta_at_post_injection",
                "bridge_pbm_rd_en_cycles_delta_at_050ms",
                "bridge_pbm_rd_en_cycles_delta_at_250ms",
                "bridge_pbm_rd_en_cycles_delta_at_500ms",
                "bridge_pbm_fire_count_delta_at_post_injection",
                "bridge_pbm_fire_count_delta_at_050ms",
                "bridge_pbm_fire_count_delta_at_250ms",
                "bridge_pbm_fire_count_delta_at_500ms",
                "bridge_inst_available_cycles_delta_at_post_injection",
                "bridge_inst_available_cycles_delta_at_050ms",
                "bridge_inst_available_cycles_delta_at_250ms",
                "bridge_inst_available_cycles_delta_at_500ms",
                "bridge_data_available_no_inst_available_cycles_delta_at_post_injection",
                "bridge_data_available_no_inst_available_cycles_delta_at_050ms",
                "bridge_data_available_no_inst_available_cycles_delta_at_250ms",
                "bridge_data_available_no_inst_available_cycles_delta_at_500ms",
                "dma_start_seen_count_delta_at_post_injection",
                "dma_start_seen_count_delta_at_050ms",
                "dma_start_seen_count_delta_at_250ms",
                "dma_start_seen_count_delta_at_500ms",
                "dma_data_cycles_delta_at_post_injection",
                "dma_data_cycles_delta_at_050ms",
                "dma_data_cycles_delta_at_250ms",
                "dma_data_cycles_delta_at_500ms",
                "dma_aw_handshake_count_delta_at_post_injection",
                "dma_aw_handshake_count_delta_at_050ms",
                "dma_aw_handshake_count_delta_at_250ms",
                "dma_aw_handshake_count_delta_at_500ms",
                "dma_w_handshake_count_delta_at_post_injection",
                "dma_w_handshake_count_delta_at_050ms",
                "dma_w_handshake_count_delta_at_250ms",
                "dma_w_handshake_count_delta_at_500ms",
                "dma_wready_low_cycles_delta_at_post_injection",
                "dma_wready_low_cycles_delta_at_050ms",
                "dma_wready_low_cycles_delta_at_250ms",
                "dma_wready_low_cycles_delta_at_500ms",
                "bridge_input_state_raw_at_post_injection",
                "bridge_input_state_raw_at_050ms",
                "bridge_input_state_raw_at_250ms",
                "bridge_input_state_raw_at_500ms",
                "dma_state_raw_at_post_injection",
                "dma_state_raw_at_050ms",
                "dma_state_raw_at_250ms",
                "dma_state_raw_at_500ms",
            ):
                row[name] = extra_deltas.get(name)
            row["stage_status"] = stage1a11_row_status(row)
        if args.stage == "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis":
            extra_deltas = case.get("extra_snapshot_deltas") or {}
            for name in (
                "bridge_tx_nonempty_cycles_delta_at_post_injection",
                "bridge_tx_nonempty_cycles_delta_at_050ms",
                "bridge_tx_nonempty_cycles_delta_at_250ms",
                "bridge_tx_nonempty_cycles_delta_at_500ms",
                "bridge_tx_rd_en_cycles_delta_at_post_injection",
                "bridge_tx_rd_en_cycles_delta_at_050ms",
                "bridge_tx_rd_en_cycles_delta_at_250ms",
                "bridge_tx_rd_en_cycles_delta_at_500ms",
                "bridge_tx_accept_cycles_delta_at_post_injection",
                "bridge_tx_accept_cycles_delta_at_050ms",
                "bridge_tx_accept_cycles_delta_at_250ms",
                "bridge_tx_accept_cycles_delta_at_500ms",
                "bridge_tx_last_seen_count_delta_at_post_injection",
                "bridge_tx_last_seen_count_delta_at_050ms",
                "bridge_tx_last_seen_count_delta_at_250ms",
                "bridge_tx_last_seen_count_delta_at_500ms",
            ):
                row[name] = extra_deltas.get(name)
            row["stage_status"] = stage1a12_row_status(row)
        if args.stage == "Stage1A13_DMAStartPathDiagnosis":
            row["stage_status"] = stage1a13_row_status(row)
        if args.stage == "Stage1A14_StartPulseInjectionOrProbeControlFix":
            row["stage_status"] = stage1a14_row_status(row)
        if args.stage == "Stage1A15_ExplicitStartBridgeHandoffDiagnosis":
            row["explicit_start_verified_by_hardware"] = (
                int_value(row.get("axil_write_hit_start_count", 0)) > 0
                and int_value(row.get("csr_start_pulse_count", 0)) > 0
                and int_value(row.get("final_start_pulse_count", 0)) > 0
                and int_value(row.get("dma_start_seen_count", 0)) > 0
            )
            row["row_level_start_and_bridge_nonempty_seen"] = (
                (
                    int_value(row.get("dma_start_seen_count", 0)) > 0
                    or int_value(row.get("dma_busy_cycles", 0)) > 0
                )
                and int_value(row.get("bridge_tx_nonempty_cycles", 0)) > 0
            )
            row["dma_or_source_reader_busy_seen"] = (
                int_value(row.get("dma_busy_cycles", 0)) > 0
                or int_value(row.get("source_reader_busy_cycles", 0)) > 0
            )
            row["stage_status"] = stage1a15_row_status(row)
        if args.stage == "Stage1A16_BridgeDataProductionDiagnosis":
            config_name = str(row.get("bridge_data_production_config") or "")
            explicit_verified = (
                int_value(row.get("axil_write_hit_start_count", 0)) > 0
                and int_value(row.get("csr_start_pulse_count", 0)) > 0
                and int_value(row.get("final_start_pulse_count", 0)) > 0
                and int_value(row.get("dma_start_seen_count", 0)) > 0
            )
            bridge_nonempty = int_value(row.get("bridge_tx_nonempty_cycles", 0)) > 0
            dma_start_seen = int_value(row.get("dma_start_seen_count", 0)) > 0
            row_level_same_row = (
                config_name == "A15_AfterWorkloadStart_Replay"
                and explicit_verified
                and bridge_nonempty
                and dma_start_seen
            )
            dma_or_reader_busy = (
                int_value(row.get("dma_busy_cycles", 0)) > 0
                or int_value(row.get("source_reader_busy_cycles", 0)) > 0
            )
            start_bit_mask = int_value(row.get("start_bit_mask", 1)) or 1
            row["explicit_start_verified_by_hardware"] = explicit_verified
            row["row_level_start_and_bridge_nonempty_seen"] = (
                (
                    int_value(row.get("dma_start_seen_count", 0)) > 0
                    or int_value(row.get("dma_busy_cycles", 0)) > 0
                )
                and bridge_nonempty
            )
            row["dma_or_source_reader_busy_seen"] = dma_or_reader_busy
            row["a15_after_start_bridge_nonempty_seen"] = (
                config_name == "A15_AfterWorkloadStart_Replay" and bridge_nonempty
            )
            row["a15_after_start_explicit_start_verified"] = (
                config_name == "A15_AfterWorkloadStart_Replay" and explicit_verified
            )
            row["a15_after_start_dma_start_seen"] = (
                config_name == "A15_AfterWorkloadStart_Replay" and dma_start_seen
            )
            row["explicit_start_and_bridge_nonempty_same_row_seen"] = row_level_same_row
            row["explicit_start_changed_control_state"] = (
                (int_value(row.get("dma_ctrl_changed_bits", 0)) & (~start_bit_mask & 0xFFFFFFFF)) != 0
            )
            if config_name == "A12_NoStart_Replay":
                row["stage_status"] = "partial" if bridge_nonempty else "fail"
            elif config_name == "A15_AfterWorkloadStart_Replay":
                row["stage_status"] = "partial" if explicit_verified else "fail"
            else:
                row["stage_status"] = "fail"
        if args.stage == "Stage1A17_PBMCommitReproductionDiagnosis":
            last_accepted = int_value(row.get("pbm_wr_last_accepted_count", 0))
            last_error_accepted = int_value(row.get("pbm_wr_last_error_accepted_count", 0))
            clean_last = last_accepted - last_error_accepted
            row["pbm_wr_last_clean_accepted_count"] = clean_last if clean_last >= 0 else None
            row["pbm_wr_last_clean_accepted_valid"] = clean_last >= 0
            if int_value(row.get("pbm_commit_entry_count", 0)) > 0 and int_value(row.get("pbm_ptr_head_commit_delta_mod", 0)) > 0:
                row["stage_status"] = "commit_reproduced"
            elif int_value(row.get("pbm_wr_accept_cycles", 0)) > 0:
                row["stage_status"] = "pbm_accept_seen"
            elif int_value(row.get("pbm_wr_valid_cycles", 0)) > 0:
                row["stage_status"] = "pbm_valid_seen"
            else:
                row["stage_status"] = "no_pbm_valid_seen"
        if args.stage == "Stage1A26_DMARdEnableEquationDiagnosis":
            row["stage_status"] = stage1a26_row_status(row)
        if args.stage == "Stage1A27_CryptoDMAIngressBackpressureDiagnosis":
            if int_value(row.get("crypto_dma_in_accept_cycles", 0)) > 0:
                row["stage_status"] = "crypto_dma_ingress_accept_seen"
            elif int_value(row.get("crypto_dma_in_valid_cycles", 0)) > 0:
                row["stage_status"] = "crypto_dma_ingress_valid_seen"
            elif int_value(row.get("bridge_tx_accept_cycles", 0)) > 0:
                row["stage_status"] = "bridge_accept_without_crypto_dma_valid"
            else:
                row["stage_status"] = "crypto_dma_ingress_backpressure_observation"
        if args.stage == "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis":
            if int_value(row.get("pbm_wr_valid_cycles", 0)) > 0:
                row["stage_status"] = "pbm_valid_reestablished"
            elif int_value(row.get("crypto_rx_valid_cycles", 0)) > 0:
                row["stage_status"] = "crypto_rx_without_pbm_valid"
            elif int_value(row.get("netdbg_classifier_dma_valid_seen", 0)) > 0:
                row["stage_status"] = "classifier_dma_valid_without_crypto_rx"
            elif int_value(row.get("netdbg_classifier_in_fire_seen", 0)) > 0:
                row["stage_status"] = "classifier_input_fire_without_classifier_dma_valid"
            elif int_value(row.get("netdbg_stage1_fire_seen", 0)) > 0:
                row["stage_status"] = "stage1_fire_seen"
            else:
                row["stage_status"] = "no_stage1_fire_seen"
        if args.stage == "Stage1A19_InjectionSourceEmissionDiagnosis":
            if int_value(row.get("netdbg_stage1_fire_seen", 0)) > 0:
                row["stage_status"] = "stage1_fire_reestablished"
            elif int_value(row.get("inj_overflow", 0)) > 0:
                row["stage_status"] = "inj_overflow_without_stage1_fire"
            elif (
                int_value(row.get("stage1_inject_tvalid", 0)) == 1
                and int_value(row.get("stage1_inject_tready", 0)) == 0
            ):
                row["stage_status"] = "stage1_valid_not_ready_without_fire"
            elif int_value(row.get("stage1_inject_tvalid", 0)) > 0:
                row["stage_status"] = "stage1_valid_without_fire"
            elif (
                int_value(row.get("inj_fifo_nonempty", 0)) == 1
                or int_value(row.get("inj_fifo_count", 0)) > 0
            ):
                row["stage_status"] = "inj_fifo_nonempty_without_stage1_valid"
            elif int_value(row.get("source_progress_post", 0)) > int_value(row.get("source_progress_pre", 0)):
                row["stage_status"] = "source_progress_without_stage1_valid"
            else:
                row["stage_status"] = "no_injection_source_activity_seen"
        if args.stage == "Stage1A20_InjectionSourceArmingDiagnosis":
            if int_value(row.get("stage1_inject_fire_cycles", 0)) > 0 or int_value(row.get("netdbg_stage1_fire_seen", 0)) > 0:
                row["stage_status"] = "stage1_fire_reestablished"
            elif int_value(row.get("inj_ctrl_write_hit_count", 0)) == 0 and int_value(row.get("inj_clear_write_hit_count", 0)) == 0 and int_value(row.get("inj_frame_word_write_hit_count", 0)) == 0 and int_value(row.get("inj_expected_words_write_hit_count", 0)) == 0:
                row["stage_status"] = "probe_write_not_observed_by_injection_csr"
            elif not truthy(row.get("inj_config_valid")):
                row["stage_status"] = "inj_config_not_valid"
            elif int_value(row.get("inj_fifo_write_count", 0)) == 0 and int_value(row.get("inj_fifo_level_max", 0)) == 0:
                row["stage_status"] = "config_valid_but_fifo_not_loaded"
            elif int_value(row.get("inj_fifo_level_max", 0)) > 0 and int_value(row.get("inj_source_active_cycles", 0)) == 0:
                row["stage_status"] = "fifo_loaded_but_source_not_active"
            elif int_value(row.get("inj_source_active_cycles", 0)) > 0 and int_value(row.get("stage1_inject_tvalid_cycles", 0)) == 0:
                row["stage_status"] = "source_active_without_stage1_valid"
            elif int_value(row.get("stage1_inject_tvalid_cycles", 0)) > 0 and int_value(row.get("stage1_inject_tready_cycles", 0)) > 0 and int_value(row.get("stage1_inject_fire_cycles", 0)) == 0:
                row["stage_status"] = "valid_ready_without_fire"
            elif int_value(row.get("stage1_inject_tvalid_cycles", 0)) > 0:
                row["stage_status"] = "stage1_valid_without_fire"
            else:
                row["stage_status"] = "no_injection_source_activity_seen"
        rows.append(row)

    if args.stage == "Stage1A7_DropPulseConditionDiffDiagnosis":
        bf8_rows = [row for row in rows if row.get("condition_diff_config") == "BF8_SM500"]
        if bf8_rows:
            baseline_netdbg = int_value(bf8_rows[0].get("netdbg_status_raw_decimal", 0))
            for row in rows:
                row["netdbg_status_xor_vs_bf8_baseline_hex"] = hex32(
                    int_value(row.get("netdbg_status_raw_decimal", 0)) ^ baseline_netdbg
                )
    return rows


def configured_injection_intensity(
    args: argparse.Namespace,
    burst_frames_override: int | None = None,
    burst_gap_us_override: float | None = None,
    settle_ms_override: float | None = None,
) -> float:
    burst_frames = max(0, int(args.burst_frames if burst_frames_override is None else burst_frames_override))
    frame_size = max(1, int(args.frame_size))
    gap_s = max(0.0, float(args.burst_gap_us if burst_gap_us_override is None else burst_gap_us_override)) / 1_000_000.0
    settle_s = max(0.0, float(args.settle_ms if settle_ms_override is None else settle_ms_override)) / 1000.0
    window_s = max(1e-9, (burst_frames * gap_s) + settle_s)
    return burst_frames / window_s


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fieldnames = list(rows[0].keys())
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def is_included_in_stats(row: dict[str, Any]) -> bool:
    return str(row.get("validation_status", "")).startswith("valid_")


def excluded_reason(row: dict[str, Any]) -> str | None:
    validation_status = str(row.get("validation_status", ""))
    if is_included_in_stats(row):
        return None
    if "log_gap" in validation_status:
        return "log_gap"
    if "restore" in validation_status:
        return "state_restore_failure"
    return "invalid_validation_status"


def build_stats(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    excluded_rows = [row for row in rows if not is_included_in_stats(row)]
    recovery_positive = [
        row
        for row in included_rows
        if any_nonzero(row, ROLLBACK_RECOVERY_COUNTERS)
    ]
    metrics = {
        "backend_accept_ratio": summarize_values([row.get("backend_accept_ratio") for row in included_rows]),
        "backend_starvation_ratio": summarize_values([row.get("backend_starvation_ratio") for row in included_rows]),
        "effective_work_ratio": summarize_values([row.get("effective_work_ratio") for row in included_rows]),
        "recovery_time_ms": summarize_values([row.get("recovery_time_ms") for row in included_rows]),
        "recovery_window_ms": summarize_values([row.get("recovery_window_ms") for row in included_rows]),
    }
    exclusion_counts: dict[str, int] = {
        "log_gap": 0,
        "state_restore_failure": 0,
        "invalid_validation_status": 0,
    }
    for row in excluded_rows:
        reason = excluded_reason(row) or "invalid_validation_status"
        exclusion_counts[reason] = exclusion_counts.get(reason, 0) + 1
    stats = {
        "stats_schema_version": STATS_SCHEMA_VERSION,
        "experiment_plan_version": args.experiment_plan_version,
        "metrics_semantics_version": METRICS_SEMANTICS_VERSION,
        "raw_sample_count": len(rows),
        "excluded_sample_count": len(excluded_rows),
        "included_sample_count": len(included_rows),
        "included_in_stats_count": len(included_rows),
        "excluded_sample_reasons": exclusion_counts,
        "trigger_rate": safe_ratio(len(recovery_positive), max(1, len(included_rows))),
        "trigger_interval_distribution": summarize_values(trigger_intervals(included_rows)),
        "metrics": metrics,
        "negative_result_types": sorted({row.get("negative_result_type") for row in included_rows if row.get("negative_result_type")}),
        "paper_ready_recovery_gate": {
            "requires_nonzero_counter": list(ROLLBACK_RECOVERY_COUNTERS),
            "requires_backend_activity": True,
            "required_triggers_in_10": 3,
            "met": len(recovery_positive) >= 3
            and len(included_rows) >= 10
            and any_nonzero_rows(included_rows, BACKEND_SERVICE_COUNTERS),
        },
    }
    if args.stage == "Stage1A_BurstSweep":
        stats["paper_ready_recovery_gate"]["met"] = False
        grouped = grouped_by_burst_frames(rows)
        decision = stage1a_decision(grouped, rows, args)
        stats["stage1a_baseline_source"] = args.stage1a_baseline_source
        stats["grouped_by_burst_frames_ordered"] = grouped
        stats["stage1a_decision"] = decision
    if args.stage == "Stage1A_DropPulseAudit":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["drop_pulse_audit"] = drop_pulse_audit(rows)
    if args.stage == "Stage1A6_PriorDropPulseReproduction":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["prior_drop_pulse_reproduction"] = prior_drop_pulse_reproduction(rows, args)
    if args.stage == "Stage1A7_DropPulseConditionDiffDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["stage1a7_condition_diff"] = stage1a7_condition_diff(rows)
    if args.stage == "Stage1A8_PBMIngressVisibilityDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["stage1a8_pbm_ingress_visibility"] = stage1a8_pbm_ingress_visibility(rows, args)
    if args.stage == "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["stage1a9_crypto_ingress_handoff_visibility"] = stage1a9_crypto_ingress_handoff_visibility(rows, args)
    if args.stage == "Stage1A10_CryptoDMAHandoffDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["crypto_dma_handoff_diagnosis"] = stage1a10_crypto_dma_handoff_diagnosis(rows, args)
    if args.stage == "Stage1A27_CryptoDMAIngressBackpressureDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["crypto_dma_ingress_backpressure_diagnosis"] = (
            stage1a27_crypto_dma_ingress_backpressure_diagnosis(rows, args)
        )
    if args.stage == "Stage1A11_PBMReadSideVisibilityDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["stage1a11_pbm_read_side_visibility"] = stage1a11_pbm_read_side_visibility(rows, args)
    if args.stage == "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["stage1a12_bridge_output_fifo_visibility"] = stage1a12_bridge_output_fifo_visibility(rows, args)
    if args.stage == "Stage1A13_DMAStartPathDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["stage1a13_dma_start_path_diagnosis"] = stage1a13_dma_start_path_diagnosis(rows, args)
    if args.stage == "Stage1A14_StartPulseInjectionOrProbeControlFix":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["start_pulse_injection_diagnosis"] = start_pulse_injection_diagnosis(rows, args)
    if args.stage == "Stage1A15_ExplicitStartBridgeHandoffDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["explicit_start_bridge_handoff_diagnosis"] = explicit_start_bridge_handoff_diagnosis(rows, args)
    if args.stage == "Stage1A16_BridgeDataProductionDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["bridge_data_production_diagnosis"] = bridge_data_production_diagnosis(rows, args)
    if args.stage == "Stage1A17_PBMCommitReproductionDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["pbm_commit_reproduction_diagnosis"] = pbm_commit_reproduction_diagnosis(rows, args)
    if args.stage == "Stage1A26_DMARdEnableEquationDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["dma_rd_en_equation_diagnosis"] = dma_rd_en_equation_diagnosis(rows, args)
    if args.stage == "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["upstream_ingress_to_pbm_visibility_diagnosis"] = (
            upstream_ingress_to_pbm_visibility_diagnosis(rows, args)
        )
    if args.stage == "Stage1A19_InjectionSourceEmissionDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["injection_source_emission_diagnosis"] = (
            injection_source_emission_diagnosis(rows, args)
        )
    if args.stage == "Stage1A20_InjectionSourceArmingDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["injection_source_arming_diagnosis"] = (
            injection_source_arming_diagnosis(rows, args)
        )
    if args.stage == "Stage1A21_PBMReadyGatingDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["stage1a21_pbm_ready_gating_diagnosis"] = (
            stage1a21_pbm_ready_gating_diagnosis(rows, args)
        )
    if args.stage == "Stage1A22_PBMPointerResetOrDrainDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["stage1a22_pbm_pointer_reset_or_drain_diagnosis"] = (
            stage1a22_pbm_pointer_reset_or_drain_diagnosis(rows, args)
        )
    if args.stage == "Stage1A23_PBMCommitTailPointerInvariantDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["stage1a23_pbm_commit_tail_pointer_invariant_diagnosis"] = (
            stage1a23_pbm_commit_tail_pointer_invariant_diagnosis(rows, args)
        )
    if args.stage == "Stage1A24_PBMResetDomainScopeDiagnosis":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["stage1a24_pbm_reset_domain_scope_diagnosis"] = (
            stage1a24_pbm_reset_domain_scope_diagnosis(rows, args)
        )
    if args.stage == "Stage1A25_PBMResetDomainRemediationPlan":
        stats["paper_ready_recovery_gate"]["met"] = False
        stats["stage1a25_pbm_reset_domain_remediation_plan"] = (
            stage1a25_pbm_reset_domain_remediation_plan(rows, args)
        )
    return stats


def grouped_by_burst_frames(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    groups: dict[int, list[dict[str, Any]]] = {}
    for row in rows:
        burst_frames = int(float(row.get("BurstFrames", 0) or 0))
        groups.setdefault(burst_frames, []).append(row)

    ordered: list[dict[str, Any]] = []
    for burst_frames in sorted(groups):
        group_rows = groups[burst_frames]
        included_rows = [row for row in group_rows if is_included_in_stats(row)]
        excluded_rows = [row for row in group_rows if not is_included_in_stats(row)]
        ordered.append(
            {
                "burst_frames": burst_frames,
                "raw_sample_count": len(group_rows),
                "included_count": len(included_rows),
                "excluded_count": len(excluded_rows),
                "backend_accept_cycles_stats": summarize_values(
                    [float(row.get("backend_accept_cycles", 0) or 0) for row in included_rows]
                ),
                "backend_starvation_cycles_stats": summarize_values(
                    [float(row.get("backend_starvation_cycles", 0) or 0) for row in included_rows]
                ),
                "effective_work_ratio_stats": summarize_values(
                    [row.get("effective_work_ratio") for row in included_rows]
                ),
                "activity_stats": summarize_values(
                    [
                        float(row.get("backend_accept_cycles", 0) or 0)
                        + float(row.get("backend_starvation_cycles", 0) or 0)
                        for row in included_rows
                    ]
                ),
                "recovery_counters_nonzero_any": any(
                    any_nonzero(row, ROLLBACK_RECOVERY_COUNTERS)
                    for row in included_rows
                ),
                "recovery_counters_max": {
                    field: max([int(row.get(field, 0) or 0) for row in included_rows] + [0])
                    for field in ROLLBACK_RECOVERY_COUNTERS
                },
            }
        )
    return ordered


def stage1a_decision(
    grouped: list[dict[str, Any]],
    rows: list[dict[str, Any]],
    args: argparse.Namespace,
) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    excluded_rows = [row for row in rows if not is_included_in_stats(row)]
    group_activity = [
        {
            "burst_frames": group["burst_frames"],
            "median_activity": float(group["activity_stats"].get("p50") or 0.0),
            "median_effective_work_ratio": group["effective_work_ratio_stats"].get("p50"),
            "included_count": group["included_count"],
        }
        for group in grouped
    ]
    baseline = next((group for group in group_activity if group["burst_frames"] == 1), None)
    baseline_activity = baseline["median_activity"] if baseline else 0.0

    higher_groups = [group for group in group_activity if group["burst_frames"] > 1]
    higher_above_floor = [
        group
        for group in higher_groups
        if group["median_activity"] > baseline_activity + ABSOLUTE_ACTIVITY_FLOOR
    ]
    required_higher_points = min(3, len(higher_groups))
    max_accept = max([float(row.get("backend_accept_cycles", 0) or 0) for row in included_rows] + [0.0])
    max_starvation = max([float(row.get("backend_starvation_cycles", 0) or 0) for row in included_rows] + [0.0])
    bf1_rows = [row for row in included_rows if int(float(row.get("BurstFrames", 0) or 0)) == 1]
    bf1_accept_mean = statistics.fmean([float(row.get("backend_accept_cycles", 0) or 0) for row in bf1_rows]) if bf1_rows else 0.0
    bf1_starvation_mean = statistics.fmean([float(row.get("backend_starvation_cycles", 0) or 0) for row in bf1_rows]) if bf1_rows else 0.0
    absolute_gain = (
        max_accept >= max(4.0 * bf1_accept_mean, float(ABSOLUTE_ACTIVITY_FLOOR))
        or max_starvation >= max(4.0 * bf1_starvation_mean, float(ABSOLUTE_ACTIVITY_FLOOR))
    )
    trend_gain = required_higher_points > 0 and len(higher_above_floor) >= required_higher_points
    systematic_amplification = absolute_gain and trend_gain

    reverse_jumps = 0
    for previous, current in zip(group_activity, group_activity[1:]):
        if current["median_activity"] + ABSOLUTE_ACTIVITY_FLOOR < previous["median_activity"]:
            reverse_jumps += 1
    if systematic_amplification and reverse_jumps <= 1:
        backend_activity_monotonic = "yes"
    elif trend_gain or (group_activity and group_activity[-1]["median_activity"] > baseline_activity):
        backend_activity_monotonic = "partial"
    else:
        backend_activity_monotonic = "no"

    mean_accept = statistics.fmean([float(row.get("backend_accept_cycles", 0) or 0) for row in included_rows]) if included_rows else 0.0
    mean_starvation = statistics.fmean([float(row.get("backend_starvation_cycles", 0) or 0) for row in included_rows]) if included_rows else 0.0
    if max(mean_accept, mean_starvation) < ABSOLUTE_ACTIVITY_FLOOR:
        dominant_backend_mode = "none"
    elif mean_accept > 1.2 * mean_starvation:
        dominant_backend_mode = "accept"
    elif mean_starvation > 1.2 * mean_accept:
        dominant_backend_mode = "starvation"
    else:
        dominant_backend_mode = "balanced"

    active_groups = [group for group in group_activity if group["median_activity"] > 0]
    effective_medians = [
        float(group["median_effective_work_ratio"])
        for group in active_groups
        if group["median_effective_work_ratio"] is not None
    ]
    if len(active_groups) < 3 or len(effective_medians) < 3:
        effective_work_ratio_trend = "insufficient_data"
    elif all(0.4 <= value <= 0.6 for value in effective_medians):
        effective_work_ratio_trend = "stable_around_0_5"
    elif sum(1 for value in effective_medians if value > 0.6) >= 3:
        effective_work_ratio_trend = "accept_skew"
    elif sum(1 for value in effective_medians if value < 0.4) >= 3:
        effective_work_ratio_trend = "starvation_skew"
    else:
        effective_work_ratio_trend = "insufficient_data"

    recovery_counters_still_zero = all(
        max([int(row.get(field, 0) or 0) for row in included_rows] + [0]) == 0
        for field in ROLLBACK_RECOVERY_COUNTERS
    )
    max_activity = max(
        [
            float(row.get("backend_accept_cycles", 0) or 0)
            + float(row.get("backend_starvation_cycles", 0) or 0)
            for row in included_rows
        ]
        + [0.0]
    )

    if args.stage1a_run_kind == "dry_run":
        if excluded_rows or len(included_rows) == 0 or len(grouped) == 0:
            recommended_next_stage = "rerun_stage1a_due_to_inconclusive"
        else:
            recommended_next_stage = "Stage1A_FullRun"
    elif excluded_rows or len(included_rows) == 0:
        recommended_next_stage = "rerun_stage1a_due_to_inconclusive"
    elif systematic_amplification and backend_activity_monotonic in {"yes", "partial"}:
        recommended_next_stage = "Stage2_ExtremeTraffic"
    elif max_activity <= 9 and recovery_counters_still_zero:
        recommended_next_stage = "PBMIngressOrCryptoDMADiagnosis"
    else:
        recommended_next_stage = "rerun_stage1a_due_to_inconclusive"

    return {
        "absolute_activity_floor": ABSOLUTE_ACTIVITY_FLOOR,
        "ratio_gain_epsilon": RATIO_GAIN_EPSILON,
        "stage1a_baseline_source": args.stage1a_baseline_source,
        "stage1a_run_kind": args.stage1a_run_kind,
        "systematic_amplification": systematic_amplification,
        "absolute_gain": absolute_gain,
        "trend_gain": trend_gain,
        "baseline_grouped_median_activity": baseline_activity,
        "backend_activity_monotonic": backend_activity_monotonic,
        "dominant_backend_mode": dominant_backend_mode,
        "effective_work_ratio_trend": effective_work_ratio_trend,
        "recovery_counters_still_zero": recovery_counters_still_zero,
        "recommended_next_stage": recommended_next_stage,
        "reverse_jump_count": reverse_jumps,
    }


def truthy(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    return str(value).strip().lower() in {"1", "true", "yes"}


def median_or_zero(values: list[float]) -> float:
    values = [float(value) for value in values if value is not None]
    if not values:
        return 0.0
    return float(statistics.median(values))


def coefficient_of_variation(values: list[float]) -> float | None:
    values = [float(value) for value in values if value is not None and float(value) > 0.0]
    if not values:
        return None
    mean_value = statistics.fmean(values)
    if mean_value == 0.0:
        return None
    return float(statistics.pstdev(values) / mean_value)


def audit_group_rows(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault(str(row.get("audit_config") or ""), []).append(row)
    return groups


def median_drop_for_group(groups: dict[str, list[dict[str, Any]]], group_name: str) -> float:
    return median_or_zero([float(row.get("drop_pulse_count", 0) or 0) for row in groups.get(group_name, [])])


def drop_pulse_audit(rows: list[dict[str, Any]]) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    excluded_rows = [row for row in rows if not is_included_in_stats(row)]
    groups = audit_group_rows(included_rows)
    idle_rows = groups.get("IdleControl", [])
    idle_nonzero_count = sum(1 for row in idle_rows if int(row.get("drop_pulse_count", 0) or 0) > 0)
    idle_median = median_or_zero([float(row.get("drop_pulse_count", 0) or 0) for row in idle_rows])
    idle_nonzero = idle_median > 0.0 or (len(idle_rows) > 0 and idle_nonzero_count >= 2)

    settle_config_names = [
        "Settle_BF1_SM10",
        "Settle_BF1_SM50",
        "Settle_BF1_SM100",
        "Shared_BF1_SM500",
    ]
    settle_rates: dict[str, float | None] = {}
    settle_medians: list[float] = []
    for config_name in settle_config_names:
        group_rows = groups.get(config_name, [])
        median_drop = median_or_zero([float(row.get("drop_pulse_count", 0) or 0) for row in group_rows])
        settle_ms = median_or_zero([float(row.get("SettleMs", 0) or 0) for row in group_rows])
        settle_rates[config_name] = safe_ratio(median_drop, settle_ms) if settle_ms > 0 else None
        settle_medians.append(median_drop)
    nonzero_rates = [float(rate) for rate in settle_rates.values() if rate is not None and float(rate) > 0.0]
    rate_cv = coefficient_of_variation(nonzero_rates)
    rate_ratio_ok = bool(nonzero_rates) and max(nonzero_rates) / max(min(nonzero_rates), 1e-9) <= 2.0
    rate_cv_ok = rate_cv is not None and rate_cv <= 0.30
    longer_windows_not_decreasing = all(
        current + ABSOLUTE_ACTIVITY_FLOOR >= previous
        for previous, current in zip(settle_medians, settle_medians[1:])
    )
    settle_linear_like = len(nonzero_rates) >= 2 and (rate_ratio_ok or rate_cv_ok) and longer_windows_not_decreasing

    bf1_median = median_drop_for_group(groups, "Shared_BF1_SM500")
    bf8_median = median_drop_for_group(groups, "Burst_BF8_SM500")
    bf64_median = median_drop_for_group(groups, "Burst_BF64_SM500")
    burst_scaled = (
        not idle_nonzero
        and bf1_median > 0.0
        and bf64_median >= 2.0 * bf1_median
        and (bf8_median >= bf1_median or bf8_median >= 0.5 * bf64_median)
    )

    backend_activity_values = [
        float(row.get("backend_accept_cycles", 0) or 0) + float(row.get("backend_starvation_cycles", 0) or 0)
        for row in included_rows
    ]
    backend_weak = max(backend_activity_values + [0.0]) < ABSOLUTE_ACTIVITY_FLOOR
    drop_nonzero_rows = [row for row in included_rows if int(row.get("drop_pulse_count", 0) or 0) > 0]
    backend_nonzero_rows = [
        row
        for row in included_rows
        if int(row.get("backend_accept_cycles", 0) or 0) > 0
        or int(row.get("backend_starvation_cycles", 0) or 0) > 0
    ]
    drop_pulse_backend_activity_coupled = bool(drop_nonzero_rows and backend_nonzero_rows and not backend_weak)

    pre_nonzero_count = sum(1 for row in included_rows if truthy(row.get("audit_pre_snapshot_after_clear_nonzero")))
    negative_delta_count = sum(1 for row in included_rows if int(row.get("drop_pulse_count", 0) or 0) < 0)
    if pre_nonzero_count > 0 or idle_nonzero or excluded_rows or negative_delta_count > 0:
        classification = "sampling_or_clear_artifact"
        recommended_next_stage = "FixCounterSamplingAndRerunStage1A"
    elif settle_linear_like and not burst_scaled and backend_weak:
        classification = "active_level_or_sustained_backpressure"
        recommended_next_stage = "PBMIngressOrCryptoDMADiagnosis"
    elif burst_scaled and not settle_linear_like:
        classification = "burst_correlated_drop_pulse"
        recommended_next_stage = "DropRollbackCouplingDiagnosis"
    else:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a_drop_pulse_audit_due_to_inconclusive"

    nonzero_counter_names = [
        field
        for field in FRONTEND_PRESSURE_COUNTERS
        if max([int(row.get(field, 0) or 0) for row in included_rows] + [0]) > 0
    ]
    return {
        "drop_pulse_idle_nonzero": idle_nonzero,
        "drop_pulse_idle_nonzero_reason": (
            f"idle_median={idle_median}, idle_nonzero_repeats={idle_nonzero_count}/{len(idle_rows)}"
        ),
        "drop_pulse_settle_linear_like": settle_linear_like,
        "drop_pulse_settle_rate_per_ms": settle_rates,
        "drop_pulse_settle_rate_cv": rate_cv,
        "drop_pulse_burst_scaled": burst_scaled,
        "drop_pulse_backend_activity_coupled": drop_pulse_backend_activity_coupled,
        "drop_pulse_nonzero_rate": safe_ratio(len(drop_nonzero_rows), max(1, len(included_rows))),
        "drop_pulse_semantics_classification": classification,
        "recommended_next_stage": recommended_next_stage,
        "pre_snapshot_after_clear_nonzero_count": pre_nonzero_count,
        "nonzero_frontend_pressure_counters": nonzero_counter_names,
        "group_median_drop_pulse_count": {
            "IdleControl": idle_median,
            "Shared_BF1_SM500": bf1_median,
            "Burst_BF8_SM500": bf8_median,
            "Burst_BF64_SM500": bf64_median,
        },
    }


def bool_or_unknown(value: bool | None) -> bool | str:
    if value is None:
        return "unknown"
    return value


def artifact_hash_match(reference_manifest: dict[str, Any], args: argparse.Namespace) -> dict[str, bool | str]:
    current_boot = sha256_file(Path(args.boot_bin)) if args.boot_bin else None
    current_bit = sha256_file(Path(args.bit_file)) if args.bit_file else None
    current_xsa = sha256_file(Path(args.xsa_file)) if args.xsa_file else None

    reference_boot = (reference_manifest.get("boot_bin") or {}).get("sha256")
    reference_bit = (reference_manifest.get("bit_file") or {}).get("sha256")
    reference_xsa = (reference_manifest.get("xsa_file") or {}).get("sha256")

    return {
        "boot_bin": bool_or_unknown(current_boot == reference_boot if current_boot and reference_boot else None),
        "bit": bool_or_unknown(current_bit == reference_bit if current_bit and reference_bit else None),
        "xsa": bool_or_unknown(current_xsa == reference_xsa if current_xsa and reference_xsa else None),
        "csr_map": "unknown",
    }


def compare_case_parameters(reference_manifest: dict[str, Any], args: argparse.Namespace) -> dict[str, list[Any]]:
    reference_params = reference_manifest.get("case_parameters") or {}
    current_params = vars(args)
    differing: dict[str, list[Any]] = {}
    for field in (
        "stage",
        "traffic_mode",
        "burst_gap_us",
        "settle_ms",
        "load_class",
        "repeat_count",
        "burst_frames",
    ):
        reference_value = reference_params.get(field)
        current_value = current_params.get(field)
        if reference_value != current_value:
            differing[field] = [reference_value, current_value]
    return differing


def old_median_drop_pulse_by_config(reference_rows: list[dict[str, Any]]) -> dict[str, float]:
    grouped: dict[str, list[float]] = {config_name: [] for config_name, _, _ in PRIOR_DROP_PULSE_CONFIG_ORDER}
    for row in reference_rows:
        burst_frames = int(float(row.get("BurstFrames", 0) or 0))
        config_name = PRIOR_DROP_PULSE_CONFIG_BY_BURST.get(burst_frames)
        if config_name:
            grouped.setdefault(config_name, []).append(float(row.get("drop_pulse_count", 0) or 0))
    return {config_name: median_or_zero(grouped.get(config_name, [])) for config_name, _, _ in PRIOR_DROP_PULSE_CONFIG_ORDER}


def replay_median_drop_pulse_by_config(rows: list[dict[str, Any]]) -> dict[str, float]:
    grouped: dict[str, list[float]] = {config_name: [] for config_name, _, _ in PRIOR_DROP_PULSE_CONFIG_ORDER}
    for row in rows:
        config_name = str(row.get("reproduction_config") or PRIOR_DROP_PULSE_CONFIG_BY_BURST.get(int(float(row.get("BurstFrames", 0) or 0)), ""))
        if config_name:
            grouped.setdefault(config_name, []).append(float(row.get("drop_pulse_count", 0) or 0))
    return {config_name: median_or_zero(grouped.get(config_name, [])) for config_name, _, _ in PRIOR_DROP_PULSE_CONFIG_ORDER}


def prior_drop_pulse_reproduction(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    excluded_rows = [row for row in rows if not is_included_in_stats(row)]
    reference_full = reference_run_payload(args.stage1a6_reference_stage1a_full_dir)
    reference_audit = reference_run_payload(args.stage1a6_reference_stage1a5_audit_dir)

    pre_nonzero_windows = [
        str(row.get("probe_window_id"))
        for row in included_rows
        if truthy(row.get("repro_pre_snapshot_after_clear_nonzero"))
    ]
    pre_nonzero_count = len(pre_nonzero_windows)
    alignment_valid = all(str(row.get("probe_window_id") or "").strip() for row in included_rows)
    negative_delta_seen = any(float(row.get("drop_pulse_count", 0) or 0) < 0.0 for row in included_rows)
    backend_activity_seen = any(
        int(row.get("backend_accept_cycles", 0) or 0) > 0 or int(row.get("backend_starvation_cycles", 0) or 0) > 0
        for row in included_rows
    )
    backend_activity_weak = max(
        [
            int(row.get("backend_accept_cycles", 0) or 0) + int(row.get("backend_starvation_cycles", 0) or 0)
            for row in included_rows
        ]
        + [0]
    ) < ABSOLUTE_ACTIVITY_FLOOR
    drop_nonzero_rows = [row for row in included_rows if int(row.get("drop_pulse_count", 0) or 0) > 0]
    old_medians = old_median_drop_pulse_by_config(reference_full.get("rows", []))
    replay_medians = replay_median_drop_pulse_by_config(included_rows)
    ratios = {
        config_name: (replay_medians[config_name] / old_medians[config_name] if old_medians[config_name] > 0 else None)
        for config_name, _, _ in PRIOR_DROP_PULSE_CONFIG_ORDER
    }

    replay_all_zero = all(replay_medians[config_name] == 0.0 for config_name, _, _ in PRIOR_DROP_PULSE_CONFIG_ORDER)
    weak_reproduction = any((ratio or 0.0) >= 0.1 for ratio in ratios.values())
    strong_reproduction = sum(1 for ratio in ratios.values() if (ratio or 0.0) >= 0.5) >= 2

    if pre_nonzero_count > 0 or negative_delta_seen or not alignment_valid:
        classification = "sampling_or_clear_artifact"
        recommended_next_stage = "FixCounterSamplingAndRerunStage1A"
        reproduced_prior_drop_pulse = False
    elif len(included_rows) < 9 or len(excluded_rows) > 0:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a6_due_to_inconclusive"
        reproduced_prior_drop_pulse = False
    elif replay_all_zero and backend_activity_weak:
        classification = "not_reproduced_under_controlled_sampling"
        recommended_next_stage = "PBMIngressOrCryptoDMADiagnosis"
        reproduced_prior_drop_pulse = False
    elif weak_reproduction or strong_reproduction:
        classification = "reproduced_prior_drop_pulse"
        recommended_next_stage = "DropPulseConditionDiffDiagnosis"
        reproduced_prior_drop_pulse = True
    else:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a6_due_to_inconclusive"
        reproduced_prior_drop_pulse = False

    return {
        "reference_stage1a_full_dir": reference_full.get("dir"),
        "reference_stage1a5_audit_dir": reference_audit.get("dir"),
        "reproduction_mode": args.reproduction_mode,
        "artifact_hash_match": artifact_hash_match(reference_full.get("manifest", {}), args),
        "invocation_diff_summary": {
            "reference_stage1a_full_differing_case_parameters": compare_case_parameters(reference_full.get("manifest", {}), args),
            "reference_stage1a5_audit_differing_case_parameters": compare_case_parameters(reference_audit.get("manifest", {}), args),
        },
        "controlled_replay_configs": [config_name for config_name, _, _ in PRIOR_DROP_PULSE_CONFIG_ORDER],
        "raw_sample_count": len(rows),
        "excluded_sample_count": len(excluded_rows),
        "pre_after_clear_nonzero_count": pre_nonzero_count,
        "pre_after_clear_nonzero_windows": pre_nonzero_windows,
        "drop_pulse_nonzero_rate": safe_ratio(len(drop_nonzero_rows), max(1, len(included_rows))),
        "backend_activity_seen": backend_activity_seen,
        "old_median_drop_pulse_by_config": old_medians,
        "replay_median_drop_pulse_by_config": replay_medians,
        "old_vs_replay_drop_ratio_by_config": {key: (0.0 if value is None else value) for key, value in ratios.items()},
        "reproduced_prior_drop_pulse": reproduced_prior_drop_pulse,
        "drop_pulse_reproduction_classification": classification,
        "recommended_next_stage": recommended_next_stage,
        "controlled_replay_invariants": {
            "boot_bin hash": True,
            "bit hash": True,
            "xsa hash": True,
            "Case2_RuntimeRingBypass": True,
            "BF1/BF8/BF64": True,
            "BurstGapUs=0": True,
            "SettleMs=500": True,
            "runtime ring bypass setting": True,
            "fastpath state": True,
            "CSR/counter address map": "unknown",
        },
        "allowed_changes": [
            "stage path",
            "controlled clear/snapshot sequence",
            "report wording",
            "paper_plot_data gate",
        ],
        "backend_activity_weak": backend_activity_weak,
    }


def group_by_condition_config(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault(str(row.get("condition_diff_config") or ""), []).append(row)
    return groups


def row_has_strong_valid_not_ready_stall(row: dict[str, Any]) -> bool:
    return (
        int_value(row.get("stage1_inject_tvalid", 0)) == 1
        and int_value(row.get("stage1_inject_tready", 0)) == 0
        and int_value(row.get("aclf_tvalid", 0)) == 1
        and int_value(row.get("aclf_tready", 0)) == 0
        and int_value(row.get("classifier_s_tvalid", 0)) == 1
        and int_value(row.get("classifier_s_tready", 0)) == 0
        and int_value(row.get("classifier_dma_tvalid", 0)) == 1
        and int_value(row.get("classifier_dma_tready", 0)) == 0
    )


def row_has_partial_valid_not_ready_stall(row: dict[str, Any]) -> bool:
    ingress_or_dma_stall = (
        (int_value(row.get("stage1_inject_tvalid", 0)) == 1 and int_value(row.get("stage1_inject_tready", 0)) == 0)
        or (int_value(row.get("classifier_s_tvalid", 0)) == 1 and int_value(row.get("classifier_s_tready", 0)) == 0)
        or (int_value(row.get("classifier_dma_tvalid", 0)) == 1 and int_value(row.get("classifier_dma_tready", 0)) == 0)
    )
    return (
        ingress_or_dma_stall
        and int_value(row.get("drop_pulse_count", 0)) > 0
        and int_value(row.get("inj_fifo_nonempty", 0)) == 1
        and not any_nonzero(row, BACKEND_SERVICE_COUNTERS)
    )


def stage1a7_condition_diff(rows: list[dict[str, Any]]) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups = group_by_condition_config(included_rows)
    bf8_rows = groups.get("BF8_SM500", [])
    bf64_rows = groups.get("BF64_SM500", [])
    bf64_sm100_rows = groups.get("BF64_SM100", [])
    bf64_extra_rows = groups.get("BF64_SM500_ExtraSnapshots", [])

    frontend_pressure_seen = any_nonzero_rows(included_rows, FRONTEND_PRESSURE_COUNTERS)
    rollback_recovery_seen = any_nonzero_rows(included_rows, ROLLBACK_RECOVERY_COUNTERS)
    backend_activity_seen = any_nonzero_rows(included_rows, BACKEND_SERVICE_COUNTERS)

    bf8_has_stall = bool_majority(bf8_rows, row_has_partial_valid_not_ready_stall)
    bf64_has_stall = bool_majority(bf64_rows, row_has_partial_valid_not_ready_stall)
    strong_stall = bool_majority(bf64_rows, row_has_strong_valid_not_ready_stall) and not bf8_has_stall
    partial_stall = (not strong_stall) and bool_majority(bf64_rows, row_has_partial_valid_not_ready_stall)
    negative_control_valid = not bf8_has_stall
    negative_control_violation_reason = (
        "BF8_SM500 entered the same decoded ingress/front-end stall state as BF64_SM500"
        if not negative_control_valid
        else "BF8_SM500 remained a clean negative control under the current board run"
    )
    if negative_control_valid:
        condition_diff_status = "clean_negative_control"
    elif bf64_has_stall:
        condition_diff_status = "no_clean_negative_control"
    else:
        condition_diff_status = "positive_condition_not_reproduced"

    ingress_progress_stalled = bool_majority(
        bf64_rows,
        lambda row: (
            int_value(row.get("inj_fifo_nonempty", 0)) == 1
            or int_value(row.get("inj_fifo_count", 0)) > 0
        )
        and int_value(row.get("source_progress_pre", 0)) == 0
        and int_value(row.get("source_progress_post", 0)) == 0
        and int_value(row.get("sink_progress_pre", 0)) == 0
        and int_value(row.get("sink_progress_post", 0)) == 0
        and int_value(row.get("observed_injection_intensity_frames_per_probe_window", 0)) == 0,
    )

    bf64_sm500_drop = median_or_zero([float(row.get("drop_pulse_count", 0) or 0) for row in bf64_rows])
    bf64_sm100_drop = median_or_zero([float(row.get("drop_pulse_count", 0) or 0) for row in bf64_sm100_rows])
    bf64_sm500_cycles = median_or_zero([float(row.get("backend_total_cycles", 0) or 0) for row in bf64_rows])
    bf64_sm100_cycles = median_or_zero([float(row.get("backend_total_cycles", 0) or 0) for row in bf64_sm100_rows])
    bf64_sm500_rate_per_cycle = safe_ratio(bf64_sm500_drop, bf64_sm500_cycles) if bf64_sm500_cycles > 0 else None
    bf64_sm100_rate_per_cycle = safe_ratio(bf64_sm100_drop, bf64_sm100_cycles) if bf64_sm100_cycles > 0 else None
    bf64_sm500_rate_per_ms = safe_ratio(bf64_sm500_drop, 500.0)
    bf64_sm100_rate_per_ms = safe_ratio(bf64_sm100_drop, 100.0)

    drop_pulse_window_scaled = (
        bf64_sm100_drop > 0
        and bf64_sm100_drop < bf64_sm500_drop
        and bf64_sm500_rate_per_cycle is not None
        and bf64_sm100_rate_per_cycle is not None
        and bf64_sm500_rate_per_cycle > 0
        and bf64_sm100_rate_per_cycle > 0
        and max(bf64_sm500_rate_per_cycle, bf64_sm100_rate_per_cycle)
        / min(bf64_sm500_rate_per_cycle, bf64_sm100_rate_per_cycle)
        <= 2.0
    )
    drop_pulse_window_short_no_trigger = bf64_sm100_drop == 0 and bf64_sm500_drop > 0

    extra_snapshot_deltas = {
        "drop_pulse_delta_at_post_injection": summarize_values(
            [row.get("drop_pulse_delta_at_post_injection") for row in bf64_extra_rows if row.get("drop_pulse_delta_at_post_injection") is not None]
        ),
        "drop_pulse_delta_at_050ms": summarize_values(
            [row.get("drop_pulse_delta_at_050ms") for row in bf64_extra_rows if row.get("drop_pulse_delta_at_050ms") is not None]
        ),
        "drop_pulse_delta_at_250ms": summarize_values(
            [row.get("drop_pulse_delta_at_250ms") for row in bf64_extra_rows if row.get("drop_pulse_delta_at_250ms") is not None]
        ),
        "drop_pulse_delta_at_500ms": summarize_values(
            [row.get("drop_pulse_delta_at_500ms") for row in bf64_extra_rows if row.get("drop_pulse_delta_at_500ms") is not None]
        ),
    }

    if strong_stall or partial_stall:
        if ingress_progress_stalled and frontend_pressure_seen and not backend_activity_seen and not rollback_recovery_seen:
            recommended_next_stage = "PBMIngressVisibilityDiagnosis"
        else:
            recommended_next_stage = "FixStatusDecodeOrSampling"
    elif rollback_recovery_seen:
        recommended_next_stage = "DropRollbackCouplingDiagnosis"
    else:
        recommended_next_stage = "FixStatusDecodeOrSampling"

    return {
        "planned_negative_control": "BF8_SM500",
        "planned_positive_condition": "BF64_SM500",
        "negative_control_valid": negative_control_valid,
        "negative_control_violation_reason": negative_control_violation_reason,
        "bf8_observed_stall": bf8_has_stall,
        "bf64_observed_stall": bf64_has_stall,
        "condition_diff_status": condition_diff_status,
        "frontend_pressure_seen": frontend_pressure_seen,
        "rollback_recovery_seen": rollback_recovery_seen,
        "backend_activity_seen": backend_activity_seen,
        "frontend_valid_not_ready_stall_strong": strong_stall,
        "frontend_valid_not_ready_stall_partial": partial_stall,
        "ingress_progress_stalled": ingress_progress_stalled,
        "drop_pulse_window_scaled": drop_pulse_window_scaled,
        "drop_pulse_window_short_no_trigger": drop_pulse_window_short_no_trigger,
        "drop_pulse_rate_per_ms": {
            "BF64_SM500": bf64_sm500_rate_per_ms,
            "BF64_SM100": bf64_sm100_rate_per_ms,
        },
        "drop_pulse_rate_per_backend_cycle": {
            "BF64_SM500": bf64_sm500_rate_per_cycle,
            "BF64_SM100": bf64_sm100_rate_per_cycle,
        },
        "extra_snapshot_deltas": extra_snapshot_deltas,
        "bf8_negative_control_netdbg": {
            "raw_decimal": bf8_rows[0].get("netdbg_status_raw_decimal") if bf8_rows else None,
            "hex": bf8_rows[0].get("netdbg_status_hex") if bf8_rows else None,
            "route_state_name": bf8_rows[0].get("netdbg_route_state_name") if bf8_rows else None,
        },
        "bf64_positive_condition_netdbg": {
            "raw_decimal": bf64_rows[0].get("netdbg_status_raw_decimal") if bf64_rows else None,
            "hex": bf64_rows[0].get("netdbg_status_hex") if bf64_rows else None,
            "route_state_name": bf64_rows[0].get("netdbg_route_state_name") if bf64_rows else None,
        },
        "recommended_next_stage": recommended_next_stage,
    }


def group_by_pbm_visibility_config(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault(str(row.get("pbm_visibility_config") or ""), []).append(row)
    return groups


def stage1a8_pbm_ingress_visibility(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups = group_by_pbm_visibility_config(included_rows)
    idle_rows = groups.get("IdleControl", [])
    bf8_rows = groups.get("BF8_SM500", [])
    bf64_rows = groups.get("BF64_SM500", [])
    bf8_extra_rows = groups.get("BF8_SM500_ExtraSnapshots", [])
    bf64_extra_rows = groups.get("BF64_SM500_ExtraSnapshots", [])

    frontend_pressure_seen = any_nonzero_rows(included_rows, FRONTEND_PRESSURE_COUNTERS)
    rollback_recovery_seen = any_nonzero_rows(included_rows, ROLLBACK_RECOVERY_COUNTERS)
    backend_activity_seen = any_nonzero_rows(included_rows, BACKEND_SERVICE_COUNTERS)
    collision = pbm_diag_csr_collision(Path(args.repo_root))
    idle_control_quiesce_guard_ms = int_value(idle_rows[0].get("idle_control_quiesce_guard_ms", 0)) if idle_rows else 0
    idle_pre_after_clear_zero = bool_majority(idle_rows, lambda row: truthy(row.get("idle_pre_after_clear_zero")))
    idle_residual_activity_seen = bool_majority(
        idle_rows,
        lambda row: truthy(row.get("idle_residual_activity_seen"))
        or int_value(row.get("pbm_valid_not_ready_cycles", 0)) > 0
        or int_value(row.get("drop_pulse_count", 0)) > 0,
    )
    sampling_or_alignment_issue = (
        collision
        or idle_residual_activity_seen
        or any(str(row.get("pbm_state_decoded", "")).startswith("unknown_state_") for row in included_rows)
    )

    pbm_ingress_valid_not_ready_stall = bool_majority(
        bf64_rows,
        lambda row: int_value(row.get("pbm_wr_valid_cycles", 0)) > 0
        and int_value(row.get("pbm_valid_not_ready_cycles", 0)) > 0
        and int_value(row.get("pbm_wr_accept_cycles", 0)) == 0,
    )
    pbm_accept_without_packet_end = bool_majority(
        bf64_rows,
        lambda row: int_value(row.get("pbm_wr_accept_cycles", 0)) > 0
        and int_value(row.get("pbm_wr_last_accepted_count", 0)) == 0
        and int_value(row.get("pbm_ptr_head_reserve_delta_mod", 0)) > 0
        and int_value(row.get("pbm_ptr_head_commit_delta_mod", 0)) == 0,
    )
    pbm_commit_without_backend_service = bool_majority(
        bf64_rows,
        lambda row: (
            int_value(row.get("pbm_commit_entry_count", 0)) > 0
            or int_value(row.get("pbm_ptr_head_commit_delta_mod", 0)) > 0
        )
        and not backend_activity_seen,
    )
    pbm_rollback_trigger_candidate_seen = bool_majority(
        bf64_rows, lambda row: int_value(row.get("pbm_wr_last_error_accepted_count", 0)) > 0
    )
    pbm_rollback_path_observed = bool_majority(
        bf64_rows, lambda row: int_value(row.get("pbm_rollback_entry_count", 0)) > 0
    ) or rollback_recovery_seen

    if sampling_or_alignment_issue:
        recommended_next_stage = "FixSamplingOrAlignment"
    elif pbm_rollback_path_observed or pbm_rollback_trigger_candidate_seen:
        recommended_next_stage = "DropRollbackCouplingDiagnosis"
    elif pbm_commit_without_backend_service:
        recommended_next_stage = "CryptoDMAHandoffDiagnosis"
    elif pbm_accept_without_packet_end:
        recommended_next_stage = "PacketTerminationVisibilityDiagnosis"
    elif pbm_ingress_valid_not_ready_stall:
        recommended_next_stage = "PBMReadyGatingDiagnosis"
    else:
        recommended_next_stage = "rerun_pbm_ingress_visibility_due_to_inconclusive"

    def summarize_extra(rows_for_group: list[dict[str, Any]], field: str) -> dict[str, Any]:
        return summarize_values([row.get(field) for row in rows_for_group if row.get(field) is not None])

    return {
        "diagnostic_csr_map_version": PBM_DIAG_CSR_MAP_VERSION,
        "diagnostic_csr_address_range": "0x154-0x190",
        "pbm_diag_csr_collision": collision,
        "frontend_pressure_seen": frontend_pressure_seen,
        "backend_activity_seen": backend_activity_seen,
        "rollback_recovery_seen": rollback_recovery_seen,
        "idle_control_quiesce_guard_ms": idle_control_quiesce_guard_ms,
        "idle_pre_after_clear_zero": idle_pre_after_clear_zero,
        "idle_residual_activity_seen": idle_residual_activity_seen,
        "pbm_ingress_valid_not_ready_stall": pbm_ingress_valid_not_ready_stall,
        "pbm_accept_without_packet_end": pbm_accept_without_packet_end,
        "pbm_commit_without_backend_service": pbm_commit_without_backend_service,
        "pbm_rollback_trigger_candidate_seen": pbm_rollback_trigger_candidate_seen,
        "pbm_rollback_path_observed": pbm_rollback_path_observed,
        "bf8_rows_seen": len(bf8_rows),
        "bf64_rows_seen": len(bf64_rows),
        "bf8_extra_rows_seen": len(bf8_extra_rows),
        "bf64_extra_rows_seen": len(bf64_extra_rows),
        "bf8_snapshot_mode": sorted({str(row.get("stage1a8_snapshot_mode") or "") for row in bf8_rows + bf8_extra_rows}),
        "bf64_snapshot_mode": sorted({str(row.get("stage1a8_snapshot_mode") or "") for row in bf64_rows + bf64_extra_rows}),
        "bf8_drop_pulse_count": summarize_values([row.get("drop_pulse_count") for row in bf8_rows]),
        "bf64_drop_pulse_count": summarize_values([row.get("drop_pulse_count") for row in bf64_rows]),
        "bf8_extra_snapshot_deltas": {
            "drop_pulse_delta_at_post_injection": summarize_extra(bf8_extra_rows, "drop_pulse_delta_at_post_injection"),
            "drop_pulse_delta_at_050ms": summarize_extra(bf8_extra_rows, "drop_pulse_delta_at_050ms"),
            "drop_pulse_delta_at_250ms": summarize_extra(bf8_extra_rows, "drop_pulse_delta_at_250ms"),
            "drop_pulse_delta_at_500ms": summarize_extra(bf8_extra_rows, "drop_pulse_delta_at_500ms"),
        },
        "bf64_extra_snapshot_deltas": {
            "drop_pulse_delta_at_post_injection": summarize_extra(bf64_extra_rows, "drop_pulse_delta_at_post_injection"),
            "drop_pulse_delta_at_050ms": summarize_extra(bf64_extra_rows, "drop_pulse_delta_at_050ms"),
            "drop_pulse_delta_at_250ms": summarize_extra(bf64_extra_rows, "drop_pulse_delta_at_250ms"),
            "drop_pulse_delta_at_500ms": summarize_extra(bf64_extra_rows, "drop_pulse_delta_at_500ms"),
            "pbm_wr_valid_cycles_delta_at_050ms": summarize_extra(bf64_extra_rows, "pbm_wr_valid_cycles_delta_at_050ms"),
            "pbm_valid_not_ready_cycles_delta_at_050ms": summarize_extra(bf64_extra_rows, "pbm_valid_not_ready_cycles_delta_at_050ms"),
            "pbm_wr_accept_cycles_delta_at_050ms": summarize_extra(bf64_extra_rows, "pbm_wr_accept_cycles_delta_at_050ms"),
        },
        "recommended_next_stage": recommended_next_stage,
    }


def group_by_pbm_ready_gating_config(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault(str(row.get("pbm_ready_gating_config") or ""), []).append(row)
    return groups


def stage1a21_pbm_ready_gating_diagnosis(
    rows: list[dict[str, Any]], args: argparse.Namespace
) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups = group_by_pbm_ready_gating_config(included_rows)
    idle_rows = groups.get("IdleControl", [])
    bf64_rows = groups.get("BF64_SM500", [])
    bf64_extra_rows = groups.get("BF64_SM500_ExtraSnapshots", [])
    active_rows = bf64_rows + bf64_extra_rows

    def state_name(row: dict[str, Any]) -> str:
        return str(row.get("pbm_state_decoded") or "")

    has_required_configs = bool(idle_rows) and bool(bf64_rows) and bool(bf64_extra_rows)
    idle_residual_activity_seen = bool_majority(
        idle_rows,
        lambda row: truthy(row.get("idle_residual_activity_seen"))
        or int_value(row.get("pbm_wr_valid_cycles", 0)) > 0
        or int_value(row.get("pbm_valid_not_ready_cycles", 0)) > 0
        or int_value(row.get("drop_pulse_count", 0)) > 0,
    )
    unknown_state_seen = any(state_name(row).startswith("unknown_state_") for row in included_rows)
    idle_commit_tail_gap_seen = bool_majority(
        idle_rows,
        lambda row: int_value(row.get("pbm_ptr_head_commit_pre", 0))
        == int_value(row.get("pbm_ptr_head_reserve_pre", 0))
        and int_value(row.get("pbm_ptr_tail_pre", 0))
        != int_value(row.get("pbm_ptr_head_commit_pre", 0)),
    )
    idle_pbm_read_side_nonempty_seen = bool_majority(
        idle_rows,
        lambda row: int_value(row.get("pbm_rd_nonempty_cycles", 0)) > 0
        or int_value(row.get("pbm_committed_available_cycles", 0)) > 0,
    )
    bf64_alloc_meta_no_ready_seen = bool_majority(
        active_rows,
        lambda row: state_name(row) in {"ALLOC_META", "ALLOC_PBM"}
        and int_value(row.get("pbm_wr_valid_cycles", 0)) > 0
        and int_value(row.get("pbm_wr_ready_high_cycles", 0)) == 0
        and int_value(row.get("pbm_wr_accept_cycles", 0)) == 0,
    )
    bf64_valid_not_ready_seen = bool_majority(
        active_rows,
        lambda row: int_value(row.get("pbm_valid_not_ready_cycles", 0)) > 0
        and int_value(row.get("pbm_wr_accept_cycles", 0)) == 0,
    )
    ready_low_due_to_full_inferred = bool_majority(
        active_rows,
        lambda row: state_name(row) in {"ALLOC_META", "ALLOC_PBM"}
        and int_value(row.get("pbm_wr_valid_cycles", 0)) > 0
        and int_value(row.get("pbm_wr_ready_high_cycles", 0)) == 0
        and int_value(row.get("pbm_valid_not_ready_cycles", 0)) > 0
        and int_value(row.get("pbm_wr_accept_cycles", 0)) == 0,
    )
    ready_low_due_to_state_inferred = bool_majority(
        active_rows,
        lambda row: state_name(row) not in {"ALLOC_META", "ALLOC_PBM"}
        and not state_name(row).startswith("unknown_state_")
        and int_value(row.get("pbm_wr_valid_cycles", 0)) > 0
        and int_value(row.get("pbm_wr_ready_high_cycles", 0)) == 0
        and int_value(row.get("pbm_valid_not_ready_cycles", 0)) > 0
        and int_value(row.get("pbm_wr_accept_cycles", 0)) == 0,
    )
    preexisting_pointer_gap_seen = idle_commit_tail_gap_seen and idle_pbm_read_side_nonempty_seen

    if not included_rows or not has_required_configs or idle_residual_activity_seen or unknown_state_seen:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a21_due_to_inconclusive"
    elif ready_low_due_to_state_inferred:
        classification = "ready_low_due_to_state_inferred"
        recommended_next_stage = "PBMStateGatingDiagnosis"
    elif ready_low_due_to_full_inferred and preexisting_pointer_gap_seen:
        classification = "ready_low_due_to_full_pointer_gap_inferred"
        recommended_next_stage = "PBMPointerResetOrDrainDiagnosis"
    elif ready_low_due_to_full_inferred:
        classification = "ready_low_due_to_full_without_idle_gap"
        recommended_next_stage = "PBMFullConditionDiagnosis"
    else:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a21_due_to_inconclusive"

    return {
        "raw_sample_count": len(rows),
        "included_sample_count": len(included_rows),
        "diagnostic_csr_map_version": PBM_DIAG_CSR_MAP_VERSION,
        "diagnostic_csr_address_range": "0x154-0x1C4",
        "pbm_diag_csr_collision": pbm_diag_csr_collision(Path(args.repo_root)),
        "idle_rows_seen": len(idle_rows),
        "bf64_rows_seen": len(bf64_rows),
        "bf64_extra_rows_seen": len(bf64_extra_rows),
        "idle_commit_tail_gap_seen": idle_commit_tail_gap_seen,
        "idle_pbm_read_side_nonempty_seen": idle_pbm_read_side_nonempty_seen,
        "preexisting_pointer_gap_seen": preexisting_pointer_gap_seen,
        "bf64_alloc_meta_no_ready_seen": bf64_alloc_meta_no_ready_seen,
        "bf64_valid_not_ready_seen": bf64_valid_not_ready_seen,
        "ready_low_due_to_full_inferred": ready_low_due_to_full_inferred,
        "ready_low_due_to_state_inferred": ready_low_due_to_state_inferred,
        "idle_snapshot_mode": sorted({str(row.get("stage1a21_snapshot_mode") or "") for row in idle_rows}),
        "bf64_snapshot_mode": sorted({str(row.get("stage1a21_snapshot_mode") or "") for row in active_rows}),
        "pbm_wr_valid_cycles": sum(int_value(row.get("pbm_wr_valid_cycles", 0)) for row in included_rows),
        "pbm_wr_ready_high_cycles": sum(int_value(row.get("pbm_wr_ready_high_cycles", 0)) for row in included_rows),
        "pbm_valid_not_ready_cycles": sum(int_value(row.get("pbm_valid_not_ready_cycles", 0)) for row in included_rows),
        "pbm_wr_accept_cycles": sum(int_value(row.get("pbm_wr_accept_cycles", 0)) for row in included_rows),
        "pbm_rd_nonempty_cycles": sum(int_value(row.get("pbm_rd_nonempty_cycles", 0)) for row in included_rows),
        "pbm_committed_available_cycles": sum(
            int_value(row.get("pbm_committed_available_cycles", 0)) for row in included_rows
        ),
        "pbm_ready_gating_classification": classification,
        "pbm_ready_gating_classification_reason": pbm_ready_gating_reason(classification),
        "recommended_next_stage": recommended_next_stage,
    }


def pbm_ready_gating_reason(classification: str) -> str:
    if classification == "ready_low_due_to_full_pointer_gap_inferred":
        return "PBM write ready stayed low while state remained ALLOC_META/ALLOC_PBM, and IdleControl already showed a commit-tail gap plus read-side nonempty state. The ready-low condition appears preexisting before workload."
    if classification == "ready_low_due_to_full_without_idle_gap":
        return "PBM write ready stayed low while state remained ALLOC_META/ALLOC_PBM, but IdleControl did not show the same preexisting pointer-gap signature."
    if classification == "ready_low_due_to_state_inferred":
        return "PBM ready is blocked by state because valid pressure was observed while PBM state was outside ALLOC_META/ALLOC_PBM."
    return "Stage1A21 did not produce enough aligned IdleControl and BF64 ready-low evidence for a clean branch."


def group_by_pbm_pointer_reset_or_drain_config(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault(str(row.get("pbm_pointer_reset_or_drain_config") or ""), []).append(row)
    return groups


def stage1a22_pbm_pointer_reset_or_drain_diagnosis(
    rows: list[dict[str, Any]], args: argparse.Namespace
) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups = group_by_pbm_pointer_reset_or_drain_config(included_rows)
    idle_no_reset_rows = groups.get("IdleControl_NoReset", [])
    idle_after_soft_reset_rows = groups.get("IdleControl_AfterSoftReset", [])
    bf64_after_soft_reset_rows = groups.get("BF64_SM500_AfterSoftReset", [])

    def pointer_gap_seen(row: dict[str, Any]) -> bool:
        commit_pre = int_value(row.get("pbm_ptr_head_commit_pre", 0))
        reserve_pre = int_value(row.get("pbm_ptr_head_reserve_pre", 0))
        tail_pre = int_value(row.get("pbm_ptr_tail_pre", 0))
        return (
            commit_pre == reserve_pre
            and tail_pre != commit_pre
            and (
                int_value(row.get("pbm_rd_nonempty_cycles", 0)) > 0
                or int_value(row.get("pbm_committed_available_cycles", 0)) > 0
            )
        )

    def gap_cleared(row: dict[str, Any]) -> bool:
        commit_pre = int_value(row.get("pbm_ptr_head_commit_pre", 0))
        reserve_pre = int_value(row.get("pbm_ptr_head_reserve_pre", 0))
        tail_pre = int_value(row.get("pbm_ptr_tail_pre", 0))
        return (
            commit_pre == reserve_pre
            and tail_pre == commit_pre
            and int_value(row.get("pbm_rd_nonempty_cycles", 0)) == 0
            and int_value(row.get("pbm_committed_available_cycles", 0)) == 0
        )

    has_required_configs = bool(idle_no_reset_rows) and bool(idle_after_soft_reset_rows) and bool(
        bf64_after_soft_reset_rows
    )
    idle_no_reset_pointer_gap_seen = bool_majority(idle_no_reset_rows, pointer_gap_seen)
    idle_after_soft_reset_gap_cleared = bool_majority(idle_after_soft_reset_rows, gap_cleared)
    idle_after_soft_reset_pointer_gap_seen = bool_majority(idle_after_soft_reset_rows, pointer_gap_seen)
    idle_after_soft_reset_read_side_nonempty_seen = bool_majority(
        idle_after_soft_reset_rows,
        lambda row: int_value(row.get("pbm_rd_nonempty_cycles", 0)) > 0
        or int_value(row.get("pbm_committed_available_cycles", 0)) > 0,
    )
    idle_after_soft_reset_read_drain_seen = bool_majority(
        idle_after_soft_reset_rows,
        lambda row: int_value(row.get("pbm_rd_en_cycles", 0)) > 0
        or int_value(row.get("pbm_rd_accept_cycles", 0)) > 0,
    )
    soft_reset_pulsed_verified = bool_majority(
        idle_after_soft_reset_rows + bf64_after_soft_reset_rows,
        lambda row: truthy(row.get("dma_soft_reset_pulsed")),
    )
    bf64_after_soft_reset_ready_recovered = bool_majority(
        bf64_after_soft_reset_rows,
        lambda row: int_value(row.get("pbm_wr_ready_high_cycles", 0)) > 0
        or int_value(row.get("pbm_wr_accept_cycles", 0)) > 0,
    )
    bf64_after_soft_reset_accept_seen = bool_majority(
        bf64_after_soft_reset_rows,
        lambda row: int_value(row.get("pbm_wr_accept_cycles", 0)) > 0,
    )
    bf64_after_soft_reset_valid_not_ready_seen = bool_majority(
        bf64_after_soft_reset_rows,
        lambda row: int_value(row.get("pbm_valid_not_ready_cycles", 0)) > 0
        and int_value(row.get("pbm_wr_accept_cycles", 0)) == 0,
    )

    if not included_rows or not has_required_configs or not soft_reset_pulsed_verified or not idle_no_reset_pointer_gap_seen:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a22_due_to_inconclusive"
    elif idle_after_soft_reset_gap_cleared and bf64_after_soft_reset_ready_recovered:
        classification = "soft_reset_clears_gap_and_ready_recovers"
        recommended_next_stage = "PBMResetOrRestorePathDiagnosis"
    elif idle_after_soft_reset_pointer_gap_seen and not idle_after_soft_reset_read_drain_seen:
        classification = "pointer_gap_persists_after_soft_reset"
        recommended_next_stage = "PBMCommitTailPointerInvariantDiagnosis"
    elif idle_after_soft_reset_read_side_nonempty_seen:
        classification = "read_side_nonempty_persists_after_soft_reset"
        recommended_next_stage = "PBMReadSideDrainDiagnosis"
    elif idle_after_soft_reset_gap_cleared:
        classification = "soft_reset_clears_gap_but_ready_stays_low"
        recommended_next_stage = "PBMResetOrRestorePathDiagnosis"
    else:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a22_due_to_inconclusive"

    return {
        "raw_sample_count": len(rows),
        "included_sample_count": len(included_rows),
        "idle_no_reset_rows_seen": len(idle_no_reset_rows),
        "idle_after_soft_reset_rows_seen": len(idle_after_soft_reset_rows),
        "bf64_after_soft_reset_rows_seen": len(bf64_after_soft_reset_rows),
        "idle_no_reset_pointer_gap_seen": idle_no_reset_pointer_gap_seen,
        "idle_after_soft_reset_gap_cleared": idle_after_soft_reset_gap_cleared,
        "idle_after_soft_reset_pointer_gap_seen": idle_after_soft_reset_pointer_gap_seen,
        "idle_after_soft_reset_read_side_nonempty_seen": idle_after_soft_reset_read_side_nonempty_seen,
        "idle_after_soft_reset_read_drain_seen": idle_after_soft_reset_read_drain_seen,
        "soft_reset_pulsed_verified": soft_reset_pulsed_verified,
        "bf64_after_soft_reset_ready_recovered": bf64_after_soft_reset_ready_recovered,
        "bf64_after_soft_reset_accept_seen": bf64_after_soft_reset_accept_seen,
        "bf64_after_soft_reset_valid_not_ready_seen": bf64_after_soft_reset_valid_not_ready_seen,
        "pbm_rd_nonempty_cycles": sum(int_value(row.get("pbm_rd_nonempty_cycles", 0)) for row in included_rows),
        "pbm_committed_available_cycles": sum(
            int_value(row.get("pbm_committed_available_cycles", 0)) for row in included_rows
        ),
        "pbm_rd_en_cycles": sum(int_value(row.get("pbm_rd_en_cycles", 0)) for row in included_rows),
        "pbm_rd_accept_cycles": sum(int_value(row.get("pbm_rd_accept_cycles", 0)) for row in included_rows),
        "pbm_wr_ready_high_cycles": sum(int_value(row.get("pbm_wr_ready_high_cycles", 0)) for row in included_rows),
        "pbm_wr_accept_cycles": sum(int_value(row.get("pbm_wr_accept_cycles", 0)) for row in included_rows),
        "pbm_pointer_reset_or_drain_classification": classification,
        "pbm_pointer_reset_or_drain_classification_reason": pbm_pointer_reset_or_drain_reason(classification),
        "recommended_next_stage": recommended_next_stage,
    }


def pbm_pointer_reset_or_drain_reason(classification: str) -> str:
    if classification == "soft_reset_clears_gap_and_ready_recovers":
        return "A DMA soft reset cleared the preexisting pointer gap/read-side nonempty state seen in IdleControl, and BF64 recovered PBM write ready or accept after the reset."
    if classification == "soft_reset_clears_gap_but_ready_stays_low":
        return "A DMA soft reset cleared the preexisting idle pointer gap, but BF64 still held PBM write ready low after the reset."
    if classification == "pointer_gap_persists_after_soft_reset":
        return "The commit-tail pointer gap persisted after soft reset with no read-side drain activity, indicating a likely PBM commit-tail invariant or reset/restore issue."
    if classification == "read_side_nonempty_persists_after_soft_reset":
        return "Read-side nonempty/committed-available state persisted after soft reset and showed drain-side activity, indicating the next diagnosis should focus on PBM read-side drain behavior."
    return "Stage1A22 did not produce enough aligned reset/no-reset pointer evidence for a clean branch."


def group_by_pbm_commit_tail_invariant_config(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault(str(row.get("pbm_commit_tail_invariant_config") or ""), []).append(row)
    return groups


def stage1a23_pbm_commit_tail_pointer_invariant_diagnosis(
    rows: list[dict[str, Any]], args: argparse.Namespace
) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups = group_by_pbm_commit_tail_invariant_config(included_rows)
    idle_no_reset_rows = groups.get("IdleControl_NoReset", [])
    idle_after_soft_reset_rows = groups.get("IdleControl_AfterSoftReset", [])
    extra_rows = groups.get("IdleControl_AfterSoftReset_ExtraSnapshots", [])

    def pointer_gap_seen(row: dict[str, Any]) -> bool:
        commit_pre = int_value(row.get("pbm_ptr_head_commit_pre", 0))
        reserve_pre = int_value(row.get("pbm_ptr_head_reserve_pre", 0))
        tail_pre = int_value(row.get("pbm_ptr_tail_pre", 0))
        return (
            commit_pre == reserve_pre
            and tail_pre != commit_pre
            and (
                int_value(row.get("pbm_rd_nonempty_cycles", 0)) > 0
                or int_value(row.get("pbm_committed_available_cycles", 0)) > 0
            )
        )

    def values_constant(row: dict[str, Any], fields: tuple[str, ...]) -> bool:
        values = [row.get(field) for field in fields if row.get(field) is not None]
        return len(values) == len(fields) and len({int_value(value or 0) for value in values}) <= 1

    def values_increase(row: dict[str, Any], fields: tuple[str, ...]) -> bool:
        values = [int_value(row.get(field, 0)) for field in fields if row.get(field) is not None]
        return len(values) == len(fields) and all(later > earlier for earlier, later in zip(values, values[1:]))

    def drain_seen(row: dict[str, Any]) -> bool:
        return any(
            int_value(row.get(field, 0)) > 0
            for field in (
                "pbm_rd_en_cycles_delta_at_post_workload",
                "pbm_rd_en_cycles_delta_at_050ms",
                "pbm_rd_en_cycles_delta_at_250ms",
                "pbm_rd_en_cycles_delta_at_500ms",
                "pbm_rd_accept_cycles_delta_at_post_workload",
                "pbm_rd_accept_cycles_delta_at_050ms",
                "pbm_rd_accept_cycles_delta_at_250ms",
                "pbm_rd_accept_cycles_delta_at_500ms",
            )
        )

    has_required_configs = bool(idle_no_reset_rows) and bool(idle_after_soft_reset_rows) and bool(extra_rows)
    soft_reset_pulsed_verified = bool_majority(
        idle_after_soft_reset_rows + extra_rows,
        lambda row: truthy(row.get("dma_soft_reset_pulsed")),
    )
    idle_no_reset_pointer_gap_seen = bool_majority(idle_no_reset_rows, pointer_gap_seen)
    idle_after_soft_reset_pointer_gap_seen = bool_majority(idle_after_soft_reset_rows, pointer_gap_seen)
    extra_snapshots_present = bool_majority(
        extra_rows,
        lambda row: truthy(row.get("stage1a23_extra_snapshots_present")),
    )
    extra_state_constant = bool_majority(
        extra_rows,
        lambda row: values_constant(
            row,
            (
                "pbm_state_raw_at_post_workload",
                "pbm_state_raw_at_050ms",
                "pbm_state_raw_at_250ms",
                "pbm_state_raw_at_500ms",
            ),
        ),
    )
    extra_pointer_constant = bool_majority(
        extra_rows,
        lambda row: values_constant(
            row,
            (
                "pbm_ptr_head_commit_at_post_workload",
                "pbm_ptr_head_commit_at_050ms",
                "pbm_ptr_head_commit_at_250ms",
                "pbm_ptr_head_commit_at_500ms",
            ),
        )
        and values_constant(
            row,
            (
                "pbm_ptr_tail_at_post_workload",
                "pbm_ptr_tail_at_050ms",
                "pbm_ptr_tail_at_250ms",
                "pbm_ptr_tail_at_500ms",
            ),
        ),
    )
    extra_read_nonempty_accumulates = bool_majority(
        extra_rows,
        lambda row: values_increase(
            row,
            (
                "pbm_rd_nonempty_cycles_delta_at_post_workload",
                "pbm_rd_nonempty_cycles_delta_at_050ms",
                "pbm_rd_nonempty_cycles_delta_at_250ms",
                "pbm_rd_nonempty_cycles_delta_at_500ms",
            ),
        )
        or values_increase(
            row,
            (
                "pbm_committed_available_cycles_delta_at_post_workload",
                "pbm_committed_available_cycles_delta_at_050ms",
                "pbm_committed_available_cycles_delta_at_250ms",
                "pbm_committed_available_cycles_delta_at_500ms",
            ),
        ),
    )
    extra_read_drain_seen = bool_majority(extra_rows, drain_seen)

    if not included_rows or not has_required_configs or not soft_reset_pulsed_verified:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a23_due_to_inconclusive"
    elif extra_snapshots_present and ((not extra_state_constant) or (not extra_pointer_constant)):
        classification = "state_or_pointer_changed_across_idle_snapshots"
        recommended_next_stage = "PBMStatePointerConsistencyDiagnosis"
    elif (
        idle_no_reset_pointer_gap_seen
        and idle_after_soft_reset_pointer_gap_seen
        and extra_snapshots_present
        and extra_state_constant
        and extra_pointer_constant
        and extra_read_nonempty_accumulates
        and not extra_read_drain_seen
    ):
        classification = "persistent_pointer_gap_state_counter_invariant"
        recommended_next_stage = "PBMResetDomainScopeDiagnosis"
    else:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a23_due_to_inconclusive"

    return {
        "raw_sample_count": len(rows),
        "included_sample_count": len(included_rows),
        "idle_no_reset_rows_seen": len(idle_no_reset_rows),
        "idle_after_soft_reset_rows_seen": len(idle_after_soft_reset_rows),
        "idle_after_soft_reset_extra_rows_seen": len(extra_rows),
        "soft_reset_pulsed_verified": soft_reset_pulsed_verified,
        "idle_no_reset_pointer_gap_seen": idle_no_reset_pointer_gap_seen,
        "idle_after_soft_reset_pointer_gap_seen": idle_after_soft_reset_pointer_gap_seen,
        "extra_snapshots_present": extra_snapshots_present,
        "extra_pointer_constant": extra_pointer_constant,
        "extra_state_constant": extra_state_constant,
        "extra_read_nonempty_accumulates": extra_read_nonempty_accumulates,
        "extra_read_drain_seen": extra_read_drain_seen,
        "pbm_rd_nonempty_cycles": sum(int_value(row.get("pbm_rd_nonempty_cycles", 0)) for row in included_rows),
        "pbm_committed_available_cycles": sum(
            int_value(row.get("pbm_committed_available_cycles", 0)) for row in included_rows
        ),
        "pbm_rd_en_cycles": sum(int_value(row.get("pbm_rd_en_cycles", 0)) for row in included_rows),
        "pbm_rd_accept_cycles": sum(int_value(row.get("pbm_rd_accept_cycles", 0)) for row in included_rows),
        "pbm_commit_tail_pointer_invariant_classification": classification,
        "pbm_commit_tail_pointer_invariant_classification_reason": pbm_commit_tail_pointer_invariant_reason(
            classification
        ),
        "recommended_next_stage": recommended_next_stage,
    }


def pbm_commit_tail_pointer_invariant_reason(classification: str) -> str:
    if classification == "persistent_pointer_gap_state_counter_invariant":
        return "The pointer gap persisted after soft reset while PBM state and commit/tail pointers stayed constant across idle extra snapshots; read-side nonempty counters accumulated without drain."
    if classification == "state_or_pointer_changed_across_idle_snapshots":
        return "PBM state or commit/tail pointer values changed across idle extra snapshots, so the invariant must be checked for state/pointer consistency before assigning reset-domain scope."
    return "Stage1A23 did not produce enough aligned idle, soft-reset, and extra-snapshot evidence for a clean branch."


def stage1a24_pbm_reset_domain_scope_diagnosis(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    prior = stage1a23_pbm_commit_tail_pointer_invariant_diagnosis(rows, args)
    static_scope = pbm_reset_domain_static_scope(Path(args.repo_root))
    prior_classification = str(prior.get("pbm_commit_tail_pointer_invariant_classification") or "")
    prior_persistent = prior_classification == "persistent_pointer_gap_state_counter_invariant"
    static_ok = truthy(static_scope.get("static_scope_parse_ok"))
    pbm_outside_soft_reset = (
        static_ok
        and truthy(static_scope.get("dma_soft_reset_generated_by_axil_csr"))
        and not truthy(static_scope.get("pbm_controller_has_soft_reset_port"))
        and not truthy(static_scope.get("dma_soft_reset_connected_to_pbm"))
        and truthy(static_scope.get("pbm_state_pointer_reset_requires_global_rst_n"))
        and truthy(static_scope.get("pbm_diag_clear_resets_diag_counters_only"))
    )

    if not prior_persistent:
        classification = "inconclusive_without_stage1a23_persistent_invariant"
        recommended_next_stage = "rerun_stage1a23_due_to_inconclusive"
    elif not static_ok:
        classification = "inconclusive_static_reset_scope_parse_failed"
        recommended_next_stage = "rerun_stage1a24_due_to_inconclusive"
    elif pbm_outside_soft_reset:
        classification = "pbm_state_pointers_outside_dma_soft_reset_scope"
        recommended_next_stage = "PBMResetDomainRemediationPlan"
    elif truthy(static_scope.get("dma_soft_reset_connected_to_pbm")):
        classification = "pbm_soft_reset_connected_but_invariant_persists"
        recommended_next_stage = "PBMSoftResetImplementationDiagnosis"
    else:
        classification = "inconclusive_reset_domain_scope"
        recommended_next_stage = "rerun_stage1a24_due_to_inconclusive"

    result = {
        "raw_sample_count": len(rows),
        "included_sample_count": len([row for row in rows if is_included_in_stats(row)]),
        "stage1a23_prior_classification": prior_classification,
        "stage1a23_prior_recommended_next_stage": prior.get("recommended_next_stage"),
        "pbm_reset_domain_scope_classification": classification,
        "pbm_reset_domain_scope_classification_reason": pbm_reset_domain_scope_reason(classification),
        "recommended_next_stage": recommended_next_stage,
    }
    result.update(static_scope)
    return result


def pbm_reset_domain_scope_reason(classification: str) -> str:
    if classification == "pbm_state_pointers_outside_dma_soft_reset_scope":
        return "Stage1A23 showed a persistent PBM pointer/read-side invariant after DMA soft reset, and static RTL scope shows PBM state/pointers are reset by global rst_n rather than csr_soft_reset; counter clear only resets diagnostics."
    if classification == "pbm_soft_reset_connected_but_invariant_persists":
        return "Stage1A23 showed a persistent invariant even though static RTL appears to connect DMA soft reset into PBM; the soft-reset implementation needs direct inspection."
    if classification == "inconclusive_without_stage1a23_persistent_invariant":
        return "Stage1A24 requires the Stage1A23 persistent invariant as input before assigning reset-domain scope."
    if classification == "inconclusive_static_reset_scope_parse_failed":
        return "Stage1A24 could not parse enough RTL reset-scope evidence for a clean decision."
    return "Stage1A24 reset-domain evidence was insufficient for a clean branch."


def stage1a25_pbm_reset_domain_remediation_plan(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    prior = stage1a24_pbm_reset_domain_scope_diagnosis(rows, args)
    prior_classification = str(prior.get("pbm_reset_domain_scope_classification") or "")
    if prior_classification == "pbm_state_pointers_outside_dma_soft_reset_scope":
        selected = "add_pbm_soft_reset_to_dma_soft_reset_scope"
        classification = "pbm_soft_reset_diagnostic_build_required"
        recommended_next_stage = "PBMSoftResetDiagnosticBuild"
        requires_rtl_change = True
        diagnostic_build_required = True
        implementation_notes = (
            "Add an explicit PBM soft-reset input driven by csr_soft_reset in the diagnostic build; "
            "reset PBM state and commit/tail pointers, reserve pointer, read-pending/output-valid state, "
            "and local BRAM command staging; counter clear remains diagnostic-only and must not reset PBM state."
        )
        rejected = [
            "global_pl_reset_only",
            "counter_clear_as_state_reset",
            "read_side_drain_only",
            "stage2_without_reset_fix",
        ]
    elif prior_classification == "pbm_soft_reset_connected_but_invariant_persists":
        selected = "inspect_existing_pbm_soft_reset_implementation"
        classification = "pbm_soft_reset_implementation_diagnosis_required"
        recommended_next_stage = "PBMSoftResetImplementationDiagnosis"
        requires_rtl_change = False
        diagnostic_build_required = False
        implementation_notes = (
            "Static scope suggests PBM soft reset is already connected, so inspect reset coverage before adding "
            "another reset path."
        )
        rejected = ["add_duplicate_pbm_soft_reset_without_coverage_audit"]
    else:
        selected = "none"
        classification = "inconclusive_without_reset_scope_evidence"
        recommended_next_stage = "rerun_stage1a24_due_to_inconclusive"
        requires_rtl_change = False
        diagnostic_build_required = False
        implementation_notes = "Stage1A25 requires a clean Stage1A24 reset-domain scope classification."
        rejected = []

    return {
        "raw_sample_count": len(rows),
        "included_sample_count": len([row for row in rows if is_included_in_stats(row)]),
        "stage1a24_prior_classification": prior_classification,
        "stage1a24_prior_recommended_next_stage": prior.get("recommended_next_stage"),
        "pbm_reset_domain_remediation_classification": classification,
        "selected_remediation": selected,
        "rejected_remediations": rejected,
        "requires_rtl_change": requires_rtl_change,
        "diagnostic_build_required": diagnostic_build_required,
        "paper_ready_recovery_gate_may_open": False,
        "candidate_for_paper_evidence_after_remediation_plan": "no",
        "implementation_notes": implementation_notes,
        "validation_plan": (
            "After implementing the diagnostic build, rerun Stage1A22/Stage1A23 to verify DMA soft reset clears "
            "the PBM commit-tail gap, then rerun Stage1A21 to verify PBM ready recovers before resuming bridge/DMA stages."
        ),
        "recommended_next_stage": recommended_next_stage,
    }


def group_by_crypto_ingress_config(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault(str(row.get("crypto_ingress_config") or ""), []).append(row)
    return groups


def stage1a9_crypto_ingress_handoff_visibility(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups = group_by_crypto_ingress_config(included_rows)
    idle_rows = groups.get("IdleControl", [])
    bf8_rows = groups.get("BF8_SM500", [])
    bf64_rows = groups.get("BF64_SM500", [])
    bf8_extra_rows = groups.get("BF8_SM500_ExtraSnapshots", [])
    bf64_extra_rows = groups.get("BF64_SM500_ExtraSnapshots", [])
    active_rows = bf8_rows + bf64_rows + bf8_extra_rows + bf64_extra_rows

    collision = crypto_ingress_diag_csr_collision(Path(args.repo_root))
    idle_residual_activity_seen = bool_majority(
        idle_rows,
        lambda row: truthy(row.get("idle_residual_activity_seen"))
        or int_value(row.get("crypto_rx_valid_cycles", 0)) > 0
        or int_value(row.get("crypto_rx_valid_not_ready_cycles", 0)) > 0
        or int_value(row.get("drop_pulse_count", 0)) > 0,
    )
    pbm_activity_seen = any(
        int_value(row.get("pbm_wr_valid_cycles", 0)) > 0
        or int_value(row.get("pbm_valid_not_ready_cycles", 0)) > 0
        or int_value(row.get("pbm_wr_accept_cycles", 0)) > 0
        for row in included_rows
    )
    crypto_rx_valid_seen = any(int_value(row.get("crypto_rx_valid_cycles", 0)) > 0 for row in bf8_rows + bf64_rows)
    crypto_rx_valid_not_ready_seen = bool_majority(
        bf8_rows + bf64_rows,
        lambda row: int_value(row.get("crypto_rx_valid_not_ready_cycles", 0)) > 0
        and int_value(row.get("crypto_rx_accept_cycles", 0)) == 0,
    )
    crypto_rx_without_pbm_activity = crypto_rx_valid_not_ready_seen and not pbm_activity_seen
    crypto_rx_accept_without_pbm_accept = bool_majority(
        bf8_rows + bf64_rows,
        lambda row: int_value(row.get("crypto_rx_accept_cycles", 0)) > 0
        and int_value(row.get("pbm_wr_accept_cycles", 0)) == 0,
    )
    pbm_accept_seen = any(int_value(row.get("pbm_wr_accept_cycles", 0)) > 0 for row in active_rows)
    pbm_valid_not_ready_seen = bool_majority(
        active_rows,
        lambda row: int_value(row.get("pbm_valid_not_ready_cycles", 0)) > 0
        and int_value(row.get("pbm_wr_accept_cycles", 0)) == 0,
    )

    def positive_int(row: dict[str, Any], field: str) -> bool:
        try:
            return int_value(row.get(field, 0)) > 0
        except (TypeError, ValueError):
            return False

    def row_has_pbm_commit(row: dict[str, Any]) -> bool:
        return positive_int(row, "pbm_commit_entry_count") or positive_int(row, "pbm_ptr_head_commit_delta_mod")

    def row_has_backend_activity(row: dict[str, Any]) -> bool:
        return positive_int(row, "backend_accept_cycles") or positive_int(row, "backend_starvation_cycles")

    pbm_commit_rows_seen = sum(1 for row in active_rows if row_has_pbm_commit(row))
    backend_activity_rows_seen = sum(1 for row in active_rows if row_has_backend_activity(row))
    committed_rows_without_backend_service_count = sum(
        1 for row in active_rows if row_has_pbm_commit(row) and not row_has_backend_activity(row)
    )
    pbm_commit_seen = pbm_commit_rows_seen > 0
    backend_activity_seen = backend_activity_rows_seen > 0
    backend_activity_stable = bool(active_rows) and backend_activity_rows_seen == len(active_rows)
    backend_activity_intermittent = backend_activity_seen and not backend_activity_stable
    pbm_commit_without_backend_service = (
        committed_rows_without_backend_service_count >= max(1, math.ceil(max(pbm_commit_rows_seen, 1) / 2))
    )
    sampling_or_alignment_issue = collision or idle_residual_activity_seen

    if sampling_or_alignment_issue:
        recommended_next_stage = "FixSamplingOrAlignment"
    elif crypto_rx_without_pbm_activity or crypto_rx_accept_without_pbm_accept:
        recommended_next_stage = "CryptoIngressToPBMBindingDiagnosis"
    elif not crypto_rx_valid_seen:
        recommended_next_stage = "WrapperClassifierDMABoundaryDiagnosis"
    elif pbm_commit_seen and (pbm_commit_without_backend_service or backend_activity_intermittent or not backend_activity_seen):
        recommended_next_stage = "CryptoDMAHandoffDiagnosis"
    elif pbm_valid_not_ready_seen and not pbm_accept_seen:
        recommended_next_stage = "PBMIngressVisibilityDiagnosis"
    elif pbm_activity_seen:
        recommended_next_stage = "rerun_stage1a9_due_to_inconclusive"
    else:
        recommended_next_stage = "rerun_stage1a9_due_to_inconclusive"

    def summarize_extra(rows_for_group: list[dict[str, Any]], field: str) -> dict[str, Any]:
        return summarize_values([row.get(field) for row in rows_for_group if row.get(field) is not None])

    return {
        "diagnostic_csr_map_version": CRYPTO_INGRESS_DIAG_CSR_MAP_VERSION,
        "diagnostic_csr_address_range": "0x194-0x1B0",
        "crypto_ingress_diag_csr_collision": collision,
        "idle_residual_activity_seen": idle_residual_activity_seen,
        "crypto_rx_valid_seen": crypto_rx_valid_seen,
        "crypto_rx_valid_not_ready_seen": crypto_rx_valid_not_ready_seen,
        "pbm_activity_seen": pbm_activity_seen,
        "pbm_accept_seen": pbm_accept_seen,
        "pbm_valid_not_ready_seen": pbm_valid_not_ready_seen,
        "pbm_commit_seen": pbm_commit_seen,
        "pbm_commit_rows_seen": pbm_commit_rows_seen,
        "backend_activity_seen": backend_activity_seen,
        "backend_activity_rows_seen": backend_activity_rows_seen,
        "backend_activity_stable": backend_activity_stable,
        "backend_activity_intermittent": backend_activity_intermittent,
        "committed_rows_without_backend_service_count": committed_rows_without_backend_service_count,
        "pbm_commit_without_backend_service": pbm_commit_without_backend_service,
        "crypto_rx_without_pbm_activity": crypto_rx_without_pbm_activity,
        "crypto_rx_accept_without_pbm_accept": crypto_rx_accept_without_pbm_accept,
        "bf8_rows_seen": len(bf8_rows),
        "bf64_rows_seen": len(bf64_rows),
        "bf8_extra_rows_seen": len(bf8_extra_rows),
        "bf64_extra_rows_seen": len(bf64_extra_rows),
        "bf8_crypto_rx_valid_not_ready_cycles": summarize_values(
            [row.get("crypto_rx_valid_not_ready_cycles") for row in bf8_rows]
        ),
        "bf64_crypto_rx_valid_not_ready_cycles": summarize_values(
            [row.get("crypto_rx_valid_not_ready_cycles") for row in bf64_rows]
        ),
        "bf8_extra_snapshot_deltas": {
            "crypto_rx_valid_cycles_delta_at_050ms": summarize_extra(
                bf8_extra_rows, "crypto_rx_valid_cycles_delta_at_050ms"
            ),
            "crypto_rx_valid_not_ready_cycles_delta_at_050ms": summarize_extra(
                bf8_extra_rows, "crypto_rx_valid_not_ready_cycles_delta_at_050ms"
            ),
            "crypto_rx_accept_cycles_delta_at_050ms": summarize_extra(
                bf8_extra_rows, "crypto_rx_accept_cycles_delta_at_050ms"
            ),
        },
        "bf64_extra_snapshot_deltas": {
            "crypto_rx_valid_cycles_delta_at_050ms": summarize_extra(
                bf64_extra_rows, "crypto_rx_valid_cycles_delta_at_050ms"
            ),
            "crypto_rx_valid_not_ready_cycles_delta_at_050ms": summarize_extra(
                bf64_extra_rows, "crypto_rx_valid_not_ready_cycles_delta_at_050ms"
            ),
            "crypto_rx_accept_cycles_delta_at_050ms": summarize_extra(
                bf64_extra_rows, "crypto_rx_accept_cycles_delta_at_050ms"
            ),
        },
        "recommended_next_stage": recommended_next_stage,
    }


def group_by_crypto_dma_handoff_config(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault(str(row.get("crypto_dma_handoff_config") or ""), []).append(row)
    return groups


def stage1a10_crypto_dma_handoff_diagnosis(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups = group_by_crypto_dma_handoff_config(included_rows)
    idle_rows = groups.get("IdleControl", [])
    bf8_rows = groups.get("BF8_SM500", [])
    bf64_rows = groups.get("BF64_SM500", [])
    bf8_extra_rows = groups.get("BF8_SM500_ExtraSnapshots", [])
    bf64_extra_rows = groups.get("BF64_SM500_ExtraSnapshots", [])
    active_rows = bf8_rows + bf64_rows + bf8_extra_rows + bf64_extra_rows

    collision = crypto_dma_handoff_diag_csr_collision(Path(args.repo_root))

    def positive_int(row: dict[str, Any], field: str) -> bool:
        try:
            return int_value(row.get(field, 0)) > 0
        except (TypeError, ValueError):
            return False

    def row_has_pbm_commit(row: dict[str, Any]) -> bool:
        return positive_int(row, "pbm_commit_entry_count") or positive_int(row, "pbm_ptr_head_commit_delta_mod")

    def row_has_backend_activity(row: dict[str, Any]) -> bool:
        return positive_int(row, "backend_accept_cycles") or positive_int(row, "backend_starvation_cycles")

    def row_has_tail_move(row: dict[str, Any]) -> bool:
        return positive_int(row, "pbm_ptr_tail_delta_mod")

    def row_has_pbm_rd_accept(row: dict[str, Any]) -> bool:
        return positive_int(row, "pbm_rd_accept_cycles")

    def row_has_crypto_dma_accept(row: dict[str, Any]) -> bool:
        return positive_int(row, "crypto_dma_in_accept_cycles")

    def row_has_completion(row: dict[str, Any]) -> bool:
        return positive_int(row, "crypto_dma_completion_count")

    idle_residual_activity_seen = bool_majority(
        idle_rows,
        lambda row: truthy(row.get("idle_residual_activity_seen"))
        or positive_int(row, "pbm_committed_available_cycles")
        or positive_int(row, "pbm_rd_accept_cycles")
        or positive_int(row, "crypto_dma_in_valid_cycles")
        or positive_int(row, "crypto_dma_in_accept_cycles")
        or row_has_backend_activity(row),
    )
    pbm_commit_rows = [row for row in active_rows if row_has_pbm_commit(row)]
    pbm_commit_rows_seen = len(pbm_commit_rows)
    backend_activity_rows_seen = sum(1 for row in active_rows if row_has_backend_activity(row))
    backend_activity_seen = backend_activity_rows_seen > 0
    backend_activity_stable = bool(active_rows) and backend_activity_rows_seen == len(active_rows)
    backend_activity_intermittent = backend_activity_seen and not backend_activity_stable
    committed_rows_with_backend_service_count = sum(
        1 for row in pbm_commit_rows if row_has_backend_activity(row)
    )
    committed_rows_without_backend_service_count = sum(
        1 for row in pbm_commit_rows if not row_has_backend_activity(row)
    )
    pbm_commit_seen = pbm_commit_rows_seen > 0
    pbm_committed_but_tail_not_moved = bool_majority(
        pbm_commit_rows, lambda row: not row_has_tail_move(row)
    )
    pbm_committed_but_rd_empty = bool_majority(
        pbm_commit_rows,
        lambda row: positive_int(row, "pbm_rd_empty_cycles")
        and not positive_int(row, "pbm_rd_nonempty_cycles"),
    )
    pbm_rd_accept_seen = any(row_has_pbm_rd_accept(row) for row in active_rows)
    crypto_dma_ingress_accept_seen = any(row_has_crypto_dma_accept(row) for row in active_rows)
    backend_accept_after_crypto_dma_seen = any(
        row_has_crypto_dma_accept(row) and row_has_backend_activity(row) for row in active_rows
    )
    pbm_rollback_trigger_candidate_seen = any(
        positive_int(row, "pbm_wr_last_error_accepted_count") for row in active_rows
    )
    pbm_rollback_path_observed = any(
        positive_int(row, "pbm_rollback_entry_count") or any_nonzero(row, ROLLBACK_RECOVERY_COUNTERS)
        for row in active_rows
    )
    completion_seen = any(row_has_completion(row) for row in active_rows)

    sampling_or_alignment_issue = collision or idle_residual_activity_seen
    if collision:
        handoff_gap_classification = "inconclusive"
        recommended_next_stage = "FixSamplingOrAlignment"
    elif pbm_rollback_path_observed or pbm_rollback_trigger_candidate_seen:
        handoff_gap_classification = "rollback_trigger_candidate_seen"
        recommended_next_stage = "DropRollbackCouplingDiagnosis"
    elif pbm_commit_seen and pbm_committed_but_tail_not_moved:
        handoff_gap_classification = "pbm_read_visibility_gap"
        recommended_next_stage = "PBMReadSideVisibilityDiagnosis"
    elif idle_residual_activity_seen:
        handoff_gap_classification = "inconclusive"
        recommended_next_stage = "FixSamplingOrAlignment"
    elif pbm_rd_accept_seen and not crypto_dma_ingress_accept_seen:
        handoff_gap_classification = "crypto_dma_ingress_backpressure"
        recommended_next_stage = "CryptoDMAIngressBackpressureDiagnosis"
    elif crypto_dma_ingress_accept_seen and (not backend_activity_seen or backend_activity_intermittent):
        handoff_gap_classification = "backend_input_gating"
        recommended_next_stage = "BackendInputGatingDiagnosis"
    elif backend_activity_stable and not completion_seen:
        handoff_gap_classification = "completion_writeback_gap"
        recommended_next_stage = "CompletionWritebackDiagnosis"
    else:
        handoff_gap_classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a10_due_to_inconclusive"

    def summarize_extra(rows_for_group: list[dict[str, Any]], field: str) -> dict[str, Any]:
        return summarize_values([row.get(field) for row in rows_for_group if row.get(field) is not None])

    return {
        "diagnostic_csr_map_version": CRYPTO_DMA_HANDOFF_DIAG_CSR_MAP_VERSION,
        "diagnostic_csr_address_range": "0x1B4-0x1DC",
        "crypto_dma_handoff_diag_csr_collision": collision,
        "idle_residual_activity_seen": idle_residual_activity_seen,
        "pbm_commit_seen": pbm_commit_seen,
        "pbm_commit_rows_seen": pbm_commit_rows_seen,
        "backend_activity_seen": backend_activity_seen,
        "backend_activity_stable": backend_activity_stable,
        "backend_activity_intermittent": backend_activity_intermittent,
        "committed_rows_with_backend_service_count": committed_rows_with_backend_service_count,
        "committed_rows_without_backend_service_count": committed_rows_without_backend_service_count,
        "pbm_committed_but_tail_not_moved": pbm_committed_but_tail_not_moved,
        "pbm_committed_but_rd_empty": pbm_committed_but_rd_empty,
        "pbm_rd_accept_seen": pbm_rd_accept_seen,
        "crypto_dma_ingress_accept_seen": crypto_dma_ingress_accept_seen,
        "backend_accept_after_crypto_dma_seen": backend_accept_after_crypto_dma_seen,
        "pbm_rollback_trigger_candidate_seen": pbm_rollback_trigger_candidate_seen,
        "pbm_rollback_path_observed": pbm_rollback_path_observed,
        "handoff_gap_classification": handoff_gap_classification,
        "bf8_rows_seen": len(bf8_rows),
        "bf64_rows_seen": len(bf64_rows),
        "bf8_extra_rows_seen": len(bf8_extra_rows),
        "bf64_extra_rows_seen": len(bf64_extra_rows),
        "bf8_extra_snapshot_deltas": {
            "pbm_rd_accept_cycles_delta_at_050ms": summarize_extra(
                bf8_extra_rows, "pbm_rd_accept_cycles_delta_at_050ms"
            ),
            "crypto_dma_in_accept_cycles_delta_at_050ms": summarize_extra(
                bf8_extra_rows, "crypto_dma_in_accept_cycles_delta_at_050ms"
            ),
            "crypto_dma_backpressure_cycles_delta_at_050ms": summarize_extra(
                bf8_extra_rows, "crypto_dma_backpressure_cycles_delta_at_050ms"
            ),
        },
        "bf64_extra_snapshot_deltas": {
            "pbm_rd_accept_cycles_delta_at_050ms": summarize_extra(
                bf64_extra_rows, "pbm_rd_accept_cycles_delta_at_050ms"
            ),
            "crypto_dma_in_accept_cycles_delta_at_050ms": summarize_extra(
                bf64_extra_rows, "crypto_dma_in_accept_cycles_delta_at_050ms"
            ),
            "crypto_dma_backpressure_cycles_delta_at_050ms": summarize_extra(
                bf64_extra_rows, "crypto_dma_backpressure_cycles_delta_at_050ms"
            ),
        },
        "recommended_next_stage": recommended_next_stage,
    }


def stage1a27_crypto_dma_ingress_backpressure_diagnosis(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]

    def positive_int(row: dict[str, Any], field: str) -> bool:
        try:
            return int_value(row.get(field, 0)) > 0
        except (TypeError, ValueError):
            return False

    bridge_accept_rows = [row for row in included_rows if positive_int(row, "bridge_tx_accept_cycles")]
    crypto_valid_rows = [row for row in included_rows if positive_int(row, "crypto_dma_in_valid_cycles")]
    crypto_ready_rows = [row for row in included_rows if positive_int(row, "crypto_dma_in_ready_cycles")]
    crypto_accept_rows = [row for row in included_rows if positive_int(row, "crypto_dma_in_accept_cycles")]
    backend_rows = [
        row
        for row in included_rows
        if positive_int(row, "backend_accept_cycles")
        or positive_int(row, "backend_starvation_cycles")
        or truthy(row.get("backend_activity_seen"))
    ]

    bridge_tx_accept_cycles = sum(int_value(row.get("bridge_tx_accept_cycles", 0)) for row in included_rows)
    bridge_tx_rd_en_cycles = sum(int_value(row.get("bridge_tx_rd_en_cycles", 0)) for row in included_rows)
    crypto_dma_in_valid_cycles = sum(int_value(row.get("crypto_dma_in_valid_cycles", 0)) for row in included_rows)
    crypto_dma_in_ready_cycles = sum(int_value(row.get("crypto_dma_in_ready_cycles", 0)) for row in included_rows)
    crypto_dma_in_accept_cycles = sum(int_value(row.get("crypto_dma_in_accept_cycles", 0)) for row in included_rows)
    backend_accept_cycles = sum(int_value(row.get("backend_accept_cycles", 0)) for row in included_rows)
    backend_starvation_cycles = sum(int_value(row.get("backend_starvation_cycles", 0)) for row in included_rows)
    loopback_mode_values = {int_value(row.get("dma_rd_en_loopback_mode_raw", 0)) for row in included_rows}
    loopback_mode_raw = next(iter(loopback_mode_values), 0) if len(loopback_mode_values) == 1 else -1
    runtime_ring_bypass_seen = any(truthy(row.get("runtime_ring_bypass_enabled")) for row in included_rows)

    bridge_accept_seen = bool(bridge_accept_rows)
    bridge_rd_en_seen = bridge_tx_rd_en_cycles > 0
    crypto_valid_seen = bool(crypto_valid_rows)
    crypto_ready_seen = bool(crypto_ready_rows)
    crypto_accept_seen = bool(crypto_accept_rows)
    backend_activity_seen = bool(backend_rows)
    backend_activity_stable = bool(included_rows) and len(backend_rows) == len(included_rows)

    if runtime_ring_bypass_seen and loopback_mode_raw == 2 and bridge_accept_seen and backend_activity_seen:
        classification = "loopback_passthrough_bridge_accept_with_backend_activity"
        recommended_next_stage = "Stage1A_EngineeringDataAcquisition"
    elif runtime_ring_bypass_seen and loopback_mode_raw == 2 and bridge_accept_seen:
        classification = "loopback_passthrough_bridge_accept_without_backend_activity"
        recommended_next_stage = "BackendInputGatingDiagnosis"
    elif runtime_ring_bypass_seen and loopback_mode_raw == 2 and bridge_rd_en_seen and not bridge_accept_seen:
        classification = "loopback_passthrough_rd_en_without_bridge_accept"
        recommended_next_stage = "BridgeAcceptPathDiagnosis"
    elif crypto_accept_seen and backend_activity_seen:
        classification = "crypto_dma_accept_with_backend_activity"
        recommended_next_stage = "Stage1A_EngineeringDataAcquisition"
    elif crypto_accept_seen:
        classification = "crypto_dma_accept_without_backend_activity"
        recommended_next_stage = "BackendInputGatingDiagnosis"
    elif bridge_accept_seen and not crypto_valid_seen:
        classification = "bridge_accept_without_crypto_dma_valid"
        recommended_next_stage = "BridgeToCryptoDMAValidVisibilityDiagnosis"
    elif crypto_valid_seen and not crypto_ready_seen:
        classification = "crypto_dma_ingress_ready_gating"
        recommended_next_stage = "CryptoDMAIngressReadyGatingDiagnosis"
    elif crypto_valid_seen and crypto_ready_seen and not crypto_accept_seen:
        classification = "crypto_dma_ingress_handshake_instrumentation_gap"
        recommended_next_stage = "CryptoDMAIngressHandshakeInstrumentationDiagnosis"
    elif backend_activity_seen:
        classification = "counter_alignment_or_instrumentation_gap"
        recommended_next_stage = "CounterAlignmentOrInstrumentationDiagnosis"
    else:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a27_due_to_inconclusive"

    return {
        "diagnostic_build": True,
        "candidate_for_paper_evidence": "no",
        "allowed_use_in_paper": "engineering evidence only",
        "evidence_risk": "high",
        "included_rows": len(included_rows),
        "runtime_ring_bypass_enabled": runtime_ring_bypass_seen,
        "dma_rd_en_loopback_mode_raw": loopback_mode_raw,
        "bridge_tx_rd_en_cycles": bridge_tx_rd_en_cycles,
        "bridge_tx_accept_cycles": bridge_tx_accept_cycles,
        "crypto_dma_in_valid_cycles": crypto_dma_in_valid_cycles,
        "crypto_dma_in_ready_cycles": crypto_dma_in_ready_cycles,
        "crypto_dma_in_accept_cycles": crypto_dma_in_accept_cycles,
        "backend_accept_cycles": backend_accept_cycles,
        "backend_starvation_cycles": backend_starvation_cycles,
        "bridge_tx_rd_en_seen": bridge_rd_en_seen,
        "bridge_accept_seen": bridge_accept_seen,
        "crypto_dma_in_valid_seen": crypto_valid_seen,
        "crypto_dma_in_ready_seen": crypto_ready_seen,
        "crypto_dma_ingress_accept_seen": crypto_accept_seen,
        "backend_activity_seen": backend_activity_seen,
        "backend_activity_stable": backend_activity_stable,
        "crypto_dma_ingress_backpressure_classification": classification,
        "recommended_next_stage": recommended_next_stage,
    }


def group_by_pbm_read_side_config(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault(str(row.get("pbm_read_side_config") or ""), []).append(row)
    return groups


def stage1a11_pbm_read_side_visibility(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups = group_by_pbm_read_side_config(included_rows)
    idle_rows = groups.get("IdleControl", [])
    bf8_rows = groups.get("BF8_SM500", [])
    bf64_rows = groups.get("BF64_SM500", [])
    bf8_extra_rows = groups.get("BF8_SM500_ExtraSnapshots", [])
    bf64_extra_rows = groups.get("BF64_SM500_ExtraSnapshots", [])
    active_rows = bf8_rows + bf64_rows + bf8_extra_rows + bf64_extra_rows

    collision = pbm_read_side_diag_csr_collision(Path(args.repo_root))

    def positive_int(row: dict[str, Any], field: str) -> bool:
        try:
            return int_value(row.get(field, 0)) > 0
        except (TypeError, ValueError):
            return False

    def row_has_commit(row: dict[str, Any]) -> bool:
        return positive_int(row, "pbm_commit_entry_count") or positive_int(row, "pbm_ptr_head_commit_delta_mod")

    def row_has_bridge_rd_en(row: dict[str, Any]) -> bool:
        return positive_int(row, "bridge_pbm_rd_en_cycles")

    def row_has_bridge_fire(row: dict[str, Any]) -> bool:
        return positive_int(row, "bridge_pbm_fire_count")

    def row_has_data_without_inst_available(row: dict[str, Any]) -> bool:
        return positive_int(row, "bridge_data_available_no_inst_available_cycles")

    def row_has_dma_start(row: dict[str, Any]) -> bool:
        return positive_int(row, "dma_start_seen_count")

    def row_has_dma_addr(row: dict[str, Any]) -> bool:
        return positive_int(row, "dma_addr_cycles")

    def row_has_dma_data(row: dict[str, Any]) -> bool:
        return positive_int(row, "dma_data_cycles")

    def row_has_dma_aw(row: dict[str, Any]) -> bool:
        return positive_int(row, "dma_aw_handshake_count")

    def row_has_dma_w(row: dict[str, Any]) -> bool:
        return positive_int(row, "dma_w_handshake_count")

    def row_has_dma_b(row: dict[str, Any]) -> bool:
        return positive_int(row, "dma_b_handshake_count")

    def row_has_dma_wready_backpressure(row: dict[str, Any]) -> bool:
        return positive_int(row, "dma_wready_low_cycles")

    def row_has_dma_progress(row: dict[str, Any]) -> bool:
        return row_has_dma_start(row) or row_has_dma_addr(row) or row_has_dma_data(row)

    def row_has_backend_activity(row: dict[str, Any]) -> bool:
        return any_nonzero(row, BACKEND_SERVICE_COUNTERS)

    idle_residual_activity_seen = bool_majority(
        idle_rows,
        lambda row: truthy(row.get("idle_residual_activity_seen"))
        or row_has_bridge_rd_en(row)
        or row_has_bridge_fire(row)
        or row_has_dma_progress(row)
        or row_has_backend_activity(row),
    )

    pbm_commit_rows = [row for row in active_rows if row_has_commit(row)]
    pbm_commit_seen = bool(pbm_commit_rows)
    pbm_commit_rows_seen = len(pbm_commit_rows)
    bridge_rd_en_seen = any(row_has_bridge_rd_en(row) for row in active_rows)
    bridge_fire_seen = any(row_has_bridge_fire(row) for row in active_rows)
    data_without_inst_available_seen = any(
        row_has_data_without_inst_available(row) for row in pbm_commit_rows
    )
    dma_start_seen = any(row_has_dma_start(row) for row in active_rows)
    dma_addr_seen = any(row_has_dma_addr(row) for row in active_rows)
    dma_data_seen = any(row_has_dma_data(row) for row in active_rows)
    dma_aw_handshake_seen = any(row_has_dma_aw(row) for row in active_rows)
    dma_w_handshake_seen = any(row_has_dma_w(row) for row in active_rows)
    dma_b_handshake_seen = any(row_has_dma_b(row) for row in active_rows)
    dma_wready_backpressure_seen = any(row_has_dma_wready_backpressure(row) for row in active_rows)
    backend_activity_rows_seen = sum(1 for row in active_rows if row_has_backend_activity(row))
    backend_activity_seen = backend_activity_rows_seen > 0
    backend_activity_stable = bool(active_rows) and backend_activity_rows_seen == len(active_rows)
    backend_activity_intermittent = backend_activity_seen and not backend_activity_stable
    pbm_rollback_trigger_candidate_seen = any(
        positive_int(row, "pbm_wr_last_error_accepted_count") for row in active_rows
    )
    pbm_rollback_path_observed = any(
        positive_int(row, "pbm_rollback_entry_count") or any_nonzero(row, ROLLBACK_RECOVERY_COUNTERS)
        for row in active_rows
    )

    if collision or idle_residual_activity_seen:
        read_side_gap_classification = "inconclusive"
        recommended_next_stage = "FixSamplingOrAlignment"
    elif pbm_rollback_path_observed or pbm_rollback_trigger_candidate_seen:
        read_side_gap_classification = "rollback_trigger_candidate_seen"
        recommended_next_stage = "DropRollbackCouplingDiagnosis"
    elif pbm_commit_seen and not bridge_rd_en_seen and data_without_inst_available_seen:
        read_side_gap_classification = "crypto_bridge_availability_gap"
        recommended_next_stage = "CryptoBridgeAvailabilityDiagnosis"
    elif bridge_fire_seen and not dma_start_seen and not dma_addr_seen and not dma_data_seen:
        read_side_gap_classification = "dma_transfer_start_gap"
        recommended_next_stage = "DMATransferStartDiagnosis"
    elif (dma_start_seen or dma_addr_seen or dma_data_seen) and not dma_w_handshake_seen and dma_wready_backpressure_seen:
        read_side_gap_classification = "dma_write_channel_backpressure"
        recommended_next_stage = "DMAWriteChannelBackpressureDiagnosis"
    elif dma_w_handshake_seen and (not backend_activity_seen or backend_activity_intermittent):
        read_side_gap_classification = "backend_input_gating"
        recommended_next_stage = "BackendInputGatingDiagnosis"
    else:
        read_side_gap_classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a11_due_to_inconclusive"

    def summarize_extra(rows_for_group: list[dict[str, Any]], field: str) -> dict[str, Any]:
        return summarize_values([row.get(field) for row in rows_for_group if row.get(field) is not None])

    return {
        "diagnostic_csr_map_version": PBM_READ_SIDE_DIAG_CSR_MAP_VERSION,
        "diagnostic_csr_address_range": "0x1E0-0x21C",
        "pbm_read_side_diag_csr_collision": collision,
        "idle_residual_activity_seen": idle_residual_activity_seen,
        "pbm_commit_seen": pbm_commit_seen,
        "pbm_commit_rows_seen": pbm_commit_rows_seen,
        "bridge_rd_en_seen": bridge_rd_en_seen,
        "bridge_fire_seen": bridge_fire_seen,
        "data_without_inst_available_seen": data_without_inst_available_seen,
        "dma_start_seen": dma_start_seen,
        "dma_addr_seen": dma_addr_seen,
        "dma_data_seen": dma_data_seen,
        "dma_aw_handshake_seen": dma_aw_handshake_seen,
        "dma_w_handshake_seen": dma_w_handshake_seen,
        "dma_b_handshake_seen": dma_b_handshake_seen,
        "dma_wready_backpressure_seen": dma_wready_backpressure_seen,
        "backend_activity_seen": backend_activity_seen,
        "backend_activity_stable": backend_activity_stable,
        "backend_activity_intermittent": backend_activity_intermittent,
        "pbm_rollback_trigger_candidate_seen": pbm_rollback_trigger_candidate_seen,
        "pbm_rollback_path_observed": pbm_rollback_path_observed,
        "read_side_gap_classification": read_side_gap_classification,
        "bf8_rows_seen": len(bf8_rows),
        "bf64_rows_seen": len(bf64_rows),
        "bf8_extra_rows_seen": len(bf8_extra_rows),
        "bf64_extra_rows_seen": len(bf64_extra_rows),
        "bf8_extra_snapshot_deltas": {
            "bridge_pbm_rd_en_cycles_delta_at_050ms": summarize_extra(
                bf8_extra_rows, "bridge_pbm_rd_en_cycles_delta_at_050ms"
            ),
            "bridge_pbm_fire_count_delta_at_050ms": summarize_extra(
                bf8_extra_rows, "bridge_pbm_fire_count_delta_at_050ms"
            ),
            "dma_start_seen_count_delta_at_050ms": summarize_extra(
                bf8_extra_rows, "dma_start_seen_count_delta_at_050ms"
            ),
            "dma_w_handshake_count_delta_at_050ms": summarize_extra(
                bf8_extra_rows, "dma_w_handshake_count_delta_at_050ms"
            ),
        },
        "bf64_extra_snapshot_deltas": {
            "bridge_pbm_rd_en_cycles_delta_at_050ms": summarize_extra(
                bf64_extra_rows, "bridge_pbm_rd_en_cycles_delta_at_050ms"
            ),
            "bridge_pbm_fire_count_delta_at_050ms": summarize_extra(
                bf64_extra_rows, "bridge_pbm_fire_count_delta_at_050ms"
            ),
            "dma_start_seen_count_delta_at_050ms": summarize_extra(
                bf64_extra_rows, "dma_start_seen_count_delta_at_050ms"
            ),
            "dma_w_handshake_count_delta_at_050ms": summarize_extra(
                bf64_extra_rows, "dma_w_handshake_count_delta_at_050ms"
            ),
        },
        "recommended_next_stage": recommended_next_stage,
    }


def group_by_bridge_output_fifo_config(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault(str(row.get("bridge_output_fifo_config") or ""), []).append(row)
    return groups


def stage1a12_bridge_output_fifo_visibility(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups = group_by_bridge_output_fifo_config(included_rows)
    idle_rows = groups.get("IdleControl", [])
    bf8_rows = groups.get("BF8_SM500", [])
    bf64_rows = groups.get("BF64_SM500", [])
    bf8_extra_rows = groups.get("BF8_SM500_ExtraSnapshots", [])
    bf64_extra_rows = groups.get("BF64_SM500_ExtraSnapshots", [])
    active_rows = bf8_rows + bf64_rows + bf8_extra_rows + bf64_extra_rows

    collision = bridge_output_fifo_diag_csr_collision(Path(args.repo_root))

    def positive_int(row: dict[str, Any], field: str) -> bool:
        try:
            return int_value(row.get(field, 0)) > 0
        except (TypeError, ValueError):
            return False

    def row_has_bridge_nonempty(row: dict[str, Any]) -> bool:
        return positive_int(row, "bridge_tx_nonempty_cycles")

    def row_has_bridge_rd_en(row: dict[str, Any]) -> bool:
        return positive_int(row, "bridge_tx_rd_en_cycles")

    def row_has_bridge_accept(row: dict[str, Any]) -> bool:
        return positive_int(row, "bridge_tx_accept_cycles")

    def row_has_bridge_last(row: dict[str, Any]) -> bool:
        return positive_int(row, "bridge_tx_last_seen_count")

    def row_has_backend_activity(row: dict[str, Any]) -> bool:
        return any_nonzero(row, BACKEND_SERVICE_COUNTERS)

    idle_control_quiesce_guard_ms = int_value(idle_rows[0].get("idle_control_quiesce_guard_ms", 0)) if idle_rows else 0
    idle_pre_after_clear_zero = bool_majority(idle_rows, lambda row: truthy(row.get("idle_pre_after_clear_zero")))
    idle_bridge_output_fifo_residual_seen = bool_majority(
        idle_rows,
        lambda row: truthy(row.get("idle_residual_activity_seen"))
        or row_has_bridge_nonempty(row)
        or row_has_bridge_rd_en(row)
        or row_has_bridge_accept(row)
        or row_has_bridge_last(row),
    )

    bridge_output_fifo_nonempty_seen = any(row_has_bridge_nonempty(row) for row in included_rows)
    bridge_output_fifo_rd_en_seen = any(row_has_bridge_rd_en(row) for row in active_rows)
    bridge_output_fifo_accept_seen = any(row_has_bridge_accept(row) for row in active_rows)
    bridge_output_fifo_last_seen = any(row_has_bridge_last(row) for row in active_rows)
    dma_start_seen = any(int_value(row.get("dma_start_seen_count", 0)) > 0 for row in active_rows)
    backend_activity_rows_seen = sum(1 for row in active_rows if row_has_backend_activity(row))
    backend_activity_seen = backend_activity_rows_seen > 0
    backend_activity_stable = bool(active_rows) and backend_activity_rows_seen == len(active_rows)
    backend_activity_intermittent = backend_activity_seen and not backend_activity_stable
    rollback_recovery_seen = any_nonzero_rows(active_rows, ROLLBACK_RECOVERY_COUNTERS)

    if collision:
        bridge_output_fifo_classification = "inconclusive"
        recommended_next_stage = "FixSamplingOrAlignment"
    elif idle_bridge_output_fifo_residual_seen and not bridge_output_fifo_accept_seen:
        bridge_output_fifo_classification = "bridge_output_fifo_residual"
        recommended_next_stage = "BridgeOutputFIFOResidualDiagnosis"
    elif (
        bridge_output_fifo_nonempty_seen
        and not bridge_output_fifo_rd_en_seen
        and not bridge_output_fifo_accept_seen
        and not dma_start_seen
    ):
        bridge_output_fifo_classification = "dma_start_path_absent"
        recommended_next_stage = "DMAStartPathDiagnosis"
    elif bridge_output_fifo_nonempty_seen and not bridge_output_fifo_rd_en_seen and not bridge_output_fifo_accept_seen:
        bridge_output_fifo_classification = "dma_rd_enable_gating"
        recommended_next_stage = "DMARdEnableGatingDiagnosis"
    elif bridge_output_fifo_accept_seen and rollback_recovery_seen:
        bridge_output_fifo_classification = "bridge_accept_with_rollback_signal"
        recommended_next_stage = "DropRollbackCouplingDiagnosis"
    elif bridge_output_fifo_accept_seen and (not backend_activity_seen or backend_activity_intermittent):
        bridge_output_fifo_classification = "bridge_accept_without_stable_backend_service"
        recommended_next_stage = "CryptoDMAIngressBackpressureDiagnosis"
    elif bridge_output_fifo_accept_seen:
        bridge_output_fifo_classification = "bridge_accept_with_backend_service"
        recommended_next_stage = "BackendInputGatingDiagnosis"
    else:
        bridge_output_fifo_classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a12_due_to_inconclusive"

    def summarize_extra(rows_for_group: list[dict[str, Any]], field: str) -> dict[str, Any]:
        return summarize_values([row.get(field) for row in rows_for_group if row.get(field) is not None])

    return {
        "diagnostic_csr_map_version": BRIDGE_OUTPUT_FIFO_DIAG_CSR_MAP_VERSION,
        "diagnostic_csr_address_range": "0x220-0x22C",
        "bridge_output_fifo_diag_csr_collision": collision,
        "idle_control_quiesce_guard_ms": idle_control_quiesce_guard_ms,
        "idle_pre_after_clear_zero": idle_pre_after_clear_zero,
        "idle_bridge_output_fifo_residual_seen": idle_bridge_output_fifo_residual_seen,
        "bridge_output_fifo_nonempty_seen": bridge_output_fifo_nonempty_seen,
        "bridge_output_fifo_rd_en_seen": bridge_output_fifo_rd_en_seen,
        "bridge_output_fifo_accept_seen": bridge_output_fifo_accept_seen,
        "bridge_output_fifo_last_seen": bridge_output_fifo_last_seen,
        "dma_start_seen": dma_start_seen,
        "bridge_output_fifo_nonzero_rate": safe_ratio(
            sum(1 for row in included_rows if row_has_bridge_nonempty(row)),
            max(1, len(included_rows)),
        ),
        "backend_activity_seen": backend_activity_seen,
        "backend_activity_stable": backend_activity_stable,
        "backend_activity_intermittent": backend_activity_intermittent,
        "bridge_output_fifo_classification": bridge_output_fifo_classification,
        "bf8_rows_seen": len(bf8_rows),
        "bf64_rows_seen": len(bf64_rows),
        "bf8_extra_rows_seen": len(bf8_extra_rows),
        "bf64_extra_rows_seen": len(bf64_extra_rows),
        "bf8_extra_snapshot_deltas": {
            "bridge_tx_nonempty_cycles_delta_at_050ms": summarize_extra(
                bf8_extra_rows, "bridge_tx_nonempty_cycles_delta_at_050ms"
            ),
            "bridge_tx_rd_en_cycles_delta_at_050ms": summarize_extra(
                bf8_extra_rows, "bridge_tx_rd_en_cycles_delta_at_050ms"
            ),
            "bridge_tx_accept_cycles_delta_at_050ms": summarize_extra(
                bf8_extra_rows, "bridge_tx_accept_cycles_delta_at_050ms"
            ),
            "bridge_tx_last_seen_count_delta_at_050ms": summarize_extra(
                bf8_extra_rows, "bridge_tx_last_seen_count_delta_at_050ms"
            ),
        },
        "bf64_extra_snapshot_deltas": {
            "bridge_tx_nonempty_cycles_delta_at_050ms": summarize_extra(
                bf64_extra_rows, "bridge_tx_nonempty_cycles_delta_at_050ms"
            ),
            "bridge_tx_rd_en_cycles_delta_at_050ms": summarize_extra(
                bf64_extra_rows, "bridge_tx_rd_en_cycles_delta_at_050ms"
            ),
            "bridge_tx_accept_cycles_delta_at_050ms": summarize_extra(
                bf64_extra_rows, "bridge_tx_accept_cycles_delta_at_050ms"
            ),
            "bridge_tx_last_seen_count_delta_at_050ms": summarize_extra(
                bf64_extra_rows, "bridge_tx_last_seen_count_delta_at_050ms"
            ),
        },
        "recommended_next_stage": recommended_next_stage,
    }


def group_by_dma_start_path_config(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault(str(row.get("dma_start_path_config") or ""), []).append(row)
    return groups


def stage1a13_dma_start_path_diagnosis(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups = group_by_dma_start_path_config(included_rows)
    current_rows = groups.get("Current_Bypass_NoExplicitStart", [])
    explicit_rows = groups.get("Bypass_WithExplicitCSRStart", [])
    collision = dma_start_path_diag_csr_collision(Path(args.repo_root))

    def any_seen(rows_for_group: list[dict[str, Any]], field: str) -> bool:
        return any(int_value(row.get(field, 0)) > 0 for row in rows_for_group)

    current_bridge_tx_nonempty_seen = any_seen(current_rows, "bridge_tx_nonempty_cycles")
    current_csr_start_seen = any_seen(current_rows, "csr_start_pulse_count")
    current_ring_doorbell_seen = any_seen(current_rows, "ring_doorbell_pulse_count")
    current_fetcher_start_seen = any_seen(current_rows, "fetcher_start_pulse_count")
    current_final_start_seen = any_seen(current_rows, "final_start_pulse_count")
    current_source_reader_start_seen = any_seen(current_rows, "source_reader_start_pulse_count")
    current_dma_start_seen = any_seen(current_rows, "dma_start_seen_count")
    current_dma_busy_seen = any_seen(current_rows, "dma_busy_cycles")
    current_bridge_tx_rd_en_seen = any_seen(current_rows, "bridge_tx_rd_en_cycles")
    current_bridge_tx_accept_seen = any_seen(current_rows, "bridge_tx_accept_cycles")

    explicit_csr_start_seen = any_seen(explicit_rows, "csr_start_pulse_count")
    explicit_ring_doorbell_seen = any_seen(explicit_rows, "ring_doorbell_pulse_count")
    explicit_fetcher_start_seen = any_seen(explicit_rows, "fetcher_start_pulse_count")
    explicit_final_start_seen = any_seen(explicit_rows, "final_start_pulse_count")
    explicit_source_reader_start_seen = any_seen(explicit_rows, "source_reader_start_pulse_count")
    explicit_dma_start_seen = any_seen(explicit_rows, "dma_start_seen_count")
    explicit_dma_busy_seen = any_seen(explicit_rows, "dma_busy_cycles")
    explicit_bridge_tx_rd_en_seen = any_seen(explicit_rows, "bridge_tx_rd_en_cycles")
    explicit_bridge_tx_accept_seen = any_seen(explicit_rows, "bridge_tx_accept_cycles")
    explicit_crypto_dma_in_accept_seen = any_seen(explicit_rows, "crypto_dma_in_accept_cycles")
    explicit_csr_start_pulsed_by_probe = any(truthy(row.get("csr_start_pulsed_by_probe")) for row in explicit_rows)

    ring_size_zero = bool_majority(included_rows, lambda row: truthy(row.get("ring_size_zero")))
    runtime_ring_bypass_enabled = bool_majority(
        included_rows, lambda row: truthy(row.get("runtime_ring_bypass_enabled"))
    )
    fastpath_enabled = bool_majority(included_rows, lambda row: truthy(row.get("fastpath_enabled")))

    if explicit_final_start_seen:
        if explicit_csr_start_seen and not explicit_ring_doorbell_seen and not explicit_fetcher_start_seen:
            final_start_source_classification = "csr_start_path"
        elif explicit_ring_doorbell_seen:
            final_start_source_classification = "ring_doorbell_path"
        elif explicit_fetcher_start_seen:
            final_start_source_classification = "fetcher_path"
        else:
            final_start_source_classification = "conflicting_start_sources"
    elif explicit_csr_start_seen or explicit_ring_doorbell_seen or explicit_fetcher_start_seen:
        final_start_source_classification = "no_start_source"
    else:
        final_start_source_classification = "no_start_source"

    if collision or not current_rows or not explicit_rows:
        dma_start_path_classification = "inconclusive"
        recommended_next_stage = "FixSamplingOrAlignment"
    elif explicit_csr_start_seen and not explicit_final_start_seen:
        dma_start_path_classification = "csr_start_seen_but_final_start_absent"
        recommended_next_stage = "FinalStartSelectionLogicDiagnosis"
    elif explicit_final_start_seen and not explicit_dma_start_seen and not explicit_dma_busy_seen:
        dma_start_path_classification = "final_start_seen_but_dma_not_active"
        recommended_next_stage = "SourceReaderStartLatchDiagnosis"
    elif (explicit_dma_start_seen or explicit_dma_busy_seen) and not explicit_bridge_tx_rd_en_seen:
        dma_start_path_classification = "dma_active_but_no_rd_en"
        recommended_next_stage = "DMARdEnableGatingDiagnosis"
    elif explicit_bridge_tx_rd_en_seen and not explicit_bridge_tx_accept_seen:
        dma_start_path_classification = "rd_en_seen_but_no_accept"
        recommended_next_stage = "BridgeAcceptPathDiagnosis"
    elif (
        current_bridge_tx_nonempty_seen
        and ring_size_zero
        and runtime_ring_bypass_enabled
        and not current_csr_start_seen
        and not current_ring_doorbell_seen
        and not current_fetcher_start_seen
        and not current_final_start_seen
        and not current_source_reader_start_seen
        and not current_dma_start_seen
        and not current_bridge_tx_rd_en_seen
    ):
        dma_start_path_classification = "start_source_absent"
        recommended_next_stage = "StartPulseInjectionOrProbeControlFix"
    else:
        dma_start_path_classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a13_due_to_inconclusive"

    return {
        "diagnostic_csr_map_version": DMA_START_PATH_DIAG_CSR_MAP_VERSION,
        "diagnostic_csr_address_range": "0x230-0x248",
        "dma_start_path_diag_csr_collision": collision,
        "ring_size_zero": ring_size_zero,
        "runtime_ring_bypass_enabled": runtime_ring_bypass_enabled,
        "fastpath_enabled": fastpath_enabled,
        "current_bridge_tx_nonempty_seen": current_bridge_tx_nonempty_seen,
        "current_csr_start_seen": current_csr_start_seen,
        "current_ring_doorbell_seen": current_ring_doorbell_seen,
        "current_fetcher_start_seen": current_fetcher_start_seen,
        "current_final_start_seen": current_final_start_seen,
        "current_source_reader_start_seen": current_source_reader_start_seen,
        "current_dma_start_seen": current_dma_start_seen,
        "current_dma_busy_seen": current_dma_busy_seen,
        "current_bridge_tx_rd_en_seen": current_bridge_tx_rd_en_seen,
        "current_bridge_tx_accept_seen": current_bridge_tx_accept_seen,
        "explicit_csr_start_seen": explicit_csr_start_seen,
        "explicit_ring_doorbell_seen": explicit_ring_doorbell_seen,
        "explicit_fetcher_start_seen": explicit_fetcher_start_seen,
        "explicit_final_start_seen": explicit_final_start_seen,
        "explicit_source_reader_start_seen": explicit_source_reader_start_seen,
        "explicit_dma_start_seen": explicit_dma_start_seen,
        "explicit_dma_busy_seen": explicit_dma_busy_seen,
        "explicit_bridge_tx_rd_en_seen": explicit_bridge_tx_rd_en_seen,
        "explicit_bridge_tx_accept_seen": explicit_bridge_tx_accept_seen,
        "explicit_crypto_dma_in_accept_seen": explicit_crypto_dma_in_accept_seen,
        "explicit_csr_start_pulsed_by_probe": explicit_csr_start_pulsed_by_probe,
        "final_start_source_classification": final_start_source_classification,
        "dma_start_path_classification": dma_start_path_classification,
        "recommended_next_stage": recommended_next_stage,
    }


def start_pulse_injection_diagnosis(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    collision = start_pulse_injection_diag_csr_collision(Path(args.repo_root))
    included_rows = [row for row in rows if is_included_in_stats(row)]

    def any_seen(field: str) -> bool:
        return any(int_value(row.get(field, 0)) > 0 for row in included_rows)

    def first_value(field: str) -> Any:
        for row in included_rows:
            value = row.get(field)
            if value not in (None, ""):
                return value
        return None

    axil_write_hit_control_seen = any_seen("axil_write_hit_control_count")
    axil_write_hit_start_seen = any_seen("axil_write_hit_start_count")
    axil_write_hit_doorbell_seen = any_seen("axil_write_hit_doorbell_count")
    csr_start_seen = any_seen("csr_start_pulse_count")
    ring_doorbell_seen = any_seen("ring_doorbell_pulse_count")
    fetcher_start_seen = any_seen("fetcher_start_pulse_count")
    final_start_seen = any_seen("final_start_pulse_count")
    source_reader_start_seen = any_seen("source_reader_start_pulse_count")
    dma_start_seen = any_seen("dma_start_seen_count")
    dma_busy_seen = any_seen("dma_busy_cycles")
    bridge_tx_nonempty_seen = any_seen("bridge_tx_nonempty_cycles")
    bridge_tx_rd_en_seen = any_seen("bridge_tx_rd_en_cycles")
    bridge_tx_accept_seen = any_seen("bridge_tx_accept_cycles")
    crypto_dma_in_accept_seen = any_seen("crypto_dma_in_accept_cycles")
    ring_size_zero = bool_majority(included_rows, lambda row: truthy(row.get("ring_size_zero")))
    runtime_ring_bypass_enabled = bool_majority(
        included_rows, lambda row: truthy(row.get("runtime_ring_bypass_enabled"))
    )
    explicit_csr_start_pulsed_by_probe = any(
        truthy(row.get("explicit_csr_start_pulsed_by_probe", row.get("csr_start_pulsed_by_probe")))
        for row in included_rows
    )
    expected_start_source = first_value("start_path_expected_source") or (
        "csr_start_due_to_ring_size_zero" if ring_size_zero else "ring_or_fetcher_start_due_to_ring_size_nonzero"
    )

    if collision or not included_rows:
        classification = "inconclusive"
        recommended_next_stage = "FixSamplingOrAlignment"
    elif not axil_write_hit_control_seen and not axil_write_hit_start_seen and not axil_write_hit_doorbell_seen:
        classification = "probe_write_not_observed_by_axil"
        recommended_next_stage = "AXILCSRAddressOrRoutingDiagnosis"
    elif axil_write_hit_control_seen and not axil_write_hit_start_seen and not csr_start_seen:
        classification = "probe_write_observed_but_no_csr_start"
        recommended_next_stage = "StartWriteValueOrWSTRBDiagnosis"
    elif axil_write_hit_start_seen and not csr_start_seen:
        classification = "probe_write_observed_but_no_csr_start"
        recommended_next_stage = "StartPulseGenerationConditionDiagnosis"
    elif csr_start_seen and not final_start_seen:
        classification = "csr_start_seen_but_no_final_start"
        recommended_next_stage = "FinalStartSelectionLogicDiagnosis"
    elif final_start_seen and not dma_start_seen and not dma_busy_seen and not source_reader_start_seen:
        classification = "final_start_seen_but_no_dma_start"
        recommended_next_stage = "SourceReaderStartLatchDiagnosis"
    elif (dma_start_seen or dma_busy_seen or source_reader_start_seen) and not bridge_tx_rd_en_seen:
        classification = "dma_start_seen_then_rd_en_absent"
        recommended_next_stage = "DMARdEnableGatingDiagnosis"
    elif bridge_tx_rd_en_seen and not bridge_tx_accept_seen:
        classification = "rd_en_seen_but_no_accept"
        recommended_next_stage = "BridgeAcceptPathDiagnosis"
    elif dma_start_seen and bridge_tx_rd_en_seen:
        classification = "start_chain_alive"
        recommended_next_stage = "BridgeOrCryptoAcceptFollowup"
    else:
        classification = "inconclusive"
        recommended_next_stage = "rerun_start_pulse_injection_due_to_inconclusive"

    return {
        "diagnostic_csr_map_version": START_PULSE_INJECTION_DIAG_CSR_MAP_VERSION,
        "diagnostic_csr_address_range": "0x24C-0x254",
        "start_pulse_injection_diag_csr_collision": collision,
        "raw_sample_count": len(rows),
        "included_sample_count": len(included_rows),
        "explicit_csr_start_pulsed_by_probe": explicit_csr_start_pulsed_by_probe,
        "explicit_start_write_addr": hex32_or_none(first_value("explicit_start_write_addr")),
        "explicit_start_write_value": hex32_or_none(first_value("explicit_start_write_value")),
        "explicit_start_write_mask_or_wstrb": hex32_or_none(first_value("explicit_start_write_mask_or_wstrb")),
        "explicit_start_readback_before": hex32_or_none(first_value("explicit_start_readback_before")),
        "explicit_start_readback_after": hex32_or_none(first_value("explicit_start_readback_after")),
        "explicit_start_readback_after_clear": hex32_or_none(first_value("explicit_start_readback_after_clear")),
        "csr_control_reg_addr_expected": hex32_or_none(first_value("csr_control_reg_addr_expected")),
        "csr_start_bit_expected": first_value("csr_start_bit_expected"),
        "axil_write_hit_control_seen": axil_write_hit_control_seen,
        "axil_write_hit_start_seen": axil_write_hit_start_seen,
        "axil_write_hit_doorbell_seen": axil_write_hit_doorbell_seen,
        "axil_write_hit_control_count_max": max_counter(included_rows, "axil_write_hit_control_count"),
        "axil_write_hit_start_count_max": max_counter(included_rows, "axil_write_hit_start_count"),
        "axil_write_hit_doorbell_count_max": max_counter(included_rows, "axil_write_hit_doorbell_count"),
        "csr_start_seen": csr_start_seen,
        "ring_doorbell_seen": ring_doorbell_seen,
        "fetcher_start_seen": fetcher_start_seen,
        "final_start_seen": final_start_seen,
        "source_reader_start_seen": source_reader_start_seen,
        "dma_start_seen": dma_start_seen,
        "dma_busy_seen": dma_busy_seen,
        "bridge_tx_nonempty_seen": bridge_tx_nonempty_seen,
        "bridge_tx_rd_en_seen": bridge_tx_rd_en_seen,
        "bridge_tx_accept_seen": bridge_tx_accept_seen,
        "crypto_dma_in_accept_seen": crypto_dma_in_accept_seen,
        "ring_size_zero": ring_size_zero,
        "runtime_ring_bypass_enabled": runtime_ring_bypass_enabled,
        "expected_start_source": expected_start_source,
        "start_pulse_injection_classification": classification,
        "recommended_next_stage": recommended_next_stage,
    }


def explicit_start_bridge_handoff_diagnosis(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in included_rows:
        groups.setdefault(str(row.get("explicit_start_bridge_handoff_config") or ""), []).append(row)

    baseline_rows = groups.get("Current_Bypass_NoExplicitStart", [])
    explicit_rows = [
        row for row in included_rows
        if str(row.get("explicit_start_timing") or "none") != "none"
    ]

    def any_seen(rows_for_group: list[dict[str, Any]], field: str) -> bool:
        return any(int_value(row.get(field, 0)) > 0 for row in rows_for_group)

    def first_value(field: str) -> Any:
        for row in included_rows:
            value = row.get(field)
            if value not in (None, ""):
                return value
        return None

    def explicit_start_verified(row: dict[str, Any]) -> bool:
        return (
            int_value(row.get("axil_write_hit_start_count", 0)) > 0
            and int_value(row.get("csr_start_pulse_count", 0)) > 0
            and int_value(row.get("final_start_pulse_count", 0)) > 0
            and int_value(row.get("dma_start_seen_count", 0)) > 0
        )

    explicit_start_missing = any(
        int_value(row.get("axil_write_hit_start_count", 0)) == 0
        or int_value(row.get("csr_start_pulse_count", 0)) == 0
        for row in explicit_rows
    )
    explicit_start_verified_any = any(explicit_start_verified(row) for row in explicit_rows)
    explicit_start_write_addr_matches_dma_csr_base = all(
        truthy(row.get("explicit_start_write_addr_matches_dma_csr_base"))
        for row in explicit_rows
    ) if explicit_rows else False
    row_level_start_and_bridge_nonempty_seen = any(
        (
            int_value(row.get("dma_start_seen_count", 0)) > 0
            or int_value(row.get("dma_busy_cycles", 0)) > 0
        )
        and int_value(row.get("bridge_tx_nonempty_cycles", 0)) > 0
        for row in explicit_rows
    )
    dma_or_source_reader_busy_seen = any(
        int_value(row.get("dma_busy_cycles", 0)) > 0
        or int_value(row.get("source_reader_busy_cycles", 0)) > 0
        for row in explicit_rows
    )

    baseline_bridge_tx_nonempty_seen = any_seen(baseline_rows, "bridge_tx_nonempty_cycles")
    baseline_dma_start_seen = any_seen(baseline_rows, "dma_start_seen_count")
    baseline_bridge_tx_rd_en_seen = any_seen(baseline_rows, "bridge_tx_rd_en_cycles")
    bridge_tx_nonempty_seen = any_seen(explicit_rows, "bridge_tx_nonempty_cycles")
    bridge_tx_rd_en_seen = any_seen(explicit_rows, "bridge_tx_rd_en_cycles")
    bridge_tx_accept_seen = any_seen(explicit_rows, "bridge_tx_accept_cycles")
    crypto_dma_in_accept_seen = any_seen(explicit_rows, "crypto_dma_in_accept_cycles")
    backend_seen = any(any_nonzero(row, BACKEND_SERVICE_COUNTERS) for row in explicit_rows)
    rollback_recovery_seen = any(any_nonzero(row, ROLLBACK_RECOVERY_COUNTERS) for row in explicit_rows)
    rollback_trigger_candidate_seen = any(
        int_value(row.get("pbm_wr_last_error_accepted_count", 0)) > 0 for row in explicit_rows
    )

    if not included_rows or not baseline_rows or not explicit_rows:
        handoff_classification = "inconclusive"
        recommended_next_stage = "FixSamplingOrAlignment"
    elif explicit_start_missing:
        handoff_classification = "explicit_start_not_verified_by_hardware"
        recommended_next_stage = "StartPulseInjectionOrProbeControlFix"
    elif rollback_recovery_seen or rollback_trigger_candidate_seen:
        handoff_classification = "rollback_or_last_error_reached"
        recommended_next_stage = "DropRollbackCouplingDiagnosis"
    elif crypto_dma_in_accept_seen and not backend_seen:
        handoff_classification = "crypto_dma_accept_without_backend_service"
        recommended_next_stage = "BackendInputGatingDiagnosis"
    elif bridge_tx_accept_seen and not crypto_dma_in_accept_seen:
        handoff_classification = "bridge_accept_without_crypto_dma_accept"
        recommended_next_stage = "CryptoDMAIngressAcceptDiagnosis"
    elif bridge_tx_rd_en_seen and not bridge_tx_accept_seen:
        handoff_classification = "rd_en_seen_but_no_bridge_accept"
        recommended_next_stage = "BridgeAcceptPathDiagnosis"
    elif row_level_start_and_bridge_nonempty_seen and dma_or_source_reader_busy_seen and not bridge_tx_rd_en_seen:
        handoff_classification = "dma_active_bridge_nonempty_but_no_rd_en"
        recommended_next_stage = "DMARdEnableGatingDiagnosis"
    elif explicit_start_verified_any and not bridge_tx_nonempty_seen:
        handoff_classification = "explicit_start_valid_but_bridge_not_nonempty"
        recommended_next_stage = "BridgeDataProductionDiagnosis"
    else:
        handoff_classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a15_due_to_inconclusive"

    return {
        "diagnostic_csr_map_version": EXPLICIT_START_BRIDGE_HANDOFF_DIAG_CSR_MAP_VERSION,
        "raw_sample_count": len(rows),
        "included_sample_count": len(included_rows),
        "shadow_control_base": hex32_or_none(first_value("shadow_control_base")) or "0x40000000",
        "dma_csr_base": hex32_or_none(first_value("dma_csr_base")) or "0x40001000",
        "explicit_start_write_addr": hex32_or_none(first_value("explicit_start_write_addr")),
        "explicit_start_write_value": hex32_or_none(first_value("explicit_start_write_value")),
        "dma_ctrl_read_before": hex32_or_none(first_value("dma_ctrl_read_before")),
        "dma_ctrl_read_after": hex32_or_none(first_value("dma_ctrl_read_after")),
        "explicit_start_write_addr_matches_dma_csr_base": explicit_start_write_addr_matches_dma_csr_base,
        "explicit_start_verified_by_hardware": explicit_start_verified_any,
        "row_level_start_and_bridge_nonempty_seen": row_level_start_and_bridge_nonempty_seen,
        "row_level_overlap_note": "row-level approximation; not strict temporal overlap",
        "dma_or_source_reader_busy_seen": dma_or_source_reader_busy_seen,
        "baseline_bridge_tx_nonempty_seen": baseline_bridge_tx_nonempty_seen,
        "baseline_dma_start_seen": baseline_dma_start_seen,
        "baseline_bridge_tx_rd_en_seen": baseline_bridge_tx_rd_en_seen,
        "bridge_tx_nonempty_seen": bridge_tx_nonempty_seen,
        "bridge_tx_rd_en_seen": bridge_tx_rd_en_seen,
        "bridge_tx_accept_seen": bridge_tx_accept_seen,
        "crypto_dma_in_accept_seen": crypto_dma_in_accept_seen,
        "backend_activity_seen": backend_seen,
        "rollback_recovery_seen": rollback_recovery_seen,
        "rollback_trigger_candidate_seen": rollback_trigger_candidate_seen,
        "handoff_classification": handoff_classification,
        "recommended_next_stage": recommended_next_stage,
    }


def dma_rd_en_equation_diagnosis(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]

    def any_seen(field: str) -> bool:
        return any(int_value(row.get(field, 0)) > 0 for row in included_rows)

    def sum_field(field: str) -> int:
        return sum(int_value(row.get(field, 0)) for row in included_rows)

    def first_nonblank(field: str) -> Any:
        for row in included_rows:
            value = row.get(field)
            if value not in (None, ""):
                return value
        return None

    explicit_start_verified = any(
        truthy(row.get("explicit_start_verified_by_hardware"))
        or (
            int_value(row.get("axil_write_hit_start_count", 0)) > 0
            and int_value(row.get("csr_start_pulse_count", 0)) > 0
            and int_value(row.get("final_start_pulse_count", 0)) > 0
            and int_value(row.get("dma_start_seen_count", 0)) > 0
        )
        for row in included_rows
    )
    loopback_mode_raw = int_value(first_nonblank("dma_rd_en_loopback_mode_raw"))
    runtime_ring_bypass_enabled = any(truthy(row.get("runtime_ring_bypass_enabled")) for row in included_rows)
    tx_axis_tready_cycles = sum_field("dma_rd_en_tx_axis_tready_cycles")
    crypto_to_dma_nonempty_cycles = sum_field("dma_rd_en_crypto_to_dma_nonempty_cycles")
    tx_ready_when_nonempty_cycles = sum_field("dma_rd_en_tx_ready_when_nonempty_cycles")
    dma_req_rd_cycles = sum_field("dma_rd_en_dma_req_rd_cycles")
    loopback_branch_selected_cycles = sum_field("dma_rd_en_loopback_branch_selected_cycles")
    normal_branch_selected_cycles = sum_field("dma_rd_en_normal_branch_selected_cycles")
    loopback_branch_candidate_cycles = sum_field("dma_rd_en_loopback_branch_candidate_cycles")
    equation_true_but_rd_en_low_cycles = sum_field("dma_rd_en_equation_true_but_rd_en_low_cycles")
    bridge_tx_rd_en_cycles = sum_field("bridge_tx_rd_en_cycles")
    bridge_tx_accept_cycles = sum_field("bridge_tx_accept_cycles")

    if not included_rows:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a26_due_to_inconclusive"
    elif bridge_tx_rd_en_cycles > 0 and bridge_tx_accept_cycles == 0:
        classification = "rd_en_seen_but_no_bridge_accept"
        recommended_next_stage = "BridgeAcceptPathDiagnosis"
    elif bridge_tx_rd_en_cycles > 0 and bridge_tx_accept_cycles > 0:
        classification = "rd_en_and_bridge_accept_seen"
        recommended_next_stage = "Stage1A10_CryptoDMAHandoffDiagnosis"
    elif runtime_ring_bypass_enabled and loopback_mode_raw != 2:
        classification = "loopback_mode_not_pbm_passthrough"
        recommended_next_stage = "DMALoopbackModeControlDiagnosis"
    elif loopback_mode_raw == 2 and tx_axis_tready_cycles == 0:
        classification = "loopback_branch_tx_axis_tready_absent"
        recommended_next_stage = "TXAxisReadyGatingDiagnosis"
    elif loopback_mode_raw == 2 and crypto_to_dma_nonempty_cycles > 0 and tx_ready_when_nonempty_cycles == 0:
        classification = "tx_ready_absent_while_bridge_nonempty"
        recommended_next_stage = "TXReadyWhileBridgeNonemptyDiagnosis"
    elif loopback_mode_raw != 2 and dma_req_rd_cycles == 0:
        classification = "normal_branch_dma_req_rd_absent"
        recommended_next_stage = "DMANormalBranchRdRequestDiagnosis"
    elif loopback_branch_candidate_cycles > 0 and bridge_tx_rd_en_cycles == 0:
        classification = "loopback_branch_equation_true_but_rd_en_low"
        recommended_next_stage = "DMARdEnableEquationInstrumentationBug"
    else:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a26_due_to_inconclusive"

    return {
        "diagnostic_csr_address_range": "0x280-0x2A0",
        "diagnostic_csr_collision": dma_rd_en_equation_diag_csr_collision(Path(args.repo_root)),
        "raw_sample_count": len(rows),
        "included_sample_count": len(included_rows),
        "explicit_start_verified_by_hardware": explicit_start_verified,
        "runtime_ring_bypass_enabled": runtime_ring_bypass_enabled,
        "dma_rd_en_loopback_mode_raw": loopback_mode_raw,
        "dma_rd_en_tx_axis_tready_cycles": tx_axis_tready_cycles,
        "dma_rd_en_crypto_to_dma_nonempty_cycles": crypto_to_dma_nonempty_cycles,
        "dma_rd_en_tx_ready_when_nonempty_cycles": tx_ready_when_nonempty_cycles,
        "dma_rd_en_dma_req_rd_cycles": dma_req_rd_cycles,
        "dma_rd_en_loopback_branch_selected_cycles": loopback_branch_selected_cycles,
        "dma_rd_en_normal_branch_selected_cycles": normal_branch_selected_cycles,
        "dma_rd_en_loopback_branch_candidate_cycles": loopback_branch_candidate_cycles,
        "dma_rd_en_equation_true_but_rd_en_low_cycles": equation_true_but_rd_en_low_cycles,
        "bridge_tx_rd_en_cycles": bridge_tx_rd_en_cycles,
        "bridge_tx_accept_cycles": bridge_tx_accept_cycles,
        "bridge_tx_rd_en_seen": bridge_tx_rd_en_cycles > 0,
        "bridge_tx_accept_seen": bridge_tx_accept_cycles > 0,
        "dma_rd_en_equation_classification": classification,
        "recommended_next_stage": recommended_next_stage,
    }


def bridge_data_production_diagnosis(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in included_rows:
        groups.setdefault(str(row.get("bridge_data_production_config") or ""), []).append(row)

    a12_rows = groups.get("A12_NoStart_Replay", [])
    a15_rows = groups.get("A15_AfterWorkloadStart_Replay", [])
    baseline_threshold = 2

    def field_int(row: dict[str, Any], field: str) -> int:
        try:
            return int_value(row.get(field, 0))
        except (TypeError, ValueError):
            return 0

    def any_seen(rows_for_group: list[dict[str, Any]], field: str) -> bool:
        return any(field_int(row, field) > 0 for row in rows_for_group)

    def sum_field(rows_for_group: list[dict[str, Any]], field: str) -> int:
        return sum(field_int(row, field) for row in rows_for_group)

    def first_value(field: str) -> Any:
        for row in included_rows:
            value = row.get(field)
            if value not in (None, ""):
                return value
        return None

    def explicit_start_verified(row: dict[str, Any]) -> bool:
        return (
            field_int(row, "axil_write_hit_start_count") > 0
            and field_int(row, "csr_start_pulse_count") > 0
            and field_int(row, "final_start_pulse_count") > 0
            and field_int(row, "dma_start_seen_count") > 0
        )

    def control_side_effect(row: dict[str, Any]) -> bool:
        start_bit_mask = field_int(row, "start_bit_mask") or 1
        return (field_int(row, "dma_ctrl_changed_bits") & (~start_bit_mask & 0xFFFFFFFF)) != 0

    a12_nonempty_repeats = sum(
        1 for row in a12_rows if field_int(row, "bridge_tx_nonempty_cycles") > 0
    )
    baseline_bridge_reproduced = a12_nonempty_repeats >= baseline_threshold
    a12_no_start_replay_bridge_nonempty_seen = a12_nonempty_repeats > 0

    a15_after_start_bridge_nonempty_seen = any_seen(a15_rows, "bridge_tx_nonempty_cycles")
    a15_after_start_explicit_start_verified = any(explicit_start_verified(row) for row in a15_rows)
    a15_after_start_dma_start_seen = any_seen(a15_rows, "dma_start_seen_count")
    a15_after_start_bridge_tx_rd_en_cycles = sum_field(a15_rows, "bridge_tx_rd_en_cycles")
    a15_after_start_bridge_tx_accept_cycles = sum_field(a15_rows, "bridge_tx_accept_cycles")
    a15_after_start_crypto_dma_in_accept_cycles = sum_field(a15_rows, "crypto_dma_in_accept_cycles")

    explicit_start_and_bridge_nonempty_rows = [
        row
        for row in a15_rows
        if explicit_start_verified(row)
        and field_int(row, "bridge_tx_nonempty_cycles") > 0
        and field_int(row, "dma_start_seen_count") > 0
    ]
    explicit_start_and_bridge_nonempty_same_row_seen = bool(explicit_start_and_bridge_nonempty_rows)
    explicit_start_and_bridge_nonempty_rows_count = len(explicit_start_and_bridge_nonempty_rows)

    bridge_tx_nonempty_seen_any = any_seen(included_rows, "bridge_tx_nonempty_cycles")
    bridge_tx_wr_en_seen = any_seen(included_rows, "bridge_tx_wr_en_cycles")
    bridge_tx_fifo_level_increased = any(
        field_int(row, "bridge_tx_fifo_level_max") > 0
        or field_int(row, "bridge_tx_fifo_level_post") > field_int(row, "bridge_tx_fifo_level_pre")
        for row in included_rows
    )
    pbm_commit_seen = any(
        field_int(row, "pbm_commit_entry_count") > 0
        or field_int(row, "pbm_ptr_head_commit_delta_mod") > 0
        for row in included_rows
    )
    explicit_start_changed_control_state = any(control_side_effect(row) for row in a15_rows)
    backend_seen = any(any_nonzero(row, BACKEND_SERVICE_COUNTERS) for row in a15_rows)
    rollback_recovery_seen = any(any_nonzero(row, ROLLBACK_RECOVERY_COUNTERS) for row in a15_rows)
    rollback_trigger_candidate_seen = any(
        field_int(row, "pbm_wr_last_error_accepted_count") > 0 for row in a15_rows
    )

    has_required_configs = bool(a12_rows) and bool(a15_rows)
    has_negative_delta = any(
        field_int(row, "pbm_ptr_head_commit_delta_mod") < 0
        or field_int(row, "pbm_ptr_tail_delta_mod") < 0
        for row in included_rows
    )

    if not included_rows or not has_required_configs or has_negative_delta:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a16_due_to_inconclusive"
    elif not baseline_bridge_reproduced and not pbm_commit_seen:
        classification = "pbm_commit_not_reproduced"
        recommended_next_stage = "PBMCommitReproductionDiagnosis"
    elif not baseline_bridge_reproduced and pbm_commit_seen:
        classification = "a12_baseline_not_reproduced"
        recommended_next_stage = "BridgeDataProductionReproductionCheck"
    elif (
        baseline_bridge_reproduced
        and a15_after_start_explicit_start_verified
        and not a15_after_start_bridge_nonempty_seen
    ):
        classification = "explicit_start_config_lost_bridge_data"
        recommended_next_stage = (
            "CSRControlSideEffectDiagnosis"
            if explicit_start_changed_control_state
            else "BridgeDataProductionUnderExplicitStartDiagnosis"
        )
    elif pbm_commit_seen and not bridge_tx_wr_en_seen and not bridge_tx_nonempty_seen_any:
        classification = "pbm_commit_without_bridge_enqueue"
        recommended_next_stage = "PBMReadSideToBridgeEnqueueDiagnosis"
    elif bridge_tx_wr_en_seen and not bridge_tx_nonempty_seen_any:
        classification = "bridge_enqueue_without_fifo_nonempty"
        recommended_next_stage = "BridgeFIFOLevelVisibilityDiagnosis"
    elif (
        a15_after_start_explicit_start_verified
        and a15_after_start_bridge_nonempty_seen
        and a15_after_start_dma_start_seen
        and a15_after_start_bridge_tx_rd_en_cycles == 0
    ):
        classification = "bridge_nonempty_with_dma_start_but_no_rd_en"
        recommended_next_stage = "DMARdEnableGatingDiagnosis"
    elif a15_after_start_bridge_tx_rd_en_cycles > 0 and a15_after_start_bridge_tx_accept_cycles == 0:
        classification = "bridge_rd_en_without_accept"
        recommended_next_stage = "BridgeAcceptPathDiagnosis"
    elif (
        a15_after_start_bridge_tx_accept_cycles > 0
        and a15_after_start_crypto_dma_in_accept_cycles == 0
    ):
        classification = "bridge_accept_without_crypto_dma_accept"
        recommended_next_stage = "CryptoDMAIngressAcceptDiagnosis"
    elif a15_after_start_crypto_dma_in_accept_cycles > 0 and not backend_seen:
        classification = "crypto_dma_accept_without_backend_activity"
        recommended_next_stage = "BackendInputGatingDiagnosis"
    elif rollback_recovery_seen or rollback_trigger_candidate_seen:
        classification = "rollback_or_last_error_reached"
        recommended_next_stage = "DropRollbackCouplingDiagnosis"
    else:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a16_due_to_inconclusive"

    return {
        "diagnostic_csr_map_version": BRIDGE_DATA_PRODUCTION_DIAG_CSR_MAP_VERSION,
        "raw_sample_count": len(rows),
        "included_sample_count": len(included_rows),
        "baseline_bridge_reproduced": baseline_bridge_reproduced,
        "baseline_bridge_reproduced_repeats": a12_nonempty_repeats,
        "baseline_bridge_reproduced_threshold": f"{baseline_threshold}/3",
        "a12_no_start_replay_bridge_nonempty_seen": a12_no_start_replay_bridge_nonempty_seen,
        "a15_after_start_bridge_nonempty_seen": a15_after_start_bridge_nonempty_seen,
        "a15_after_start_explicit_start_verified": a15_after_start_explicit_start_verified,
        "a15_after_start_dma_start_seen": a15_after_start_dma_start_seen,
        "a15_after_start_bridge_tx_rd_en_cycles": a15_after_start_bridge_tx_rd_en_cycles,
        "a15_after_start_bridge_tx_accept_cycles": a15_after_start_bridge_tx_accept_cycles,
        "a15_after_start_crypto_dma_in_accept_cycles": a15_after_start_crypto_dma_in_accept_cycles,
        "explicit_start_and_bridge_nonempty_same_row_seen": explicit_start_and_bridge_nonempty_same_row_seen,
        "explicit_start_and_bridge_nonempty_rows_count": explicit_start_and_bridge_nonempty_rows_count,
        "bridge_tx_nonempty_seen_any": bridge_tx_nonempty_seen_any,
        "bridge_tx_wr_en_seen": bridge_tx_wr_en_seen,
        "bridge_tx_fifo_level_increased": bridge_tx_fifo_level_increased,
        "bridge_fifo_sampling_semantics": {
            "bridge_tx_fifo_level_pre_post": "snapshot values",
            "bridge_tx_fifo_level_max": "maximum level observed during the probe window",
            "bridge_tx_nonempty_cycles": "level-active cycle count",
            "bridge_tx_wr_en_cycles": "enqueue-event cycle count",
        },
        "dma_ctrl_read_before": hex32_or_none(first_value("dma_ctrl_read_before")),
        "explicit_start_write_value": hex32_or_none(first_value("explicit_start_write_value")),
        "dma_ctrl_read_after": hex32_or_none(first_value("dma_ctrl_read_after")),
        "dma_ctrl_changed_bits": hex32_or_none(first_value("dma_ctrl_changed_bits")),
        "start_bit_mask": hex32_or_none(first_value("start_bit_mask")) or "0x00000001",
        "explicit_start_changed_control_state": explicit_start_changed_control_state,
        "bit_hash_match_with_reference_a12": None,
        "diagnostic_bit_changed_since_stage1a12": None,
        "bridge_data_production_classification": classification,
        "bridge_data_production_classification_reason": bridge_data_production_reason(
            classification,
            baseline_bridge_reproduced,
            pbm_commit_seen,
            a15_after_start_explicit_start_verified,
            a15_after_start_bridge_nonempty_seen,
        ),
        "recommended_next_stage": recommended_next_stage,
    }


def bridge_data_production_reason(
    classification: str,
    baseline_bridge_reproduced: bool,
    pbm_commit_seen: bool,
    a15_after_start_explicit_start_verified: bool,
    a15_after_start_bridge_nonempty_seen: bool,
) -> str:
    if classification == "pbm_commit_not_reproduced":
        return "A12_NoStart_Replay did not reproduce PBM commit or bridge nonempty under the current diagnostic bit."
    if classification == "a12_baseline_not_reproduced":
        return "PBM commit was observed, but the A12 no-start bridge nonempty baseline was not reproduced."
    if classification == "explicit_start_config_lost_bridge_data":
        return "A12 baseline reproduced, but the A15 after-workload explicit-start config did not reproduce bridge nonempty."
    if classification == "bridge_nonempty_with_dma_start_but_no_rd_en":
        return "Explicit start, DMA start, and bridge nonempty appeared in the A15 config while bridge rd_en stayed zero."
    if classification == "inconclusive":
        return "Stage1A16 did not produce enough aligned config-level evidence for a clean branch."
    return (
        f"classification={classification}; baseline_bridge_reproduced={baseline_bridge_reproduced}; "
        f"pbm_commit_seen={pbm_commit_seen}; "
        f"a15_after_start_explicit_start_verified={a15_after_start_explicit_start_verified}; "
        f"a15_after_start_bridge_nonempty_seen={a15_after_start_bridge_nonempty_seen}"
    )


def pbm_commit_reproduction_diagnosis(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in included_rows:
        groups.setdefault(str(row.get("pbm_commit_reproduction_config") or ""), []).append(row)

    reference_rows = groups.get("CommitReferenceReplay", [])
    extra_rows = groups.get("CommitReplay_WithExtraPBMSnapshots", [])

    def field_int(row: dict[str, Any], field: str) -> int:
        try:
            return int_value(row.get(field, 0))
        except (TypeError, ValueError):
            return 0

    def sum_field(field: str) -> int:
        return sum(field_int(row, field) for row in included_rows)

    def any_field(field: str) -> bool:
        return any(field_int(row, field) > 0 for row in included_rows)

    def commit_seen(row: dict[str, Any]) -> bool:
        return (
            field_int(row, "pbm_commit_entry_count") > 0
            and field_int(row, "pbm_ptr_head_commit_delta_mod") > 0
        )

    has_required_configs = bool(reference_rows) and bool(extra_rows)
    invalid_clean_last_rows = 0
    clean_last_total = 0
    for row in included_rows:
        clean_last = field_int(row, "pbm_wr_last_accepted_count") - field_int(
            row, "pbm_wr_last_error_accepted_count"
        )
        if clean_last < 0:
            invalid_clean_last_rows += 1
        else:
            clean_last_total += clean_last

    has_negative_delta = any(
        field_int(row, "pbm_ptr_head_reserve_delta_mod") < 0
        or field_int(row, "pbm_ptr_head_commit_delta_mod") < 0
        or field_int(row, "pbm_ptr_tail_delta_mod") < 0
        for row in included_rows
    )
    commit_delta_unknown = any(
        field_int(row, "pbm_commit_entry_count") > 0
        and row.get("pbm_ptr_head_commit_delta_mod") in (None, "", "unknown")
        for row in included_rows
    )

    pbm_wr_valid_cycles = sum_field("pbm_wr_valid_cycles")
    pbm_wr_ready_high_cycles = sum_field("pbm_wr_ready_high_cycles")
    pbm_valid_not_ready_cycles = sum_field("pbm_valid_not_ready_cycles")
    pbm_wr_accept_cycles = sum_field("pbm_wr_accept_cycles")
    pbm_wr_last_accepted_count = sum_field("pbm_wr_last_accepted_count")
    pbm_wr_error_accepted_count = sum_field("pbm_wr_error_accepted_count")
    pbm_wr_last_error_accepted_count = sum_field("pbm_wr_last_error_accepted_count")
    pbm_alloc_meta_entry_count = sum_field("pbm_alloc_meta_entry_count")
    pbm_alloc_pbm_entry_count = sum_field("pbm_alloc_pbm_entry_count")
    pbm_commit_entry_count = sum_field("pbm_commit_entry_count")
    pbm_rollback_entry_count = sum_field("pbm_rollback_entry_count")
    ptr_head_reserve_delta_mod = sum_field("pbm_ptr_head_reserve_delta_mod")
    ptr_head_commit_delta_mod = sum_field("pbm_ptr_head_commit_delta_mod")
    ptr_tail_delta_mod = sum_field("pbm_ptr_tail_delta_mod")

    rollback_recovery_seen = (
        pbm_rollback_entry_count > 0
        or any(any_nonzero(row, ROLLBACK_RECOVERY_COUNTERS) for row in included_rows)
    )
    commit_reference_replay_commit_seen = any(commit_seen(row) for row in reference_rows)
    extra_snapshot_replay_commit_seen = any(commit_seen(row) for row in extra_rows)

    if (
        not included_rows
        or not has_required_configs
        or has_negative_delta
        or commit_delta_unknown
        or invalid_clean_last_rows > 0
    ):
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a17_due_to_inconclusive"
    elif rollback_recovery_seen:
        classification = "pbm_rollback_or_recovery_seen"
        recommended_next_stage = "DropRollbackCouplingDiagnosis"
    elif pbm_commit_entry_count > 0 and ptr_head_commit_delta_mod > 0:
        classification = "pbm_commit_reproduced"
        recommended_next_stage = "BridgeDataProductionDiagnosis"
    elif pbm_commit_entry_count > 0 and ptr_head_commit_delta_mod == 0:
        classification = "pbm_commit_entry_without_commit_pointer_delta"
        recommended_next_stage = "PBMCommitPointerVisibilityDiagnosis"
    elif pbm_wr_last_error_accepted_count > 0 and pbm_rollback_entry_count == 0:
        classification = "pbm_last_error_without_rollback"
        recommended_next_stage = "DropRollbackCouplingDiagnosis"
    elif clean_last_total > 0 and pbm_commit_entry_count == 0 and pbm_rollback_entry_count == 0:
        classification = "pbm_clean_last_without_commit"
        recommended_next_stage = "PBMCommitTransitionDiagnosis"
    elif (
        pbm_wr_accept_cycles > 0
        and pbm_wr_last_accepted_count == 0
        and pbm_commit_entry_count == 0
        and ptr_head_reserve_delta_mod > 0
        and ptr_head_commit_delta_mod == 0
    ):
        classification = "pbm_accept_without_packet_end"
        recommended_next_stage = "PacketTerminationVisibilityDiagnosis"
    elif (
        pbm_wr_valid_cycles > 0
        and pbm_valid_not_ready_cycles > 0
        and pbm_wr_accept_cycles == 0
        and pbm_commit_entry_count == 0
    ):
        classification = "pbm_ready_gating"
        recommended_next_stage = "PBMReadyGatingDiagnosis"
    elif pbm_wr_valid_cycles == 0 and pbm_wr_accept_cycles == 0 and pbm_commit_entry_count == 0:
        classification = "pbm_no_valid_seen"
        recommended_next_stage = "UpstreamIngressToPBMVisibilityDiagnosis"
    else:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a17_due_to_inconclusive"

    return {
        "raw_sample_count": len(rows),
        "included_sample_count": len(included_rows),
        "commit_reference_replay_rows": len(reference_rows),
        "extra_snapshot_replay_rows": len(extra_rows),
        "extra_snapshots_are_subsnapshots": True,
        "commit_reference_replay_commit_seen": commit_reference_replay_commit_seen,
        "extra_snapshot_replay_commit_seen": extra_snapshot_replay_commit_seen,
        "pbm_wr_valid_cycles": pbm_wr_valid_cycles,
        "pbm_wr_ready_high_cycles": pbm_wr_ready_high_cycles,
        "pbm_valid_not_ready_cycles": pbm_valid_not_ready_cycles,
        "pbm_wr_accept_cycles": pbm_wr_accept_cycles,
        "pbm_wr_last_accepted_count": pbm_wr_last_accepted_count,
        "pbm_wr_error_accepted_count": pbm_wr_error_accepted_count,
        "pbm_wr_last_error_accepted_count": pbm_wr_last_error_accepted_count,
        "pbm_wr_last_clean_accepted_count": clean_last_total,
        "invalid_clean_last_rows": invalid_clean_last_rows,
        "pbm_alloc_meta_entry_count": pbm_alloc_meta_entry_count,
        "pbm_alloc_pbm_entry_count": pbm_alloc_pbm_entry_count,
        "pbm_commit_entry_count": pbm_commit_entry_count,
        "pbm_rollback_entry_count": pbm_rollback_entry_count,
        "pbm_ptr_head_reserve_delta_mod": ptr_head_reserve_delta_mod,
        "pbm_ptr_head_commit_delta_mod": ptr_head_commit_delta_mod,
        "pbm_ptr_tail_delta_mod": ptr_tail_delta_mod,
        "pointer_delta_semantics": "modulo PBM depth; raw pre/post values are preserved in case_results.csv; unknown depth yields null/unknown delta",
        "rollback_recovery_seen": rollback_recovery_seen,
        "frontend_pressure_seen": any(any_nonzero(row, FRONTEND_PRESSURE_COUNTERS) for row in included_rows),
        "backend_activity_seen": any(any_nonzero(row, BACKEND_SERVICE_COUNTERS) for row in included_rows),
        "reference_stage1a9_dir": "shadow_recovery_probe_2026-04-24_161222",
        "reference_stage1a12_dir": "shadow_recovery_probe_2026-04-24_215540",
        "current_stage1a16_dir": "shadow_recovery_probe_2026-04-25_122304",
        "reference_commit_positive_source": "Stage1A9/Stage1A12 BF64_SM500 commit-positive engineering reference",
        "reference_case_name": "Case2_RuntimeRingBypass",
        "reference_burst_frames": 64,
        "reference_settle_ms": 500,
        "reference_burst_gap_us": 0,
        "reference_runtime_ring_bypass": True,
        "reference_fastpath_state": "fastpath disabled during runtime ring bypass",
        "reference_frame_words_hash": "unknown",
        "reference_comparison_note": "Stage1A17 replays the closest known commit-positive BF64 condition under the current diagnostic bit; bit hash differences are context, not automatic failure.",
        "pbm_commit_reproduction_classification": classification,
        "pbm_commit_reproduction_classification_reason": pbm_commit_reproduction_reason(classification),
        "recommended_next_stage": recommended_next_stage,
    }


def pbm_commit_reproduction_reason(classification: str) -> str:
    if classification == "pbm_no_valid_seen":
        return "PBM write ingress did not observe valid, accept, or commit activity."
    if classification == "pbm_ready_gating":
        return "PBM write ingress saw valid pressure but did not accept beats."
    if classification == "pbm_accept_without_packet_end":
        return "PBM accepted beats and reserve-side movement occurred, but no accepted packet last or commit was observed."
    if classification == "pbm_clean_last_without_commit":
        return "A clean accepted packet last reached PBM, but COMMIT and ROLLBACK entries stayed zero."
    if classification == "pbm_last_error_without_rollback":
        return "An error-qualified accepted packet last reached PBM, but ROLLBACK entry stayed zero."
    if classification == "pbm_commit_entry_without_commit_pointer_delta":
        return "PBM COMMIT entry was counted, but the commit pointer did not advance."
    if classification == "pbm_commit_reproduced":
        return "PBM COMMIT entry and commit pointer movement were both reproduced."
    if classification == "pbm_rollback_or_recovery_seen":
        return "Rollback or recovery counters were observed and take priority over commit reproduction branches."
    return "Stage1A17 did not produce enough aligned PBM write/FSM/pointer evidence for a clean branch."


def upstream_ingress_to_pbm_visibility_diagnosis(
    rows: list[dict[str, Any]], args: argparse.Namespace
) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in included_rows:
        groups.setdefault(
            str(row.get("upstream_ingress_to_pbm_visibility_config") or ""), []
        ).append(row)

    reference_rows = groups.get("IngressReferenceReplay", [])
    extra_rows = groups.get("IngressReplay_WithExtraSnapshots", [])

    def field_int(row: dict[str, Any], field: str) -> int:
        try:
            return int_value(row.get(field, 0))
        except (TypeError, ValueError):
            return 0

    def sum_field(field: str) -> int:
        return sum(field_int(row, field) for row in included_rows)

    def any_field(field: str) -> bool:
        return any(field_int(row, field) > 0 for row in included_rows)

    has_required_configs = bool(reference_rows) and bool(extra_rows)
    stage1_fire_seen = any_field("netdbg_stage1_fire_seen")
    acl_fire_seen = any_field("netdbg_acl_fire_seen")
    classifier_in_fire_seen = any_field("netdbg_classifier_in_fire_seen")
    classifier_dma_valid_seen = any_field("netdbg_classifier_dma_valid_seen")
    classifier_dma_fire_seen = any_field("netdbg_classifier_dma_fire_seen")
    classifier_dma_ready_seen = any_field("netdbg_classifier_dma_ready_seen")
    crypto_rx_valid_cycles = sum_field("crypto_rx_valid_cycles")
    crypto_rx_accept_cycles = sum_field("crypto_rx_accept_cycles")
    crypto_rx_valid_not_ready_cycles = sum_field("crypto_rx_valid_not_ready_cycles")
    pbm_wr_valid_cycles = sum_field("pbm_wr_valid_cycles")
    pbm_wr_accept_cycles = sum_field("pbm_wr_accept_cycles")
    pbm_valid_not_ready_cycles = sum_field("pbm_valid_not_ready_cycles")

    if not included_rows or not has_required_configs:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a18_due_to_inconclusive"
    elif pbm_wr_valid_cycles > 0 or pbm_wr_accept_cycles > 0:
        classification = "pbm_valid_reestablished"
        recommended_next_stage = "PBMCommitReproductionDiagnosis"
    elif (
        crypto_rx_valid_cycles > 0
        or crypto_rx_accept_cycles > 0
        or crypto_rx_valid_not_ready_cycles > 0
    ):
        classification = "crypto_rx_without_pbm_valid"
        recommended_next_stage = "PBMInputBindingDiagnosis"
    elif classifier_dma_valid_seen or classifier_dma_fire_seen:
        classification = "classifier_dma_valid_without_crypto_rx"
        recommended_next_stage = "ClassifierToSubsystemVisibilityDiagnosis"
    elif classifier_in_fire_seen:
        classification = "classifier_input_fire_without_classifier_dma_valid"
        recommended_next_stage = "ClassifierPayloadAdmissionDiagnosis"
    elif acl_fire_seen:
        classification = "acl_fire_without_classifier_input_fire"
        recommended_next_stage = "ACLToClassifierHandoffDiagnosis"
    elif stage1_fire_seen:
        classification = "stage1_fire_without_acl_fire"
        recommended_next_stage = "ACLFilterIngressDiagnosis"
    else:
        classification = "no_stage1_fire_seen"
        recommended_next_stage = "InjectionSourceEmissionDiagnosis"

    route_state_names_seen = sorted(
        {
            str(row.get("netdbg_route_state_name"))
            for row in included_rows
            if row.get("netdbg_route_state_name")
        }
    )

    return {
        "raw_sample_count": len(rows),
        "included_sample_count": len(included_rows),
        "ingress_reference_replay_rows": len(reference_rows),
        "extra_snapshot_replay_rows": len(extra_rows),
        "extra_snapshots_are_subsnapshots": True,
        "stage1_fire_seen": stage1_fire_seen,
        "acl_fire_seen": acl_fire_seen,
        "classifier_in_fire_seen": classifier_in_fire_seen,
        "classifier_dma_valid_seen": classifier_dma_valid_seen,
        "classifier_dma_fire_seen": classifier_dma_fire_seen,
        "classifier_dma_ready_seen": classifier_dma_ready_seen,
        "crypto_rx_valid_cycles": crypto_rx_valid_cycles,
        "crypto_rx_accept_cycles": crypto_rx_accept_cycles,
        "crypto_rx_valid_not_ready_cycles": crypto_rx_valid_not_ready_cycles,
        "pbm_wr_valid_cycles": pbm_wr_valid_cycles,
        "pbm_wr_accept_cycles": pbm_wr_accept_cycles,
        "pbm_valid_not_ready_cycles": pbm_valid_not_ready_cycles,
        "route_state_names_seen": route_state_names_seen,
        "upstream_ingress_to_pbm_classification": classification,
        "upstream_ingress_to_pbm_classification_reason": upstream_ingress_to_pbm_reason(
            classification
        ),
        "recommended_next_stage": recommended_next_stage,
    }


def upstream_ingress_to_pbm_reason(classification: str) -> str:
    if classification == "pbm_valid_reestablished":
        return "PBM write-valid activity reappeared, so PBM commit reproduction can be retried."
    if classification == "crypto_rx_without_pbm_valid":
        return "Crypto RX activity was observed, but PBM write-valid remained zero."
    if classification == "classifier_dma_valid_without_crypto_rx":
        return "Classifier DMA-valid evidence appeared, but subsystem RX counters remained zero."
    if classification == "classifier_input_fire_without_classifier_dma_valid":
        return "Classifier input fire appeared without classifier DMA-valid evidence."
    if classification == "acl_fire_without_classifier_input_fire":
        return "ACL fire appeared without downstream classifier input fire."
    if classification == "stage1_fire_without_acl_fire":
        return "Stage1 fire appeared without ACL fire."
    if classification == "no_stage1_fire_seen":
        return "No stage1 fire was observed under the current workload."
    return "Stage1A18 did not produce enough aligned ingress-to-PBM evidence for a clean branch."


def injection_source_emission_diagnosis(
    rows: list[dict[str, Any]], args: argparse.Namespace
) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in included_rows:
        groups.setdefault(str(row.get("injection_source_emission_config") or ""), []).append(row)

    reference_rows = groups.get("EmissionReferenceReplay", [])
    extra_rows = groups.get("EmissionReplay_WithExtraSnapshots", [])

    def field_int(row: dict[str, Any], field: str) -> int:
        try:
            return int_value(row.get(field, 0))
        except (TypeError, ValueError):
            return 0

    def any_field(field: str) -> bool:
        return any(field_int(row, field) > 0 for row in included_rows)

    has_required_configs = bool(reference_rows) and bool(extra_rows)
    stage1_fire_seen = any_field("netdbg_stage1_fire_seen")
    stage1_inject_tvalid_seen = any_field("stage1_inject_tvalid")
    stage1_inject_tready_seen = any_field("stage1_inject_tready")
    stage1_valid_not_ready_seen = any(
        field_int(row, "stage1_inject_tvalid") == 1 and field_int(row, "stage1_inject_tready") == 0
        for row in included_rows
    )
    inj_fifo_nonempty_seen = any_field("inj_fifo_nonempty")
    inj_fifo_count_max = max((field_int(row, "inj_fifo_count") for row in included_rows), default=0)
    inj_done_seen = any_field("inj_done")
    inj_overflow_seen = any_field("inj_overflow")
    source_progress_delta_seen = any(
        field_int(row, "source_progress_post") > field_int(row, "source_progress_pre")
        for row in included_rows
    )

    if not included_rows or not has_required_configs:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a19_due_to_inconclusive"
    elif stage1_fire_seen:
        classification = "stage1_fire_reestablished"
        recommended_next_stage = "ACLFilterIngressDiagnosis"
    elif inj_overflow_seen:
        classification = "inj_overflow_without_stage1_fire"
        recommended_next_stage = "InjectionFIFOOverflowDiagnosis"
    elif stage1_valid_not_ready_seen:
        classification = "stage1_valid_not_ready_without_fire"
        recommended_next_stage = "Stage1InjectReadyGatingDiagnosis"
    elif stage1_inject_tvalid_seen:
        classification = "stage1_valid_without_fire"
        recommended_next_stage = "Stage1FireAccountingDiagnosis"
    elif inj_fifo_nonempty_seen or inj_fifo_count_max > 0:
        classification = "inj_fifo_nonempty_without_stage1_valid"
        recommended_next_stage = "InjectionToStage1BindingDiagnosis"
    elif source_progress_delta_seen:
        classification = "source_progress_without_stage1_valid"
        recommended_next_stage = "InjectionToStage1BindingDiagnosis"
    else:
        classification = "no_injection_source_activity_seen"
        recommended_next_stage = "InjectionSourceArmingDiagnosis"

    route_state_names_seen = sorted(
        {
            str(row.get("netdbg_route_state_name"))
            for row in included_rows
            if row.get("netdbg_route_state_name")
        }
    )

    return {
        "raw_sample_count": len(rows),
        "included_sample_count": len(included_rows),
        "emission_reference_replay_rows": len(reference_rows),
        "extra_snapshot_replay_rows": len(extra_rows),
        "extra_snapshots_are_subsnapshots": True,
        "stage1_fire_seen": stage1_fire_seen,
        "stage1_inject_tvalid_seen": stage1_inject_tvalid_seen,
        "stage1_inject_tready_seen": stage1_inject_tready_seen,
        "stage1_valid_not_ready_seen": stage1_valid_not_ready_seen,
        "inj_fifo_nonempty_seen": inj_fifo_nonempty_seen,
        "inj_fifo_count_max": inj_fifo_count_max,
        "inj_done_seen": inj_done_seen,
        "inj_overflow_seen": inj_overflow_seen,
        "source_progress_delta_seen": source_progress_delta_seen,
        "route_state_names_seen": route_state_names_seen,
        "injection_source_emission_classification": classification,
        "injection_source_emission_classification_reason": injection_source_emission_reason(
            classification
        ),
        "recommended_next_stage": recommended_next_stage,
    }


def injection_source_emission_reason(classification: str) -> str:
    if classification == "stage1_fire_reestablished":
        return "Stage1 fire was observed again, so diagnosis can move back to the ACL ingress boundary."
    if classification == "inj_overflow_without_stage1_fire":
        return "Injection overflow was observed before any stage1 fire."
    if classification == "stage1_valid_not_ready_without_fire":
        return "Stage1 inject valid was observed while ready stayed low and no fire was recorded."
    if classification == "stage1_valid_without_fire":
        return "Stage1 inject valid appeared without a matching fire event."
    if classification == "inj_fifo_nonempty_without_stage1_valid":
        return "Injection FIFO retained data, but stage1 inject valid remained zero."
    if classification == "source_progress_without_stage1_valid":
        return "Source progress advanced, but stage1 inject valid remained zero."
    if classification == "no_injection_source_activity_seen":
        return "No injection FIFO activity, source progress, or stage1 emission was observed."
    return "Stage1A19 did not produce enough aligned injection-source evidence for a clean branch."


def injection_source_arming_diagnosis(
    rows: list[dict[str, Any]], args: argparse.Namespace
) -> dict[str, Any]:
    included_rows = [row for row in rows if is_included_in_stats(row)]
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in included_rows:
        groups.setdefault(str(row.get("injection_source_arming_config") or ""), []).append(row)

    arm_only_rows = groups.get("InjectionArmOnly", [])
    readback_rows = groups.get("InjectionArmWithReadback", [])

    def field_int(row: dict[str, Any], field: str) -> int:
        try:
            return int_value(row.get(field, 0))
        except (TypeError, ValueError):
            return 0

    has_required_configs = bool(arm_only_rows) and bool(readback_rows)
    inj_ctrl_write_hit_seen = any(field_int(row, "inj_ctrl_write_hit_count") > 0 for row in included_rows)
    inj_clear_write_hit_seen = any(field_int(row, "inj_clear_write_hit_count") > 0 for row in included_rows)
    inj_frame_word_write_hit_seen = any(field_int(row, "inj_frame_word_write_hit_count") > 0 for row in included_rows)
    inj_expected_words_write_hit_seen = any(
        field_int(row, "inj_expected_words_write_hit_count") > 0 for row in included_rows
    )
    inj_config_valid_seen = any(truthy(row.get("inj_config_valid")) for row in included_rows)
    inj_fifo_write_count = max((field_int(row, "inj_fifo_write_count") for row in included_rows), default=0)
    inj_fifo_level_max = max((field_int(row, "inj_fifo_level_max") for row in included_rows), default=0)
    inj_source_active_cycles = max((field_int(row, "inj_source_active_cycles") for row in included_rows), default=0)
    inj_source_emitting_cycles = max((field_int(row, "inj_source_emitting_cycles") for row in included_rows), default=0)
    stage1_inject_tvalid_cycles = max((field_int(row, "stage1_inject_tvalid_cycles") for row in included_rows), default=0)
    stage1_inject_tready_cycles = max((field_int(row, "stage1_inject_tready_cycles") for row in included_rows), default=0)
    stage1_inject_fire_cycles = max((field_int(row, "stage1_inject_fire_cycles") for row in included_rows), default=0)
    stage1_inject_last_seen_count = max((field_int(row, "stage1_inject_last_seen_count") for row in included_rows), default=0)
    route_state_names_seen = sorted(
        {str(row.get("netdbg_route_state_name")) for row in included_rows if row.get("netdbg_route_state_name")}
    )

    if not included_rows or not has_required_configs:
        classification = "inconclusive"
        recommended_next_stage = "rerun_stage1a20_due_to_inconclusive"
    elif stage1_inject_fire_cycles > 0 or any(field_int(row, "netdbg_stage1_fire_seen") > 0 for row in included_rows):
        classification = "stage1_fire_reestablished"
        recommended_next_stage = "UpstreamIngressToPBMVisibilityDiagnosis"
    elif not (inj_ctrl_write_hit_seen or inj_clear_write_hit_seen or inj_frame_word_write_hit_seen or inj_expected_words_write_hit_seen):
        classification = "probe_write_not_observed_by_injection_csr"
        recommended_next_stage = "InjectionCSRAddressOrDecodeDiagnosis"
    elif not inj_config_valid_seen:
        classification = "invalid_injection_configuration"
        recommended_next_stage = "InjectionFrameConfigDiagnosis"
    elif inj_fifo_write_count == 0 and inj_fifo_level_max == 0:
        classification = "config_valid_but_fifo_not_loaded"
        recommended_next_stage = "InjectionFIFOLoadDiagnosis"
    elif inj_fifo_level_max > 0 and inj_source_active_cycles == 0 and stage1_inject_tvalid_cycles == 0:
        classification = "fifo_loaded_but_source_not_active"
        recommended_next_stage = "InjectionSourceFSMArmingDiagnosis"
    elif inj_source_active_cycles > 0 and stage1_inject_tvalid_cycles == 0:
        classification = "source_active_without_stage1_valid"
        recommended_next_stage = "InjectionEmissionGatingDiagnosis"
    elif stage1_inject_tvalid_cycles > 0 and stage1_inject_tready_cycles > 0 and stage1_inject_fire_cycles == 0:
        classification = "valid_ready_without_fire"
        recommended_next_stage = "StreamHandshakeObservationDiagnosis"
    elif stage1_inject_tvalid_cycles > 0:
        classification = "stage1_valid_without_fire"
        recommended_next_stage = "InjectionEmissionGatingDiagnosis"
    else:
        classification = "no_injection_source_activity_seen"
        recommended_next_stage = "InjectionSourceArmingDiagnosis"

    same_row_fire_seen = sum(
        1
        for row in readback_rows
        if field_int(row, "stage1_inject_fire_cycles") > 0 or field_int(row, "netdbg_stage1_fire_seen") > 0
    )

    return {
        "raw_sample_count": len(rows),
        "included_sample_count": len(included_rows),
        "injection_arm_only_rows": len(arm_only_rows),
        "injection_arm_with_readback_rows": len(readback_rows),
        "inj_ctrl_write_hit_seen": inj_ctrl_write_hit_seen,
        "inj_clear_write_hit_seen": inj_clear_write_hit_seen,
        "inj_frame_word_write_hit_seen": inj_frame_word_write_hit_seen,
        "inj_expected_words_write_hit_seen": inj_expected_words_write_hit_seen,
        "inj_config_valid_seen": inj_config_valid_seen,
        "inj_fifo_write_count": inj_fifo_write_count,
        "inj_fifo_level_max": inj_fifo_level_max,
        "inj_source_active_cycles": inj_source_active_cycles,
        "inj_source_emitting_cycles": inj_source_emitting_cycles,
        "stage1_inject_tvalid_cycles": stage1_inject_tvalid_cycles,
        "stage1_inject_tready_cycles": stage1_inject_tready_cycles,
        "stage1_inject_fire_cycles": stage1_inject_fire_cycles,
        "stage1_inject_last_seen_count": stage1_inject_last_seen_count,
        "route_state_names_seen": route_state_names_seen,
        "explicit_start_and_bridge_nonempty_rows_count": same_row_fire_seen,
        "injection_source_arming_classification": classification,
        "injection_source_arming_classification_reason": injection_source_arming_reason(classification),
        "recommended_next_stage": recommended_next_stage,
    }


def injection_source_arming_reason(classification: str) -> str:
    if classification == "stage1_fire_reestablished":
        return "Stage1 fire reappeared, so the diagnosis can move back to upstream ingress-to-PBM visibility."
    if classification == "probe_write_not_observed_by_injection_csr":
        return "Probe writes did not register at the injection CSR boundary."
    if classification == "invalid_injection_configuration":
        return "Injection control writes appeared, but the frame-length/config readback was invalid."
    if classification == "config_valid_but_fifo_not_loaded":
        return "Injection configuration was valid, but no FIFO load activity was observed."
    if classification == "fifo_loaded_but_source_not_active":
        return "The injection FIFO loaded data, but the source FSM never entered an active/emitting state."
    if classification == "source_active_without_stage1_valid":
        return "The injection source became active, but stage1 inject valid never asserted."
    if classification == "valid_ready_without_fire":
        return "Stage1 valid and ready were both observed, but fire never registered."
    if classification == "stage1_valid_without_fire":
        return "Stage1 inject valid appeared without a matching fire event."
    if classification == "no_injection_source_activity_seen":
        return "No injection CSR hit, FIFO load, source activity, or stage1 emission was observed."
    return "Stage1A20 did not produce enough aligned injection-source arming evidence for a clean branch."


def trigger_intervals(rows: list[dict[str, Any]]) -> list[float]:
    trigger_indices = [
        index
        for index, row in enumerate(rows)
        if any_nonzero(row, ROLLBACK_RECOVERY_COUNTERS)
    ]
    return [float(b - a) for a, b in zip(trigger_indices, trigger_indices[1:])]


def stage0_gate_status(rows: list[dict[str, Any]]) -> tuple[str, dict[str, int]]:
    pass_counts = {
        "Case0_OriginalWrongPort": 0,
        "Case1_HeaderAccepted": 0,
        "Case2_RuntimeRingBypass": 0,
    }
    for row in rows:
        case_name = str(row.get("case", ""))
        if row.get("stage_status") == "pass" and case_name in pass_counts:
            pass_counts[case_name] += 1

    if (
        pass_counts["Case0_OriginalWrongPort"] >= SANITY_CASE0_MIN_PASS
        and pass_counts["Case1_HeaderAccepted"] >= SANITY_CASE1_MIN_PASS
        and pass_counts["Case2_RuntimeRingBypass"] >= SANITY_CASE2_MIN_PASS
    ):
        return "pass", pass_counts
    if any(count > 0 for count in pass_counts.values()):
        return "partial", pass_counts
    return "fail", pass_counts


def build_probe_window_index_map(summary: dict[str, Any], rows: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    cases_by_name = {case.get("name"): case for case in summary.get("cases", [])}
    window_map: dict[str, dict[str, Any]] = {}
    for row in rows:
        case_name = row.get("case")
        case_instance = row.get("case_instance") or case_name
        case = cases_by_name.get(case_instance, {})
        probe_window_id = str(row.get("probe_window_id"))
        window_map[probe_window_id] = {
            "case": case_name,
            "case_instance": case_instance,
            "repeat": row.get("repeat"),
            "stage": row.get("stage"),
            "burst_frames": row.get("BurstFrames"),
            "burst_gap_us": row.get("BurstGapUs"),
            "settle_ms": row.get("SettleMs"),
            "reproduction_config": row.get("reproduction_config"),
            "reproduction_mode": row.get("reproduction_mode"),
            "condition_diff_config": row.get("condition_diff_config"),
            "pbm_visibility_config": row.get("pbm_visibility_config"),
            "crypto_dma_handoff_config": row.get("crypto_dma_handoff_config"),
            "pbm_read_side_config": row.get("pbm_read_side_config"),
            "bridge_output_fifo_config": row.get("bridge_output_fifo_config"),
            "dma_start_path_config": row.get("dma_start_path_config"),
            "explicit_start_bridge_handoff_config": row.get("explicit_start_bridge_handoff_config"),
            "bridge_data_production_config": row.get("bridge_data_production_config"),
            "pbm_commit_reproduction_config": row.get("pbm_commit_reproduction_config"),
            "dma_rd_en_equation_config": row.get("dma_rd_en_equation_config"),
            "upstream_ingress_to_pbm_visibility_config": row.get(
                "upstream_ingress_to_pbm_visibility_config"
            ),
            "injection_source_emission_config": row.get("injection_source_emission_config"),
            "pbm_commit_tail_invariant_config": row.get("pbm_commit_tail_invariant_config"),
            "xsct_log": summary.get("xsct_log"),
            "uart_log": summary.get("uart_log"),
            "xsct_script": summary.get("xsct_script"),
            "pre_snapshot_label": f"{case_instance}.pre",
            "post_snapshot_label": f"{case_instance}.post",
            "delta_label": f"{case_instance}.delta",
            "extra_snapshot_labels": (
                [
                    f"{case_instance}.post_workload_immediate",
                    f"{case_instance}.mid_050ms",
                    f"{case_instance}.mid_250ms",
                ]
                if row.get("stage1a19_snapshot_mode") == "extra_snapshots"
                and row.get("stage1a19_extra_snapshots_present", True)
                else [
                    f"{case_instance}.post_workload_immediate",
                    f"{case_instance}.mid_050ms",
                    f"{case_instance}.mid_250ms",
                ]
                if row.get("stage1a23_snapshot_mode") == "extra_snapshots"
                and row.get("stage1a23_extra_snapshots_present", True)
                else [
                    f"{case_instance}.post_workload_immediate",
                    f"{case_instance}.mid_050ms",
                    f"{case_instance}.mid_250ms",
                ]
                if row.get("stage1a17_snapshot_mode") == "extra_snapshots"
                and row.get("stage1a17_extra_snapshots_present", True)
                else [
                    f"{case_instance}.post_workload_immediate",
                    f"{case_instance}.mid_050ms",
                    f"{case_instance}.mid_250ms",
                ]
                if row.get("stage1a18_snapshot_mode") == "extra_snapshots"
                and row.get("stage1a18_extra_snapshots_present", True)
                else [
                    f"{case_instance}.post_injection_immediate",
                    f"{case_instance}.mid_050ms",
                    f"{case_instance}.mid_250ms",
                ]
                if row.get("stage1a21_snapshot_mode") == "extra_snapshots"
                and row.get("stage1a21_extra_snapshots_present", True)
                else [
                    f"{case_instance}.post_injection_immediate",
                    f"{case_instance}.mid_050ms",
                    f"{case_instance}.mid_250ms",
                ]
                if row.get("condition_diff_config") == "BF64_SM500_ExtraSnapshots"
                or row.get("stage1a8_snapshot_mode") == "extra_snapshots"
                or row.get("stage1a9_snapshot_mode") == "extra_snapshots"
                or row.get("stage1a10_snapshot_mode") == "extra_snapshots"
                or row.get("stage1a11_snapshot_mode") == "extra_snapshots"
                or row.get("stage1a12_snapshot_mode") == "extra_snapshots"
                else []
            ),
            "raw_log_lookup": "Use labels above in raw XSCT/UART logs when explicit probe-window tags are not emitted.",
            "inj_status_active": case.get("inj_status_active"),
        }
    return window_map


def build_manifest(summary: dict[str, Any], args: argparse.Namespace, repo_root: Path, rows: list[dict[str, Any]]) -> dict[str, Any]:
    commit = script_commit_hash(repo_root)
    boot_bin = Path(args.boot_bin) if args.boot_bin else None
    bit_file = Path(args.bit_file) if args.bit_file else None
    xsa_file = Path(args.xsa_file) if args.xsa_file else None
    sequence = build_fault_sequence(
        repeat_count=max(1, int(args.repeat_count)),
        fault_ratio=float(args.fault_ratio),
        fault_mode=args.fault_mode,
        noise_pattern=args.noise_pattern,
        seed=int(args.fault_schedule_seed),
    )
    return {
        "manifest_schema_version": MANIFEST_SCHEMA_VERSION,
        "stats_schema_version": STATS_SCHEMA_VERSION,
        "plot_schema_version": PLOT_SCHEMA_VERSION,
        "metrics_semantics_version": METRICS_SEMANTICS_VERSION,
        "experiment_plan_version": args.experiment_plan_version,
        "invocation_digest": invocation_digest(args, sys.argv),
        **commit,
        "start_timestamp": summary.get("timestamp"),
        "end_timestamp": dt.datetime.now(tz=dt.timezone.utc).isoformat(),
        "tool_versions": {
            "python": sys.version.split()[0],
            "platform": platform.platform(),
            "xsct_path": args.xsct_path,
            "vivado_version": args.vivado_version,
            "vitis_version": args.vitis_version,
        },
        "host_snapshot": host_snapshot(),
        "boot_bin": file_record(boot_bin, repo_root) if boot_bin else None,
        "bit_file": file_record(bit_file, repo_root) if bit_file else None,
        "xsa_file": file_record(xsa_file, repo_root) if xsa_file else None,
        "board": {
            "boot_mode": args.boot_mode,
            "boot_source": args.boot_source,
            "active_pl_programming": args.active_pl_programming,
            "active_ps_programming": args.active_ps_programming,
            "active_bit_path": args.active_bit_path or args.bit_file,
            "active_bit_sha256": sha256_file(Path(args.active_bit_path or args.bit_file))
            if (args.active_bit_path or args.bit_file)
            else None,
            "active_xsa_path": args.active_xsa_path or args.xsa_file,
            "active_xsa_sha256": sha256_file(Path(args.active_xsa_path or args.xsa_file))
            if (args.active_xsa_path or args.xsa_file)
            else None,
            "uart_port": args.port,
            "uart_baud": args.baud,
            "jtag_policy": "accept CSR fallback when targets text is empty",
        },
        "case_parameters": vars(args),
        "csr_baseline": summary.get("baseline"),
        "raw_logs": {
            "xsct_log": summary.get("xsct_log"),
            "xsct_script": summary.get("xsct_script"),
            "uart_log": summary.get("uart_log"),
        },
        "reference_runs": {
            "stage1a_full_dir": args.stage1a6_reference_stage1a_full_dir,
            "stage1a5_audit_dir": args.stage1a6_reference_stage1a5_audit_dir,
            "reproduction_mode": args.reproduction_mode,
        },
        "probe_window_index_map": build_probe_window_index_map(summary, rows),
        "randomness": {
            "random_seed": args.random_seed,
            "fault_schedule_seed": args.fault_schedule_seed,
            "traffic_generator_version": TRAFFIC_GENERATOR_VERSION,
            "fault_sequence_digest": digest_fault_sequence(sequence),
        },
        "schema_migration_policy": {
            "do_not_overwrite_old_schema": True,
            "field_additions_are_append_only": True,
            "semantic_change_requires_version_bump": True,
        },
    }


def host_snapshot() -> dict[str, Any]:
    return {
        "machine": platform.machine(),
        "processor": platform.processor(),
        "python_executable": sys.executable,
        "cpu_count": os.cpu_count(),
    }


def build_stage_report(rows: list[dict[str, Any]], stats: dict[str, Any], args: argparse.Namespace) -> str:
    rollback_recovery_seen = any_nonzero_rows(rows, ROLLBACK_RECOVERY_COUNTERS)
    frontend_pressure_seen = any_nonzero_rows(rows, FRONTEND_PRESSURE_COUNTERS)
    backend_seen = any_nonzero_rows(rows, BACKEND_SERVICE_COUNTERS)
    stage1a_decision = stats.get("stage1a_decision") if args.stage == "Stage1A_BurstSweep" else None
    audit_decision = stats.get("drop_pulse_audit") if args.stage == "Stage1A_DropPulseAudit" else None
    reproduction_decision = (
        stats.get("prior_drop_pulse_reproduction") if args.stage == "Stage1A6_PriorDropPulseReproduction" else None
    )
    stage1a7_decision = (
        stats.get("stage1a7_condition_diff") if args.stage == "Stage1A7_DropPulseConditionDiffDiagnosis" else None
    )
    stage1a8_decision = (
        stats.get("stage1a8_pbm_ingress_visibility") if args.stage == "Stage1A8_PBMIngressVisibilityDiagnosis" else None
    )
    stage1a9_decision = (
        stats.get("stage1a9_crypto_ingress_handoff_visibility")
        if args.stage == "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis"
        else None
    )
    stage1a10_decision = (
        stats.get("crypto_dma_handoff_diagnosis")
        if args.stage == "Stage1A10_CryptoDMAHandoffDiagnosis"
        else None
    )
    stage1a11_decision = (
        stats.get("stage1a11_pbm_read_side_visibility")
        if args.stage == "Stage1A11_PBMReadSideVisibilityDiagnosis"
        else None
    )
    stage1a12_decision = (
        stats.get("stage1a12_bridge_output_fifo_visibility")
        if args.stage == "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis"
        else None
    )
    stage1a13_decision = (
        stats.get("stage1a13_dma_start_path_diagnosis")
        if args.stage == "Stage1A13_DMAStartPathDiagnosis"
        else None
    )
    stage1a14_decision = (
        stats.get("start_pulse_injection_diagnosis")
        if args.stage == "Stage1A14_StartPulseInjectionOrProbeControlFix"
        else None
    )
    stage1a15_decision = (
        stats.get("explicit_start_bridge_handoff_diagnosis")
        if args.stage == "Stage1A15_ExplicitStartBridgeHandoffDiagnosis"
        else None
    )
    stage1a16_decision = (
        stats.get("bridge_data_production_diagnosis")
        if args.stage == "Stage1A16_BridgeDataProductionDiagnosis"
        else None
    )
    stage1a17_decision = (
        stats.get("pbm_commit_reproduction_diagnosis")
        if args.stage == "Stage1A17_PBMCommitReproductionDiagnosis"
        else None
    )
    stage1a26_decision = (
        stats.get("dma_rd_en_equation_diagnosis")
        if args.stage == "Stage1A26_DMARdEnableEquationDiagnosis"
        else None
    )
    stage1a27_decision = (
        stats.get("crypto_dma_ingress_backpressure_diagnosis")
        if args.stage == "Stage1A27_CryptoDMAIngressBackpressureDiagnosis"
        else None
    )
    stage1a18_decision = (
        stats.get("upstream_ingress_to_pbm_visibility_diagnosis")
        if args.stage == "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis"
        else None
    )
    stage1a19_decision = (
        stats.get("injection_source_emission_diagnosis")
        if args.stage == "Stage1A19_InjectionSourceEmissionDiagnosis"
        else None
    )
    stage1a20_decision = (
        stats.get("injection_source_arming_diagnosis")
        if args.stage == "Stage1A20_InjectionSourceArmingDiagnosis"
        else None
    )
    stage1a21_decision = (
        stats.get("stage1a21_pbm_ready_gating_diagnosis")
        if args.stage == "Stage1A21_PBMReadyGatingDiagnosis"
        else None
    )
    stage1a22_decision = (
        stats.get("stage1a22_pbm_pointer_reset_or_drain_diagnosis")
        if args.stage == "Stage1A22_PBMPointerResetOrDrainDiagnosis"
        else None
    )
    stage1a23_decision = (
        stats.get("stage1a23_pbm_commit_tail_pointer_invariant_diagnosis")
        if args.stage == "Stage1A23_PBMCommitTailPointerInvariantDiagnosis"
        else None
    )
    stage1a24_decision = (
        stats.get("stage1a24_pbm_reset_domain_scope_diagnosis")
        if args.stage == "Stage1A24_PBMResetDomainScopeDiagnosis"
        else None
    )
    stage1a25_decision = (
        stats.get("stage1a25_pbm_reset_domain_remediation_plan")
        if args.stage == "Stage1A25_PBMResetDomainRemediationPlan"
        else None
    )
    stage1a7_drop_nonzero_rate = safe_ratio(
        sum(1 for row in rows if int_value(row.get("drop_pulse_count", 0)) > 0),
        max(1, len(rows)),
    )

    if args.stage == "Stage0_Sanity":
        status, sanity_pass_counts = stage0_gate_status(rows)
    elif args.stage == "Stage1A_BurstSweep":
        sanity_pass_counts = {}
        if args.stage1a_run_kind == "dry_run":
            status = "pass" if stage1a_decision and stage1a_decision.get("recommended_next_stage") == "Stage1A_FullRun" else "fail"
        else:
            recommended = stage1a_decision.get("recommended_next_stage") if stage1a_decision else None
            if recommended == "Stage2_ExtremeTraffic":
                status = "pass"
            elif recommended == "PBMIngressOrCryptoDMADiagnosis":
                status = "partial"
            else:
                status = "fail"
    elif args.stage == "Stage1A_DropPulseAudit":
        sanity_pass_counts = {}
        status = "fail" if audit_decision and audit_decision.get("drop_pulse_semantics_classification") == "inconclusive" else "partial"
    elif args.stage == "Stage1A6_PriorDropPulseReproduction":
        sanity_pass_counts = {}
        if reproduction_decision and reproduction_decision.get("drop_pulse_reproduction_classification") in {
            "sampling_or_clear_artifact",
            "inconclusive",
        }:
            status = "fail"
        else:
            status = "partial"
    elif args.stage == "Stage1A7_DropPulseConditionDiffDiagnosis":
        sanity_pass_counts = {}
        if stage1a7_decision and stage1a7_decision.get("recommended_next_stage") == "PBMIngressVisibilityDiagnosis":
            status = "partial"
        elif stage1a7_decision and stage1a7_decision.get("recommended_next_stage") == "DropRollbackCouplingDiagnosis":
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A8_PBMIngressVisibilityDiagnosis":
        sanity_pass_counts = {}
        if stage1a8_decision and stage1a8_decision.get("recommended_next_stage") in {
            "PBMReadyGatingDiagnosis",
            "PacketTerminationVisibilityDiagnosis",
            "CryptoDMAHandoffDiagnosis",
            "DropRollbackCouplingDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis":
        sanity_pass_counts = {}
        if stage1a9_decision and stage1a9_decision.get("recommended_next_stage") in {
            "CryptoIngressToPBMBindingDiagnosis",
            "WrapperClassifierDMABoundaryDiagnosis",
            "PBMIngressVisibilityDiagnosis",
            "CryptoDMAHandoffDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A10_CryptoDMAHandoffDiagnosis":
        sanity_pass_counts = {}
        if stage1a10_decision and stage1a10_decision.get("recommended_next_stage") in {
            "PBMReadSideVisibilityDiagnosis",
            "CryptoDMAIngressBackpressureDiagnosis",
            "BackendInputGatingDiagnosis",
            "CompletionWritebackDiagnosis",
            "DropRollbackCouplingDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A11_PBMReadSideVisibilityDiagnosis":
        sanity_pass_counts = {}
        if stage1a11_decision and stage1a11_decision.get("recommended_next_stage") in {
            "CryptoBridgeAvailabilityDiagnosis",
            "DMATransferStartDiagnosis",
            "DMAWriteChannelBackpressureDiagnosis",
            "BackendInputGatingDiagnosis",
            "DropRollbackCouplingDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis":
        sanity_pass_counts = {}
        if stage1a12_decision and stage1a12_decision.get("recommended_next_stage") in {
            "BridgeOutputFIFOResidualDiagnosis",
            "DMAStartPathDiagnosis",
            "DMARdEnableGatingDiagnosis",
            "CryptoDMAIngressBackpressureDiagnosis",
            "BackendInputGatingDiagnosis",
            "DropRollbackCouplingDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A13_DMAStartPathDiagnosis":
        sanity_pass_counts = {}
        if stage1a13_decision and stage1a13_decision.get("recommended_next_stage") in {
            "StartPulseInjectionOrProbeControlFix",
            "FinalStartSelectionLogicDiagnosis",
            "SourceReaderStartLatchDiagnosis",
            "DMARdEnableGatingDiagnosis",
            "BridgeAcceptPathDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A14_StartPulseInjectionOrProbeControlFix":
        sanity_pass_counts = {}
        if stage1a14_decision and stage1a14_decision.get("recommended_next_stage") in {
            "AXILCSRAddressOrRoutingDiagnosis",
            "StartWriteValueOrWSTRBDiagnosis",
            "StartPulseGenerationConditionDiagnosis",
            "FinalStartSelectionLogicDiagnosis",
            "SourceReaderStartLatchDiagnosis",
            "DMARdEnableGatingDiagnosis",
            "BridgeAcceptPathDiagnosis",
            "BridgeOrCryptoAcceptFollowup",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A15_ExplicitStartBridgeHandoffDiagnosis":
        sanity_pass_counts = {}
        if stage1a15_decision and stage1a15_decision.get("recommended_next_stage") in {
            "StartPulseInjectionOrProbeControlFix",
            "BridgeDataProductionDiagnosis",
            "DMARdEnableGatingDiagnosis",
            "BridgeAcceptPathDiagnosis",
            "CryptoDMAIngressAcceptDiagnosis",
            "BackendInputGatingDiagnosis",
            "DropRollbackCouplingDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A16_BridgeDataProductionDiagnosis":
        sanity_pass_counts = {}
        if stage1a16_decision and stage1a16_decision.get("recommended_next_stage") in {
            "PBMCommitReproductionDiagnosis",
            "BridgeDataProductionReproductionCheck",
            "CSRControlSideEffectDiagnosis",
            "BridgeDataProductionUnderExplicitStartDiagnosis",
            "PBMReadSideToBridgeEnqueueDiagnosis",
            "BridgeFIFOLevelVisibilityDiagnosis",
            "DMARdEnableGatingDiagnosis",
            "BridgeAcceptPathDiagnosis",
            "CryptoDMAIngressAcceptDiagnosis",
            "BackendInputGatingDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A17_PBMCommitReproductionDiagnosis":
        sanity_pass_counts = {}
        if stage1a17_decision and stage1a17_decision.get("recommended_next_stage") in {
            "DropRollbackCouplingDiagnosis",
            "BridgeDataProductionDiagnosis",
            "PBMCommitPointerVisibilityDiagnosis",
            "PBMCommitTransitionDiagnosis",
            "PacketTerminationVisibilityDiagnosis",
            "PBMReadyGatingDiagnosis",
            "UpstreamIngressToPBMVisibilityDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A26_DMARdEnableEquationDiagnosis":
        sanity_pass_counts = {}
        if stage1a26_decision and stage1a26_decision.get("recommended_next_stage") in {
            "DMALoopbackModeControlDiagnosis",
            "TXAxisReadyGatingDiagnosis",
            "TXReadyWhileBridgeNonemptyDiagnosis",
            "DMANormalBranchRdRequestDiagnosis",
            "DMARdEnableEquationInstrumentationBug",
            "BridgeAcceptPathDiagnosis",
            "Stage1A10_CryptoDMAHandoffDiagnosis",
            "rerun_stage1a26_due_to_inconclusive",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A27_CryptoDMAIngressBackpressureDiagnosis":
        sanity_pass_counts = {}
        if stage1a27_decision and stage1a27_decision.get("recommended_next_stage") in {
            "BridgeToCryptoDMAValidVisibilityDiagnosis",
            "CryptoDMAIngressReadyGatingDiagnosis",
            "CryptoDMAIngressHandshakeInstrumentationDiagnosis",
            "CounterAlignmentOrInstrumentationDiagnosis",
            "BackendInputGatingDiagnosis",
            "Stage1A_EngineeringDataAcquisition",
            "rerun_stage1a27_due_to_inconclusive",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis":
        sanity_pass_counts = {}
        if stage1a18_decision and stage1a18_decision.get("recommended_next_stage") in {
            "PBMCommitReproductionDiagnosis",
            "PBMInputBindingDiagnosis",
            "ClassifierToSubsystemVisibilityDiagnosis",
            "ClassifierPayloadAdmissionDiagnosis",
            "ACLToClassifierHandoffDiagnosis",
            "ACLFilterIngressDiagnosis",
            "InjectionSourceEmissionDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A19_InjectionSourceEmissionDiagnosis":
        sanity_pass_counts = {}
        if stage1a19_decision and stage1a19_decision.get("recommended_next_stage") in {
            "ACLFilterIngressDiagnosis",
            "InjectionFIFOOverflowDiagnosis",
            "Stage1InjectReadyGatingDiagnosis",
            "Stage1FireAccountingDiagnosis",
            "InjectionToStage1BindingDiagnosis",
            "InjectionSourceArmingDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A20_InjectionSourceArmingDiagnosis":
        sanity_pass_counts = {}
        if stage1a20_decision and stage1a20_decision.get("recommended_next_stage") in {
            "UpstreamIngressToPBMVisibilityDiagnosis",
            "InjectionCSRAddressOrDecodeDiagnosis",
            "InjectionFrameConfigDiagnosis",
            "InjectionFIFOLoadDiagnosis",
            "InjectionSourceFSMArmingDiagnosis",
            "InjectionEmissionGatingDiagnosis",
            "StreamHandshakeObservationDiagnosis",
            "InjectionSourceArmingDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A21_PBMReadyGatingDiagnosis":
        sanity_pass_counts = {}
        if stage1a21_decision and stage1a21_decision.get("recommended_next_stage") in {
            "PBMPointerResetOrDrainDiagnosis",
            "PBMFullConditionDiagnosis",
            "PBMStateGatingDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A22_PBMPointerResetOrDrainDiagnosis":
        sanity_pass_counts = {}
        if stage1a22_decision and stage1a22_decision.get("recommended_next_stage") in {
            "PBMResetOrRestorePathDiagnosis",
            "PBMReadSideDrainDiagnosis",
            "PBMCommitTailPointerInvariantDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A23_PBMCommitTailPointerInvariantDiagnosis":
        sanity_pass_counts = {}
        if stage1a23_decision and stage1a23_decision.get("recommended_next_stage") in {
            "PBMResetDomainScopeDiagnosis",
            "PBMStatePointerConsistencyDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A24_PBMResetDomainScopeDiagnosis":
        sanity_pass_counts = {}
        if stage1a24_decision and stage1a24_decision.get("recommended_next_stage") in {
            "PBMResetDomainRemediationPlan",
            "PBMSoftResetImplementationDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    elif args.stage == "Stage1A25_PBMResetDomainRemediationPlan":
        sanity_pass_counts = {}
        if stage1a25_decision and stage1a25_decision.get("recommended_next_stage") in {
            "PBMSoftResetDiagnosticBuild",
            "PBMSoftResetImplementationDiagnosis",
        }:
            status = "partial"
        else:
            status = "fail"
    else:
        sanity_pass_counts = {}
        status = "partial" if backend_seen else "fail"

    negative_type = "none" if rollback_recovery_seen else ("negative_backend_activity_only" if backend_seen else "negative_no_backend_activity")
    if args.stage in {"Stage1A_DropPulseAudit", "Stage1A6_PriorDropPulseReproduction", "Stage1A7_DropPulseConditionDiffDiagnosis", "Stage1A8_PBMIngressVisibilityDiagnosis", "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis", "Stage1A10_CryptoDMAHandoffDiagnosis", "Stage1A11_PBMReadSideVisibilityDiagnosis", "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis", "Stage1A13_DMAStartPathDiagnosis", "Stage1A14_StartPulseInjectionOrProbeControlFix", "Stage1A15_ExplicitStartBridgeHandoffDiagnosis", "Stage1A16_BridgeDataProductionDiagnosis", "Stage1A17_PBMCommitReproductionDiagnosis", "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis", "Stage1A19_InjectionSourceEmissionDiagnosis", "Stage1A20_InjectionSourceArmingDiagnosis", "Stage1A21_PBMReadyGatingDiagnosis", "Stage1A22_PBMPointerResetOrDrainDiagnosis", "Stage1A23_PBMCommitTailPointerInvariantDiagnosis", "Stage1A24_PBMResetDomainScopeDiagnosis", "Stage1A25_PBMResetDomainRemediationPlan", "Stage1A26_DMARdEnableEquationDiagnosis", "Stage1A27_CryptoDMAIngressBackpressureDiagnosis"}:
        negative_type = "negative_diagnostic_only"

    if args.stage in {
        "Stage1A_BurstSweep",
        "Stage1A_DropPulseAudit",
        "Stage1A6_PriorDropPulseReproduction",
        "Stage1A7_DropPulseConditionDiffDiagnosis",
        "Stage1A8_PBMIngressVisibilityDiagnosis",
        "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis",
        "Stage1A10_CryptoDMAHandoffDiagnosis",
        "Stage1A11_PBMReadSideVisibilityDiagnosis",
        "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis",
        "Stage1A13_DMAStartPathDiagnosis",
        "Stage1A14_StartPulseInjectionOrProbeControlFix",
        "Stage1A15_ExplicitStartBridgeHandoffDiagnosis",
        "Stage1A16_BridgeDataProductionDiagnosis",
        "Stage1A17_PBMCommitReproductionDiagnosis",
        "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis",
        "Stage1A19_InjectionSourceEmissionDiagnosis",
        "Stage1A20_InjectionSourceArmingDiagnosis",
        "Stage1A21_PBMReadyGatingDiagnosis",
        "Stage1A22_PBMPointerResetOrDrainDiagnosis",
        "Stage1A23_PBMCommitTailPointerInvariantDiagnosis",
        "Stage1A24_PBMResetDomainScopeDiagnosis",
        "Stage1A25_PBMResetDomainRemediationPlan",
    }:
        candidate = "no"
        evidence_risk = "high"
        reason = f"{args.stage} is engineering evidence only and does not satisfy the paper-ready recovery gate"
        allowed_use_in_paper = "engineering evidence only"
    else:
        candidate = "yes" if rollback_recovery_seen and stats["paper_ready_recovery_gate"]["met"] else "no"
        evidence_risk = "medium" if rollback_recovery_seen else "high"
        reason = (
            "meets recovery trigger and repeat gate"
            if candidate == "yes"
            else "does not meet the paper-ready recovery gate"
        )
        allowed_use_in_paper = "candidate figure" if candidate == "yes" else "engineering evidence only"

    stage1a_lines: list[str] = []
    if stage1a_decision:
        backend_total_stats = summarize_values([float(row.get("backend_total_cycles", 0) or 0) for row in rows])
        stage1a_lines = [
            "",
            "## Stage 1A Burst Sweep Decision",
            f"- stage1a_run_kind: {stage1a_decision.get('stage1a_run_kind')}",
            f"- stage1a_baseline_source: {stage1a_decision.get('stage1a_baseline_source')}",
            f"- backend_activity_monotonic: {stage1a_decision.get('backend_activity_monotonic')}",
            f"- dominant_backend_mode: {stage1a_decision.get('dominant_backend_mode')}",
            f"- effective_work_ratio_trend: {stage1a_decision.get('effective_work_ratio_trend')}",
            f"- recovery_counters_still_zero: {str(stage1a_decision.get('recovery_counters_still_zero')).lower()}",
            f"- recommended_next_stage: {stage1a_decision.get('recommended_next_stage')}",
            f"- backend_total_cycles_order_of_magnitude: max={backend_total_stats.get('max')}, p50={backend_total_stats.get('p50')}",
            "- note: backend accept/starvation ratios can remain tiny when backend_total_cycles is large; nonzero cycle counts are reported separately.",
        ]

    audit_lines: list[str] = []
    if audit_decision:
        audit_lines = [
            "",
            "## Stage 1A.5 Drop-Pulse Semantics Audit",
            f"- drop_pulse_idle_nonzero: {str(audit_decision.get('drop_pulse_idle_nonzero')).lower()}",
            f"- drop_pulse_idle_nonzero_reason: {audit_decision.get('drop_pulse_idle_nonzero_reason')}",
            f"- drop_pulse_settle_linear_like: {str(audit_decision.get('drop_pulse_settle_linear_like')).lower()}",
            f"- drop_pulse_settle_rate_per_ms: {json.dumps(audit_decision.get('drop_pulse_settle_rate_per_ms'), sort_keys=True)}",
            f"- drop_pulse_burst_scaled: {str(audit_decision.get('drop_pulse_burst_scaled')).lower()}",
            f"- drop_pulse_backend_activity_coupled: {str(audit_decision.get('drop_pulse_backend_activity_coupled')).lower()}",
            f"- drop_pulse_nonzero_rate: {audit_decision.get('drop_pulse_nonzero_rate')}",
            f"- drop_pulse_semantics_classification: {audit_decision.get('drop_pulse_semantics_classification')}",
            f"- recommended_next_stage: {audit_decision.get('recommended_next_stage')}",
            (
                "Interpretation: drop_pulse_count is interpreted as "
                f"{audit_decision.get('drop_pulse_semantics_classification')}. "
                "It is not suitable as packet-level drop or recovery evidence until this classification is resolved."
            ),
        ]

    reproduction_lines: list[str] = []
    if reproduction_decision:
        artifact_match = reproduction_decision.get("artifact_hash_match", {})
        ratios = reproduction_decision.get("old_vs_replay_drop_ratio_by_config", {})
        reproduction_lines = [
            "",
            "## Stage 1A.6 Prior-DropPulse Reproduction Check",
            f"- reproduction_mode: {reproduction_decision.get('reproduction_mode')}",
            f"- reference_stage1a_full_dir: {reproduction_decision.get('reference_stage1a_full_dir')}",
            f"- reference_stage1a5_audit_dir: {reproduction_decision.get('reference_stage1a5_audit_dir')}",
            "- Controlled replay invariants",
            f"- artifact_hash_match.boot_bin: {str(artifact_match.get('boot_bin')).lower()}",
            f"- artifact_hash_match.bit: {str(artifact_match.get('bit')).lower()}",
            f"- artifact_hash_match.xsa: {str(artifact_match.get('xsa')).lower()}",
            f"- artifact_hash_match.csr_map: {artifact_match.get('csr_map')}",
            "- Allowed changes",
            "- stage path",
            "- controlled clear/snapshot sequence",
            "- report wording",
            "- paper_plot_data gate",
            f"- pre_after_clear_nonzero_count: {reproduction_decision.get('pre_after_clear_nonzero_count')}",
            f"- drop_pulse_nonzero_rate: {reproduction_decision.get('drop_pulse_nonzero_rate')}",
            f"- backend_activity_seen: {str(reproduction_decision.get('backend_activity_seen')).lower()}",
            f"- reproduced_prior_drop_pulse: {str(reproduction_decision.get('reproduced_prior_drop_pulse')).lower()}",
            f"- drop_pulse_reproduction_classification: {reproduction_decision.get('drop_pulse_reproduction_classification')}",
            f"- old_vs_replay_drop_ratio_by_config: {json.dumps(ratios, sort_keys=True)}",
            f"- recommended_next_stage: {reproduction_decision.get('recommended_next_stage')}",
            (
                "The prior nonzero drop_pulse_count observation is evaluated only as an engineering diagnostic. "
                "It is not used as paper-ready recovery/drop evidence."
            ),
        ]
        if reproduction_decision.get("drop_pulse_reproduction_classification") == "not_reproduced_under_controlled_sampling":
            reproduction_lines.append(
                "The prior nonzero drop_pulse_count was not reproduced under controlled sampling replay. "
                "The drop-pulse line is suspended as a recovery-evidence path, and the next diagnostic focus shifts to "
                "PBM ingress / crypto DMA ingress visibility."
            )
    stage1a7_lines: list[str] = []
    if stage1a7_decision:
        stage1a7_lines = [
            "",
            "## Stage 1A.7 DropPulse Condition-Diff Diagnosis",
            f"- planned_negative_control: {stage1a7_decision.get('planned_negative_control')}",
            f"- planned_positive_condition: {stage1a7_decision.get('planned_positive_condition')}",
            f"- negative_control_valid: {str(stage1a7_decision.get('negative_control_valid')).lower()}",
            f"- negative_control_violation_reason: {stage1a7_decision.get('negative_control_violation_reason')}",
            f"- bf8_observed_stall: {str(stage1a7_decision.get('bf8_observed_stall')).lower()}",
            f"- bf64_observed_stall: {str(stage1a7_decision.get('bf64_observed_stall')).lower()}",
            f"- condition_diff_status: {stage1a7_decision.get('condition_diff_status')}",
            f"- frontend_pressure_seen: {str(stage1a7_decision.get('frontend_pressure_seen')).lower()}",
            f"- rollback_recovery_seen: {str(stage1a7_decision.get('rollback_recovery_seen')).lower()}",
            f"- backend_activity_seen: {str(stage1a7_decision.get('backend_activity_seen')).lower()}",
            f"- frontend_valid_not_ready_stall_strong: {str(stage1a7_decision.get('frontend_valid_not_ready_stall_strong')).lower()}",
            f"- frontend_valid_not_ready_stall_partial: {str(stage1a7_decision.get('frontend_valid_not_ready_stall_partial')).lower()}",
            f"- ingress_progress_stalled: {str(stage1a7_decision.get('ingress_progress_stalled')).lower()}",
            f"- drop_pulse_window_scaled: {str(stage1a7_decision.get('drop_pulse_window_scaled')).lower()}",
            f"- drop_pulse_window_short_no_trigger: {str(stage1a7_decision.get('drop_pulse_window_short_no_trigger')).lower()}",
            f"- drop_pulse_rate_per_ms: {json.dumps(stage1a7_decision.get('drop_pulse_rate_per_ms'), sort_keys=True)}",
            f"- drop_pulse_rate_per_backend_cycle: {json.dumps(stage1a7_decision.get('drop_pulse_rate_per_backend_cycle'), sort_keys=True)}",
            f"- bf8_negative_control_netdbg: {json.dumps(stage1a7_decision.get('bf8_negative_control_netdbg'), sort_keys=True)}",
            f"- bf64_positive_condition_netdbg: {json.dumps(stage1a7_decision.get('bf64_positive_condition_netdbg'), sort_keys=True)}",
            f"- extra_snapshot_deltas: {json.dumps(stage1a7_decision.get('extra_snapshot_deltas'), sort_keys=True)}",
            f"- recommended_next_stage: {stage1a7_decision.get('recommended_next_stage')}",
        ]
    stage1a8_lines: list[str] = []
    if stage1a8_decision:
        stage1a8_lines = [
            "",
            "## Stage 1A.8 PBM Ingress Visibility Diagnosis",
            f"- diagnostic_csr_map_version: {stage1a8_decision.get('diagnostic_csr_map_version')}",
            f"- diagnostic_csr_address_range: {stage1a8_decision.get('diagnostic_csr_address_range')}",
            f"- pbm_diag_csr_collision: {str(stage1a8_decision.get('pbm_diag_csr_collision')).lower()}",
            f"- idle_control_quiesce_guard_ms: {stage1a8_decision.get('idle_control_quiesce_guard_ms')}",
            f"- idle_pre_after_clear_zero: {str(stage1a8_decision.get('idle_pre_after_clear_zero')).lower()}",
            f"- idle_residual_activity_seen: {str(stage1a8_decision.get('idle_residual_activity_seen')).lower()}",
            f"- frontend_pressure_seen: {str(stage1a8_decision.get('frontend_pressure_seen')).lower()}",
            f"- backend_activity_seen: {str(stage1a8_decision.get('backend_activity_seen')).lower()}",
            f"- rollback_recovery_seen: {str(stage1a8_decision.get('rollback_recovery_seen')).lower()}",
            f"- pbm_ingress_valid_not_ready_stall: {str(stage1a8_decision.get('pbm_ingress_valid_not_ready_stall')).lower()}",
            f"- pbm_accept_without_packet_end: {str(stage1a8_decision.get('pbm_accept_without_packet_end')).lower()}",
            f"- pbm_commit_without_backend_service: {str(stage1a8_decision.get('pbm_commit_without_backend_service')).lower()}",
            f"- pbm_rollback_trigger_candidate_seen: {str(stage1a8_decision.get('pbm_rollback_trigger_candidate_seen')).lower()}",
            f"- pbm_rollback_path_observed: {str(stage1a8_decision.get('pbm_rollback_path_observed')).lower()}",
            f"- recommended_next_stage: {stage1a8_decision.get('recommended_next_stage')}",
        ]
    stage1a9_lines: list[str] = []
    if stage1a9_decision:
        stage1a9_lines = [
            "",
            "## Stage 1A.9 Crypto Ingress Handoff Visibility Diagnosis",
            f"- diagnostic_csr_map_version: {stage1a9_decision.get('diagnostic_csr_map_version')}",
            f"- diagnostic_csr_address_range: {stage1a9_decision.get('diagnostic_csr_address_range')}",
            f"- crypto_ingress_diag_csr_collision: {str(stage1a9_decision.get('crypto_ingress_diag_csr_collision')).lower()}",
            f"- idle_residual_activity_seen: {str(stage1a9_decision.get('idle_residual_activity_seen')).lower()}",
            f"- crypto_rx_valid_seen: {str(stage1a9_decision.get('crypto_rx_valid_seen')).lower()}",
            f"- crypto_rx_valid_not_ready_seen: {str(stage1a9_decision.get('crypto_rx_valid_not_ready_seen')).lower()}",
            f"- pbm_activity_seen: {str(stage1a9_decision.get('pbm_activity_seen')).lower()}",
            f"- pbm_accept_seen: {str(stage1a9_decision.get('pbm_accept_seen')).lower()}",
            f"- pbm_commit_seen: {str(stage1a9_decision.get('pbm_commit_seen')).lower()}",
            f"- pbm_commit_rows_seen: {stage1a9_decision.get('pbm_commit_rows_seen')}",
            f"- backend_activity_seen: {str(stage1a9_decision.get('backend_activity_seen')).lower()}",
            f"- backend_activity_rows_seen: {stage1a9_decision.get('backend_activity_rows_seen')}",
            f"- backend_activity_stable: {str(stage1a9_decision.get('backend_activity_stable')).lower()}",
            f"- backend_activity_intermittent: {str(stage1a9_decision.get('backend_activity_intermittent')).lower()}",
            f"- pbm_commit_without_backend_service: {str(stage1a9_decision.get('pbm_commit_without_backend_service')).lower()}",
            f"- crypto_rx_without_pbm_activity: {str(stage1a9_decision.get('crypto_rx_without_pbm_activity')).lower()}",
            f"- crypto_rx_accept_without_pbm_accept: {str(stage1a9_decision.get('crypto_rx_accept_without_pbm_accept')).lower()}",
            f"- recommended_next_stage: {stage1a9_decision.get('recommended_next_stage')}",
        ]
    stage1a10_lines: list[str] = []
    if stage1a10_decision:
        stage1a10_lines = [
            "",
            "## Stage 1A.10 Crypto DMA Handoff Diagnosis",
            f"- diagnostic_csr_map_version: {stage1a10_decision.get('diagnostic_csr_map_version')}",
            f"- diagnostic_csr_address_range: {stage1a10_decision.get('diagnostic_csr_address_range')}",
            f"- crypto_dma_handoff_diag_csr_collision: {str(stage1a10_decision.get('crypto_dma_handoff_diag_csr_collision')).lower()}",
            f"- idle_residual_activity_seen: {str(stage1a10_decision.get('idle_residual_activity_seen')).lower()}",
            f"- pbm_commit_seen: {str(stage1a10_decision.get('pbm_commit_seen')).lower()}",
            f"- pbm_commit_rows_seen: {stage1a10_decision.get('pbm_commit_rows_seen')}",
            f"- backend_activity_seen: {str(stage1a10_decision.get('backend_activity_seen')).lower()}",
            f"- backend_activity_stable: {str(stage1a10_decision.get('backend_activity_stable')).lower()}",
            f"- backend_activity_intermittent: {str(stage1a10_decision.get('backend_activity_intermittent')).lower()}",
            f"- committed_rows_with_backend_service_count: {stage1a10_decision.get('committed_rows_with_backend_service_count')}",
            f"- committed_rows_without_backend_service_count: {stage1a10_decision.get('committed_rows_without_backend_service_count')}",
            f"- pbm_committed_but_tail_not_moved: {str(stage1a10_decision.get('pbm_committed_but_tail_not_moved')).lower()}",
            f"- pbm_committed_but_rd_empty: {str(stage1a10_decision.get('pbm_committed_but_rd_empty')).lower()}",
            f"- pbm_rd_accept_seen: {str(stage1a10_decision.get('pbm_rd_accept_seen')).lower()}",
            f"- crypto_dma_ingress_accept_seen: {str(stage1a10_decision.get('crypto_dma_ingress_accept_seen')).lower()}",
            f"- backend_accept_after_crypto_dma_seen: {str(stage1a10_decision.get('backend_accept_after_crypto_dma_seen')).lower()}",
            f"- handoff_gap_classification: {stage1a10_decision.get('handoff_gap_classification')}",
            f"- recommended_next_stage: {stage1a10_decision.get('recommended_next_stage')}",
        ]
    stage1a11_lines: list[str] = []
    if stage1a11_decision:
        stage1a11_lines = [
            "",
            "## Stage 1A.11 PBM Read-Side Visibility Diagnosis",
            f"- diagnostic_csr_map_version: {stage1a11_decision.get('diagnostic_csr_map_version')}",
            f"- diagnostic_csr_address_range: {stage1a11_decision.get('diagnostic_csr_address_range')}",
            f"- pbm_read_side_diag_csr_collision: {str(stage1a11_decision.get('pbm_read_side_diag_csr_collision')).lower()}",
            f"- idle_residual_activity_seen: {str(stage1a11_decision.get('idle_residual_activity_seen')).lower()}",
            f"- pbm_commit_seen: {str(stage1a11_decision.get('pbm_commit_seen')).lower()}",
            f"- pbm_commit_rows_seen: {stage1a11_decision.get('pbm_commit_rows_seen')}",
            f"- bridge_rd_en_seen: {str(stage1a11_decision.get('bridge_rd_en_seen')).lower()}",
            f"- bridge_fire_seen: {str(stage1a11_decision.get('bridge_fire_seen')).lower()}",
            f"- data_without_inst_available_seen: {str(stage1a11_decision.get('data_without_inst_available_seen')).lower()}",
            f"- dma_start_seen: {str(stage1a11_decision.get('dma_start_seen')).lower()}",
            f"- dma_addr_seen: {str(stage1a11_decision.get('dma_addr_seen')).lower()}",
            f"- dma_data_seen: {str(stage1a11_decision.get('dma_data_seen')).lower()}",
            f"- dma_aw_handshake_seen: {str(stage1a11_decision.get('dma_aw_handshake_seen')).lower()}",
            f"- dma_w_handshake_seen: {str(stage1a11_decision.get('dma_w_handshake_seen')).lower()}",
            f"- dma_b_handshake_seen: {str(stage1a11_decision.get('dma_b_handshake_seen')).lower()}",
            f"- dma_wready_backpressure_seen: {str(stage1a11_decision.get('dma_wready_backpressure_seen')).lower()}",
            f"- backend_activity_seen: {str(stage1a11_decision.get('backend_activity_seen')).lower()}",
            f"- backend_activity_stable: {str(stage1a11_decision.get('backend_activity_stable')).lower()}",
            f"- backend_activity_intermittent: {str(stage1a11_decision.get('backend_activity_intermittent')).lower()}",
            f"- read_side_gap_classification: {stage1a11_decision.get('read_side_gap_classification')}",
            f"- recommended_next_stage: {stage1a11_decision.get('recommended_next_stage')}",
        ]
    stage1a12_lines: list[str] = []
    if stage1a12_decision:
        stage1a12_lines = [
            "",
            "## Stage 1A.12 Bridge Output FIFO Visibility Diagnosis",
            f"- diagnostic_csr_map_version: {stage1a12_decision.get('diagnostic_csr_map_version')}",
            f"- diagnostic_csr_address_range: {stage1a12_decision.get('diagnostic_csr_address_range')}",
            f"- bridge_output_fifo_diag_csr_collision: {str(stage1a12_decision.get('bridge_output_fifo_diag_csr_collision')).lower()}",
            f"- idle_control_quiesce_guard_ms: {stage1a12_decision.get('idle_control_quiesce_guard_ms')}",
            f"- idle_pre_after_clear_zero: {str(stage1a12_decision.get('idle_pre_after_clear_zero')).lower()}",
            f"- idle_bridge_output_fifo_residual_seen: {str(stage1a12_decision.get('idle_bridge_output_fifo_residual_seen')).lower()}",
            f"- bridge_output_fifo_nonempty_seen: {str(stage1a12_decision.get('bridge_output_fifo_nonempty_seen')).lower()}",
            f"- bridge_output_fifo_rd_en_seen: {str(stage1a12_decision.get('bridge_output_fifo_rd_en_seen')).lower()}",
            f"- bridge_output_fifo_accept_seen: {str(stage1a12_decision.get('bridge_output_fifo_accept_seen')).lower()}",
            f"- bridge_output_fifo_last_seen: {str(stage1a12_decision.get('bridge_output_fifo_last_seen')).lower()}",
            f"- dma_start_seen: {str(stage1a12_decision.get('dma_start_seen')).lower()}",
            f"- bridge_output_fifo_nonzero_rate: {stage1a12_decision.get('bridge_output_fifo_nonzero_rate')}",
            f"- backend_activity_seen: {str(stage1a12_decision.get('backend_activity_seen')).lower()}",
            f"- backend_activity_stable: {str(stage1a12_decision.get('backend_activity_stable')).lower()}",
            f"- backend_activity_intermittent: {str(stage1a12_decision.get('backend_activity_intermittent')).lower()}",
            f"- bridge_output_fifo_classification: {stage1a12_decision.get('bridge_output_fifo_classification')}",
            f"- recommended_next_stage: {stage1a12_decision.get('recommended_next_stage')}",
        ]
    stage1a13_lines: list[str] = []
    if stage1a13_decision:
        stage1a13_lines = [
            "",
            "## Stage 1A.13 DMA Start Path Diagnosis",
            f"- diagnostic_csr_map_version: {stage1a13_decision.get('diagnostic_csr_map_version')}",
            f"- diagnostic_csr_address_range: {stage1a13_decision.get('diagnostic_csr_address_range')}",
            f"- dma_start_path_diag_csr_collision: {str(stage1a13_decision.get('dma_start_path_diag_csr_collision')).lower()}",
            f"- ring_size_zero: {str(stage1a13_decision.get('ring_size_zero')).lower()}",
            f"- runtime_ring_bypass_enabled: {str(stage1a13_decision.get('runtime_ring_bypass_enabled')).lower()}",
            f"- fastpath_enabled: {str(stage1a13_decision.get('fastpath_enabled')).lower()}",
            f"- current_bridge_tx_nonempty_seen: {str(stage1a13_decision.get('current_bridge_tx_nonempty_seen')).lower()}",
            f"- current_dma_start_seen: {str(stage1a13_decision.get('current_dma_start_seen')).lower()}",
            f"- explicit_csr_start_pulsed_by_probe: {str(stage1a13_decision.get('explicit_csr_start_pulsed_by_probe')).lower()}",
            f"- explicit_csr_start_seen: {str(stage1a13_decision.get('explicit_csr_start_seen')).lower()}",
            f"- explicit_final_start_seen: {str(stage1a13_decision.get('explicit_final_start_seen')).lower()}",
            f"- explicit_dma_start_seen: {str(stage1a13_decision.get('explicit_dma_start_seen')).lower()}",
            f"- explicit_dma_busy_seen: {str(stage1a13_decision.get('explicit_dma_busy_seen')).lower()}",
            f"- explicit_bridge_tx_rd_en_seen: {str(stage1a13_decision.get('explicit_bridge_tx_rd_en_seen')).lower()}",
            f"- explicit_bridge_tx_accept_seen: {str(stage1a13_decision.get('explicit_bridge_tx_accept_seen')).lower()}",
            f"- final_start_source_classification: {stage1a13_decision.get('final_start_source_classification')}",
            f"- dma_start_path_classification: {stage1a13_decision.get('dma_start_path_classification')}",
            f"- recommended_next_stage: {stage1a13_decision.get('recommended_next_stage')}",
            "Explicit CSR start is a diagnostic intervention used to validate the DMA start chain. It is not treated as a normal-path performance or recovery result.",
        ]
    stage1a14_lines: list[str] = []
    if stage1a14_decision:
        stage1a14_lines = [
            "",
            "## Stage 1A.14 Start Pulse Injection / Probe Control Fix",
            f"- diagnostic_csr_map_version: {stage1a14_decision.get('diagnostic_csr_map_version')}",
            f"- diagnostic_csr_address_range: {stage1a14_decision.get('diagnostic_csr_address_range')}",
            f"- start_pulse_injection_diag_csr_collision: {str(stage1a14_decision.get('start_pulse_injection_diag_csr_collision')).lower()}",
            f"- explicit_csr_start_pulsed_by_probe: {str(stage1a14_decision.get('explicit_csr_start_pulsed_by_probe')).lower()}",
            f"- explicit_start_write_addr: {stage1a14_decision.get('explicit_start_write_addr')}",
            f"- explicit_start_write_value: {stage1a14_decision.get('explicit_start_write_value')}",
            f"- explicit_start_write_mask_or_wstrb: {stage1a14_decision.get('explicit_start_write_mask_or_wstrb')}",
            f"- explicit_start_readback_before: {stage1a14_decision.get('explicit_start_readback_before')}",
            f"- explicit_start_readback_after: {stage1a14_decision.get('explicit_start_readback_after')}",
            f"- csr_control_reg_addr_expected: {stage1a14_decision.get('csr_control_reg_addr_expected')}",
            f"- csr_start_bit_expected: {stage1a14_decision.get('csr_start_bit_expected')}",
            f"- axil_write_hit_control_seen: {str(stage1a14_decision.get('axil_write_hit_control_seen')).lower()}",
            f"- axil_write_hit_start_seen: {str(stage1a14_decision.get('axil_write_hit_start_seen')).lower()}",
            f"- csr_start_seen: {str(stage1a14_decision.get('csr_start_seen')).lower()}",
            f"- final_start_seen: {str(stage1a14_decision.get('final_start_seen')).lower()}",
            f"- dma_start_seen: {str(stage1a14_decision.get('dma_start_seen')).lower()}",
            f"- expected_start_source: {stage1a14_decision.get('expected_start_source')}",
            f"- start_pulse_injection_classification: {stage1a14_decision.get('start_pulse_injection_classification')}",
            f"- recommended_next_stage: {stage1a14_decision.get('recommended_next_stage')}",
            "Explicit CSR start is a diagnostic intervention used to validate whether the probe write reaches axil_csr.o_start; it is not treated as normal-path performance or recovery evidence.",
        ]
    stage1a15_lines: list[str] = []
    if stage1a15_decision:
        stage1a15_lines = [
            "",
            "## Stage 1A.15 Explicit Start Bridge Handoff Diagnosis",
            "- Current_Bypass_NoExplicitStart is a baseline and is not a start-failure test.",
            f"- shadow_control_base: {stage1a15_decision.get('shadow_control_base')}",
            f"- dma_csr_base: {stage1a15_decision.get('dma_csr_base')}",
            f"- explicit_start_write_addr: {stage1a15_decision.get('explicit_start_write_addr')}",
            f"- explicit_start_write_value: {stage1a15_decision.get('explicit_start_write_value')}",
            f"- dma_ctrl_read_before: {stage1a15_decision.get('dma_ctrl_read_before')}",
            f"- dma_ctrl_read_after: {stage1a15_decision.get('dma_ctrl_read_after')}",
            f"- explicit_start_write_addr_matches_dma_csr_base: {str(stage1a15_decision.get('explicit_start_write_addr_matches_dma_csr_base')).lower()}",
            f"- explicit_start_verified_by_hardware: {str(stage1a15_decision.get('explicit_start_verified_by_hardware')).lower()}",
            f"- row_level_start_and_bridge_nonempty_seen: {str(stage1a15_decision.get('row_level_start_and_bridge_nonempty_seen')).lower()}",
            f"- row_level_overlap_note: {stage1a15_decision.get('row_level_overlap_note')}",
            f"- dma_or_source_reader_busy_seen: {str(stage1a15_decision.get('dma_or_source_reader_busy_seen')).lower()}",
            f"- baseline_bridge_tx_nonempty_seen: {str(stage1a15_decision.get('baseline_bridge_tx_nonempty_seen')).lower()}",
            f"- baseline_dma_start_seen: {str(stage1a15_decision.get('baseline_dma_start_seen')).lower()}",
            f"- bridge_tx_nonempty_seen: {str(stage1a15_decision.get('bridge_tx_nonempty_seen')).lower()}",
            f"- bridge_tx_rd_en_seen: {str(stage1a15_decision.get('bridge_tx_rd_en_seen')).lower()}",
            f"- bridge_tx_accept_seen: {str(stage1a15_decision.get('bridge_tx_accept_seen')).lower()}",
            f"- crypto_dma_in_accept_seen: {str(stage1a15_decision.get('crypto_dma_in_accept_seen')).lower()}",
            f"- handoff_classification: {stage1a15_decision.get('handoff_classification')}",
            f"- recommended_next_stage: {stage1a15_decision.get('recommended_next_stage')}",
            "Explicit CSR start is a diagnostic intervention used to test whether start and bridge/FIFO data can line up in one row; it is not treated as normal-path performance or recovery evidence.",
        ]
    stage1a16_lines: list[str] = []
    if stage1a16_decision:
        stage1a16_lines = [
            "",
            "## Stage 1A.16 Bridge Data Production Diagnosis",
            "- A12_NoStart_Replay is the baseline reproduction gate; A15_AfterWorkloadStart_Replay is the explicit-start config.",
            "- bridge_tx_nonempty_seen_any is stage overview only and is not allowed to trigger DMARdEnableGatingDiagnosis.",
            f"- baseline_bridge_reproduced: {str(stage1a16_decision.get('baseline_bridge_reproduced')).lower()}",
            f"- baseline_bridge_reproduced_repeats: {stage1a16_decision.get('baseline_bridge_reproduced_repeats')}",
            f"- baseline_bridge_reproduced_threshold: {stage1a16_decision.get('baseline_bridge_reproduced_threshold')}",
            f"- a12_no_start_replay_bridge_nonempty_seen: {str(stage1a16_decision.get('a12_no_start_replay_bridge_nonempty_seen')).lower()}",
            f"- a15_after_start_bridge_nonempty_seen: {str(stage1a16_decision.get('a15_after_start_bridge_nonempty_seen')).lower()}",
            f"- a15_after_start_explicit_start_verified: {str(stage1a16_decision.get('a15_after_start_explicit_start_verified')).lower()}",
            f"- a15_after_start_dma_start_seen: {str(stage1a16_decision.get('a15_after_start_dma_start_seen')).lower()}",
            f"- explicit_start_and_bridge_nonempty_same_row_seen: {str(stage1a16_decision.get('explicit_start_and_bridge_nonempty_same_row_seen')).lower()}",
            f"- explicit_start_and_bridge_nonempty_rows_count: {stage1a16_decision.get('explicit_start_and_bridge_nonempty_rows_count')}",
            f"- bridge_tx_nonempty_seen_any: {str(stage1a16_decision.get('bridge_tx_nonempty_seen_any')).lower()}",
            f"- bridge_tx_wr_en_seen: {str(stage1a16_decision.get('bridge_tx_wr_en_seen')).lower()}",
            f"- bridge_tx_fifo_level_increased: {str(stage1a16_decision.get('bridge_tx_fifo_level_increased')).lower()}",
            f"- explicit_start_changed_control_state: {str(stage1a16_decision.get('explicit_start_changed_control_state')).lower()}",
            f"- bridge_data_production_classification: {stage1a16_decision.get('bridge_data_production_classification')}",
            f"- bridge_data_production_classification_reason: {stage1a16_decision.get('bridge_data_production_classification_reason')}",
            f"- recommended_next_stage: {stage1a16_decision.get('recommended_next_stage')}",
            "bridge_tx_fifo_level_pre/post are snapshot values; bridge_tx_fifo_level_max is the maximum level observed during the window; bridge_tx_nonempty_cycles is a level-active cycle count; bridge_tx_wr_en_cycles is an enqueue-event cycle count.",
        ]
    stage1a17_lines: list[str] = []
    if stage1a17_decision:
        stage1a17_lines = [
            "",
            "## Stage 1A.17 PBM Commit Reproduction Diagnosis",
            "- Stage1A17 replays the closest known PBM commit-positive BF64 condition and does not evaluate bridge, DMA, backend, or Stage 2 evidence.",
            "- Extra snapshots are sub-snapshots within the same probe window and do not add main sample rows.",
            f"- reference_stage1a9_dir: {stage1a17_decision.get('reference_stage1a9_dir')}",
            f"- reference_stage1a12_dir: {stage1a17_decision.get('reference_stage1a12_dir')}",
            f"- current_stage1a16_dir: {stage1a17_decision.get('current_stage1a16_dir')}",
            f"- reference_commit_positive_source: {stage1a17_decision.get('reference_commit_positive_source')}",
            f"- reference_case_name: {stage1a17_decision.get('reference_case_name')}",
            f"- reference_burst_frames: {stage1a17_decision.get('reference_burst_frames')}",
            f"- reference_settle_ms: {stage1a17_decision.get('reference_settle_ms')}",
            f"- reference_burst_gap_us: {stage1a17_decision.get('reference_burst_gap_us')}",
            f"- commit_reference_replay_rows: {stage1a17_decision.get('commit_reference_replay_rows')}",
            f"- extra_snapshot_replay_rows: {stage1a17_decision.get('extra_snapshot_replay_rows')}",
            f"- commit_reference_replay_commit_seen: {str(stage1a17_decision.get('commit_reference_replay_commit_seen')).lower()}",
            f"- extra_snapshot_replay_commit_seen: {str(stage1a17_decision.get('extra_snapshot_replay_commit_seen')).lower()}",
            f"- pbm_wr_valid_cycles: {stage1a17_decision.get('pbm_wr_valid_cycles')}",
            f"- pbm_valid_not_ready_cycles: {stage1a17_decision.get('pbm_valid_not_ready_cycles')}",
            f"- pbm_wr_accept_cycles: {stage1a17_decision.get('pbm_wr_accept_cycles')}",
            f"- pbm_wr_last_accepted_count: {stage1a17_decision.get('pbm_wr_last_accepted_count')}",
            f"- pbm_wr_last_clean_accepted_count: {stage1a17_decision.get('pbm_wr_last_clean_accepted_count')}",
            f"- pbm_wr_last_error_accepted_count: {stage1a17_decision.get('pbm_wr_last_error_accepted_count')}",
            f"- pbm_commit_entry_count: {stage1a17_decision.get('pbm_commit_entry_count')}",
            f"- pbm_rollback_entry_count: {stage1a17_decision.get('pbm_rollback_entry_count')}",
            f"- pbm_ptr_head_reserve_delta_mod: {stage1a17_decision.get('pbm_ptr_head_reserve_delta_mod')}",
            f"- pbm_ptr_head_commit_delta_mod: {stage1a17_decision.get('pbm_ptr_head_commit_delta_mod')}",
            f"- pbm_commit_reproduction_classification: {stage1a17_decision.get('pbm_commit_reproduction_classification')}",
            f"- pbm_commit_reproduction_classification_reason: {stage1a17_decision.get('pbm_commit_reproduction_classification_reason')}",
            f"- recommended_next_stage: {stage1a17_decision.get('recommended_next_stage')}",
        ]
    stage1a26_lines: list[str] = []
    if stage1a26_decision:
        stage1a26_lines = [
            "",
            "## Stage 1A.26 DMA rd_en Equation Diagnosis",
            "- Stage1A26 is diagnostic-only and observes the bridge_tx_rd_en equation inputs without changing datapath behavior.",
            f"- diagnostic_csr_address_range: {stage1a26_decision.get('diagnostic_csr_address_range')}",
            f"- diagnostic_csr_collision: {str(stage1a26_decision.get('diagnostic_csr_collision')).lower()}",
            f"- explicit_start_verified_by_hardware: {str(stage1a26_decision.get('explicit_start_verified_by_hardware')).lower()}",
            f"- runtime_ring_bypass_enabled: {str(stage1a26_decision.get('runtime_ring_bypass_enabled')).lower()}",
            f"- dma_rd_en_loopback_mode_raw: {stage1a26_decision.get('dma_rd_en_loopback_mode_raw')}",
            f"- dma_rd_en_tx_axis_tready_cycles: {stage1a26_decision.get('dma_rd_en_tx_axis_tready_cycles')}",
            f"- dma_rd_en_crypto_to_dma_nonempty_cycles: {stage1a26_decision.get('dma_rd_en_crypto_to_dma_nonempty_cycles')}",
            f"- dma_rd_en_tx_ready_when_nonempty_cycles: {stage1a26_decision.get('dma_rd_en_tx_ready_when_nonempty_cycles')}",
            f"- dma_rd_en_dma_req_rd_cycles: {stage1a26_decision.get('dma_rd_en_dma_req_rd_cycles')}",
            f"- dma_rd_en_loopback_branch_selected_cycles: {stage1a26_decision.get('dma_rd_en_loopback_branch_selected_cycles')}",
            f"- dma_rd_en_normal_branch_selected_cycles: {stage1a26_decision.get('dma_rd_en_normal_branch_selected_cycles')}",
            f"- dma_rd_en_loopback_branch_candidate_cycles: {stage1a26_decision.get('dma_rd_en_loopback_branch_candidate_cycles')}",
            f"- dma_rd_en_equation_true_but_rd_en_low_cycles: {stage1a26_decision.get('dma_rd_en_equation_true_but_rd_en_low_cycles')}",
            f"- bridge_tx_rd_en_cycles: {stage1a26_decision.get('bridge_tx_rd_en_cycles')}",
            f"- bridge_tx_accept_cycles: {stage1a26_decision.get('bridge_tx_accept_cycles')}",
            f"- dma_rd_en_equation_classification: {stage1a26_decision.get('dma_rd_en_equation_classification')}",
            f"- recommended_next_stage: {stage1a26_decision.get('recommended_next_stage')}",
        ]
    stage1a27_lines: list[str] = []
    if stage1a27_decision:
        stage1a27_lines = [
            "",
            "## Stage 1A.27 Crypto DMA Ingress Backpressure Diagnosis",
            "- Stage1A27 is diagnostic-only and localizes the bridge-to-crypto-DMA ingress handoff.",
            f"- included_rows: {stage1a27_decision.get('included_rows')}",
            f"- bridge_tx_accept_cycles: {stage1a27_decision.get('bridge_tx_accept_cycles')}",
            f"- crypto_dma_in_valid_cycles: {stage1a27_decision.get('crypto_dma_in_valid_cycles')}",
            f"- crypto_dma_in_ready_cycles: {stage1a27_decision.get('crypto_dma_in_ready_cycles')}",
            f"- crypto_dma_in_accept_cycles: {stage1a27_decision.get('crypto_dma_in_accept_cycles')}",
            f"- backend_activity_seen: {str(stage1a27_decision.get('backend_activity_seen')).lower()}",
            f"- crypto_dma_ingress_backpressure_classification: {stage1a27_decision.get('crypto_dma_ingress_backpressure_classification')}",
            f"- recommended_next_stage: {stage1a27_decision.get('recommended_next_stage')}",
        ]
    stage1a18_lines: list[str] = []
    if stage1a18_decision:
        stage1a18_lines = [
            "",
            "## Stage 1A.18 Upstream Ingress To PBM Visibility Diagnosis",
            "- Stage1A18 isolates ingress-to-PBM visibility and must not interpret bridge, DMA, backend, or Stage 2 behavior.",
            "- Extra snapshots are sub-snapshots within the same probe window and do not add main sample rows.",
            f"- ingress_reference_replay_rows: {stage1a18_decision.get('ingress_reference_replay_rows')}",
            f"- extra_snapshot_replay_rows: {stage1a18_decision.get('extra_snapshot_replay_rows')}",
            f"- stage1_fire_seen: {str(stage1a18_decision.get('stage1_fire_seen')).lower()}",
            f"- acl_fire_seen: {str(stage1a18_decision.get('acl_fire_seen')).lower()}",
            f"- classifier_in_fire_seen: {str(stage1a18_decision.get('classifier_in_fire_seen')).lower()}",
            f"- classifier_dma_valid_seen: {str(stage1a18_decision.get('classifier_dma_valid_seen')).lower()}",
            f"- classifier_dma_fire_seen: {str(stage1a18_decision.get('classifier_dma_fire_seen')).lower()}",
            f"- classifier_dma_ready_seen: {str(stage1a18_decision.get('classifier_dma_ready_seen')).lower()}",
            f"- crypto_rx_valid_cycles: {stage1a18_decision.get('crypto_rx_valid_cycles')}",
            f"- crypto_rx_accept_cycles: {stage1a18_decision.get('crypto_rx_accept_cycles')}",
            f"- crypto_rx_valid_not_ready_cycles: {stage1a18_decision.get('crypto_rx_valid_not_ready_cycles')}",
            f"- pbm_wr_valid_cycles: {stage1a18_decision.get('pbm_wr_valid_cycles')}",
            f"- pbm_wr_accept_cycles: {stage1a18_decision.get('pbm_wr_accept_cycles')}",
            f"- pbm_valid_not_ready_cycles: {stage1a18_decision.get('pbm_valid_not_ready_cycles')}",
            f"- route_state_names_seen: {json.dumps(stage1a18_decision.get('route_state_names_seen', []), sort_keys=True)}",
            f"- upstream_ingress_to_pbm_classification: {stage1a18_decision.get('upstream_ingress_to_pbm_classification')}",
            f"- upstream_ingress_to_pbm_classification_reason: {stage1a18_decision.get('upstream_ingress_to_pbm_classification_reason')}",
            f"- recommended_next_stage: {stage1a18_decision.get('recommended_next_stage')}",
        ]
    stage1a19_lines: list[str] = []
    if stage1a19_decision:
        stage1a19_lines = [
            "",
            "## Stage 1A.19 Injection Source Emission Diagnosis",
            "- Stage1A19 isolates injection-source emission and must not interpret ACL, classifier, PBM, bridge, DMA, backend, or Stage 2 behavior.",
            "- Extra snapshots are sub-snapshots within the same probe window and do not add main sample rows.",
            f"- emission_reference_replay_rows: {stage1a19_decision.get('emission_reference_replay_rows')}",
            f"- extra_snapshot_replay_rows: {stage1a19_decision.get('extra_snapshot_replay_rows')}",
            f"- stage1_fire_seen: {str(stage1a19_decision.get('stage1_fire_seen')).lower()}",
            f"- stage1_inject_tvalid_seen: {str(stage1a19_decision.get('stage1_inject_tvalid_seen')).lower()}",
            f"- stage1_inject_tready_seen: {str(stage1a19_decision.get('stage1_inject_tready_seen')).lower()}",
            f"- stage1_valid_not_ready_seen: {str(stage1a19_decision.get('stage1_valid_not_ready_seen')).lower()}",
            f"- inj_fifo_nonempty_seen: {str(stage1a19_decision.get('inj_fifo_nonempty_seen')).lower()}",
            f"- inj_fifo_count_max: {stage1a19_decision.get('inj_fifo_count_max')}",
            f"- inj_done_seen: {str(stage1a19_decision.get('inj_done_seen')).lower()}",
            f"- inj_overflow_seen: {str(stage1a19_decision.get('inj_overflow_seen')).lower()}",
            f"- source_progress_delta_seen: {str(stage1a19_decision.get('source_progress_delta_seen')).lower()}",
            f"- route_state_names_seen: {json.dumps(stage1a19_decision.get('route_state_names_seen', []), sort_keys=True)}",
            f"- injection_source_emission_classification: {stage1a19_decision.get('injection_source_emission_classification')}",
            f"- injection_source_emission_classification_reason: {stage1a19_decision.get('injection_source_emission_classification_reason')}",
            f"- recommended_next_stage: {stage1a19_decision.get('recommended_next_stage')}",
        ]
    stage1a20_lines: list[str] = []
    if stage1a20_decision:
        stage1a20_lines = [
            "",
            "## Stage 1A.20 Injection Source Arming Diagnosis",
            "- Stage1A20 isolates injection CSR hit, source arming/configuration, FIFO load, and stage1 emission before any downstream interpretation.",
            f"- injection_arm_only_rows: {stage1a20_decision.get('injection_arm_only_rows')}",
            f"- injection_arm_with_readback_rows: {stage1a20_decision.get('injection_arm_with_readback_rows')}",
            f"- inj_ctrl_write_hit_seen: {str(stage1a20_decision.get('inj_ctrl_write_hit_seen')).lower()}",
            f"- inj_clear_write_hit_seen: {str(stage1a20_decision.get('inj_clear_write_hit_seen')).lower()}",
            f"- inj_frame_word_write_hit_seen: {str(stage1a20_decision.get('inj_frame_word_write_hit_seen')).lower()}",
            f"- inj_expected_words_write_hit_seen: {str(stage1a20_decision.get('inj_expected_words_write_hit_seen')).lower()}",
            f"- inj_config_valid_seen: {str(stage1a20_decision.get('inj_config_valid_seen')).lower()}",
            f"- inj_fifo_write_count: {stage1a20_decision.get('inj_fifo_write_count')}",
            f"- inj_fifo_level_max: {stage1a20_decision.get('inj_fifo_level_max')}",
            f"- inj_source_active_cycles: {stage1a20_decision.get('inj_source_active_cycles')}",
            f"- stage1_inject_tvalid_cycles: {stage1a20_decision.get('stage1_inject_tvalid_cycles')}",
            f"- stage1_inject_tready_cycles: {stage1a20_decision.get('stage1_inject_tready_cycles')}",
            f"- stage1_inject_fire_cycles: {stage1a20_decision.get('stage1_inject_fire_cycles')}",
            f"- route_state_names_seen: {json.dumps(stage1a20_decision.get('route_state_names_seen', []), sort_keys=True)}",
            f"- injection_source_arming_classification: {stage1a20_decision.get('injection_source_arming_classification')}",
            f"- injection_source_arming_classification_reason: {stage1a20_decision.get('injection_source_arming_classification_reason')}",
            f"- recommended_next_stage: {stage1a20_decision.get('recommended_next_stage')}",
        ]
    stage1a21_lines: list[str] = []
    if stage1a21_decision:
        stage1a21_lines = [
            "",
            "## Stage 1A.21 PBM Ready-Gating Diagnosis",
            f"- diagnostic_csr_map_version: {stage1a21_decision.get('diagnostic_csr_map_version')}",
            f"- diagnostic_csr_address_range: {stage1a21_decision.get('diagnostic_csr_address_range')}",
            f"- pbm_diag_csr_collision: {str(stage1a21_decision.get('pbm_diag_csr_collision')).lower()}",
            f"- idle_rows_seen: {stage1a21_decision.get('idle_rows_seen')}",
            f"- bf64_rows_seen: {stage1a21_decision.get('bf64_rows_seen')}",
            f"- bf64_extra_rows_seen: {stage1a21_decision.get('bf64_extra_rows_seen')}",
            f"- idle_commit_tail_gap_seen: {str(stage1a21_decision.get('idle_commit_tail_gap_seen')).lower()}",
            f"- idle_pbm_read_side_nonempty_seen: {str(stage1a21_decision.get('idle_pbm_read_side_nonempty_seen')).lower()}",
            f"- preexisting_pointer_gap_seen: {str(stage1a21_decision.get('preexisting_pointer_gap_seen')).lower()}",
            f"- ready_low_due_to_full_inferred: {str(stage1a21_decision.get('ready_low_due_to_full_inferred')).lower()}",
            f"- ready_low_due_to_state_inferred: {str(stage1a21_decision.get('ready_low_due_to_state_inferred')).lower()}",
            f"- pbm_ready_gating_classification: {stage1a21_decision.get('pbm_ready_gating_classification')}",
            f"- pbm_ready_gating_classification_reason: {stage1a21_decision.get('pbm_ready_gating_classification_reason')}",
            f"- recommended_next_stage: {stage1a21_decision.get('recommended_next_stage')}",
        ]
    stage1a22_lines: list[str] = []
    if stage1a22_decision:
        stage1a22_lines = [
            "",
            "## Stage 1A.22 PBM Pointer Reset Or Drain Diagnosis",
            f"- idle_no_reset_rows_seen: {stage1a22_decision.get('idle_no_reset_rows_seen')}",
            f"- idle_after_soft_reset_rows_seen: {stage1a22_decision.get('idle_after_soft_reset_rows_seen')}",
            f"- bf64_after_soft_reset_rows_seen: {stage1a22_decision.get('bf64_after_soft_reset_rows_seen')}",
            f"- idle_no_reset_pointer_gap_seen: {str(stage1a22_decision.get('idle_no_reset_pointer_gap_seen')).lower()}",
            f"- idle_after_soft_reset_gap_cleared: {str(stage1a22_decision.get('idle_after_soft_reset_gap_cleared')).lower()}",
            f"- idle_after_soft_reset_read_side_nonempty_seen: {str(stage1a22_decision.get('idle_after_soft_reset_read_side_nonempty_seen')).lower()}",
            f"- idle_after_soft_reset_read_drain_seen: {str(stage1a22_decision.get('idle_after_soft_reset_read_drain_seen')).lower()}",
            f"- bf64_after_soft_reset_ready_recovered: {str(stage1a22_decision.get('bf64_after_soft_reset_ready_recovered')).lower()}",
            f"- bf64_after_soft_reset_accept_seen: {str(stage1a22_decision.get('bf64_after_soft_reset_accept_seen')).lower()}",
            f"- pbm_pointer_reset_or_drain_classification: {stage1a22_decision.get('pbm_pointer_reset_or_drain_classification')}",
            f"- pbm_pointer_reset_or_drain_classification_reason: {stage1a22_decision.get('pbm_pointer_reset_or_drain_classification_reason')}",
            f"- recommended_next_stage: {stage1a22_decision.get('recommended_next_stage')}",
        ]
    stage1a23_lines: list[str] = []
    if stage1a23_decision:
        stage1a23_lines = [
            "",
            "## Stage 1A.23 PBM Commit-Tail Pointer Invariant Diagnosis",
            "- Stage1A23 checks whether the idle commit-tail pointer gap is a stable PBM state/counter invariant after DMA soft reset.",
            f"- idle_no_reset_rows_seen: {stage1a23_decision.get('idle_no_reset_rows_seen')}",
            f"- idle_after_soft_reset_rows_seen: {stage1a23_decision.get('idle_after_soft_reset_rows_seen')}",
            f"- idle_after_soft_reset_extra_rows_seen: {stage1a23_decision.get('idle_after_soft_reset_extra_rows_seen')}",
            f"- soft_reset_pulsed_verified: {str(stage1a23_decision.get('soft_reset_pulsed_verified')).lower()}",
            f"- idle_no_reset_pointer_gap_seen: {str(stage1a23_decision.get('idle_no_reset_pointer_gap_seen')).lower()}",
            f"- idle_after_soft_reset_pointer_gap_seen: {str(stage1a23_decision.get('idle_after_soft_reset_pointer_gap_seen')).lower()}",
            f"- extra_snapshots_present: {str(stage1a23_decision.get('extra_snapshots_present')).lower()}",
            f"- extra_pointer_constant: {str(stage1a23_decision.get('extra_pointer_constant')).lower()}",
            f"- extra_state_constant: {str(stage1a23_decision.get('extra_state_constant')).lower()}",
            f"- extra_read_nonempty_accumulates: {str(stage1a23_decision.get('extra_read_nonempty_accumulates')).lower()}",
            f"- extra_read_drain_seen: {str(stage1a23_decision.get('extra_read_drain_seen')).lower()}",
            f"- pbm_commit_tail_pointer_invariant_classification: {stage1a23_decision.get('pbm_commit_tail_pointer_invariant_classification')}",
            f"- pbm_commit_tail_pointer_invariant_classification_reason: {stage1a23_decision.get('pbm_commit_tail_pointer_invariant_classification_reason')}",
            f"- recommended_next_stage: {stage1a23_decision.get('recommended_next_stage')}",
        ]
    stage1a24_lines: list[str] = []
    if stage1a24_decision:
        stage1a24_lines = [
            "",
            "## Stage 1A.24 PBM Reset-Domain Scope Diagnosis",
            "- Stage1A24 combines Stage1A23 persistent invariant evidence with static RTL reset-scope checks.",
            f"- stage1a23_prior_classification: {stage1a24_decision.get('stage1a23_prior_classification')}",
            f"- dma_soft_reset_generated_by_axil_csr: {str(stage1a24_decision.get('dma_soft_reset_generated_by_axil_csr')).lower()}",
            f"- dma_soft_reset_connected_to_fetcher: {str(stage1a24_decision.get('dma_soft_reset_connected_to_fetcher')).lower()}",
            f"- dma_soft_reset_connected_to_source_reader: {str(stage1a24_decision.get('dma_soft_reset_connected_to_source_reader')).lower()}",
            f"- pbm_controller_has_soft_reset_port: {str(stage1a24_decision.get('pbm_controller_has_soft_reset_port')).lower()}",
            f"- dma_soft_reset_connected_to_pbm: {str(stage1a24_decision.get('dma_soft_reset_connected_to_pbm')).lower()}",
            f"- pbm_state_pointer_reset_requires_global_rst_n: {str(stage1a24_decision.get('pbm_state_pointer_reset_requires_global_rst_n')).lower()}",
            f"- pbm_diag_clear_resets_diag_counters_only: {str(stage1a24_decision.get('pbm_diag_clear_resets_diag_counters_only')).lower()}",
            f"- pbm_reset_domain_scope_classification: {stage1a24_decision.get('pbm_reset_domain_scope_classification')}",
            f"- pbm_reset_domain_scope_classification_reason: {stage1a24_decision.get('pbm_reset_domain_scope_classification_reason')}",
            f"- recommended_next_stage: {stage1a24_decision.get('recommended_next_stage')}",
        ]
    stage1a25_lines: list[str] = []
    if stage1a25_decision:
        stage1a25_lines = [
            "",
            "## Stage 1A.25 PBM Reset-Domain Remediation Plan",
            "- Stage1A25 turns the Stage1A24 reset-domain classification into a constrained engineering remediation plan.",
            f"- stage1a24_prior_classification: {stage1a25_decision.get('stage1a24_prior_classification')}",
            f"- selected_remediation: {stage1a25_decision.get('selected_remediation')}",
            f"- rejected_remediations: {', '.join(stage1a25_decision.get('rejected_remediations') or []) if stage1a25_decision.get('rejected_remediations') else 'none'}",
            f"- requires_rtl_change: {str(stage1a25_decision.get('requires_rtl_change')).lower()}",
            f"- diagnostic_build_required: {str(stage1a25_decision.get('diagnostic_build_required')).lower()}",
            f"- paper_ready_recovery_gate_may_open: {str(stage1a25_decision.get('paper_ready_recovery_gate_may_open')).lower()}",
            f"- implementation_notes: {stage1a25_decision.get('implementation_notes')}",
            f"- validation_plan: {stage1a25_decision.get('validation_plan')}",
            f"- recommended_next_stage: {stage1a25_decision.get('recommended_next_stage')}",
        ]

    nonzero_frontend_pressure_counters = [
        field for field in FRONTEND_PRESSURE_COUNTERS if max_counter(rows, field) > 0
    ]
    nonzero_rollback_recovery_counters = [
        field for field in ROLLBACK_RECOVERY_COUNTERS if max_counter(rows, field) > 0
    ]
    nonzero_backend_service_counters = [
        field for field in BACKEND_SERVICE_COUNTERS if max_counter(rows, field) > 0
    ]
    observed_rate_line = (
        f"- drop_pulse_nonzero_rate: {audit_decision.get('drop_pulse_nonzero_rate')}"
        if audit_decision
        else (
            f"- drop_pulse_nonzero_rate: {reproduction_decision.get('drop_pulse_nonzero_rate')}"
            if reproduction_decision
            else (
                f"- drop_pulse_nonzero_rate: {stage1a7_drop_nonzero_rate}"
                if stage1a7_decision
                else (
                    f"- bridge_output_fifo_nonzero_rate: {stage1a12_decision.get('bridge_output_fifo_nonzero_rate')}"
                    if stage1a12_decision
                    else (
                    f"- bridge_output_fifo_nonzero_rate: {safe_ratio(sum(1 for row in rows if int_value(row.get('bridge_tx_nonempty_cycles', 0)) > 0), max(1, len(rows)))}"
                    if stage1a13_decision or stage1a16_decision
                    else (
                    f"- drop_pulse_nonzero_rate: {safe_ratio(sum(1 for row in rows if int_value(row.get('drop_pulse_count', 0)) > 0), max(1, len(rows)))}"
                    if stage1a8_decision or stage1a9_decision or stage1a10_decision or stage1a11_decision
                    else f"- Trigger rate: {stats.get('trigger_rate')}"
                    )
                    )
                )
            )
        )
    )
    stage_objectives = {
        "Stage0_Sanity": "Validate recovery-trigger evidence without changing RTL thresholds.",
        "Stage1A_DropPulseAudit": "Audit drop_pulse_count semantics before treating it as recovery/drop evidence.",
        "Stage1A6_PriorDropPulseReproduction": "Reproduce prior nonzero drop_pulse_count under controlled sampling before continuing the diagnostic path.",
        "Stage1A7_DropPulseConditionDiffDiagnosis": "Explain why BF64 enters a reproducible ingress/front-end stall without backend or rollback progression.",
        "Stage1A8_PBMIngressVisibilityDiagnosis": "Locate whether the observed ingress/front-end stall stops at PBM ready gating, packet termination visibility, commit, or rollback.",
        "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis": "Locate whether activity reaches the crypto DMA RX boundary but fails to bind to the instrumented PBM ingress.",
        "Stage1A10_CryptoDMAHandoffDiagnosis": "Locate whether PBM commit is visible on the read side and whether commit-to-backend handoff stalls at PBM read, crypto DMA ingress, backend input, or completion.",
        "Stage1A11_PBMReadSideVisibilityDiagnosis": "Locate whether committed PBM data stalls at the bridge dequeue boundary, DMA start boundary, or AXI write channel.",
        "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis": "Determine whether crypto-bridge output FIFO activity is residual-only, gated before DMA read enable, or genuinely accepted toward downstream handoff.",
        "Stage1A13_DMAStartPathDiagnosis": "Determine whether the DMA start chain is missing its start source, blocked at final_start selection, or stalls before bridge dequeue.",
        "Stage1A16_BridgeDataProductionDiagnosis": "Replay the Stage1A12 bridge/FIFO nonempty baseline, then evaluate explicit-start handoff only inside the explicit-start config.",
        "Stage1A17_PBMCommitReproductionDiagnosis": "Re-establish whether the current workload reaches PBM valid, accept, accepted last, COMMIT, or ROLLBACK before any bridge/DMA interpretation.",
        "Stage1A26_DMARdEnableEquationDiagnosis": "Expose the bridge_tx_rd_en equation inputs and selected branch before changing DMA or bridge datapath behavior.",
        "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis": "Locate whether activity reaches stage1 fire, ACL fire, classifier input fire, classifier DMA valid, crypto RX, or PBM valid before any bridge/DMA interpretation.",
        "Stage1A19_InjectionSourceEmissionDiagnosis": "Locate whether the injection source arms, buffers data, drives stage1 valid, stalls on stage1 ready, or re-establishes stage1 fire before any ACL/classifier/PBM interpretation.",
        "Stage1A20_InjectionSourceArmingDiagnosis": "Confirm whether probe writes hit the injection CSR path, load frame configuration/FIFO state, activate the injection source FSM, and re-establish stage1 fire.",
        "Stage1A21_PBMReadyGatingDiagnosis": "Determine whether PBM write ready is low because full is inferred, because state blocks it, or because a preexisting pointer gap already exists before workload.",
        "Stage1A22_PBMPointerResetOrDrainDiagnosis": "Determine whether a DMA soft reset clears the preexisting PBM commit-tail gap/read-side nonempty condition, and whether PBM write ready recovers afterward.",
        "Stage1A23_PBMCommitTailPointerInvariantDiagnosis": "Determine whether the PBM commit-tail pointer gap and read-side nonempty counters are stable invariants across idle soft-reset extra snapshots.",
        "Stage1A24_PBMResetDomainScopeDiagnosis": "Determine whether the persistent PBM commit-tail invariant is explained by PBM state/pointers being outside the DMA soft-reset domain.",
        "Stage1A25_PBMResetDomainRemediationPlan": "Select a constrained remediation path for the PBM state/pointer reset-domain mismatch before changing RTL.",
    }
    stage_objective = stage_objectives.get(
        args.stage,
        "Validate Stage 1A burst-sweep execution chain before interpreting recovery behavior.",
    )
    expected_behaviors = {
        "Stage0_Sanity": "- Stage 0 sanity should reproduce classifier drop, header acceptance, and runtime ring bypass backend activity.",
        "Stage1A_DropPulseAudit": "- Stage1A_DropPulseAudit should classify drop_pulse_count semantics without entering paper_plot_data.",
        "Stage1A6_PriorDropPulseReproduction": "- Stage1A6_PriorDropPulseReproduction should only decide whether the prior nonzero drop_pulse_count is reproducible under controlled sampling.",
        "Stage1A7_DropPulseConditionDiffDiagnosis": "- Stage1A7 should differentiate BF8 negative-control behavior from BF64 ingress/front-end stall behavior without entering Stage 2.",
        "Stage1A8_PBMIngressVisibilityDiagnosis": "- Stage1A8 should classify the stall boundary at PBM ingress, packet termination, commit, or rollback without changing datapath behavior.",
        "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis": "- Stage1A9 should decide whether crypto RX boundary activity exists without matching PBM diagnostic activity.",
        "Stage1A10_CryptoDMAHandoffDiagnosis": "- Stage1A10 should decide whether committed rows stop at PBM read visibility, crypto DMA ingress, backend input gating, or completion/writeback.",
        "Stage1A11_PBMReadSideVisibilityDiagnosis": "- Stage1A11 should decide whether committed rows stall before bridge dequeue, before DMA start, or on the DMA write channel.",
        "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis": "- Stage1A12 should decide whether bridge output FIFO nonempty time is residual-only, blocked before rd_en, or accepted into downstream handoff.",
        "Stage1A13_DMAStartPathDiagnosis": "- Stage1A13 should decide whether the DMA start chain is absent, blocked before final_start, stalled before DMA activation, or active without bridge rd_en.",
        "Stage1A16_BridgeDataProductionDiagnosis": "- Stage1A16 should first check the A12 no-start bridge-nonempty baseline gate, then only evaluate rd_en gating inside A15_AfterWorkloadStart_Replay rows.",
        "Stage1A17_PBMCommitReproductionDiagnosis": "- Stage1A17 should classify PBM ingress as no-valid, ready-gated, accept-without-last, last-without-commit, commit-pointer mismatch, commit reproduced, or rollback/recovery observed.",
        "Stage1A26_DMARdEnableEquationDiagnosis": "- Stage1A26 should classify the DMA rd_en equation as loopback-mode control, TX ready gating, normal-branch request absence, equation instrumentation mismatch, bridge accept gap, or ready for crypto DMA handoff.",
        "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis": "- Stage1A18 should classify ingress visibility as no-stage1-fire, ACL handoff only, classifier input without DMA-valid, classifier DMA-valid without crypto RX, crypto RX without PBM valid, or PBM valid reestablished, and must not interpret bridge, DMA, backend, or Stage 2 behavior.",
        "Stage1A19_InjectionSourceEmissionDiagnosis": "- Stage1A19 should classify injection emission as no-source-activity, FIFO-buffered without stage1-valid, source-progress without stage1-valid, stage1-valid without fire, stage1-valid blocked by ready, overflow, or stage1-fire reestablished, and must not interpret ACL, classifier, PBM, bridge, DMA, backend, or Stage 2 behavior.",
        "Stage1A20_InjectionSourceArmingDiagnosis": "- Stage1A20 should classify injection CSR hit, configuration validity, FIFO load, source FSM arming, stage1 valid/fire reestablishment, and must not interpret ACL, classifier, PBM, bridge, DMA, backend, or Stage 2 behavior.",
        "Stage1A21_PBMReadyGatingDiagnosis": "- Stage1A21 should classify PBM ready-low as full/pointer-gap inferred, full without idle-gap, or state gating inferred, and must not interpret bridge, DMA, backend, or Stage 2 behavior.",
        "Stage1A22_PBMPointerResetOrDrainDiagnosis": "- Stage1A22 should classify whether soft reset clears the preexisting PBM pointer gap/read-side nonempty state and whether PBM write ready recovers afterward, without interpreting bridge, DMA, backend, or Stage 2 behavior.",
        "Stage1A23_PBMCommitTailPointerInvariantDiagnosis": "- Stage1A23 should classify whether the soft-reset idle pointer gap is a stable state/counter invariant or a changing state/pointer consistency issue, without interpreting bridge, DMA, backend, or Stage 2 behavior.",
        "Stage1A24_PBMResetDomainScopeDiagnosis": "- Stage1A24 should classify reset-domain scope using Stage1A23 invariant evidence and static RTL wiring, without interpreting bridge, DMA, backend, or Stage 2 behavior.",
        "Stage1A25_PBMResetDomainRemediationPlan": "- Stage1A25 should produce an engineering remediation plan only; it must not claim recovery evidence or alter the paper-ready gate.",
    }
    expected_behavior = expected_behaviors.get(
        args.stage,
        "- Dry run should validate probe_window_id, raw-log alignment, grouped burst stats, and next-stage routing."
        if args.stage1a_run_kind == "dry_run"
        else "- Full Stage 1A should determine whether backend activity scales with burst pressure.",
    )
    included_line = (
        f"- Sanity pass counts: {json.dumps(sanity_pass_counts, sort_keys=True)}"
        if args.stage == "Stage0_Sanity"
        else (
            f"- Included audit samples: {stats.get('included_in_stats_count')}"
            if args.stage == "Stage1A_DropPulseAudit"
            else (
                f"- Included reproduction samples: {stats.get('included_in_stats_count')}"
                if args.stage == "Stage1A6_PriorDropPulseReproduction"
                else (
                    f"- Included condition-diff samples: {stats.get('included_in_stats_count')}"
                    if args.stage == "Stage1A7_DropPulseConditionDiffDiagnosis"
                    else (
                        f"- Included bridge-output-fifo visibility samples: {stats.get('included_in_stats_count')}"
                        if args.stage == "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis"
                        else (
                        f"- Included DMA-start-path samples: {stats.get('included_in_stats_count')}"
                        if args.stage == "Stage1A13_DMAStartPathDiagnosis"
                        else (
                        f"- Included crypto-ingress visibility samples: {stats.get('included_in_stats_count')}"
                        if args.stage == "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis"
                        else f"- Included crypto-DMA handoff samples: {stats.get('included_in_stats_count')}"
                        if args.stage == "Stage1A10_CryptoDMAHandoffDiagnosis"
                        else f"- Included PBM-read-side visibility samples: {stats.get('included_in_stats_count')}"
                        if args.stage == "Stage1A11_PBMReadSideVisibilityDiagnosis"
                        else f"- Included PBM-commit reproduction samples: {stats.get('included_in_stats_count')}"
                        if args.stage == "Stage1A17_PBMCommitReproductionDiagnosis"
                        else f"- Included upstream-ingress visibility samples: {stats.get('included_in_stats_count')}"
                        if args.stage == "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis"
                        else f"- Included injection-source emission samples: {stats.get('included_in_stats_count')}"
                        if args.stage == "Stage1A19_InjectionSourceEmissionDiagnosis"
                        else f"- Included injection-source arming samples: {stats.get('included_in_stats_count')}"
                        if args.stage == "Stage1A20_InjectionSourceArmingDiagnosis"
                        else f"- Included PBM ready-gating samples: {stats.get('included_in_stats_count')}"
                        if args.stage == "Stage1A21_PBMReadyGatingDiagnosis"
                        else f"- Included PBM pointer-reset-or-drain samples: {stats.get('included_in_stats_count')}"
                        if args.stage == "Stage1A22_PBMPointerResetOrDrainDiagnosis"
                        else f"- Included PBM commit-tail pointer-invariant samples: {stats.get('included_in_stats_count')}"
                        if args.stage == "Stage1A23_PBMCommitTailPointerInvariantDiagnosis"
                        else f"- Included PBM-visibility samples: {stats.get('included_in_stats_count')}"
                        if args.stage == "Stage1A8_PBMIngressVisibilityDiagnosis"
                        else f"- Included burst groups: {len(stats.get('grouped_by_burst_frames_ordered', []))}"
                        )
                        )
                    )
                )
            )
        )
    )
    next_action = (
        "- Continue staged burst/noise/fault exploration only if Stage 0 remains reproducible."
        if args.stage == "Stage0_Sanity"
        else (
            f"- recommended_next_stage: {audit_decision.get('recommended_next_stage') if audit_decision else 'rerun_stage1a_drop_pulse_audit_due_to_inconclusive'}"
            if args.stage == "Stage1A_DropPulseAudit"
            else (
                f"- recommended_next_stage: {reproduction_decision.get('recommended_next_stage') if reproduction_decision else 'rerun_stage1a6_due_to_inconclusive'}"
                if args.stage == "Stage1A6_PriorDropPulseReproduction"
                else (
                    f"- recommended_next_stage: {stage1a7_decision.get('recommended_next_stage') if stage1a7_decision else 'FixStatusDecodeOrSampling'}"
                    if args.stage == "Stage1A7_DropPulseConditionDiffDiagnosis"
                    else (
                        f"- recommended_next_stage: {stage1a12_decision.get('recommended_next_stage') if stage1a12_decision else 'rerun_stage1a12_due_to_inconclusive'}"
                        if args.stage == "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis"
                        else (
                        f"- recommended_next_stage: {stage1a13_decision.get('recommended_next_stage') if stage1a13_decision else 'rerun_stage1a13_due_to_inconclusive'}"
                        if args.stage == "Stage1A13_DMAStartPathDiagnosis"
                        else (
                        f"- recommended_next_stage: {stage1a9_decision.get('recommended_next_stage') if stage1a9_decision else 'rerun_stage1a9_due_to_inconclusive'}"
                        if args.stage == "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis"
                        else f"- recommended_next_stage: {stage1a10_decision.get('recommended_next_stage') if stage1a10_decision else 'rerun_stage1a10_due_to_inconclusive'}"
                        if args.stage == "Stage1A10_CryptoDMAHandoffDiagnosis"
                        else f"- recommended_next_stage: {stage1a11_decision.get('recommended_next_stage') if stage1a11_decision else 'rerun_stage1a11_due_to_inconclusive'}"
                        if args.stage == "Stage1A11_PBMReadSideVisibilityDiagnosis"
                        else f"- recommended_next_stage: {stage1a17_decision.get('recommended_next_stage') if stage1a17_decision else 'rerun_stage1a17_due_to_inconclusive'}"
                        if args.stage == "Stage1A17_PBMCommitReproductionDiagnosis"
                        else f"- recommended_next_stage: {stage1a18_decision.get('recommended_next_stage') if stage1a18_decision else 'rerun_stage1a18_due_to_inconclusive'}"
                        if args.stage == "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis"
                        else f"- recommended_next_stage: {stage1a19_decision.get('recommended_next_stage') if stage1a19_decision else 'rerun_stage1a19_due_to_inconclusive'}"
                        if args.stage == "Stage1A19_InjectionSourceEmissionDiagnosis"
                        else f"- recommended_next_stage: {stage1a20_decision.get('recommended_next_stage') if stage1a20_decision else 'rerun_stage1a20_due_to_inconclusive'}"
                        if args.stage == "Stage1A20_InjectionSourceArmingDiagnosis"
                        else f"- recommended_next_stage: {stage1a21_decision.get('recommended_next_stage') if stage1a21_decision else 'rerun_stage1a21_due_to_inconclusive'}"
                        if args.stage == "Stage1A21_PBMReadyGatingDiagnosis"
                        else f"- recommended_next_stage: {stage1a22_decision.get('recommended_next_stage') if stage1a22_decision else 'rerun_stage1a22_due_to_inconclusive'}"
                        if args.stage == "Stage1A22_PBMPointerResetOrDrainDiagnosis"
                        else f"- recommended_next_stage: {stage1a23_decision.get('recommended_next_stage') if stage1a23_decision else 'rerun_stage1a23_due_to_inconclusive'}"
                        if args.stage == "Stage1A23_PBMCommitTailPointerInvariantDiagnosis"
                        else f"- recommended_next_stage: {stage1a8_decision.get('recommended_next_stage') if stage1a8_decision else 'rerun_pbm_ingress_visibility_due_to_inconclusive'}"
                        if args.stage == "Stage1A8_PBMIngressVisibilityDiagnosis"
                        else f"- recommended_next_stage: {stage1a_decision.get('recommended_next_stage') if stage1a_decision else 'rerun_stage1a_due_to_inconclusive'}"
                        )
                        )
                    )
                )
            )
        )
    )
    if stage1a14_decision:
        stage_objective = "Verify whether the probe explicit start write reaches axil_csr.o_start and the downstream DMA start chain."
        expected_behavior = "- Stage1A14 should classify the explicit start write path at AXI-Lite CSR hit, csr_start generation, final_start selection, DMA activation, or rd_en gating."
        included_line = f"- Included start-pulse injection samples: {stats.get('included_in_stats_count')}"
        observed_rate_line = f"- axil_write_hit_start_seen: {str(stage1a14_decision.get('axil_write_hit_start_seen')).lower()}"
        next_action = f"- recommended_next_stage: {stage1a14_decision.get('recommended_next_stage') if stage1a14_decision else 'rerun_start_pulse_injection_due_to_inconclusive'}"
    if stage1a15_decision:
        stage_objective = "Integrate the verified DMA CSR explicit start with the bridge/FIFO data reproduction window and classify the start-to-bridge handoff."
        expected_behavior = "- Stage1A15 should determine whether explicit DMA start and bridge/FIFO nonempty state appear in the same row, then route to rd_en, bridge accept, crypto DMA accept, backend input, or recovery coupling diagnosis."
        included_line = f"- Included explicit-start bridge handoff samples: {stats.get('included_in_stats_count')}"
        observed_rate_line = f"- row_level_start_and_bridge_nonempty_seen: {str(stage1a15_decision.get('row_level_start_and_bridge_nonempty_seen')).lower()}"
        next_action = f"- recommended_next_stage: {stage1a15_decision.get('recommended_next_stage') if stage1a15_decision else 'rerun_stage1a15_due_to_inconclusive'}"
    if stage1a16_decision:
        stage_objective = "Replay the Stage1A12 bridge/FIFO data-production baseline and evaluate explicit-start handoff only in the A15 replay config."
        expected_behavior = "- Stage1A16 should stop at the baseline gate if A12_NoStart_Replay does not reproduce bridge nonempty, and must not use stage-level any to trigger rd_en gating."
        included_line = f"- Included bridge-data-production samples: {stats.get('included_in_stats_count')}"
        observed_rate_line = f"- baseline_bridge_reproduced: {str(stage1a16_decision.get('baseline_bridge_reproduced')).lower()}"
        next_action = f"- recommended_next_stage: {stage1a16_decision.get('recommended_next_stage') if stage1a16_decision else 'rerun_stage1a16_due_to_inconclusive'}"
    if stage1a17_decision:
        stage_objective = "Replay the closest PBM commit-positive BF64 condition and classify the PBM write/FSM/pointer boundary before bridge or DMA interpretation."
        expected_behavior = "- Stage1A17 should stop at PBM ingress/FSM/pointer evidence and must not interpret bridge, DMA, backend, or Stage 2 behavior."
        included_line = f"- Included PBM-commit reproduction samples: {stats.get('included_in_stats_count')}"
        observed_rate_line = f"- pbm_commit_reproduction_classification: {stage1a17_decision.get('pbm_commit_reproduction_classification')}"
        next_action = f"- recommended_next_stage: {stage1a17_decision.get('recommended_next_stage') if stage1a17_decision else 'rerun_stage1a17_due_to_inconclusive'}"
    if stage1a26_decision:
        stage_objective = "Expose bridge_tx_rd_en equation inputs and classify the DMA-layer rd_en gap without changing datapath behavior."
        expected_behavior = "- Stage1A26 should stop at DMA rd_en equation evidence and route to loopback-mode, TX ready, normal request, instrumentation, bridge accept, or crypto DMA handoff diagnosis."
        included_line = f"- Included DMA rd_en equation samples: {stats.get('included_in_stats_count')}"
        observed_rate_line = f"- dma_rd_en_equation_classification: {stage1a26_decision.get('dma_rd_en_equation_classification')}"
        next_action = f"- recommended_next_stage: {stage1a26_decision.get('recommended_next_stage') if stage1a26_decision else 'rerun_stage1a26_due_to_inconclusive'}"
    if stage1a18_decision:
        stage_objective = "Classify whether activity reaches stage1 fire, ACL fire, classifier DMA visibility, crypto RX, or PBM valid before any bridge or DMA interpretation."
        expected_behavior = "- Stage1A18 should stop at ingress-to-PBM evidence and must not interpret bridge, DMA, backend, or Stage 2 behavior."
        included_line = f"- Included upstream-ingress visibility samples: {stats.get('included_in_stats_count')}"
        observed_rate_line = f"- upstream_ingress_to_pbm_classification: {stage1a18_decision.get('upstream_ingress_to_pbm_classification')}"
        next_action = f"- recommended_next_stage: {stage1a18_decision.get('recommended_next_stage') if stage1a18_decision else 'rerun_stage1a18_due_to_inconclusive'}"
    if stage1a19_decision:
        stage_objective = "Classify whether the injection source arms, buffers data, emits stage1 valid, stalls on stage1 ready, or re-establishes stage1 fire before any downstream interpretation."
        expected_behavior = "- Stage1A19 should stop at injection-source emission evidence and must not interpret ACL, classifier, PBM, bridge, DMA, backend, or Stage 2 behavior."
        included_line = f"- Included injection-source emission samples: {stats.get('included_in_stats_count')}"
        observed_rate_line = f"- injection_source_emission_classification: {stage1a19_decision.get('injection_source_emission_classification')}"
        next_action = f"- recommended_next_stage: {stage1a19_decision.get('recommended_next_stage') if stage1a19_decision else 'rerun_stage1a19_due_to_inconclusive'}"
    if stage1a20_decision:
        stage_objective = "Confirm whether the injection source is actually armed/configured, loads FIFO data, enters an active/emitting state, and re-establishes stage1 fire."
        expected_behavior = "- Stage1A20 should stop at injection-source arming/configuration evidence and must not interpret ACL, classifier, PBM, bridge, DMA, backend, or Stage 2 behavior."
        included_line = f"- Included injection-source arming samples: {stats.get('included_in_stats_count')}"
        observed_rate_line = f"- injection_source_arming_classification: {stage1a20_decision.get('injection_source_arming_classification')}"
        next_action = f"- recommended_next_stage: {stage1a20_decision.get('recommended_next_stage') if stage1a20_decision else 'rerun_stage1a20_due_to_inconclusive'}"
    if stage1a21_decision:
        stage_objective = "Determine whether PBM write ready stays low because full is inferred, because PBM state blocks it, or because a preexisting pointer gap already exists before workload."
        expected_behavior = "- Stage1A21 should stop at PBM ready-low inference and must not interpret bridge, DMA, backend, or Stage 2 behavior."
        included_line = f"- Included PBM ready-gating samples: {stats.get('included_in_stats_count')}"
        observed_rate_line = f"- pbm_ready_gating_classification: {stage1a21_decision.get('pbm_ready_gating_classification')}"
        next_action = f"- recommended_next_stage: {stage1a21_decision.get('recommended_next_stage') if stage1a21_decision else 'rerun_stage1a21_due_to_inconclusive'}"
    if stage1a22_decision:
        stage_objective = "Determine whether DMA soft reset or restore clears the preexisting PBM commit-tail gap/read-side nonempty state and whether PBM write ready recovers after reset."
        expected_behavior = "- Stage1A22 should stop at PBM pointer/reset-or-drain evidence and must not interpret bridge, DMA, backend, or Stage 2 behavior."
        included_line = f"- Included PBM pointer-reset-or-drain samples: {stats.get('included_in_stats_count')}"
        observed_rate_line = f"- pbm_pointer_reset_or_drain_classification: {stage1a22_decision.get('pbm_pointer_reset_or_drain_classification')}"
        next_action = f"- recommended_next_stage: {stage1a22_decision.get('recommended_next_stage') if stage1a22_decision else 'rerun_stage1a22_due_to_inconclusive'}"
    if stage1a23_decision:
        stage_objective = "Determine whether the PBM commit-tail pointer gap and read-side nonempty counters remain invariant across idle soft-reset snapshots."
        expected_behavior = "- Stage1A23 should stop at PBM commit-tail invariant evidence and must not interpret bridge, DMA, backend, or Stage 2 behavior."
        included_line = f"- Included PBM commit-tail pointer-invariant samples: {stats.get('included_in_stats_count')}"
        observed_rate_line = f"- pbm_commit_tail_pointer_invariant_classification: {stage1a23_decision.get('pbm_commit_tail_pointer_invariant_classification')}"
        next_action = f"- recommended_next_stage: {stage1a23_decision.get('recommended_next_stage') if stage1a23_decision else 'rerun_stage1a23_due_to_inconclusive'}"
    if stage1a24_decision:
        stage_objective = "Determine whether Stage1A23's persistent PBM commit-tail invariant is explained by PBM state/pointers being outside the DMA soft-reset domain."
        expected_behavior = "- Stage1A24 should stop at reset-domain scope evidence and must not interpret bridge, DMA, backend, or Stage 2 behavior."
        included_line = f"- Included PBM reset-domain scope samples: {stats.get('included_in_stats_count')}"
        observed_rate_line = f"- pbm_reset_domain_scope_classification: {stage1a24_decision.get('pbm_reset_domain_scope_classification')}"
        next_action = f"- recommended_next_stage: {stage1a24_decision.get('recommended_next_stage') if stage1a24_decision else 'rerun_stage1a24_due_to_inconclusive'}"
    if stage1a25_decision:
        stage_objective = "Select a constrained PBM reset-domain remediation path from Stage1A24 evidence before changing RTL."
        expected_behavior = "- Stage1A25 should recommend a diagnostic remediation path only and must not open the paper-ready recovery gate."
        included_line = f"- Included PBM reset-domain remediation samples: {stats.get('included_in_stats_count')}"
        observed_rate_line = f"- selected_remediation: {stage1a25_decision.get('selected_remediation')}"
        next_action = f"- recommended_next_stage: {stage1a25_decision.get('recommended_next_stage') if stage1a25_decision else 'rerun_stage1a25_due_to_inconclusive'}"
    failure_reason = negative_type if (not rollback_recovery_seen or audit_decision or reproduction_decision or stage1a7_decision or stage1a8_decision or stage1a9_decision or stage1a10_decision or stage1a11_decision or stage1a12_decision or stage1a13_decision or stage1a14_decision or stage1a15_decision or stage1a16_decision or stage1a17_decision or stage1a26_decision or stage1a27_decision or stage1a18_decision or stage1a19_decision or stage1a20_decision or stage1a21_decision or stage1a22_decision or stage1a23_decision or stage1a24_decision or stage1a25_decision) else "none"

    return "\n".join(
        [
            f"# {args.stage} Stage Report",
            "",
            "## Stage objective",
            stage_objective,
            "",
            "## Executed configurations",
            f"- TrafficMode: {args.traffic_mode}",
            f"- FaultMode: {args.fault_mode}",
            f"- FaultRatio: {args.fault_ratio}",
            f"- BurstFrames: {args.burst_frames}",
            f"- BurstGapUs: {args.burst_gap_us}",
            f"- SettleMs: {args.settle_ms}",
            "",
            "## Expected behavior",
            expected_behavior,
            "",
            "## Observed behavior",
            f"- Stage status: {status}",
            included_line,
            observed_rate_line,
            f"- Negative result type: {negative_type}",
            *stage1a_lines,
            *audit_lines,
            *reproduction_lines,
            *stage1a7_lines,
            *stage1a8_lines,
            *stage1a9_lines,
            *stage1a10_lines,
            *stage1a11_lines,
            *stage1a12_lines,
            *stage1a13_lines,
            *stage1a14_lines,
            *stage1a15_lines,
            *stage1a16_lines,
            *stage1a17_lines,
            *stage1a26_lines,
            *stage1a27_lines,
            *stage1a18_lines,
            *stage1a19_lines,
            *stage1a20_lines,
            *stage1a21_lines,
            *stage1a22_lines,
            *stage1a23_lines,
            *stage1a24_lines,
            *stage1a25_lines,
            "",
            "## Monitored diagnostic counters",
            f"- rollback/recovery counters: {', '.join(ROLLBACK_RECOVERY_COUNTERS)}",
            f"- front-end pressure counters: {', '.join(FRONTEND_PRESSURE_COUNTERS)}",
            f"- backend service counters: {', '.join(BACKEND_SERVICE_COUNTERS)}",
            f"Nonzero front-end pressure counters: {', '.join(nonzero_frontend_pressure_counters) if nonzero_frontend_pressure_counters else 'none'}",
            f"Nonzero rollback/recovery counters: {', '.join(nonzero_rollback_recovery_counters) if nonzero_rollback_recovery_counters else 'none'}",
            f"Nonzero backend service counters: {', '.join(nonzero_backend_service_counters) if nonzero_backend_service_counters else 'none'}",
            "",
            "## Backend activity summary",
            json.dumps(stats.get("metrics", {}), indent=2, sort_keys=True),
            "",
            "## Failure reasons",
            f"- failure_reason: {failure_reason}",
            "",
            "## Limitations",
            "- This report describes the current probe window and does not imply normal-path recovery unless candidate_for_paper_evidence is yes.",
            "- Known unrelated release-test failures: legacy/handoff assets and existing py.exe contract assumptions. These failures are tracked separately and are not considered blockers for current engineering diagnosis.",
            "",
            "## Next action",
            next_action,
            "",
            "## Candidate value for paper evidence",
            f"- candidate_for_paper_evidence: {candidate}",
            f"- why_it_is_or_is_not_candidate: {reason}",
            "",
            "## Paper Mapping",
            "- Relevant paper claim: front-end recovery evidence and backend utilization must remain separated until recovery counters are nonzero.",
            f"- Allowed use in paper: {allowed_use_in_paper}",
            "",
            "## Evidence Risk",
            f"- {evidence_risk}: {'recovery evidence is not yet stable' if evidence_risk == 'high' else 'requires repeat confirmation'}",
            "",
        ]
    )


def write_minimal_png(path: Path, rows: list[dict[str, Any]], title: str) -> None:
    width, height = 960, 540
    pixels = bytearray()
    max_value = max([float(row.get("backend_accept_cycles", 0) or 0) for row in rows] + [1.0])
    bar_width = max(20, width // max(1, len(rows) * 3))
    for y in range(height):
        pixels.append(0)
        for x in range(width):
            r, g, b = 255, 255, 255
            if y < 40:
                r, g, b = 238, 242, 247
            for idx, row in enumerate(rows):
                value = float(row.get("backend_accept_cycles", 0) or 0)
                bar_h = int((height - 120) * value / max_value)
                x0 = 80 + idx * bar_width * 3
                if x0 <= x < x0 + bar_width and height - 60 - bar_h <= y < height - 60:
                    r, g, b = 40, 96, 160
            if x in (60, 61) and 60 <= y <= height - 60:
                r, g, b = 0, 0, 0
            if y in (height - 60, height - 59) and 60 <= x <= width - 40:
                r, g, b = 0, 0, 0
            pixels.extend((r, g, b))
    raw = bytes(pixels)
    compressor = zlib.compressobj()
    compressed = compressor.compress(raw) + compressor.flush()
    with path.open("wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        write_png_chunk(handle, b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        write_png_chunk(handle, b"tEXt", f"Title\x00{title}".encode("latin1", errors="ignore"))
        write_png_chunk(handle, b"IDAT", compressed)
        write_png_chunk(handle, b"IEND", b"")


def write_png_chunk(handle, chunk_type: bytes, data: bytes) -> None:
    handle.write(struct.pack(">I", len(data)))
    handle.write(chunk_type)
    handle.write(data)
    crc = zlib.crc32(chunk_type)
    crc = zlib.crc32(data, crc)
    handle.write(struct.pack(">I", crc & 0xFFFFFFFF))


def write_plot_html(path: Path, rows: list[dict[str, Any]], title: str) -> None:
    rows_json = json.dumps(rows, indent=2)
    path.write_text(
        f"""<!doctype html>
<html><head><meta charset="utf-8"><title>{title}</title></head>
<body>
<h1>{title}</h1>
<p>TrafficMode/FaultMode/FaultRatio/fault_severity_value/BurstFrames/BurstGapUs are embedded in the table below.</p>
<pre id="data">{rows_json}</pre>
</body></html>
""",
        encoding="utf-8",
    )


def write_plots(output_dir: Path, rows: list[dict[str, Any]]) -> list[Path]:
    plots_dir = output_dir / "plots"
    plots_dir.mkdir(parents=True, exist_ok=True)
    plot_names = [
        "plot_recovery_trigger_rate",
        "plot_recovery_window_vs_mode",
        "plot_tail_latency_cdf",
        "plot_recovery_time_vs_latency",
        "plot_backend_effective_work_ratio",
        "plot_burst_heatmap",
    ]
    paths: list[Path] = []
    for name in plot_names:
        png_path = plots_dir / f"{name}.png"
        html_path = plots_dir / f"{name}.html"
        write_minimal_png(png_path, rows, name)
        write_plot_html(html_path, rows, name)
        paths.extend([png_path, html_path])
    return paths


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary-json", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--probe-script", required=True)
    parser.add_argument("--clock-hz", type=int, default=50_000_000)
    parser.add_argument("--repeat-count", type=int, default=1)
    parser.add_argument("--stage", default="Stage0_Sanity")
    parser.add_argument("--traffic-mode", default="fixed")
    parser.add_argument("--fault-mode", default="none")
    parser.add_argument("--fault-ratio", type=float, default=0.0)
    parser.add_argument("--noise-pattern", default="none")
    parser.add_argument("--burst-frames", type=int, default=1)
    parser.add_argument("--burst-gap-us", type=float, default=0.0)
    parser.add_argument("--settle-ms", type=float, default=500.0)
    parser.add_argument("--frame-size", type=int, default=76)
    parser.add_argument("--load-class", default="baseline")
    parser.add_argument("--random-seed", type=int, default=20260423)
    parser.add_argument("--fault-schedule-seed", type=int, default=20260423)
    parser.add_argument("--fault-severity-value", default="")
    parser.add_argument("--fault-severity-unit", default="null", choices=sorted(ALLOWED_FAULT_SEVERITY_UNITS))
    parser.add_argument("--fault-severity-note", default="")
    parser.add_argument("--experiment-plan-version", default=EXPERIMENT_PLAN_VERSION)
    parser.add_argument("--stage1a-baseline-source", default="not_applicable")
    parser.add_argument("--stage1a-run-kind", default="not_applicable")
    parser.add_argument("--reproduction-mode", default="controlled_sampling_replay")
    parser.add_argument("--stage1a6-reference-stage1a-full-dir", default="")
    parser.add_argument("--stage1a6-reference-stage1a5-audit-dir", default="")
    parser.add_argument("--xsct-path", default="")
    parser.add_argument("--vivado-version", default="")
    parser.add_argument("--vitis-version", default="")
    parser.add_argument("--boot-mode", default="SD")
    parser.add_argument("--boot-source", default="SD_BOOT_BIN")
    parser.add_argument("--active-pl-programming", default="workspace_bit_path")
    parser.add_argument("--active-ps-programming", default="sd_boot_runtime")
    parser.add_argument("--active-bit-path", default="")
    parser.add_argument("--active-xsa-path", default="")
    parser.add_argument("--port", default="COM9")
    parser.add_argument("--baud", default="115200")
    parser.add_argument("--boot-bin", default="")
    parser.add_argument("--bit-file", default="")
    parser.add_argument("--xsa-file", default="")
    args = parser.parse_args()

    summary_path = Path(args.summary_json)
    output_root = Path(args.output_root)
    repo_root = Path(args.repo_root)
    summary = json.loads(summary_path.read_text(encoding="utf-8-sig"))

    rows = make_case_rows(summary, args)
    case_results_path = output_root / "case_results.csv"
    stats_path = output_root / "summary_stats.json"
    manifest_path = output_root / "run_manifest.json"
    stage_report_path = output_root / "stage_report.md"
    experiment_report_path = output_root / "experiment_report.md"
    artifact_hashes_path = output_root / "artifact_hashes.json"

    write_csv(case_results_path, rows)
    stats = build_stats(rows, args)
    write_json(stats_path, stats)
    manifest = build_manifest(summary, args, repo_root, rows)
    write_json(manifest_path, manifest)
    stage_report = build_stage_report(rows, stats, args)
    stage_report_path.write_text(stage_report, encoding="utf-8")
    experiment_report_path.write_text(stage_report.replace("Stage Report", "Experiment Report", 1), encoding="utf-8")
    plot_paths = write_plots(output_root, rows)

    artifact_paths = [
        manifest_path,
        case_results_path,
        stats_path,
        stage_report_path,
        experiment_report_path,
        summary_path,
        Path(summary.get("xsct_log", "")),
        Path(summary.get("xsct_script", "")),
        Path(summary.get("uart_log", "")),
        *plot_paths,
    ]
    artifact_hashes = {
        "manifest_schema_version": MANIFEST_SCHEMA_VERSION,
        "experiment_plan_version": args.experiment_plan_version,
        "artifacts": [file_record(path, repo_root) for path in artifact_paths if str(path)],
    }
    write_json(artifact_hashes_path, artifact_hashes)

    print(
        json.dumps(
            {
                "run_manifest": str(manifest_path),
                "artifact_hashes": str(artifact_hashes_path),
                "case_results": str(case_results_path),
                "summary_stats": str(stats_path),
                "stage_report": str(stage_report_path),
                "experiment_report": str(experiment_report_path),
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
