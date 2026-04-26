#!/usr/bin/env python3
"""Autonomous control-plane runner for Shadow-Mirror data acquisition."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
DEFAULT_REGISTRY = REPO_ROOT / "HCS_SOC" / "shadow_pipeline" / "stage_registry.json"
DEFAULT_STATE_TEMPLATE = REPO_ROOT / "HCS_SOC" / "shadow_pipeline" / "current_state.template.json"
DEFAULT_STATE = REPO_ROOT / "doc" / "reports" / "engineering_evidence" / "pipeline_state" / "current_state.json"
DEFAULT_XSCT = Path("D:/Xilinx/Vitis/2024.1/bin/xsct.bat")
PIPELINE_STATE_DIR = REPO_ROOT / "doc" / "reports" / "engineering_evidence" / "pipeline_state"
FEATURE_MASK_PREFLIGHT_ARTIFACT = PIPELINE_STATE_DIR / "diagnostic_feature_mask_preflight.json"
FEATURE_MASK_PREFLIGHT_TCL = PIPELINE_STATE_DIR / "diagnostic_feature_mask_preflight.tcl"
PAPER_CANDIDATE_EXPORT_ARTIFACT = PIPELINE_STATE_DIR / "paper_candidate_export.json"
PAPER_FINAL_EXPORT_ARTIFACT = PIPELINE_STATE_DIR / "paper_final_export.json"
DIAGNOSTIC_CSR_BASE = 0x40001270
DIAGNOSTIC_BUILD_ID_ADDR = 0x40001270
DIAGNOSTIC_FEATURE_MASK_ADDR = 0x40001274
DIAGNOSTIC_REGISTRY_HASH_LOW_ADDR = 0x40001278
DIAGNOSTIC_REGISTRY_HASH_HIGH_ADDR = 0x4000127C
REQUIRED_DIAGNOSTIC_FEATURE_MASK = 0x000003FF
FEATURE_MASK_BITS = {
    0: "PBM_SOFT_RESET",
    1: "PBM_READY_REASON",
    2: "PBM_INGRESS_DIAG",
    3: "PBM_READ_SIDE_DIAG",
    4: "BRIDGE_FIFO_DIAG",
    5: "DMA_START_DIAG",
    6: "AXIL_WRITE_HIT",
    7: "INJECTION_SOURCE_DIAG",
    8: "DMA_RD_EN_EQUATION_DIAG",
    9: "INJECTION_ERROR_DIAG",
}

if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import shadow_pipeline_gates as gates  # noqa: E402
from day21_counter_snapshot_export import write_counter_artifacts  # noqa: E402


def load_json(path: str | Path) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def reconcile_runtime_state(state: dict[str, Any]) -> dict[str, Any]:
    updated = dict(state)
    if (
        updated.get("paper_candidate_collected")
        and not updated.get("paper_data_exported")
        and not updated.get("recovery_evidence_collected")
        and updated.get("recommended_next_stage") == "PaperDataFinalExport"
    ):
        recovery_gate = _paper_gate_met(updated.get("paper_ready_recovery_gate"))
        updated["recommended_next_stage"] = (
            "DropRollbackCouplingDiagnosis" if recovery_gate else "Stage2_ExtremeTraffic"
        )
        updated["failed_gate"] = "paper_candidate_collected" if recovery_gate else "paper_ready_recovery_gate"
    if (
        updated.get("last_stage") == "Stage2_ExtremeTraffic"
        and updated.get("terminal_blocker") == "repeated_same_failure_signature"
        and updated.get("recommended_next_stage") == "Stage2_ExtremeTraffic"
        and not updated.get("paper_ready_recovery_gate")
        and not updated.get("recovery_evidence_collected")
    ):
        updated["terminal_blocker"] = None
        updated["terminal_blocker_detail"] = None
        updated["recommended_next_stage"] = "Stage2_SyntheticFaultTraffic"
        updated["failed_gate"] = "paper_ready_recovery_gate"
    return updated


def load_or_initialize_state(state_path: str | Path, template_path: str | Path) -> dict[str, Any]:
    state = Path(state_path)
    if state.exists():
        loaded = load_json(state)
        reconciled = reconcile_runtime_state(loaded)
        if reconciled != loaded:
            write_state_atomic(state, reconciled, history_path=state.with_name("current_state.history.jsonl"))
        return reconciled
    template = load_json(template_path)
    write_state_atomic(state, template, history_path=state.with_name("current_state.history.jsonl"))
    return template


def write_state_atomic(path: str | Path, state: dict[str, Any], history_path: str | Path | None = None) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(f"{target.name}.tmp")
    payload = json.dumps(state, indent=2, sort_keys=False) + "\n"
    with tmp.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, target)
    if history_path is not None:
        history = Path(history_path)
        history.parent.mkdir(parents=True, exist_ok=True)
        event = dict(state)
        event["history_timestamp_utc"] = datetime.now(timezone.utc).isoformat()
        with history.open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(json.dumps(event, sort_keys=False) + "\n")
            handle.flush()
            os.fsync(handle.fileno())


def write_json_atomic(path: str | Path, payload: dict[str, Any]) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(f"{target.name}.tmp")
    with tmp.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(payload, indent=2, sort_keys=False) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, target)


def copy_artifact_if_exists(source: Path, destination_dir: Path) -> str | None:
    if not source.exists():
        return None
    destination_dir.mkdir(parents=True, exist_ok=True)
    target = destination_dir / source.name
    shutil.copy2(source, target)
    return str(target)


def resolve_source_run_dir(repo_root: Path, state: dict[str, Any]) -> Path | None:
    candidate = Path(str(state.get("last_run_dir") or ""))
    if candidate.exists() and (candidate / "summary_stats.json").exists():
        return candidate
    return find_latest_run_dir(repo_root / "doc" / "reports" / "engineering_evidence")


def _paper_gate_met(value: Any) -> bool:
    if isinstance(value, dict):
        return bool(value.get("met"))
    return bool(value)


def paper_candidate_export_artifact_path(repo_root: Path) -> Path:
    return repo_root / "doc" / "reports" / "engineering_evidence" / "pipeline_state" / "paper_candidate_export.json"


def paper_final_export_artifact_path(repo_root: Path) -> Path:
    return repo_root / "doc" / "reports" / "engineering_evidence" / "pipeline_state" / "paper_final_export.json"


def drop_rollback_coupling_artifact_path(repo_root: Path) -> Path:
    return repo_root / "doc" / "reports" / "engineering_evidence" / "pipeline_state" / "drop_rollback_coupling_diagnosis.json"


def export_paper_candidate(repo_root: Path, state: dict[str, Any]) -> dict[str, Any]:
    source_run_dir = resolve_source_run_dir(repo_root, state)
    if source_run_dir is None:
        payload = {
            "status": "fail",
            "recommended_next_stage": state.get("recommended_next_stage") or "Stage1A_EngineeringDataAcquisition",
            "reason": "missing_source_run_dir",
        }
        write_json_atomic(paper_candidate_export_artifact_path(repo_root), payload)
        return payload

    summary, manifest = load_stage_outputs(source_run_dir)
    throughput_gate = gates.evaluate_summary(
        summary=summary,
        current_state=state,
        registry_entry={
            "stage": "Stage1A_EngineeringDataAcquisition",
            "gate": "engineering_data_collected",
            "phase": "paper_candidate",
        },
        manifest=manifest,
    ).get("paper_ready_throughput_gate", False)
    recovery_gate = _paper_gate_met(summary.get("paper_ready_recovery_gate")) or _paper_gate_met(
        state.get("paper_ready_recovery_gate")
    )
    if not (throughput_gate or recovery_gate):
        payload = {
            "status": "fail",
            "recommended_next_stage": summary.get("stage1a_decision", {}).get("recommended_next_stage") or "Stage2_ExtremeTraffic",
            "reason": "paper_candidate_gate_not_met",
            "source_run_dir": str(source_run_dir),
        }
        write_json_atomic(paper_candidate_export_artifact_path(repo_root), payload)
        return payload

    output_dir = repo_root / "doc" / "reports" / "paper_plot_data_candidate" / source_run_dir.name
    output_dir.mkdir(parents=True, exist_ok=True)
    snapshot = summary.get("csr_baseline") if isinstance(summary.get("csr_baseline"), dict) else {}
    if not snapshot:
        snapshot = manifest.get("csr_baseline") if isinstance(manifest.get("csr_baseline"), dict) else {}
    clock_hz = int(manifest.get("case_parameters", {}).get("clock_hz") or 50_000_000)
    exported = write_counter_artifacts(snapshot, output_dir, clock_hz=clock_hz) if snapshot else {}

    copied = {}
    for filename in ("summary_stats.json", "case_results.csv", "run_manifest.json", "stage_report.md"):
        copied_path = copy_artifact_if_exists(source_run_dir / filename, output_dir)
        if copied_path:
            copied[filename] = copied_path

    write_json_atomic(
        output_dir / "candidate_export_manifest.json",
        {
            "source_run_dir": str(source_run_dir),
            "throughput_gate_met": bool(throughput_gate),
            "recovery_gate_met": bool(recovery_gate),
            "active_bit_sha256": manifest.get("board", {}).get("active_bit_sha256"),
            "active_xsa_sha256": manifest.get("board", {}).get("active_xsa_sha256"),
            "exported_at_utc": datetime.now(timezone.utc).isoformat(),
        },
    )
    payload = {
        "status": "pass",
        "output_dir": str(output_dir),
        "recommended_next_stage": "DropRollbackCouplingDiagnosis" if recovery_gate else "Stage2_ExtremeTraffic",
        "throughput_gate_met": bool(throughput_gate),
        "recovery_gate_met": bool(recovery_gate),
        "copied_artifacts": copied,
        "counter_artifacts": {name: str(path) for name, path in exported.items()},
    }
    write_json_atomic(paper_candidate_export_artifact_path(repo_root), payload)
    return payload


def export_paper_final(repo_root: Path, state: dict[str, Any]) -> dict[str, Any]:
    candidate_dir = Path(str(state.get("paper_candidate_dir") or ""))
    candidate_artifact = paper_candidate_export_artifact_path(repo_root)
    if not candidate_dir.exists() and candidate_artifact.exists():
        candidate_dir = Path(str(load_json(candidate_artifact).get("output_dir") or ""))
    if not candidate_dir.exists():
        payload = {
            "status": "fail",
            "reason": "missing_paper_candidate_dir",
            "recommended_next_stage": "PaperDataCandidateExport",
        }
        write_json_atomic(paper_final_export_artifact_path(repo_root), payload)
        return payload

    final_dir = repo_root / "doc" / "reports" / "paper_plot_data" / candidate_dir.name
    if final_dir.exists():
        shutil.rmtree(final_dir)
    shutil.copytree(candidate_dir, final_dir)
    payload = {
        "status": "pass",
        "output_dir": str(final_dir),
        "recommended_next_stage": "PaperDataFinalExport",
    }
    write_json_atomic(paper_final_export_artifact_path(repo_root), payload)
    return payload


def run_drop_rollback_coupling_diagnosis(repo_root: Path, state: dict[str, Any]) -> dict[str, Any]:
    source_run_dir = resolve_source_run_dir(repo_root, state)
    if source_run_dir is None:
        payload = {
            "status": "fail",
            "reason": "missing_source_run_dir",
            "recommended_next_stage": state.get("recommended_next_stage") or "Stage2_ExtremeTraffic",
        }
        write_json_atomic(drop_rollback_coupling_artifact_path(repo_root), payload)
        return payload

    summary, manifest = load_stage_outputs(source_run_dir)
    recovery_gate = _paper_gate_met(summary.get("paper_ready_recovery_gate")) or _paper_gate_met(
        state.get("paper_ready_recovery_gate")
    )
    rollback_recovery_seen = bool(summary.get("rollback_recovery_seen")) or any(
        bool(summary.get(field)) for field in ("rollback_event_count", "recovery_active_cycles")
    )
    payload = {
        "status": "pass" if (recovery_gate and rollback_recovery_seen) else "partial",
        "source_run_dir": str(source_run_dir),
        "recovery_gate_met": bool(recovery_gate),
        "rollback_recovery_seen": bool(rollback_recovery_seen),
        "rollback_event_count": int(summary.get("rollback_event_count") or 0),
        "recovery_active_cycles": int(summary.get("recovery_active_cycles") or 0),
        "active_bit_sha256": manifest.get("board", {}).get("active_bit_sha256"),
        "active_xsa_sha256": manifest.get("board", {}).get("active_xsa_sha256"),
        "recommended_next_stage": "PaperDataCandidateExport" if recovery_gate else "Stage2_ExtremeTraffic",
    }
    write_json_atomic(drop_rollback_coupling_artifact_path(repo_root), payload)
    return payload


def _hex32(value: int) -> str:
    return f"0x{value & 0xFFFFFFFF:08X}"


def render_diagnostic_feature_mask_preflight_tcl() -> str:
    reads = [
        DIAGNOSTIC_BUILD_ID_ADDR,
        DIAGNOSTIC_FEATURE_MASK_ADDR,
        DIAGNOSTIC_REGISTRY_HASH_LOW_ADDR,
        DIAGNOSTIC_REGISTRY_HASH_HIGH_ADDR,
    ]
    body = [
        "connect",
        "puts \"targets=[targets]\"",
        "proc select_ps_access_target {} {",
        "    foreach pattern [list \"*APU*\" \"*ARM Cortex-A9 MPCore #0*\" \"*Cortex-A9 MPCore #0*\" \"*PS7*\" \"*DAP*\"] {",
        "        if {![catch {targets -set -filter [format {name =~ \"%s\"} $pattern]}]} {",
        "            if {![catch {mrd -force -value 0x40000090}]} {",
        "                puts [format \"selected_target=%s\" $pattern]",
        "                return $pattern",
        "            }",
        "        }",
        "    }",
        "    if {![catch {mrd -force -value 0x40000090}]} {",
        "        puts \"selected_target=implicit_current_target\"",
        "        return \"implicit_current_target\"",
        "    }",
        "    error \"no PS-access target supports CSR memory read\"",
        "}",
        "select_ps_access_target",
        "proc rd32 {addr} { puts [format \"0x%08X: %08X\" $addr [mrd -force -value $addr]] }",
    ]
    for addr in reads:
        body.append(f"rd32 {_hex32(addr)}")
    body.append("puts \"DIAGNOSTIC_FEATURE_MASK_PREFLIGHT_DONE=1\"")
    body.append("exit")
    return "\n".join(body) + "\n"


def parse_diagnostic_feature_mask_preflight_output(xsct_output: str) -> dict[str, Any]:
    values: dict[int, int] = {}
    pattern = re.compile(r"(?:0x)?([0-9A-Fa-f]{8})\s*[:=]\s*(?:0x)?([0-9A-Fa-f]{8})")
    for match in pattern.finditer(xsct_output):
        addr = int(match.group(1), 16)
        value = int(match.group(2), 16)
        values[addr] = value

    feature_mask = values.get(DIAGNOSTIC_FEATURE_MASK_ADDR, 0)
    return {
        "diagnostic_csr_base": _hex32(DIAGNOSTIC_CSR_BASE),
        "diagnostic_build_id": _hex32(values.get(DIAGNOSTIC_BUILD_ID_ADDR, 0)),
        "diagnostic_build_id_value": values.get(DIAGNOSTIC_BUILD_ID_ADDR, 0),
        "diagnostic_feature_mask": _hex32(feature_mask),
        "diagnostic_feature_mask_value": feature_mask,
        "diagnostic_registry_hash_low": _hex32(values.get(DIAGNOSTIC_REGISTRY_HASH_LOW_ADDR, 0)),
        "diagnostic_registry_hash_low_value": values.get(DIAGNOSTIC_REGISTRY_HASH_LOW_ADDR, 0),
        "diagnostic_registry_hash_high": _hex32(values.get(DIAGNOSTIC_REGISTRY_HASH_HIGH_ADDR, 0)),
        "diagnostic_registry_hash_high_value": values.get(DIAGNOSTIC_REGISTRY_HASH_HIGH_ADDR, 0),
        "feature_mask_bits": {
            name: bool(feature_mask & (1 << bit))
            for bit, name in FEATURE_MASK_BITS.items()
        },
        "raw_xsct_output": xsct_output,
    }


def evaluate_diagnostic_feature_mask_preflight(parsed: dict[str, Any]) -> dict[str, Any]:
    feature_mask = int(parsed.get("diagnostic_feature_mask_value", 0))
    missing = [
        name
        for bit, name in FEATURE_MASK_BITS.items()
        if REQUIRED_DIAGNOSTIC_FEATURE_MASK & (1 << bit) and not (feature_mask & (1 << bit))
    ]
    build_id_value = int(parsed.get("diagnostic_build_id_value", 0))
    status = "pass" if build_id_value != 0 and not missing else "fail"
    return {
        "status": status,
        "diagnostic_feature_mask_required": _hex32(REQUIRED_DIAGNOSTIC_FEATURE_MASK),
        "diagnostic_feature_mask_required_bits_present": not missing,
        "missing_required_features": missing,
        "recommended_next_stage": (
            "Stage1A22_PBMPointerResetOrDrainDiagnosis" if status == "pass" else "CSRMapOrBitLoadingDiagnosis"
        ),
    }


def write_diagnostic_feature_mask_preflight_artifact(
    artifact_path: str | Path,
    *,
    xsct_output: str,
    xsct_returncode: int,
    xsct_error: str = "",
    xsct_script_path: str | Path | None = None,
) -> int:
    parsed = parse_diagnostic_feature_mask_preflight_output(xsct_output)
    verdict = evaluate_diagnostic_feature_mask_preflight(parsed)
    if xsct_returncode != 0:
        verdict = {
            **verdict,
            "status": "fail",
            "recommended_next_stage": "CSRMapOrBitLoadingDiagnosis",
        }
    payload = {
        **parsed,
        **verdict,
        "xsct_returncode": xsct_returncode,
        "xsct_error": xsct_error,
        "xsct_script": str(xsct_script_path) if xsct_script_path else "",
        "preflight_timestamp_utc": datetime.now(timezone.utc).isoformat(),
    }
    write_json_atomic(artifact_path, payload)
    return 0


def run_diagnostic_feature_mask_preflight(repo_root: str | Path) -> int:
    repo = Path(repo_root)
    artifact = repo / "doc" / "reports" / "engineering_evidence" / "pipeline_state" / "diagnostic_feature_mask_preflight.json"
    tcl_path = repo / "doc" / "reports" / "engineering_evidence" / "pipeline_state" / "diagnostic_feature_mask_preflight.tcl"
    tcl_path.parent.mkdir(parents=True, exist_ok=True)
    tcl_path.write_text(render_diagnostic_feature_mask_preflight_tcl(), encoding="utf-8")

    if not DEFAULT_XSCT.exists():
        return write_diagnostic_feature_mask_preflight_artifact(
            artifact,
            xsct_output="",
            xsct_returncode=127,
            xsct_error=f"xsct executable not found: {DEFAULT_XSCT}",
            xsct_script_path=tcl_path,
        )

    try:
        completed = subprocess.run(
            [str(DEFAULT_XSCT), str(tcl_path)],
            cwd=str(repo),
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired as exc:
        return write_diagnostic_feature_mask_preflight_artifact(
            artifact,
            xsct_output=(exc.stdout or "") + "\n" + (exc.stderr or ""),
            xsct_returncode=124,
            xsct_error="xsct diagnostic feature-mask preflight timed out",
            xsct_script_path=tcl_path,
        )
    return write_diagnostic_feature_mask_preflight_artifact(
        artifact,
        xsct_output=(completed.stdout or "") + "\n" + (completed.stderr or ""),
        xsct_returncode=int(completed.returncode),
        xsct_error=completed.stderr or "",
        xsct_script_path=tcl_path,
    )


def apply_feature_mask_preflight_transition(
    state: dict[str, Any],
    *,
    registry_entry: dict[str, Any],
    artifact_path: str | Path,
) -> dict[str, Any]:
    artifact = load_json(artifact_path)
    updated = dict(state)
    updated["last_stage"] = registry_entry["stage"]
    updated["current_phase"] = registry_entry["phase"]
    updated["failed_gate"] = registry_entry.get("gate")
    updated["diagnostic_build_id"] = artifact.get("diagnostic_build_id")
    updated["diagnostic_feature_mask"] = artifact.get("diagnostic_feature_mask")
    updated["diagnostic_feature_mask_bits"] = artifact.get("feature_mask_bits", {})
    updated["diagnostic_registry_hash_low"] = artifact.get("diagnostic_registry_hash_low")
    updated["diagnostic_registry_hash_high"] = artifact.get("diagnostic_registry_hash_high")
    updated["diagnostic_feature_mask_preflight_artifact"] = str(artifact_path)
    updated["last_action_status"] = artifact.get("status")
    post_build_return_stage = updated.get("post_build_return_stage")
    if artifact.get("status") == "pass" and post_build_return_stage:
        updated["recommended_next_stage"] = post_build_return_stage
        updated.pop("post_build_return_stage", None)
    else:
        updated["recommended_next_stage"] = artifact.get("recommended_next_stage") or (
            "Stage1A22_PBMPointerResetOrDrainDiagnosis"
            if artifact.get("status") == "pass"
            else "CSRMapOrBitLoadingDiagnosis"
        )
    if artifact.get("status") != "pass":
        updated["last_failure_signature"] = gates.make_failure_signature(
            stage=registry_entry["stage"],
            failed_gate=str(registry_entry.get("gate")),
            recommended_next_stage=str(updated["recommended_next_stage"]),
            summary={
                "diagnostic_feature_mask": artifact.get("diagnostic_feature_mask_value", 0),
                "active_bit_sha256": state.get("active_bit_sha256", "unknownbit"),
            },
            manifest={},
        )
    return updated


def record_attempt(
    state: dict[str, Any],
    *,
    gate: str,
    failure_signature: str,
    max_retries_per_gate: int,
) -> dict[str, Any]:
    updated = dict(state)
    attempts = list(updated.get("attempts", []))
    matching = [
        attempt
        for attempt in attempts
        if attempt.get("gate") == gate and attempt.get("failure_signature") == failure_signature
    ]
    attempt_count = len(matching) + 1
    attempts.append(
        {
            "gate": gate,
            "failure_signature": failure_signature,
            "attempt": attempt_count,
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        }
    )
    updated["attempts"] = attempts
    updated["last_failure_signature"] = failure_signature
    if attempt_count >= max_retries_per_gate:
        updated["terminal_blocker"] = "repeated_same_failure_signature"
        updated["terminal_blocker_detail"] = {
            "gate": gate,
            "failure_signature": failure_signature,
            "attempts": attempt_count,
        }
    return updated


def apply_gate_result(
    state: dict[str, Any],
    result: dict[str, Any],
    *,
    registry_entry: dict[str, Any],
    max_retries_per_gate: int,
    last_run_dir: str | None = None,
) -> dict[str, Any]:
    updated = dict(state)
    updated.update(result.get("gate_updates", {}))
    updated["normal_data_acquisition_ready"] = result.get("normal_data_acquisition_ready", False)
    levels = result.get("level_readiness", {})
    updated["level1_architecture_evidence_ready"] = levels.get("level1_architecture_evidence_ready", False)
    updated["level2_engineering_performance_ready"] = levels.get("level2_engineering_performance_ready", False)
    updated["level3_paper_recovery_ready"] = levels.get("level3_paper_recovery_ready", False)
    updated["architecture_evidence_ready"] = updated["level1_architecture_evidence_ready"]
    updated["engineering_performance_ready"] = updated["level2_engineering_performance_ready"]
    updated["paper_ready_throughput_gate"] = bool(result.get("paper_ready_throughput_gate", updated.get("paper_ready_throughput_gate", False)))
    updated["paper_ready_recovery_gate"] = bool(result.get("paper_ready_recovery_gate", updated.get("paper_ready_recovery_gate", False)))
    if registry_entry["stage"] == "Stage1A_EngineeringDataAcquisition" and result.get("stage_status") == "pass":
        updated["engineering_data_collected"] = True
    updated["last_stage"] = registry_entry["stage"]
    updated["current_phase"] = registry_entry["phase"]
    updated["failed_gate"] = result.get("failed_gate")
    updated["recommended_next_stage"] = result.get("recommended_next_stage")
    if last_run_dir:
        updated["last_run_dir"] = last_run_dir
    if result.get("stage_status") in {"fail", "blocked", "partial"}:
        updated = record_attempt(
            updated,
            gate=str(result.get("failed_gate")),
            failure_signature=str(result.get("failure_signature")),
            max_retries_per_gate=max_retries_per_gate,
        )
    if result.get("terminal_blocker_candidate") and not updated.get("terminal_blocker"):
        updated["terminal_blocker"] = result["terminal_blocker_candidate"]
    return updated


def next_after_action(stage: str) -> str | None:
    transitions = {
        "PBMSoftResetDiagnosticBuild": "DiagnosticBitstreamBuild",
        "DiagnosticBitstreamBuild": "DiagnosticJtagProgram",
        "DiagnosticJtagProgram": "DiagnosticFeatureMaskPreflight",
        "DiagnosticFeatureMaskPreflight": "Stage1A22_PBMPointerResetOrDrainDiagnosis",
        "TXAxisReadyDefaultReadyBuildFix": "DiagnosticBitstreamBuild",
        "CSRMapOrBitLoadingDiagnosis": "PBMSoftResetDiagnosticBuild",
        "ResetCoverageDiagnosis": "PBMSoftResetDiagnosticBuild",
    }
    return transitions.get(stage)


def apply_action_transition(
    state: dict[str, Any],
    *,
    registry_entry: dict[str, Any],
    next_stage: str,
    status: str = "pass",
) -> dict[str, Any]:
    updated = dict(state)
    updated["last_stage"] = registry_entry["stage"]
    updated["current_phase"] = registry_entry["phase"]
    updated["recommended_next_stage"] = next_stage
    updated["last_action_status"] = status
    updated["failed_gate"] = registry_entry.get("gate")
    if registry_entry["stage"] == "TXAxisReadyDefaultReadyBuildFix":
        updated["post_build_return_stage"] = "Stage1A26_DMARdEnableEquationDiagnosis"
    return updated


def find_latest_run_dir(root: Path) -> Path | None:
    if not root.exists():
        return None
    dirs = [path for path in root.iterdir() if path.is_dir() and (path / "summary_stats.json").exists()]
    if not dirs:
        return None
    return max(dirs, key=lambda path: path.stat().st_mtime)


def load_stage_outputs(run_dir: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    summary = load_json(run_dir / "summary_stats.json")
    manifest_path = run_dir / "run_manifest.json"
    manifest = load_json(manifest_path) if manifest_path.exists() else {}
    return summary, manifest


def plan_next_action(registry: dict[str, Any], state: dict[str, Any]) -> dict[str, Any]:
    return gates.normalize_stage_name(state.get("recommended_next_stage"), registry)


def auto_run_target_reached(target: str, state: dict[str, Any]) -> bool:
    """Return true only when the requested terminal target is fully qualified."""
    if target == "EngineeringDataCollected":
        return bool(
            state.get("engineering_data_collected")
            and state.get("normal_data_acquisition_ready")
            and state.get("level2_engineering_performance_ready")
        )
    if target == "PaperCandidateCollected":
        return bool(state.get("paper_candidate_collected"))
    if target == "FullDataCollected":
        return bool(
            state.get("engineering_data_collected")
            and state.get("paper_candidate_collected")
            and state.get("recovery_evidence_collected")
        )
    return False


def run_command(command: str, cwd: Path) -> int:
    completed = subprocess.run(command, shell=True, cwd=str(cwd))
    return int(completed.returncode)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", default=str(DEFAULT_REGISTRY))
    parser.add_argument("--state", default=str(DEFAULT_STATE))
    parser.add_argument("--state-template", default=str(DEFAULT_STATE_TEMPLATE))
    parser.add_argument("--repo-root", default=str(REPO_ROOT))
    parser.add_argument("--mode", default="FullDataAcquisition")
    parser.add_argument("--auto-run-until", default="EngineeringDataCollected")
    parser.add_argument("--max-retries-per-gate", type=int, default=2)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--allow-diagnostic-rtl-fixes", action="store_true")
    parser.add_argument("--allow-build", action="store_true")
    parser.add_argument("--allow-jtag-program", action="store_true")
    parser.add_argument("--allow-engineering-data", action="store_true")
    parser.add_argument("--allow-paper-candidate", action="store_true")
    parser.add_argument("--allow-paper-export", action="store_true")
    parser.add_argument("--manual-final-export-ack", action="store_true")
    parser.add_argument("--internal-action", default="")
    args = parser.parse_args(argv)

    registry = gates.load_stage_registry(args.registry)
    state_path = Path(args.state)
    state = load_or_initialize_state(state_path, args.state_template)
    history_path = state_path.with_name("current_state.history.jsonl")
    next_entry = plan_next_action(registry, state)

    if args.internal_action:
        if args.internal_action == "DiagnosticFeatureMaskPreflight":
            rc = run_diagnostic_feature_mask_preflight(args.repo_root)
            artifact = FEATURE_MASK_PREFLIGHT_ARTIFACT
            if Path(args.repo_root) != REPO_ROOT:
                artifact = (
                    Path(args.repo_root)
                    / "doc"
                    / "reports"
                    / "engineering_evidence"
                    / "pipeline_state"
                    / "diagnostic_feature_mask_preflight.json"
                )
            payload = load_json(artifact) if artifact.exists() else {"status": "missing_artifact"}
            print(json.dumps(payload, indent=2))
            return rc
        if args.internal_action == "PaperDataCandidateExport":
            payload = export_paper_candidate(Path(args.repo_root), state)
            if payload.get("status") == "pass":
                state["paper_candidate_collected"] = True
                state["paper_candidate_dir"] = payload.get("output_dir")
                state["paper_ready_throughput_gate"] = bool(payload.get("throughput_gate_met"))
                state["paper_ready_recovery_gate"] = bool(payload.get("recovery_gate_met"))
                state["recommended_next_stage"] = payload.get("recommended_next_stage") or "Stage2_ExtremeTraffic"
                state["failed_gate"] = (
                    "paper_ready_recovery_gate"
                    if payload.get("recommended_next_stage") == "Stage2_ExtremeTraffic"
                    else "paper_candidate_collected"
                )
            else:
                state["paper_candidate_collected"] = False
                state["recommended_next_stage"] = payload.get("recommended_next_stage") or state.get("recommended_next_stage")
            state["last_stage"] = "PaperDataCandidateExport"
            state["current_phase"] = "paper_candidate"
            state["last_action_status"] = payload.get("status")
            write_state_atomic(state_path, state, history_path=history_path)
            print(json.dumps(payload, indent=2))
            return 0
        if args.internal_action == "DropRollbackCouplingDiagnosis":
            payload = run_drop_rollback_coupling_diagnosis(Path(args.repo_root), state)
            state["recovery_evidence_collected"] = bool(payload.get("recovery_gate_met") and payload.get("rollback_recovery_seen"))
            state["paper_ready_recovery_gate"] = bool(payload.get("recovery_gate_met"))
            state["last_stage"] = "DropRollbackCouplingDiagnosis"
            state["current_phase"] = "recovery_gate"
            state["recommended_next_stage"] = payload.get("recommended_next_stage") or state.get("recommended_next_stage")
            state["failed_gate"] = "paper_candidate_collected" if state["recovery_evidence_collected"] else "paper_ready_recovery_gate"
            state["last_action_status"] = payload.get("status")
            write_state_atomic(state_path, state, history_path=history_path)
            print(json.dumps(payload, indent=2))
            return 0
        if args.internal_action == "PaperDataFinalExport":
            payload = export_paper_final(Path(args.repo_root), state)
            if payload.get("status") == "pass":
                state["paper_data_exported"] = True
                state["paper_final_dir"] = payload.get("output_dir")
            state["last_stage"] = "PaperDataFinalExport"
            state["current_phase"] = "paper_final"
            state["recommended_next_stage"] = payload.get("recommended_next_stage") or state.get("recommended_next_stage")
            state["failed_gate"] = "paper_data_exported"
            state["last_action_status"] = payload.get("status")
            write_state_atomic(state_path, state, history_path=history_path)
            print(json.dumps(payload, indent=2))
            return 0
        print(json.dumps({"internal_action": args.internal_action, "status": "ok"}, indent=2))
        return 0

    if args.plan_only:
        print(json.dumps({"mode": "PlanOnly", "next_action": next_entry}, indent=2))
        return 0

    if args.dry_run:
        unresolved: list[str] = []
        for entry in registry.get("stages", []):
            for route in entry.get("fail_routes", {}).values():
                try:
                    gates.normalize_stage_name(route, registry)
                except KeyError:
                    unresolved.append(f"{entry['stage']} -> {route}")
        reset_block_ok = bool(state.get("reset_gate_passed", False)) or next_entry["stage"] in gates.RESET_LOOP_STAGES
        paper_final_locked = not (args.allow_paper_export and args.manual_final_export_ack)
        payload = {
            "mode": "DryRun",
            "next_action": next_entry["stage"],
            "unresolved_routes": unresolved,
            "reset_gate_downstream_block_ok": reset_block_ok,
            "paper_final_export_locked": paper_final_locked,
            "ordinary_gate_fail_routes_without_stopping": True,
        }
        print(json.dumps(payload, indent=2))
        return 1 if unresolved else 0

    max_actions = 100
    for _ in range(max_actions):
        state = load_or_initialize_state(state_path, args.state_template)
        next_entry = plan_next_action(registry, state)

        if state.get("terminal_blocker"):
            return 1
        if auto_run_target_reached(args.auto_run_until, state):
            return 0

        if next_entry["action_type"] == "terminal":
            if next_entry["stage"] == "PaperDataFinalExport" and not (
                args.allow_paper_export and args.manual_final_export_ack
            ):
                state["terminal_blocker"] = "paper_final_export_requires_manual_ack"
                write_state_atomic(state_path, state, history_path=history_path)
                return 1

        if next_entry["requires_rtl_build"] and not args.allow_diagnostic_rtl_fixes:
            state["terminal_blocker"] = "diagnostic_rtl_fix_not_allowed"
            write_state_atomic(state_path, state, history_path=history_path)
            return 1
        if next_entry["action_type"] == "build" and not args.allow_build:
            state["terminal_blocker"] = "build_not_allowed"
            write_state_atomic(state_path, state, history_path=history_path)
            return 1
        if next_entry["requires_jtag_program"] and not args.allow_jtag_program:
            state["terminal_blocker"] = "jtag_program_not_allowed"
            write_state_atomic(state_path, state, history_path=history_path)
            return 1
        if next_entry["stage"] == "PaperDataCandidateExport" and not args.allow_paper_candidate:
            state["terminal_blocker"] = "paper_candidate_export_not_allowed"
            write_state_atomic(state_path, state, history_path=history_path)
            return 1

        rc = run_command(next_entry["command"], cwd=Path(args.repo_root))
        if rc != 0:
            state["terminal_blocker"] = f"command_failed_rc_{rc}"
            state["terminal_blocker_detail"] = {"stage": next_entry["stage"], "command": next_entry["command"]}
            write_state_atomic(state_path, state, history_path=history_path)
            return rc

        if next_entry["stage"] == "DiagnosticFeatureMaskPreflight":
            artifact_path = (
                Path(args.repo_root)
                / "doc"
                / "reports"
                / "engineering_evidence"
                / "pipeline_state"
                / "diagnostic_feature_mask_preflight.json"
            )
            if not artifact_path.exists():
                state["terminal_blocker"] = "diagnostic_feature_mask_preflight_missing_artifact"
                write_state_atomic(state_path, state, history_path=history_path)
                return 1
            updated = apply_feature_mask_preflight_transition(
                state,
                registry_entry=next_entry,
                artifact_path=artifact_path,
            )
            if updated.get("last_action_status") != "pass":
                updated = record_attempt(
                    updated,
                    gate=str(next_entry.get("gate")),
                    failure_signature=str(updated.get("last_failure_signature")),
                    max_retries_per_gate=args.max_retries_per_gate,
                )
            write_state_atomic(state_path, updated, history_path=history_path)
            if updated.get("terminal_blocker"):
                return 1
            continue

        if next_entry["stage"] in {"PaperDataCandidateExport", "PaperDataFinalExport"}:
            state = load_or_initialize_state(state_path, args.state_template)
            if state.get("terminal_blocker"):
                return 1
            continue

        action_next = next_after_action(next_entry["stage"])
        if next_entry["action_type"] != "run_stage" and action_next is not None:
            updated = apply_action_transition(state, registry_entry=next_entry, next_stage=action_next)
            write_state_atomic(state_path, updated, history_path=history_path)
            continue

        latest = find_latest_run_dir(Path(args.repo_root) / "doc" / "reports" / "engineering_evidence")
        if latest is None:
            state["terminal_blocker"] = "missing_summary_stats_after_stage"
            write_state_atomic(state_path, state, history_path=history_path)
            return 1
        summary, manifest = load_stage_outputs(latest)
        result = gates.evaluate_summary(
            summary=summary,
            current_state=state,
            registry_entry=next_entry,
            manifest=manifest,
        )
        updated = apply_gate_result(
            state,
            result,
            registry_entry=next_entry,
            max_retries_per_gate=args.max_retries_per_gate,
            last_run_dir=str(latest),
        )
        write_state_atomic(state_path, updated, history_path=history_path)
        if updated.get("terminal_blocker"):
            return 1

    state["terminal_blocker"] = "max_pipeline_actions_exceeded"
    write_state_atomic(state_path, state, history_path=history_path)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
