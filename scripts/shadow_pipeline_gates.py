#!/usr/bin/env python3
"""Gate evaluation helpers for the Shadow-Mirror autonomous pipeline."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


GATE_KEYS = (
    "reset_gate_passed",
    "injection_gate_passed",
    "pbm_gate_passed",
    "bridge_gate_passed",
    "dma_gate_passed",
    "backend_gate_passed",
    "reset_isolation_passed",
)

RESET_LOOP_STAGES = {
    "PBMSoftResetDiagnosticBuild",
    "ResetCoverageDiagnosis",
    "CSRMapOrBitLoadingDiagnosis",
    "Stage1A22_PBMPointerResetOrDrainDiagnosis",
    "Stage1A23_PBMCommitTailPointerInvariantDiagnosis",
    "Stage1A24_PBMResetDomainScopeDiagnosis",
    "Stage1A25_PBMResetDomainRemediationPlan",
}

MACHINE_FIELD_PRIORITY = ("summary_stats.json", "case_results.csv", "run_manifest.json")


def load_stage_registry(path: str | Path) -> dict[str, Any]:
    registry_path = Path(path)
    data = json.loads(registry_path.read_text(encoding="utf-8"))
    _validate_aliases(data)
    return data


def _validate_aliases(registry: dict[str, Any]) -> None:
    seen: dict[str, str] = {}
    for entry in registry.get("stages", []):
        for name in [entry["stage"], *entry.get("aliases", [])]:
            if name in seen:
                raise ValueError(f"duplicate registry alias {name!r} for {entry['stage']} and {seen[name]}")
            seen[name] = entry["stage"]


def normalize_stage_name(name: str | None, registry: dict[str, Any]) -> dict[str, Any]:
    if not name:
        raise KeyError("empty stage name cannot be resolved")
    for entry in registry.get("stages", []):
        if name == entry.get("stage") or name in entry.get("aliases", []):
            return entry
    normalized = _compact_stage_name(name)
    for entry in registry.get("stages", []):
        candidates = [entry.get("stage", ""), *entry.get("aliases", [])]
        if normalized in {_compact_stage_name(candidate) for candidate in candidates}:
            return entry
    raise KeyError(f"stage name {name!r} is not present in stage registry")


def _compact_stage_name(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())


def _num(value: Any, default: int = 0) -> int:
    if isinstance(value, bool):
        return int(value)
    if value is None or value == "":
        return default
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def _bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if value is None:
        return False
    return str(value).strip().lower() in {"1", "true", "yes", "pass", "passed"}


def _gate_met(value: Any) -> bool:
    if isinstance(value, dict):
        return _bool(value.get("met"))
    return _bool(value)


def _stage_section(summary: dict[str, Any], key: str) -> dict[str, Any]:
    section = summary.get(key)
    return section if isinstance(section, dict) else {}


def _field(summary: dict[str, Any], section_key: str, field: str, default: Any = None) -> Any:
    if field in summary:
        return summary.get(field)
    return _stage_section(summary, section_key).get(field, default)


def _metric_max(summary: dict[str, Any], metric_name: str) -> int:
    metrics = summary.get("metrics")
    if not isinstance(metrics, dict):
        return 0
    metric = metrics.get(metric_name)
    if not isinstance(metric, dict):
        return 0
    return _num(metric.get("max"))


def _initial_gate_updates(current_state: dict[str, Any]) -> dict[str, bool]:
    return {key: bool(current_state.get(key, False)) for key in GATE_KEYS}


def _level_readiness(gates: dict[str, bool], state: dict[str, Any], summary: dict[str, Any]) -> dict[str, bool]:
    level1 = gates["reset_gate_passed"] and gates["injection_gate_passed"] and gates["pbm_gate_passed"]
    level2 = level1 and gates["bridge_gate_passed"] and gates["dma_gate_passed"] and gates["backend_gate_passed"]
    level3 = level2 and (_gate_met(state.get("paper_ready_recovery_gate")) or _gate_met(summary.get("paper_ready_recovery_gate")))
    return {
        "level1_architecture_evidence_ready": level1,
        "level2_engineering_performance_ready": level2,
        "level3_paper_recovery_ready": level3,
    }


def _hash_present(value: Any) -> bool:
    text = str(value or "").strip().lower()
    return bool(text and text not in {"unknown", "unknownbit", "none", "null"})


def _paper_ready_throughput_gate(summary: dict[str, Any], manifest: dict[str, Any]) -> dict[str, Any]:
    declared = summary.get("paper_ready_throughput_gate")
    if isinstance(declared, dict):
        return {
            "met": _bool(declared.get("met")),
            **declared,
        }
    if isinstance(declared, bool):
        return {"met": declared}

    stage1a_decision = summary.get("stage1a_decision") if isinstance(summary.get("stage1a_decision"), dict) else {}
    grouped = summary.get("grouped_by_burst_frames_ordered")
    grouped_rows = grouped if isinstance(grouped, list) else []
    included_rows = _num(summary.get("included_sample_count"))
    backend_monotonic = str(stage1a_decision.get("backend_activity_monotonic", "")).lower() in {"yes", "partial"}
    dominant_backend_mode = str(stage1a_decision.get("dominant_backend_mode", "")).lower()
    stable_groups = [
        group for group in grouped_rows
        if _num(group.get("included_count")) >= 3 and _num(_nested_value(group, "std")) == 0
    ]
    activity_groups = [
        group for group in grouped_rows
        if _num(_nested_value(group, "mean")) > 0
    ]
    manifest_board = manifest.get("board") if isinstance(manifest.get("board"), dict) else {}
    bit_hash = manifest_board.get("active_bit_sha256") or summary.get("active_bit_sha256")
    xsa_hash = manifest_board.get("active_xsa_sha256") or summary.get("active_xsa_sha256")
    hashes_present = _hash_present(bit_hash) and _hash_present(xsa_hash)
    met = (
        backend_monotonic
        and dominant_backend_mode not in {"", "none"}
        and included_rows >= 10
        and len(activity_groups) >= 3
        and len(stable_groups) >= 3
        and hashes_present
    )
    return {
        "met": met,
        "requires_backend_stability": True,
        "requires_repeated_stability_passes": True,
        "requires_fixed_bit_xsa_hash": True,
        "included_sample_count_min": 10,
        "stable_activity_group_count": len(stable_groups),
        "hashes_present": hashes_present,
    }


def evaluate_summary(
    *,
    summary: dict[str, Any],
    current_state: dict[str, Any],
    registry_entry: dict[str, Any],
    case_rows: list[dict[str, Any]] | None = None,
    manifest: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Evaluate one stage summary using layer-local evidence only."""
    del case_rows
    manifest = manifest or {}
    gates = _initial_gate_updates(current_state)
    stage = registry_entry.get("stage") or summary.get("stage")
    recommended = summary.get("recommended_next_stage") or stage
    failed_gate = registry_entry.get("gate") or current_state.get("failed_gate")
    status = "fail"
    terminal = None

    if not gates["reset_gate_passed"] and stage not in RESET_LOOP_STAGES:
        return _result(
            stage_status="blocked",
            gates=gates,
            state=current_state,
            summary=summary,
            failed_gate="reset_gate",
            recommended_next_stage="PBMSoftResetDiagnosticBuild",
            terminal_blocker_candidate=None,
            manifest=manifest,
            stage_name=stage,
        )

    if stage == "PBMSoftResetDiagnosticBuild":
        recommended = "Stage1A22_PBMPointerResetOrDrainDiagnosis"
        status = "partial"
    elif stage == "Stage1A22_PBMPointerResetOrDrainDiagnosis":
        stage1a22 = "stage1a22_pbm_pointer_reset_or_drain_diagnosis"
        reset_pulsed = _bool(_field(summary, stage1a22, "dma_soft_reset_pulsed_verified")) or _bool(
            _field(summary, stage1a22, "soft_reset_pulsed_verified")
        )
        reset_gap_cleared = _bool(_field(summary, stage1a22, "idle_after_soft_reset_gap_cleared")) or not _bool(
            _field(summary, stage1a22, "persistent_pointer_gap_after_reset")
        )
        ready_recovered = _bool(_field(summary, stage1a22, "bf64_after_soft_reset_ready_recovered"))
        accept_seen = _bool(_field(summary, stage1a22, "bf64_after_soft_reset_accept_seen"))
        if reset_pulsed and reset_gap_cleared and (ready_recovered or accept_seen):
            recommended = "Stage1A23_PBMCommitTailPointerInvariantDiagnosis"
            status = "pass"
        else:
            recommended = _field(summary, stage1a22, "recommended_next_stage") or "PBMSoftResetImplementationDiagnosis"
    elif stage == "Stage1A23_PBMCommitTailPointerInvariantDiagnosis":
        stage1a23 = "stage1a23_pbm_commit_tail_pointer_invariant_diagnosis"
        classification = str(_field(summary, stage1a23, "pbm_commit_tail_pointer_invariant_classification", ""))
        invariant_seen = _bool(_field(summary, stage1a23, "persistent_pointer_gap_state_counter_invariant")) or (
            classification == "persistent_pointer_gap_state_counter_invariant"
        )
        if not invariant_seen:
            gates["reset_gate_passed"] = True
            gates["reset_isolation_passed"] = True
            recommended = "Stage1A20_InjectionSourceArmingDiagnosis"
            status = "pass"
        else:
            recommended = _field(summary, stage1a23, "recommended_next_stage") or "PBMResetDomainScopeDiagnosis"
    elif stage == "Stage1A24_PBMResetDomainScopeDiagnosis":
        stage1a24 = "stage1a24_pbm_reset_domain_scope_diagnosis"
        recommended = _field(summary, stage1a24, "recommended_next_stage") or "PBMResetDomainRemediationPlan"
        status = "partial"
    elif stage == "Stage1A25_PBMResetDomainRemediationPlan":
        stage1a25 = "stage1a25_pbm_reset_domain_remediation_plan"
        recommended = _field(summary, stage1a25, "recommended_next_stage") or "PBMSoftResetDiagnosticBuild"
        status = "partial"
    elif stage == "Stage1A20_InjectionSourceArmingDiagnosis":
        stage1a20 = "injection_source_arming_diagnosis"
        if _num(_field(summary, stage1a20, "stage1_inject_fire_cycles")) > 0 or _bool(
            _field(summary, stage1a20, "stage1_fire_seen")
        ):
            gates["injection_gate_passed"] = True
            recommended = "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis"
            status = "pass"
        else:
            recommended = _field(summary, stage1a20, "recommended_next_stage") or "InjectionSourceArmingDiagnosis"
    elif stage == "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis":
        stage1a18 = "upstream_ingress_to_pbm_visibility_diagnosis"
        if _num(_field(summary, stage1a18, "pbm_wr_valid_cycles")) > 0:
            recommended = "Stage1A21_PBMReadyGatingDiagnosis"
            status = "pass"
        else:
            recommended = _field(summary, stage1a18, "recommended_next_stage") or "Stage1A20_InjectionSourceArmingDiagnosis"
    elif stage == "Stage1A21_PBMReadyGatingDiagnosis":
        stage1a21 = "stage1a21_pbm_ready_gating_diagnosis"
        if _num(_field(summary, stage1a21, "pbm_wr_valid_cycles")) > 0 and _num(
            _field(summary, stage1a21, "pbm_wr_accept_cycles")
        ) > 0:
            recommended = "Stage1A17_PBMCommitReproductionDiagnosis"
            status = "pass"
        else:
            recommended = _field(summary, stage1a21, "recommended_next_stage") or "PBMReadyGatingDiagnosis"
            if _bool(_field(summary, stage1a21, "preexisting_pointer_gap_seen")) or (
                recommended == "PBMPointerResetOrDrainDiagnosis"
            ):
                gates["reset_gate_passed"] = False
                gates["reset_isolation_passed"] = False
                failed_gate = "reset_gate_passed"
    elif stage == "Stage1A17_PBMCommitReproductionDiagnosis":
        stage1a17 = "pbm_commit_reproduction_diagnosis"
        if (
            _num(_field(summary, stage1a17, "rollback_event_count")) > 0
            or _num(_field(summary, stage1a17, "recovery_active_cycles")) > 0
            or _bool(_field(summary, stage1a17, "rollback_recovery_seen"))
        ):
            recommended = "DropRollbackCouplingDiagnosis"
            status = "partial"
        elif _num(_field(summary, stage1a17, "pbm_wr_accept_cycles")) > 0 and _num(
            _field(summary, stage1a17, "pbm_commit_entry_count")
        ) > 0:
            gates["pbm_gate_passed"] = True
            recommended = "Stage1A16_BridgeDataProductionDiagnosis"
            status = "pass"
        else:
            recommended = _field(summary, stage1a17, "recommended_next_stage") or "Stage1A17_PBMCommitReproductionDiagnosis"
    elif stage == "Stage1A11_PBMReadSideVisibilityDiagnosis":
        stage1a11 = "stage1a11_pbm_read_side_visibility"
        if _bool(_field(summary, stage1a11, "pbm_rollback_path_observed")) or _bool(
            _field(summary, stage1a11, "pbm_rollback_trigger_candidate_seen")
        ):
            recommended = "DropRollbackCouplingDiagnosis"
            status = "partial"
        elif _bool(_field(summary, stage1a11, "bridge_fire_seen")):
            gates["bridge_gate_passed"] = True
            recommended = _field(summary, stage1a11, "recommended_next_stage") or "Stage1A15_ExplicitStartBridgeHandoffDiagnosis"
            status = "pass"
        elif _bool(_field(summary, stage1a11, "bridge_rd_en_seen")):
            recommended = _field(summary, stage1a11, "recommended_next_stage") or "BridgeAcceptPathDiagnosis"
        else:
            recommended = _field(summary, stage1a11, "recommended_next_stage") or "PBMReadSideVisibilityDiagnosis"
    elif stage == "Stage1A16_BridgeDataProductionDiagnosis":
        stage1a16 = "bridge_data_production_diagnosis"
        if _bool(_field(summary, stage1a16, "a15_after_start_explicit_start_verified")) and not _bool(
            _field(summary, stage1a16, "a15_after_start_bridge_nonempty_seen")
        ):
            recommended = (
                "CSRControlSideEffectDiagnosis"
                if _bool(_field(summary, stage1a16, "explicit_start_changed_control_state"))
                else "BridgeDataProductionUnderExplicitStartDiagnosis"
            )
        elif _bool(_field(summary, stage1a16, "baseline_bridge_reproduced")) and (
            _bool(_field(summary, stage1a16, "bridge_tx_nonempty_seen_any"))
            or _bool(_field(summary, stage1a16, "a12_no_start_replay_bridge_nonempty_seen"))
        ):
            gates["bridge_gate_passed"] = True
            recommended = "Stage1A15_ExplicitStartBridgeHandoffDiagnosis"
            status = "pass"
        else:
            recommended = _field(summary, stage1a16, "recommended_next_stage") or "BridgeDataProductionReproductionCheck"
    elif stage == "Stage1A15_ExplicitStartBridgeHandoffDiagnosis":
        stage1a15 = "explicit_start_bridge_handoff_diagnosis"
        if (
            _bool(_field(summary, stage1a15, "explicit_start_verified_by_hardware"))
            and (
                _num(_field(summary, stage1a15, "bridge_tx_rd_en_cycles")) > 0
                or _bool(_field(summary, stage1a15, "bridge_tx_rd_en_seen"))
            )
            and (
                _num(_field(summary, stage1a15, "bridge_tx_accept_cycles")) > 0
                or _bool(_field(summary, stage1a15, "bridge_tx_accept_seen"))
            )
        ):
            gates["dma_gate_passed"] = True
            recommended = "Stage1A10_CryptoDMAHandoffDiagnosis"
            status = "pass"
        else:
            recommended = _field(summary, stage1a15, "recommended_next_stage") or "Stage1A15_ExplicitStartBridgeHandoffDiagnosis"
            if recommended == "DMARdEnableGatingDiagnosis":
                recommended = "Stage1A26_DMARdEnableEquationDiagnosis"
    elif stage == "Stage1A26_DMARdEnableEquationDiagnosis":
        stage1a26 = "dma_rd_en_equation_diagnosis"
        loopback_mode = _num(_field(summary, stage1a26, "dma_rd_en_loopback_mode_raw"))
        runtime_bypass = _bool(_field(summary, stage1a26, "runtime_ring_bypass_enabled"))
        tx_ready_cycles = _num(_field(summary, stage1a26, "dma_rd_en_tx_axis_tready_cycles"))
        nonempty_cycles = _num(_field(summary, stage1a26, "dma_rd_en_crypto_to_dma_nonempty_cycles"))
        tx_ready_when_nonempty = _num(_field(summary, stage1a26, "dma_rd_en_tx_ready_when_nonempty_cycles"))
        dma_req_rd_cycles = _num(_field(summary, stage1a26, "dma_rd_en_dma_req_rd_cycles"))
        loopback_candidate = _num(_field(summary, stage1a26, "dma_rd_en_loopback_branch_candidate_cycles"))
        bridge_rd_en_cycles = _num(_field(summary, stage1a26, "bridge_tx_rd_en_cycles"))
        bridge_accept_cycles = _num(_field(summary, stage1a26, "bridge_tx_accept_cycles"))

        if bridge_rd_en_cycles > 0 and bridge_accept_cycles == 0:
            recommended = "BridgeAcceptPathDiagnosis"
        elif bridge_rd_en_cycles > 0 and bridge_accept_cycles > 0:
            gates["dma_gate_passed"] = True
            recommended = "Stage1A10_CryptoDMAHandoffDiagnosis"
            status = "pass"
        elif runtime_bypass and loopback_mode != 2:
            recommended = "DMALoopbackModeControlDiagnosis"
        elif loopback_mode == 2 and tx_ready_cycles == 0:
            recommended = "TXAxisReadyGatingDiagnosis"
        elif loopback_mode == 2 and nonempty_cycles > 0 and tx_ready_when_nonempty == 0:
            recommended = "TXReadyWhileBridgeNonemptyDiagnosis"
        elif loopback_mode != 2 and dma_req_rd_cycles == 0:
            recommended = "DMANormalBranchRdRequestDiagnosis"
        elif loopback_candidate > 0 and bridge_rd_en_cycles == 0:
            recommended = "DMARdEnableEquationInstrumentationBug"
        else:
            recommended = _field(summary, stage1a26, "recommended_next_stage") or "rerun_stage1a26_due_to_inconclusive"
    elif stage == "Stage1A10_CryptoDMAHandoffDiagnosis":
        stage1a10 = "crypto_dma_handoff_diagnosis"
        if _num(_field(summary, stage1a10, "crypto_dma_in_accept_cycles")) > 0 or _bool(
            _field(summary, stage1a10, "crypto_dma_ingress_accept_seen")
        ):
            gates["dma_gate_passed"] = True
        if (
            _num(_field(summary, stage1a10, "backend_accept_cycles")) > 0
            or _num(_field(summary, stage1a10, "backend_starvation_cycles")) > 0
            or _bool(_field(summary, stage1a10, "backend_activity_seen"))
        ):
            gates["backend_gate_passed"] = True
            if gates["dma_gate_passed"]:
                recommended = "Stage1A_EngineeringDataAcquisition"
                status = "pass"
            else:
                recommended = _field(summary, stage1a10, "recommended_next_stage") or "Stage1A27_CryptoDMAIngressBackpressureDiagnosis"
                if recommended == "CryptoDMAIngressBackpressureDiagnosis":
                    recommended = "Stage1A27_CryptoDMAIngressBackpressureDiagnosis"
                status = "partial"
        elif _bool(_field(summary, stage1a10, "pbm_commit_seen")) and _bool(
            _field(summary, stage1a10, "pbm_committed_but_tail_not_moved")
        ):
            recommended = "PBMReadSideVisibilityDiagnosis"
        else:
            recommended = _field(summary, stage1a10, "recommended_next_stage") or "BackendInputGatingDiagnosis"
            if recommended == "CryptoDMAIngressBackpressureDiagnosis":
                recommended = "Stage1A27_CryptoDMAIngressBackpressureDiagnosis"
    elif stage == "Stage1A27_CryptoDMAIngressBackpressureDiagnosis":
        stage1a27 = "crypto_dma_ingress_backpressure_diagnosis"
        if not _stage_section(summary, stage1a27):
            stage1a27 = "crypto_dma_handoff_diagnosis"
        bridge_accept_cycles = _num(_field(summary, stage1a27, "bridge_tx_accept_cycles"))
        bridge_rd_en_cycles = _num(_field(summary, stage1a27, "bridge_tx_rd_en_cycles"))
        crypto_valid_cycles = _num(_field(summary, stage1a27, "crypto_dma_in_valid_cycles"))
        crypto_ready_cycles = _num(_field(summary, stage1a27, "crypto_dma_in_ready_cycles"))
        crypto_accept_cycles = _num(_field(summary, stage1a27, "crypto_dma_in_accept_cycles"))
        loopback_mode = _num(_field(summary, stage1a27, "dma_rd_en_loopback_mode_raw"))
        runtime_bypass = _bool(_field(summary, stage1a27, "runtime_ring_bypass_enabled"))
        backend_seen = (
            _num(_field(summary, stage1a27, "backend_accept_cycles")) > 0
            or _num(_field(summary, stage1a27, "backend_starvation_cycles")) > 0
            or _bool(_field(summary, stage1a27, "backend_activity_seen"))
        )
        if runtime_bypass and loopback_mode == 2 and bridge_accept_cycles > 0:
            gates["dma_gate_passed"] = True
            if backend_seen:
                gates["backend_gate_passed"] = True
                recommended = "Stage1A_EngineeringDataAcquisition"
                status = "pass"
            else:
                recommended = "BackendInputGatingDiagnosis"
                status = "partial"
        elif runtime_bypass and loopback_mode == 2 and bridge_rd_en_cycles > 0 and bridge_accept_cycles == 0:
            recommended = "BridgeAcceptPathDiagnosis"
        elif crypto_accept_cycles > 0:
            gates["dma_gate_passed"] = True
            if backend_seen:
                gates["backend_gate_passed"] = True
                recommended = "Stage1A_EngineeringDataAcquisition"
                status = "pass"
            else:
                recommended = "BackendInputGatingDiagnosis"
                status = "partial"
        elif bridge_accept_cycles > 0 and crypto_valid_cycles == 0:
            recommended = "BridgeToCryptoDMAValidVisibilityDiagnosis"
        elif crypto_valid_cycles > 0 and crypto_ready_cycles == 0:
            recommended = "CryptoDMAIngressReadyGatingDiagnosis"
        elif crypto_valid_cycles > 0 and crypto_ready_cycles > 0 and crypto_accept_cycles == 0:
            recommended = "CryptoDMAIngressHandshakeInstrumentationDiagnosis"
        elif backend_seen and crypto_accept_cycles == 0:
            gates["backend_gate_passed"] = True
            recommended = "CounterAlignmentOrInstrumentationDiagnosis"
        else:
            recommended = _field(summary, stage1a27, "recommended_next_stage") or "rerun_stage1a27_due_to_inconclusive"
    elif stage == "Stage1A_EngineeringDataAcquisition":
        stage1a_decision = summary.get("stage1a_decision") if isinstance(summary.get("stage1a_decision"), dict) else {}
        engineering_matrix_present = bool(stage1a_decision) and _num(summary.get("included_sample_count")) > 0
        negative_result_types = summary.get("negative_result_types")
        negative_no_backend = isinstance(negative_result_types, list) and "negative_no_backend_activity" in negative_result_types
        throughput_gate = _paper_ready_throughput_gate(summary, manifest)
        recovery_gate_met = _gate_met(summary.get("paper_ready_recovery_gate")) or _gate_met(
            current_state.get("paper_ready_recovery_gate")
        )
        backend_activity_seen = (
            _metric_max(summary, "backend_accept_ratio") > 0
            or _metric_max(summary, "backend_starvation_ratio") > 0
            or stage1a_decision.get("backend_activity_monotonic") in {"yes", "partial"}
            or stage1a_decision.get("dominant_backend_mode") not in {None, "", "none"}
        )
        if negative_no_backend and engineering_matrix_present:
            gates["backend_gate_passed"] = False
            recommended = stage1a_decision.get("recommended_next_stage") or "Stage1A10_CryptoDMAHandoffDiagnosis"
            status = "fail"
        elif (
            engineering_matrix_present
            and not negative_no_backend
            and all(gates[key] for key in GATE_KEYS)
            and (throughput_gate.get("met") or recovery_gate_met)
        ):
            failed_gate = "paper_candidate_collected"
            recommended = "PaperDataCandidateExport"
            status = "pass"
        elif engineering_matrix_present and not negative_no_backend and all(gates[key] for key in GATE_KEYS):
            failed_gate = "paper_ready_throughput_gate"
            recommended = stage1a_decision.get("recommended_next_stage") or "Stage2_ExtremeTraffic"
            status = "pass"
        elif engineering_matrix_present:
            recommended = stage1a_decision.get("recommended_next_stage") or "Stage1A10_CryptoDMAHandoffDiagnosis"
            status = "partial"
        else:
            recommended = summary.get("recommended_next_stage") or "Stage1A_EngineeringDataAcquisition"
    elif stage == "Stage2_ExtremeTraffic":
        recovery_gate_met = _gate_met(summary.get("paper_ready_recovery_gate")) or _gate_met(
            current_state.get("paper_ready_recovery_gate")
        )
        negative_types = {str(value) for value in (summary.get("negative_result_types") or [])}
        trigger_rate = float(summary.get("trigger_rate", 0.0) or 0.0)
        if recovery_gate_met:
            failed_gate = "paper_candidate_collected"
            recommended = "DropRollbackCouplingDiagnosis"
            status = "pass"
        elif "negative_backend_activity_only" in negative_types and trigger_rate == 0.0:
            failed_gate = "paper_ready_recovery_gate"
            recommended = "Stage2_SyntheticFaultTraffic"
            status = "partial"
        else:
            failed_gate = "paper_ready_recovery_gate"
            recommended = summary.get("recommended_next_stage") or "Stage2_ExtremeTraffic"
            status = "partial"
    elif stage == "Stage2_SyntheticFaultTraffic":
        recovery_gate_met = _gate_met(summary.get("paper_ready_recovery_gate")) or _gate_met(
            current_state.get("paper_ready_recovery_gate")
        )
        if recovery_gate_met:
            failed_gate = "paper_candidate_collected"
            recommended = "DropRollbackCouplingDiagnosis"
            status = "pass"
        else:
            failed_gate = "paper_ready_recovery_gate"
            recommended = summary.get("recommended_next_stage") or "Stage2_SyntheticFaultTraffic"
            status = "partial"

    return _result(
        stage_status=status,
        gates=gates,
        state=current_state,
        summary=summary,
        failed_gate=failed_gate,
        recommended_next_stage=recommended,
        terminal_blocker_candidate=terminal,
        manifest=manifest,
        stage_name=stage,
    )


def _result(
    *,
    stage_status: str,
    gates: dict[str, bool],
    state: dict[str, Any],
    summary: dict[str, Any],
    failed_gate: str,
    recommended_next_stage: str,
    terminal_blocker_candidate: str | None,
    manifest: dict[str, Any],
    stage_name: str | None = None,
) -> dict[str, Any]:
    normal_ready = all(gates[key] for key in GATE_KEYS)
    levels = _level_readiness(gates, state, summary)
    signature = make_failure_signature(
        stage=str(summary.get("stage") or stage_name or ""),
        failed_gate=failed_gate,
        recommended_next_stage=recommended_next_stage,
        summary=summary,
        manifest=manifest,
    )
    return {
        "stage_status": stage_status,
        "gate_updates": gates,
        "normal_data_acquisition_ready": normal_ready,
        "level_readiness": levels,
        "paper_ready_throughput_gate": _paper_ready_throughput_gate(summary, manifest).get("met"),
        "paper_ready_recovery_gate": _gate_met(summary.get("paper_ready_recovery_gate")) or _gate_met(
            state.get("paper_ready_recovery_gate")
        ),
        "failed_gate": failed_gate,
        "failure_signature": signature,
        "recommended_next_stage": recommended_next_stage,
        "terminal_blocker_candidate": terminal_blocker_candidate,
    }


def make_failure_signature(
    *,
    stage: str,
    failed_gate: str,
    recommended_next_stage: str,
    summary: dict[str, Any],
    manifest: dict[str, Any] | None = None,
) -> str:
    manifest = manifest or {}
    bit = str(
        summary.get("active_bit_sha256")
        or summary.get("active_bit_hash")
        or manifest.get("active_bit_sha256")
        or manifest.get("bit_sha256")
        or "unknownbit"
    )[:12]
    config_hash = str(
        summary.get("configuration_hash")
        or manifest.get("configuration_hash")
        or "unknowncfg"
    )[:12]
    pattern_keys = (
        "pbm_wr_valid_cycles",
        "pbm_wr_accept_cycles",
        "pbm_valid_not_ready_cycles",
        "pbm_commit_entry_count",
        "pbm_wr_last_error_accepted_count",
        "rollback_event_count",
        "recovery_active_cycles",
        "error_qualified_packet_count",
        "bridge_tx_nonempty_cycles",
        "bridge_tx_rd_en_cycles",
        "crypto_dma_in_accept_cycles",
        "backend_accept_cycles",
        "stage1_inject_fire_cycles",
        "trigger_rate",
        "explicit_start_verified_by_hardware",
        "row_level_start_and_bridge_nonempty_seen",
        "dma_or_source_reader_busy_seen",
        "bridge_tx_nonempty_seen",
        "bridge_tx_rd_en_seen",
        "bridge_tx_accept_seen",
    )
    pattern_parts = []
    for key in pattern_keys:
        value = _nested_value(summary, key)
        if value is not None:
            pattern_parts.append(f"{key}{_num(value)}")
    pattern = "_".join(pattern_parts)
    if not pattern:
        pattern = "no_key_counters"
    raw = f"{stage}|{failed_gate}|{recommended_next_stage}|bit_{bit}|cfg_{config_hash}|{pattern}"
    return re.sub(r"[^A-Za-z0-9_.:-]+", "_", raw)


def _nested_value(data: Any, key: str) -> Any:
    if not isinstance(data, dict):
        return None
    if key in data:
        return data[key]
    for value in data.values():
        found = _nested_value(value, key)
        if found is not None:
            return found
    return None
