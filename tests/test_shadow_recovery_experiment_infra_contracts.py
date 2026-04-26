import importlib.util
import csv
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
PROBE_SCRIPT = REPO_ROOT / "HCS_SOC" / "run_ax7020_udp_gateway_shadow_mirror_recovery_counter_probe.ps1"
INFRA_SCRIPT = REPO_ROOT / "scripts" / "shadow_recovery_experiment_infra.py"
PIPELINE_GATES_SCRIPT = REPO_ROOT / "scripts" / "shadow_pipeline_gates.py"
PIPELINE_RUNNER_SCRIPT = REPO_ROOT / "scripts" / "shadow_full_data_acquisition_pipeline.py"
PIPELINE_REGISTRY_JSON = REPO_ROOT / "HCS_SOC" / "shadow_pipeline" / "stage_registry.json"
PIPELINE_STATE_TEMPLATE_JSON = REPO_ROOT / "HCS_SOC" / "shadow_pipeline" / "current_state.template.json"
PIPELINE_WRAPPER = REPO_ROOT / "HCS_SOC" / "run_shadow_full_data_acquisition_pipeline.ps1"
EXPORT_XSA_WRAPPER = REPO_ROOT / "HCS_SOC" / "export_udp_gateway_shadow_mirror_xsa.ps1"
AXIL_CSR = REPO_ROOT / "rtl" / "core" / "axil_csr.sv"
SCHEMA_DIR = REPO_ROOT / "doc" / "reports" / "engineering_evidence" / "shadow_recovery_probe_schema"
METRIC_SEMANTICS_MD = SCHEMA_DIR / "metric_semantics.md"
METRICS_SCHEMA_JSON = SCHEMA_DIR / "metrics_schema.json"


def load_infra_module():
    spec = importlib.util.spec_from_file_location("shadow_recovery_experiment_infra", INFRA_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_pipeline_gates_module():
    spec = importlib.util.spec_from_file_location("shadow_pipeline_gates", PIPELINE_GATES_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_pipeline_runner_module():
    spec = importlib.util.spec_from_file_location("shadow_full_data_acquisition_pipeline", PIPELINE_RUNNER_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestShadowRecoveryExperimentInfraContracts(unittest.TestCase):
    @staticmethod
    def _sha256(path: pathlib.Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def _write_reference_stage1a6_dirs(
        self,
        root: pathlib.Path,
        boot_file: pathlib.Path,
        bit_file: pathlib.Path,
        xsa_file: pathlib.Path,
    ) -> tuple[pathlib.Path, pathlib.Path]:
        full_dir = root / "shadow_recovery_probe_2026-04-24_000133"
        audit_dir = root / "shadow_recovery_probe_2026-04-24_075907"
        full_dir.mkdir(parents=True, exist_ok=True)
        audit_dir.mkdir(parents=True, exist_ok=True)

        boot_sha = self._sha256(boot_file)
        bit_sha = self._sha256(bit_file)
        xsa_sha = self._sha256(xsa_file)

        (full_dir / "run_manifest.json").write_text(
            json.dumps(
                {
                    "invocation_digest": "full-reference-digest",
                    "case_parameters": {
                        "stage": "Stage1A_BurstSweep",
                        "traffic_mode": "burst",
                        "burst_gap_us": 0,
                        "settle_ms": 500,
                        "load_class": "stage1_staircase",
                    },
                    "boot_bin": {"sha256": boot_sha},
                    "bit_file": {"sha256": bit_sha},
                    "xsa_file": {"sha256": xsa_sha},
                }
            ),
            encoding="utf-8",
        )
        with (full_dir / "case_results.csv").open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=["BurstFrames", "drop_pulse_count", "probe_window_id"])
            writer.writeheader()
            writer.writerows(
                [
                    {
                        "BurstFrames": "1",
                        "drop_pulse_count": "26000000",
                        "probe_window_id": "Stage1A_BurstSweep:bf0001:bg0000us:sm0500ms:r01:Case2_RuntimeRingBypass",
                    },
                    {
                        "BurstFrames": "8",
                        "drop_pulse_count": "27000000",
                        "probe_window_id": "Stage1A_BurstSweep:bf0008:bg0000us:sm0500ms:r01:Case2_RuntimeRingBypass",
                    },
                    {
                        "BurstFrames": "64",
                        "drop_pulse_count": "28000000",
                        "probe_window_id": "Stage1A_BurstSweep:bf0064:bg0000us:sm0500ms:r01:Case2_RuntimeRingBypass",
                    },
                ]
            )

        (audit_dir / "run_manifest.json").write_text(
            json.dumps(
                {
                    "invocation_digest": "audit-reference-digest",
                    "case_parameters": {
                        "stage": "Stage1A_DropPulseAudit",
                        "traffic_mode": "burst",
                        "burst_gap_us": 0,
                        "settle_ms": 500,
                        "load_class": "drop_pulse_audit",
                    },
                    "boot_bin": {"sha256": boot_sha},
                    "bit_file": {"sha256": bit_sha},
                    "xsa_file": {"sha256": xsa_sha},
                }
            ),
            encoding="utf-8",
        )
        return full_dir, audit_dir

    def _build_stage1a6_summary(
        self,
        tmp_path: pathlib.Path,
        drop_by_config: dict[str, int],
        pre_after_clear_nonzero_configs: set[str] | None = None,
    ) -> pathlib.Path:
        pre_after_clear_nonzero_configs = pre_after_clear_nonzero_configs or set()
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        configs = [("BF1_SM500", 1), ("BF8_SM500", 8), ("BF64_SM500", 64)]
        cases = []
        probe_ids = []
        for config_name, burst_frames in configs:
            for repeat in range(1, 4):
                probe_id = (
                    f"Stage1A6_PriorDropPulseReproduction:{config_name}:"
                    f"bf{burst_frames:04d}:sm0500ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                cases.append(
                    {
                        "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                        "base_name": "Case2_RuntimeRingBypass",
                        "reproduction_config": config_name,
                        "repeat": repeat,
                        "burst_frames": burst_frames,
                        "burst_gap_us": 0,
                        "settle_ms": 500,
                        "probe_window_id": probe_id,
                        "reproduction_mode": "controlled_sampling_replay",
                        "repro_pre_snapshot_after_clear_nonzero": config_name in pre_after_clear_nonzero_configs,
                        "source_progress_pre": 0,
                        "source_progress_post": burst_frames,
                        "sink_progress_pre": 0,
                        "sink_progress_post": 0,
                        "inj_status_active": "0x00000000",
                        "delta": {
                            "backend_total_cycles": 25_000_000,
                            "backend_accept_cycles": 0,
                            "backend_starvation_cycles": 0,
                            "rollback_event_count": 0,
                            "recovery_active_cycles": 0,
                            "high_water_count": 0,
                            "drop_pulse_count": drop_by_config[config_name],
                        },
                        "post": {"netdbg_status": "0x000521A5"},
                    }
                )

        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-24T10:00:00+00:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a6_cli(
        self,
        tmp_path: pathlib.Path,
        summary_path: pathlib.Path,
        full_dir: pathlib.Path,
        audit_dir: pathlib.Path,
        boot_file: pathlib.Path,
        bit_file: pathlib.Path,
        xsa_file: pathlib.Path,
    ) -> tuple[dict, str]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A6_PriorDropPulseReproduction",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "prior_drop_pulse_reproduction",
            "--reproduction-mode",
            "controlled_sampling_replay",
            "--stage1a6-reference-stage1a-full-dir",
            str(full_dir),
            "--stage1a6-reference-stage1a5-audit-dir",
            str(audit_dir),
            "--boot-bin",
            str(boot_file),
            "--bit-file",
            str(bit_file),
            "--xsa-file",
            str(xsa_file),
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        return stats, report

    def _build_stage1a7_summary(self, tmp_path: pathlib.Path) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        cases = []
        probe_ids = []
        configs = [
            ("BF8_SM500", 8, 500, "standard", "0x00000000", "0x00043FAA", 0),
            ("BF64_SM500", 64, 500, "standard", "0x00010008", "0x0000CF55", 27_000_000),
            ("BF64_SM100", 64, 100, "standard", "0x00010008", "0x0000CF55", 0),
            ("BF64_SM500_ExtraSnapshots", 64, 500, "extra_snapshots", "0x00010008", "0x0000CF55", 27_000_000),
        ]
        for config_name, burst_frames, settle_ms, snapshot_mode, inj_status, netdbg_status, drop_delta in configs:
            for repeat in range(1, 4):
                probe_id = (
                    f"Stage1A7_DropPulseConditionDiffDiagnosis:{config_name}:"
                    f"bf{burst_frames:04d}:sm{settle_ms:04d}ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                case = {
                    "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                    "base_name": "Case2_RuntimeRingBypass",
                    "condition_diff_config": config_name,
                    "repeat": repeat,
                    "burst_frames": burst_frames,
                    "burst_gap_us": 0,
                    "settle_ms": settle_ms,
                    "probe_window_id": probe_id,
                    "stage1a7_snapshot_mode": snapshot_mode,
                    "source_progress_pre": 0,
                    "source_progress_post": 0,
                    "sink_progress_pre": 0,
                    "sink_progress_post": 0,
                    "observed_injection_intensity_frames_per_probe_window": 0,
                    "inj_status_active": inj_status,
                    "delta": {
                        "backend_total_cycles": 90_000_000 if settle_ms == 500 else 18_000_000,
                        "backend_accept_cycles": 0,
                        "backend_starvation_cycles": 0,
                        "rollback_event_count": 0,
                        "recovery_active_cycles": 0,
                        "recovery_last_window_cycles": 0,
                        "recovery_max_window_cycles": 0,
                        "high_water_count": 0,
                        "drop_pulse_count": drop_delta,
                    },
                    "post": {"netdbg_status": netdbg_status},
                }
                if config_name.startswith("BF64"):
                    case.update(
                        {
                            "stage1_inject_tvalid": 1,
                            "stage1_inject_tready": 0,
                            "aclf_tvalid": 1,
                            "aclf_tready": 0,
                            "classifier_s_tvalid": 1,
                            "classifier_s_tready": 0,
                            "classifier_dma_tvalid": 1,
                            "classifier_dma_tready": 0,
                        }
                    )
                else:
                    case.update(
                        {
                            "stage1_inject_tvalid": 0,
                            "stage1_inject_tready": 1,
                            "aclf_tvalid": 0,
                            "aclf_tready": 1,
                            "classifier_s_tvalid": 0,
                            "classifier_s_tready": 1,
                            "classifier_dma_tvalid": 0,
                            "classifier_dma_tready": 1,
                        }
                    )
                if snapshot_mode == "extra_snapshots":
                    case["extra_snapshot_deltas"] = {
                        "drop_pulse_delta_at_post_injection": 1_000_000,
                        "drop_pulse_delta_at_050ms": 5_000_000,
                        "drop_pulse_delta_at_250ms": 15_000_000,
                        "drop_pulse_delta_at_500ms": 27_000_000,
                    }
                cases.append(case)

        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-24T12:00:00+00:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a7_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A7_DropPulseConditionDiffDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "drop_pulse_condition_diff",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _build_stage1a8_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        bf8_stall: bool = True,
        bf64_accept_cycles: int = 0,
        bf64_last_accepted_count: int = 0,
        bf64_last_error_accepted_count: int = 0,
        bf64_commit_entry_count: int = 0,
        bf64_rollback_entry_count: int = 0,
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        cases = []
        probe_ids = []
        configs = [
            ("IdleControl", 0, 500, "standard"),
            ("BF8_SM500", 8, 500, "standard"),
            ("BF64_SM500", 64, 500, "standard"),
            ("BF8_SM500_ExtraSnapshots", 8, 500, "extra_snapshots"),
            ("BF64_SM500_ExtraSnapshots", 64, 500, "extra_snapshots"),
        ]
        for config_name, burst_frames, settle_ms, snapshot_mode in configs:
            for repeat in range(1, 4):
                probe_id = (
                    f"Stage1A8_PBMIngressVisibilityDiagnosis:{config_name}:"
                    f"bf{burst_frames:04d}:sm{settle_ms:04d}ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                is_idle = config_name == "IdleControl"
                is_bf8 = config_name.startswith("BF8_")
                is_bf64 = config_name.startswith("BF64_")
                stall = (bf8_stall and is_bf8) or is_bf64
                drop_delta = 0 if is_idle or not stall else (9_000_000 if is_bf8 else 27_000_000)
                valid_cycles = 0 if is_idle else (3_000 if stall else 0)
                valid_not_ready_cycles = 0 if is_idle else (2_800 if stall else 0)
                accept_cycles = 0
                last_accepted = 0
                last_error_accepted = 0
                commit_entry = 0
                rollback_entry = 0
                ptr_reserve_post = 0
                ptr_commit_post = 0
                ptr_tail_post = 0
                buffer_usage_post = 0
                state_raw = 0
                if is_bf64:
                    accept_cycles = bf64_accept_cycles
                    last_accepted = bf64_last_accepted_count
                    last_error_accepted = bf64_last_error_accepted_count
                    commit_entry = bf64_commit_entry_count
                    rollback_entry = bf64_rollback_entry_count
                    ptr_reserve_post = 4 if bf64_accept_cycles > 0 else 0
                    ptr_commit_post = 4 if bf64_commit_entry_count > 0 else 0
                    buffer_usage_post = ptr_commit_post
                    state_raw = 1 if bf64_accept_cycles > 0 else 0
                case = {
                    "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                    "base_name": "Case2_RuntimeRingBypass",
                    "pbm_visibility_config": config_name,
                    "repeat": repeat,
                    "burst_frames": burst_frames,
                    "burst_gap_us": 0,
                    "settle_ms": settle_ms,
                    "probe_window_id": probe_id,
                    "stage1a8_snapshot_mode": snapshot_mode,
                    "source_progress_pre": 0,
                    "source_progress_post": 0,
                    "sink_progress_pre": 0,
                    "sink_progress_post": 0,
                    "observed_injection_intensity_frames_per_probe_window": 0,
                    "idle_control_quiesce_guard_ms": 10,
                    "idle_pre_after_clear_zero": True,
                    "idle_residual_activity_seen": False,
                    "delta": {
                        "backend_total_cycles": 90_000_000,
                        "backend_accept_cycles": 0,
                        "backend_starvation_cycles": 0,
                        "rollback_event_count": 0,
                        "recovery_active_cycles": 0,
                        "recovery_last_window_cycles": 0,
                        "recovery_max_window_cycles": 0,
                        "high_water_count": 0,
                        "drop_pulse_count": drop_delta,
                    },
                    "post": {
                        "netdbg_status": "0x0000CF55" if stall else "0x00043FAA",
                        "pbm_state_raw": state_raw,
                        "pbm_ptr_head_reserve": ptr_reserve_post,
                        "pbm_ptr_head_commit": ptr_commit_post,
                        "pbm_ptr_tail": ptr_tail_post,
                        "pbm_buffer_usage": buffer_usage_post,
                    },
                    "pbm_wr_valid_cycles": valid_cycles,
                    "pbm_wr_ready_high_cycles": 0 if stall else 1_000,
                    "pbm_valid_not_ready_cycles": valid_not_ready_cycles,
                    "pbm_wr_accept_cycles": accept_cycles,
                    "pbm_wr_last_accepted_count": last_accepted,
                    "pbm_wr_error_accepted_count": last_error_accepted,
                    "pbm_wr_last_error_accepted_count": last_error_accepted,
                    "pbm_alloc_meta_entry_count": 1 if accept_cycles > 0 else 0,
                    "pbm_alloc_pbm_entry_count": 1 if accept_cycles > 0 and last_accepted == 0 else 0,
                    "pbm_commit_entry_count": commit_entry,
                    "pbm_rollback_entry_count": rollback_entry,
                    "pbm_ptr_head_reserve_pre": 0,
                    "pbm_ptr_head_commit_pre": 0,
                    "pbm_ptr_tail_pre": 0,
                    "pbm_buffer_usage_pre": 0,
                    "inj_status_active": "0x00010008" if stall else "0x00000000",
                }
                if snapshot_mode == "extra_snapshots":
                    case["extra_snapshot_deltas"] = {
                        "drop_pulse_delta_at_post_injection": 500_000 if stall else 0,
                        "drop_pulse_delta_at_050ms": 2_000_000 if stall else 0,
                        "drop_pulse_delta_at_250ms": 8_000_000 if stall else 0,
                        "drop_pulse_delta_at_500ms": drop_delta,
                        "pbm_wr_valid_cycles_delta_at_post_injection": 200 if stall else 0,
                        "pbm_wr_valid_cycles_delta_at_050ms": 800 if stall else 0,
                        "pbm_wr_valid_cycles_delta_at_250ms": 1_600 if stall else 0,
                        "pbm_wr_valid_cycles_delta_at_500ms": valid_cycles,
                        "pbm_valid_not_ready_cycles_delta_at_post_injection": 180 if stall else 0,
                        "pbm_valid_not_ready_cycles_delta_at_050ms": 750 if stall else 0,
                        "pbm_valid_not_ready_cycles_delta_at_250ms": 1_500 if stall else 0,
                        "pbm_valid_not_ready_cycles_delta_at_500ms": valid_not_ready_cycles,
                        "pbm_wr_accept_cycles_delta_at_post_injection": 0,
                        "pbm_wr_accept_cycles_delta_at_050ms": 0,
                        "pbm_wr_accept_cycles_delta_at_250ms": accept_cycles,
                        "pbm_wr_accept_cycles_delta_at_500ms": accept_cycles,
                        "pbm_state_raw_at_post_injection": state_raw,
                        "pbm_state_raw_at_050ms": state_raw,
                        "pbm_state_raw_at_250ms": state_raw,
                        "pbm_state_raw_at_500ms": state_raw,
                        "pbm_ptr_head_reserve_at_post_injection": 0,
                        "pbm_ptr_head_reserve_at_050ms": 0,
                        "pbm_ptr_head_reserve_at_250ms": ptr_reserve_post,
                        "pbm_ptr_head_reserve_at_500ms": ptr_reserve_post,
                        "pbm_ptr_head_commit_at_post_injection": 0,
                        "pbm_ptr_head_commit_at_050ms": 0,
                        "pbm_ptr_head_commit_at_250ms": ptr_commit_post,
                        "pbm_ptr_head_commit_at_500ms": ptr_commit_post,
                        "pbm_ptr_tail_at_post_injection": 0,
                        "pbm_ptr_tail_at_050ms": 0,
                        "pbm_ptr_tail_at_250ms": ptr_tail_post,
                        "pbm_ptr_tail_at_500ms": ptr_tail_post,
                        "pbm_buffer_usage_at_post_injection": 0,
                        "pbm_buffer_usage_at_050ms": 0,
                        "pbm_buffer_usage_at_250ms": buffer_usage_post,
                        "pbm_buffer_usage_at_500ms": buffer_usage_post,
                    }
                cases.append(case)

        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-24T13:00:00+00:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a8_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A8_PBMIngressVisibilityDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "pbm_ingress_visibility",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _build_stage1a9_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        crypto_rx_seen: bool = True,
        pbm_seen: bool = False,
        crypto_rx_backpressured: bool = True,
        pbm_accept_seen: bool = False,
        pbm_commit_seen: bool = False,
        backend_activity_pattern: str = "none",
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        cases = []
        probe_ids = []
        configs = [
            ("IdleControl", 0, 500, "standard"),
            ("BF8_SM500", 8, 500, "standard"),
            ("BF64_SM500", 64, 500, "standard"),
            ("BF8_SM500_ExtraSnapshots", 8, 500, "extra_snapshots"),
            ("BF64_SM500_ExtraSnapshots", 64, 500, "extra_snapshots"),
        ]
        for config_name, burst_frames, settle_ms, snapshot_mode in configs:
            for repeat in range(1, 4):
                probe_id = (
                    f"Stage1A9_CryptoIngressHandoffVisibilityDiagnosis:{config_name}:"
                    f"bf{burst_frames:04d}:sm{settle_ms:04d}ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                is_idle = config_name == "IdleControl"
                active = (not is_idle) and crypto_rx_seen
                crypto_valid = 3_000 if active else 0
                crypto_vnr = 2_800 if active and crypto_rx_backpressured else 0
                crypto_accept = crypto_valid if active and not crypto_rx_backpressured else 0
                pbm_valid = 4 if active and pbm_seen else 0
                if active and (pbm_accept_seen or pbm_commit_seen):
                    pbm_valid = crypto_valid
                pbm_accept = pbm_valid if active and (pbm_accept_seen or pbm_commit_seen) else 0
                pbm_last_accepted = burst_frames if pbm_accept > 0 else 0
                pbm_commit = burst_frames if active and pbm_commit_seen else 0
                ptr_commit = pbm_accept if pbm_commit_seen else 0
                backend_active = (
                    active
                    and (
                        backend_activity_pattern == "all"
                        or (backend_activity_pattern == "intermittent" and config_name == "BF8_SM500")
                    )
                )
                case = {
                    "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                    "base_name": "Case2_RuntimeRingBypass",
                    "crypto_ingress_config": config_name,
                    "repeat": repeat,
                    "burst_frames": burst_frames,
                    "burst_gap_us": 0,
                    "settle_ms": settle_ms,
                    "probe_window_id": probe_id,
                    "stage1a9_snapshot_mode": snapshot_mode,
                    "source_progress_pre": 0,
                    "source_progress_post": 0,
                    "sink_progress_pre": 0,
                    "sink_progress_post": 0,
                    "observed_injection_intensity_frames_per_probe_window": 0,
                    "idle_control_quiesce_guard_ms": 10,
                    "idle_pre_after_clear_zero": True,
                    "idle_residual_activity_seen": False,
                    "delta": {
                        "backend_total_cycles": 90_000_000,
                        "backend_accept_cycles": 32 if backend_active else 0,
                        "backend_starvation_cycles": 32 if backend_active else 0,
                        "rollback_event_count": 0,
                        "recovery_active_cycles": 0,
                        "recovery_last_window_cycles": 0,
                        "recovery_max_window_cycles": 0,
                        "high_water_count": 0,
                        "drop_pulse_count": 27_000_000 if active else 0,
                    },
                    "post": {
                        "netdbg_status": "0x0000CF55" if active else "0x00043FAA",
                        "pbm_state_raw": 0,
                        "pbm_ptr_head_reserve": 0,
                        "pbm_ptr_head_commit": ptr_commit,
                        "pbm_ptr_tail": 0,
                        "pbm_buffer_usage": 0,
                    },
                    "pbm_wr_valid_cycles": pbm_valid,
                    "pbm_wr_ready_high_cycles": 0,
                    "pbm_valid_not_ready_cycles": 0,
                    "pbm_wr_accept_cycles": pbm_accept,
                    "pbm_wr_last_accepted_count": pbm_last_accepted,
                    "pbm_wr_error_accepted_count": 0,
                    "pbm_wr_last_error_accepted_count": 0,
                    "pbm_alloc_meta_entry_count": 0,
                    "pbm_alloc_pbm_entry_count": 0,
                    "pbm_commit_entry_count": pbm_commit,
                    "pbm_rollback_entry_count": 0,
                    "pbm_ptr_head_reserve_pre": 0,
                    "pbm_ptr_head_commit_pre": 0,
                    "pbm_ptr_tail_pre": 0,
                    "pbm_buffer_usage_pre": 0,
                    "crypto_rx_valid_cycles": crypto_valid,
                    "crypto_rx_ready_high_cycles": 0 if active else 1_000,
                    "crypto_rx_valid_not_ready_cycles": crypto_vnr,
                    "crypto_rx_accept_cycles": crypto_accept,
                    "crypto_rx_last_accepted_count": burst_frames if crypto_accept > 0 else 0,
                    "crypto_rx_error_accepted_count": 0,
                    "crypto_rx_last_error_accepted_count": 0,
                    "crypto_rx_pkt_end_accepted_count": burst_frames if crypto_accept > 0 else 0,
                    "inj_status_active": "0x00010008" if active else "0x00000000",
                }
                if snapshot_mode == "extra_snapshots":
                    case["extra_snapshot_deltas"] = {
                        "drop_pulse_delta_at_post_injection": 1_000_000 if active else 0,
                        "drop_pulse_delta_at_050ms": 6_000_000 if active else 0,
                        "drop_pulse_delta_at_250ms": 19_000_000 if active else 0,
                        "drop_pulse_delta_at_500ms": 35_000_000 if active else 0,
                        "crypto_rx_valid_cycles_delta_at_050ms": 500 if active else 0,
                        "crypto_rx_valid_not_ready_cycles_delta_at_050ms": 450 if active else 0,
                        "crypto_rx_accept_cycles_delta_at_050ms": 0,
                    }
                cases.append(case)
        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-24T14:30:00+00:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a9_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "crypto_ingress_handoff_visibility",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _build_stage1a10_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        tail_moves: bool = False,
        crypto_dma_accept_seen: bool = False,
        backend_activity_pattern: str = "none",
        completion_seen: bool = False,
        idle_crypto_dma_residual_seen: bool = False,
        active_commit_seen: bool = True,
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        cases = []
        probe_ids = []
        configs = [
            ("IdleControl", 0, 500, "standard"),
            ("BF8_SM500", 8, 500, "standard"),
            ("BF64_SM500", 64, 500, "standard"),
            ("BF8_SM500_ExtraSnapshots", 8, 500, "extra_snapshots"),
            ("BF64_SM500_ExtraSnapshots", 64, 500, "extra_snapshots"),
        ]
        for config_name, burst_frames, settle_ms, snapshot_mode in configs:
            for repeat in range(1, 4):
                probe_id = (
                    f"Stage1A10_CryptoDMAHandoffDiagnosis:{config_name}:"
                    f"bf{burst_frames:04d}:sm{settle_ms:04d}ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                is_idle = config_name == "IdleControl"
                active = not is_idle
                pbm_commit = burst_frames if active and active_commit_seen else 0
                pbm_accept = burst_frames * 8 if active and active_commit_seen else 0
                ptr_tail_delta = pbm_accept if active and tail_moves else 0
                crypto_dma_accept = pbm_accept if active and crypto_dma_accept_seen else 0
                crypto_dma_valid_cycles = 0
                crypto_dma_backpressure_cycles = 0
                if active:
                    crypto_dma_valid_cycles = 1_000
                    crypto_dma_backpressure_cycles = 1_000 - min(crypto_dma_accept, 1_000)
                elif idle_crypto_dma_residual_seen:
                    crypto_dma_valid_cycles = 1_000
                    crypto_dma_backpressure_cycles = 1_000
                backend_active = (
                    active
                    and (
                        backend_activity_pattern == "all"
                        or (backend_activity_pattern == "intermittent" and config_name == "BF8_SM500")
                    )
                )
                completion_count = 1 if active and completion_seen else 0
                case = {
                    "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                    "base_name": "Case2_RuntimeRingBypass",
                    "crypto_dma_handoff_config": config_name,
                    "repeat": repeat,
                    "burst_frames": burst_frames,
                    "burst_gap_us": 0,
                    "settle_ms": settle_ms,
                    "probe_window_id": probe_id,
                    "stage1a10_snapshot_mode": snapshot_mode,
                    "source_progress_pre": 0,
                    "source_progress_post": 0,
                    "sink_progress_pre": 0,
                    "sink_progress_post": 0,
                    "observed_injection_intensity_frames_per_probe_window": 0,
                    "idle_control_quiesce_guard_ms": 10,
                    "idle_pre_after_clear_zero": True,
                    "idle_residual_activity_seen": False,
                    "delta": {
                        "backend_total_cycles": 90_000_000,
                        "backend_accept_cycles": 32 if backend_active else 0,
                        "backend_starvation_cycles": 32 if backend_active else 0,
                        "rollback_event_count": 0,
                        "recovery_active_cycles": 0,
                        "recovery_last_window_cycles": 0,
                        "recovery_max_window_cycles": 0,
                        "high_water_count": 0,
                        "drop_pulse_count": 0,
                    },
                    "post": {
                        "netdbg_status": "0x0000CF55" if active else "0x00043FAA",
                        "pbm_state_raw": 0,
                        "pbm_ptr_head_reserve": pbm_accept,
                        "pbm_ptr_head_commit": pbm_accept,
                        "pbm_ptr_tail": ptr_tail_delta,
                        "pbm_buffer_usage": pbm_accept - ptr_tail_delta,
                    },
                    "pbm_wr_valid_cycles": pbm_accept,
                    "pbm_wr_ready_high_cycles": pbm_accept,
                    "pbm_valid_not_ready_cycles": 0,
                    "pbm_wr_accept_cycles": pbm_accept,
                    "pbm_wr_last_accepted_count": pbm_commit,
                    "pbm_wr_error_accepted_count": 0,
                    "pbm_wr_last_error_accepted_count": 0,
                    "pbm_alloc_meta_entry_count": 0,
                    "pbm_alloc_pbm_entry_count": pbm_commit,
                    "pbm_commit_entry_count": pbm_commit,
                    "pbm_rollback_entry_count": 0,
                    "pbm_ptr_head_reserve_pre": 0,
                    "pbm_ptr_head_commit_pre": 0,
                    "pbm_ptr_tail_pre": 0,
                    "pbm_buffer_usage_pre": 0,
                    "pbm_committed_available_cycles": 1_000 if active else 0,
                    "pbm_rd_empty_cycles": 0 if active else 1_000,
                    "pbm_rd_nonempty_cycles": 1_000 if active else 0,
                    "pbm_rd_en_cycles": ptr_tail_delta,
                    "pbm_rd_accept_cycles": ptr_tail_delta,
                    "crypto_rx_valid_cycles": pbm_accept,
                    "crypto_rx_ready_high_cycles": pbm_accept,
                    "crypto_rx_valid_not_ready_cycles": 0,
                    "crypto_rx_accept_cycles": pbm_accept,
                    "crypto_rx_last_accepted_count": pbm_commit,
                    "crypto_rx_error_accepted_count": 0,
                    "crypto_rx_last_error_accepted_count": 0,
                    "crypto_rx_pkt_end_accepted_count": pbm_commit,
                    "crypto_dma_in_valid_cycles": crypto_dma_valid_cycles,
                    "crypto_dma_in_ready_cycles": crypto_dma_accept,
                    "crypto_dma_in_accept_cycles": crypto_dma_accept,
                    "crypto_dma_backpressure_cycles": crypto_dma_backpressure_cycles,
                    "crypto_dma_in_last_seen_count": burst_frames if crypto_dma_accept > 0 else 0,
                    "crypto_dma_completion_count": completion_count,
                    "inj_status_active": "0x00010008" if active else "0x00000000",
                }
                if snapshot_mode == "extra_snapshots":
                    case["extra_snapshot_deltas"] = {
                        "pbm_rd_accept_cycles_delta_at_050ms": ptr_tail_delta,
                        "crypto_dma_in_accept_cycles_delta_at_050ms": crypto_dma_accept,
                        "crypto_dma_backpressure_cycles_delta_at_050ms": case["crypto_dma_backpressure_cycles"],
                    }
                cases.append(case)
        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-24T15:30:00+00:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a10_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A10_CryptoDMAHandoffDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "crypto_dma_handoff_diagnosis",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _build_stage1a11_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        bridge_rd_en_seen: bool = False,
        bridge_fire_seen: bool = False,
        data_without_inst_available_seen: bool = False,
        dma_start_seen: bool = False,
        dma_addr_seen: bool = False,
        dma_data_seen: bool = False,
        dma_aw_handshake_seen: bool = False,
        dma_w_handshake_seen: bool = False,
        dma_b_handshake_seen: bool = False,
        dma_wready_backpressure_seen: bool = False,
        backend_activity_pattern: str = "none",
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        cases = []
        probe_ids = []
        configs = [
            ("IdleControl", 0, 500, "standard"),
            ("BF8_SM500", 8, 500, "standard"),
            ("BF64_SM500", 64, 500, "standard"),
            ("BF8_SM500_ExtraSnapshots", 8, 500, "extra_snapshots"),
            ("BF64_SM500_ExtraSnapshots", 64, 500, "extra_snapshots"),
        ]
        for config_name, burst_frames, settle_ms, snapshot_mode in configs:
            for repeat in range(1, 4):
                probe_id = (
                    f"Stage1A11_PBMReadSideVisibilityDiagnosis:{config_name}:"
                    f"bf{burst_frames:04d}:sm{settle_ms:04d}ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                is_idle = config_name == "IdleControl"
                active = not is_idle
                pbm_commit = burst_frames if active else 0
                bridge_rd_en = burst_frames if active and bridge_rd_en_seen else 0
                bridge_fire = burst_frames if active and bridge_fire_seen else 0
                data_no_inst = 1_000 if active and data_without_inst_available_seen else 0
                dma_start = 1 if active and dma_start_seen else 0
                dma_addr = 32 if active and dma_addr_seen else 0
                dma_data = 64 if active and dma_data_seen else 0
                dma_aw = 1 if active and dma_aw_handshake_seen else 0
                dma_w = 64 if active and dma_w_handshake_seen else 0
                dma_b = 1 if active and dma_b_handshake_seen else 0
                dma_wready_low = 1_000 if active and dma_wready_backpressure_seen else 0
                backend_active = (
                    active
                    and (
                        backend_activity_pattern == "all"
                        or (backend_activity_pattern == "intermittent" and config_name == "BF8_SM500")
                    )
                )
                case = {
                    "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                    "base_name": "Case2_RuntimeRingBypass",
                    "pbm_read_side_config": config_name,
                    "repeat": repeat,
                    "burst_frames": burst_frames,
                    "burst_gap_us": 0,
                    "settle_ms": settle_ms,
                    "probe_window_id": probe_id,
                    "stage1a11_snapshot_mode": snapshot_mode,
                    "source_progress_pre": 0,
                    "source_progress_post": 0,
                    "sink_progress_pre": 0,
                    "sink_progress_post": 0,
                    "observed_injection_intensity_frames_per_probe_window": 0,
                    "idle_control_quiesce_guard_ms": 10,
                    "idle_pre_after_clear_zero": True,
                    "idle_residual_activity_seen": False,
                    "delta": {
                        "backend_total_cycles": 90_000_000,
                        "backend_accept_cycles": 16 if backend_active else 0,
                        "backend_starvation_cycles": 16 if backend_active else 0,
                        "rollback_event_count": 0,
                        "recovery_active_cycles": 0,
                        "recovery_last_window_cycles": 0,
                        "recovery_max_window_cycles": 0,
                        "high_water_count": 0,
                        "drop_pulse_count": 0,
                    },
                    "post": {
                        "netdbg_status": "0x0000CF55" if active else "0x00000000",
                        "pbm_state_raw": 0,
                        "pbm_ptr_head_reserve": burst_frames * 8 if active else 0,
                        "pbm_ptr_head_commit": burst_frames * 8 if active else 0,
                        "pbm_ptr_tail": 0,
                        "pbm_buffer_usage": burst_frames * 8 if active else 0,
                        "bridge_input_state_raw": 1 if active else 0,
                        "dma_state_raw": 2 if active and dma_data_seen else 0,
                    },
                    "pbm_commit_entry_count": pbm_commit,
                    "pbm_ptr_head_commit_pre": 0,
                    "pbm_ptr_head_commit": burst_frames * 8 if active else 0,
                    "pbm_ptr_head_reserve_pre": 0,
                    "pbm_ptr_head_reserve": burst_frames * 8 if active else 0,
                    "pbm_ptr_tail_pre": 0,
                    "pbm_ptr_tail": 0,
                    "pbm_buffer_usage_pre": 0,
                    "bridge_pbm_rd_en_cycles": bridge_rd_en,
                    "bridge_pbm_fire_count": bridge_fire,
                    "bridge_inst_available_cycles": 1_000 if active and (bridge_rd_en_seen or bridge_fire_seen) else 0,
                    "bridge_data_available_no_inst_available_cycles": data_no_inst,
                    "bridge_mid_fifo_full_cycles": 0,
                    "bridge_out_fifo_full_cycles": 0,
                    "bridge_input_state_raw": 1 if active else 0,
                    "dma_start_seen_count": dma_start,
                    "dma_addr_cycles": dma_addr,
                    "dma_data_cycles": dma_data,
                    "dma_resp_cycles": 16 if active and dma_b_handshake_seen else 0,
                    "dma_aw_handshake_count": dma_aw,
                    "dma_w_handshake_count": dma_w,
                    "dma_b_handshake_count": dma_b,
                    "dma_wready_low_cycles": dma_wready_low,
                    "dma_state_raw": 2 if active and dma_data_seen else 0,
                    "inj_status_active": "0x00010008" if active else "0x00000000",
                }
                if snapshot_mode == "extra_snapshots":
                    case["extra_snapshot_deltas"] = {
                        "bridge_pbm_rd_en_cycles_delta_at_050ms": bridge_rd_en,
                        "bridge_pbm_fire_count_delta_at_050ms": bridge_fire,
                        "dma_start_seen_count_delta_at_050ms": dma_start,
                        "dma_w_handshake_count_delta_at_050ms": dma_w,
                    }
                cases.append(case)
        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-24T16:30:00+00:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a11_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A11_PBMReadSideVisibilityDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "pbm_read_side_visibility",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _build_stage1a12_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        idle_bridge_residual_seen: bool = False,
        dma_start_seen: bool = False,
        bridge_tx_rd_en_seen: bool = False,
        bridge_tx_accept_seen: bool = False,
        bridge_tx_last_seen: bool = False,
        backend_activity_pattern: str = "none",
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        cases = []
        probe_ids = []
        configs = [
            ("IdleControl", 0, 500, "standard"),
            ("BF8_SM500", 8, 500, "standard"),
            ("BF64_SM500", 64, 500, "standard"),
            ("BF8_SM500_ExtraSnapshots", 8, 500, "extra_snapshots"),
            ("BF64_SM500_ExtraSnapshots", 64, 500, "extra_snapshots"),
        ]
        for config_name, burst_frames, settle_ms, snapshot_mode in configs:
            for repeat in range(1, 4):
                probe_id = (
                    f"Stage1A12_BridgeOutputFIFOVisibilityDiagnosis:{config_name}:"
                    f"bf{burst_frames:04d}:sm{settle_ms:04d}ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                is_idle = config_name == "IdleControl"
                active = not is_idle
                bridge_nonempty = 0
                if active:
                    bridge_nonempty = 1_000 + burst_frames
                elif idle_bridge_residual_seen:
                    bridge_nonempty = 2_000
                bridge_rd_en = burst_frames if active and bridge_tx_rd_en_seen else 0
                bridge_accept = burst_frames if active and bridge_tx_accept_seen else 0
                bridge_last = 1 if active and bridge_tx_last_seen else 0
                backend_active = (
                    active
                    and (
                        backend_activity_pattern == "all"
                        or (backend_activity_pattern == "intermittent" and config_name == "BF8_SM500")
                    )
                )
                case = {
                    "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                    "base_name": "Case2_RuntimeRingBypass",
                    "bridge_output_fifo_config": config_name,
                    "repeat": repeat,
                    "burst_frames": burst_frames,
                    "burst_gap_us": 0,
                    "settle_ms": settle_ms,
                    "probe_window_id": probe_id,
                    "stage1a12_snapshot_mode": snapshot_mode,
                    "source_progress_pre": 0,
                    "source_progress_post": 0,
                    "sink_progress_pre": 0,
                    "sink_progress_post": 0,
                    "observed_injection_intensity_frames_per_probe_window": 0,
                    "idle_control_quiesce_guard_ms": 10,
                    "idle_pre_after_clear_zero": True,
                    "idle_residual_activity_seen": False,
                    "delta": {
                        "backend_total_cycles": 90_000_000,
                        "backend_accept_cycles": 16 if backend_active else 0,
                        "backend_starvation_cycles": 16 if backend_active else 0,
                        "rollback_event_count": 0,
                        "recovery_active_cycles": 0,
                        "recovery_last_window_cycles": 0,
                        "recovery_max_window_cycles": 0,
                        "high_water_count": 0,
                        "drop_pulse_count": 0,
                    },
                    "post": {
                        "netdbg_status": "0x0000CF55" if active else "0x00000000",
                        "pbm_state_raw": 0,
                    },
                    "bridge_tx_nonempty_cycles": bridge_nonempty,
                    "bridge_tx_rd_en_cycles": bridge_rd_en,
                    "bridge_tx_accept_cycles": bridge_accept,
                    "bridge_tx_last_seen_count": bridge_last,
                    "dma_start_seen_count": 1 if active and dma_start_seen else 0,
                    "dma_state_raw": 2 if active and dma_start_seen else 0,
                    "inj_status_active": "0x00010008" if active else "0x00000000",
                }
                if snapshot_mode == "extra_snapshots":
                    case["extra_snapshot_deltas"] = {
                        "bridge_tx_nonempty_cycles_delta_at_post_injection": bridge_nonempty // 4,
                        "bridge_tx_nonempty_cycles_delta_at_050ms": bridge_nonempty // 2,
                        "bridge_tx_nonempty_cycles_delta_at_250ms": (bridge_nonempty * 3) // 4,
                        "bridge_tx_nonempty_cycles_delta_at_500ms": bridge_nonempty,
                        "bridge_tx_rd_en_cycles_delta_at_post_injection": bridge_rd_en // 4,
                        "bridge_tx_rd_en_cycles_delta_at_050ms": bridge_rd_en // 2,
                        "bridge_tx_rd_en_cycles_delta_at_250ms": (bridge_rd_en * 3) // 4,
                        "bridge_tx_rd_en_cycles_delta_at_500ms": bridge_rd_en,
                        "bridge_tx_accept_cycles_delta_at_post_injection": bridge_accept // 4,
                        "bridge_tx_accept_cycles_delta_at_050ms": bridge_accept // 2,
                        "bridge_tx_accept_cycles_delta_at_250ms": (bridge_accept * 3) // 4,
                        "bridge_tx_accept_cycles_delta_at_500ms": bridge_accept,
                        "bridge_tx_last_seen_count_delta_at_post_injection": 0,
                        "bridge_tx_last_seen_count_delta_at_050ms": 0,
                        "bridge_tx_last_seen_count_delta_at_250ms": 0,
                        "bridge_tx_last_seen_count_delta_at_500ms": bridge_last,
                    }
                cases.append(case)
        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-24T20:55:00+00:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a12_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "bridge_output_fifo_visibility",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _build_stage1a13_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        current_overrides: dict[str, object] | None = None,
        explicit_overrides: dict[str, object] | None = None,
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        cases: list[dict[str, object]] = []
        probe_ids: list[str] = []

        base_defaults = {
            "burst_gap_us": 0,
            "settle_ms": 500,
            "source_progress_pre": 0,
            "source_progress_post": 0,
            "sink_progress_pre": 0,
            "sink_progress_post": 0,
            "observed_injection_intensity_frames_per_probe_window": 0,
            "runtime_ring_bypass_enabled": True,
            "fastpath_enabled": False,
            "ring_size_zero": True,
            "bridge_tx_nonempty_cycles": 1_064,
            "bridge_tx_rd_en_cycles": 0,
            "bridge_tx_accept_cycles": 0,
            "bridge_tx_last_seen_count": 0,
            "csr_start_pulse_count": 0,
            "ring_doorbell_pulse_count": 0,
            "fetcher_start_pulse_count": 0,
            "final_start_pulse_count": 0,
            "source_reader_start_pulse_count": 0,
            "dma_start_seen_count": 0,
            "dma_busy_cycles": 0,
            "source_reader_busy_cycles": 0,
            "crypto_dma_in_accept_cycles": 0,
            "inj_status_active": "0x00010008",
            "delta": {
                "backend_total_cycles": 90_000_000,
                "backend_accept_cycles": 0,
                "backend_starvation_cycles": 0,
                "rollback_event_count": 0,
                "recovery_active_cycles": 0,
                "recovery_last_window_cycles": 0,
                "recovery_max_window_cycles": 0,
                "high_water_count": 0,
                "drop_pulse_count": 0,
            },
            "post": {
                "netdbg_status": "0x0000CF55",
                "pbm_state_raw": 0,
            },
        }

        current_defaults = {
            **base_defaults,
            "dma_start_path_config": "Current_Bypass_NoExplicitStart",
            "stage1a13_explicit_csr_start": False,
        }
        explicit_defaults = {
            **base_defaults,
            "dma_start_path_config": "Bypass_WithExplicitCSRStart",
            "stage1a13_explicit_csr_start": True,
            "bridge_tx_rd_en_cycles": 64,
            "bridge_tx_accept_cycles": 64,
            "csr_start_pulse_count": 1,
            "final_start_pulse_count": 1,
            "dma_start_seen_count": 1,
            "dma_busy_cycles": 64,
            "crypto_dma_in_accept_cycles": 64,
        }
        if current_overrides:
            current_defaults.update(current_overrides)
        if explicit_overrides:
            explicit_defaults.update(explicit_overrides)

        configs = [
            (current_defaults["dma_start_path_config"], current_defaults),
            (explicit_defaults["dma_start_path_config"], explicit_defaults),
        ]
        for config_name, config in configs:
            for repeat in range(1, 4):
                burst_frames = 64
                settle_ms = int(config["settle_ms"])
                probe_id = (
                    f"Stage1A13_DMAStartPathDiagnosis:{config_name}:"
                    f"bf{burst_frames:04d}:sm{settle_ms:04d}ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                case = {
                    "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                    "base_name": "Case2_RuntimeRingBypass",
                    "dma_start_path_config": config_name,
                    "repeat": repeat,
                    "burst_frames": burst_frames,
                    "burst_gap_us": config["burst_gap_us"],
                    "settle_ms": settle_ms,
                    "probe_window_id": probe_id,
                    "source_progress_pre": config["source_progress_pre"],
                    "source_progress_post": config["source_progress_post"],
                    "sink_progress_pre": config["sink_progress_pre"],
                    "sink_progress_post": config["sink_progress_post"],
                    "observed_injection_intensity_frames_per_probe_window": config[
                        "observed_injection_intensity_frames_per_probe_window"
                    ],
                    "runtime_ring_bypass_enabled": config["runtime_ring_bypass_enabled"],
                    "fastpath_enabled": config["fastpath_enabled"],
                    "ring_size_zero": config["ring_size_zero"],
                    "stage1a13_explicit_csr_start": config["stage1a13_explicit_csr_start"],
                    "bridge_tx_nonempty_cycles": config["bridge_tx_nonempty_cycles"],
                    "bridge_tx_rd_en_cycles": config["bridge_tx_rd_en_cycles"],
                    "bridge_tx_accept_cycles": config["bridge_tx_accept_cycles"],
                    "bridge_tx_last_seen_count": config["bridge_tx_last_seen_count"],
                    "csr_start_pulse_count": config["csr_start_pulse_count"],
                    "ring_doorbell_pulse_count": config["ring_doorbell_pulse_count"],
                    "fetcher_start_pulse_count": config["fetcher_start_pulse_count"],
                    "final_start_pulse_count": config["final_start_pulse_count"],
                    "source_reader_start_pulse_count": config["source_reader_start_pulse_count"],
                    "dma_start_seen_count": config["dma_start_seen_count"],
                    "dma_busy_cycles": config["dma_busy_cycles"],
                    "source_reader_busy_cycles": config["source_reader_busy_cycles"],
                    "crypto_dma_in_accept_cycles": config["crypto_dma_in_accept_cycles"],
                    "inj_status_active": config["inj_status_active"],
                    "delta": config["delta"],
                    "post": config["post"],
                }
                cases.append(case)
        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-24T22:10:00+00:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a13_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A13_DMAStartPathDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "dma_start_path",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _build_stage1a14_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        overrides: dict[str, object] | None = None,
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        config = {
            "start_pulse_injection_config": "ExplicitStartWrite_Readback",
            "explicit_start_write_addr": "0x40001000",
            "explicit_start_write_value": "0x00000801",
            "explicit_start_write_mask_or_wstrb": "0xF",
            "explicit_start_readback_before": "0x00000800",
            "explicit_start_readback_after": "0x00000800",
            "csr_start_pulsed_by_probe": True,
            "explicit_csr_start_pulsed_by_probe": True,
            "csr_control_reg_addr_expected": "0x40001000",
            "csr_start_bit_expected": 0,
            "axil_write_hit_control_count": 1,
            "axil_write_hit_start_count": 0,
            "axil_write_hit_doorbell_count": 0,
            "csr_start_pulse_count": 0,
            "ring_doorbell_pulse_count": 0,
            "fetcher_start_pulse_count": 0,
            "final_start_pulse_count": 0,
            "source_reader_start_pulse_count": 0,
            "dma_start_seen_count": 0,
            "ring_size_zero": True,
            "runtime_ring_bypass_enabled": True,
            "fastpath_enabled": False,
            "bridge_tx_nonempty_cycles": 1024,
            "bridge_tx_rd_en_cycles": 0,
            "bridge_tx_accept_cycles": 0,
            "crypto_dma_in_accept_cycles": 0,
        }
        if overrides:
            config.update(overrides)

        cases: list[dict[str, object]] = []
        probe_ids: list[str] = []
        for repeat in range(1, 4):
            probe_id = (
                "Stage1A14_StartPulseInjectionOrProbeControlFix:"
                f"{config['start_pulse_injection_config']}:"
                f"bf0064:sm0500ms:r{repeat:02d}:Case2_RuntimeRingBypass"
            )
            probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
            cases.append(
                {
                    "name": f"{config['start_pulse_injection_config']}.r{repeat:02d}.Case2_RuntimeRingBypass",
                    "base_name": "Case2_RuntimeRingBypass",
                    "repeat": repeat,
                    "burst_frames": 64,
                    "burst_gap_us": 0,
                    "settle_ms": 500,
                    "probe_window_id": probe_id,
                    "delta": {
                        "backend_total_cycles": 90_000_000,
                        "backend_accept_cycles": 0,
                        "backend_starvation_cycles": 0,
                        "rollback_event_count": 0,
                        "recovery_active_cycles": 0,
                        "recovery_last_window_cycles": 0,
                        "recovery_max_window_cycles": 0,
                        "high_water_count": 0,
                        "drop_pulse_count": 0,
                    },
                    "post": {"netdbg_status": "0x0000CF55"},
                    **config,
                }
            )

        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-25T00:20:00+08:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a14_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A14_StartPulseInjectionOrProbeControlFix",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "start_pulse_injection",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _build_stage1a15_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        config_overrides: dict[str, dict[str, object]] | None = None,
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        defaults_by_config: dict[str, dict[str, object]] = {
            "Current_Bypass_NoExplicitStart": {
                "explicit_start_timing": "none",
                "start_delay_ms": 0,
                "csr_start_pulsed_by_probe": False,
                "explicit_csr_start_pulsed_by_probe": False,
                "axil_write_hit_start_count": 0,
                "csr_start_pulse_count": 0,
                "final_start_pulse_count": 0,
                "dma_start_seen_count": 0,
                "dma_busy_cycles": 0,
                "source_reader_busy_cycles": 0,
                "bridge_tx_nonempty_cycles": 1024,
            },
            "Bypass_ExplicitStart_BeforeWorkload": {
                "explicit_start_timing": "before_workload",
                "start_delay_ms": 0,
                "csr_start_pulsed_by_probe": True,
                "explicit_csr_start_pulsed_by_probe": True,
                "axil_write_hit_start_count": 1,
                "csr_start_pulse_count": 1,
                "final_start_pulse_count": 1,
                "dma_start_seen_count": 1,
                "dma_busy_cycles": 1,
                "source_reader_busy_cycles": 1,
                "bridge_tx_nonempty_cycles": 0,
            },
            "Bypass_ExplicitStart_AfterWorkload": {
                "explicit_start_timing": "after_workload_50ms",
                "start_delay_ms": 50,
                "csr_start_pulsed_by_probe": True,
                "explicit_csr_start_pulsed_by_probe": True,
                "axil_write_hit_start_count": 1,
                "csr_start_pulse_count": 1,
                "final_start_pulse_count": 1,
                "dma_start_seen_count": 1,
                "dma_busy_cycles": 1,
                "source_reader_busy_cycles": 1,
                "bridge_tx_nonempty_cycles": 0,
            },
        }
        if config_overrides:
            for config_name, overrides in config_overrides.items():
                defaults_by_config[config_name].update(overrides)

        cases: list[dict[str, object]] = []
        probe_ids: list[str] = []
        for config_name, config in defaults_by_config.items():
            for repeat in range(1, 4):
                probe_id = (
                    "Stage1A15_ExplicitStartBridgeHandoffDiagnosis:"
                    f"{config_name}:bf0064:sm0500ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                cases.append(
                    {
                        "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                        "base_name": "Case2_RuntimeRingBypass",
                        "repeat": repeat,
                        "burst_frames": 64,
                        "burst_gap_us": 0,
                        "settle_ms": 500,
                        "probe_window_id": probe_id,
                        "delta": {
                            "backend_total_cycles": 90_000_000,
                            "backend_accept_cycles": 0,
                            "backend_starvation_cycles": 0,
                            "rollback_event_count": 0,
                            "recovery_active_cycles": 0,
                            "recovery_last_window_cycles": 0,
                            "recovery_max_window_cycles": 0,
                            "high_water_count": 0,
                            "drop_pulse_count": 0,
                        },
                        "post": {"netdbg_status": "0x0000CF55"},
                        "explicit_start_bridge_handoff_config": config_name,
                        "shadow_control_base": "0x40000000",
                        "dma_csr_base": "0x40001000",
                        "explicit_start_write_addr": "0x40001000",
                        "explicit_start_write_value": "0x00000801",
                        "explicit_start_write_mask_or_wstrb": "0xF",
                        "explicit_start_write_addr_matches_dma_csr_base": True,
                        "dma_ctrl_read_before": "0x00000800",
                        "dma_ctrl_read_after": "0x00000800",
                        "explicit_start_readback_before": "0x00000800",
                        "explicit_start_readback_after": "0x00000800",
                        "axil_write_hit_control_count": 1 if config["explicit_start_timing"] != "none" else 0,
                        "axil_write_hit_doorbell_count": 0,
                        "bridge_tx_rd_en_cycles": 0,
                        "bridge_tx_accept_cycles": 0,
                        "crypto_dma_in_accept_cycles": 0,
                        **config,
                    }
                )

        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-25T10:40:00+08:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a15_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A15_ExplicitStartBridgeHandoffDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "explicit_start_bridge_handoff",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _build_stage1a16_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        config_overrides: dict[str, dict[str, object]] | None = None,
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        defaults_by_config: dict[str, dict[str, object]] = {
            "A12_NoStart_Replay": {
                "explicit_start_timing": "none",
                "start_delay_ms": 0,
                "axil_write_hit_start_count": 0,
                "csr_start_pulse_count": 0,
                "final_start_pulse_count": 0,
                "dma_start_seen_count": 0,
                "dma_busy_cycles": 0,
                "source_reader_busy_cycles": 0,
                "pbm_commit_entry_count": 1,
                "bridge_tx_nonempty_cycles": 1024,
                "bridge_tx_wr_en_cycles": 32,
                "bridge_tx_fifo_level": 1,
                "bridge_tx_fifo_level_max": 4,
            },
            "A15_AfterWorkloadStart_Replay": {
                "explicit_start_timing": "after_workload_50ms",
                "start_delay_ms": 50,
                "axil_write_hit_start_count": 1,
                "csr_start_pulse_count": 1,
                "final_start_pulse_count": 1,
                "dma_start_seen_count": 1,
                "dma_busy_cycles": 1,
                "source_reader_busy_cycles": 1,
                "pbm_commit_entry_count": 1,
                "bridge_tx_nonempty_cycles": 0,
                "bridge_tx_wr_en_cycles": 0,
                "bridge_tx_fifo_level": 0,
                "bridge_tx_fifo_level_max": 0,
            },
        }
        if config_overrides:
            for config_name, overrides in config_overrides.items():
                defaults_by_config[config_name].update(overrides)

        cases: list[dict[str, object]] = []
        probe_ids: list[str] = []
        for config_name, config in defaults_by_config.items():
            for repeat in range(1, 4):
                probe_id = (
                    "Stage1A16_BridgeDataProductionDiagnosis:"
                    f"{config_name}:bf0064:sm0500ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                bridge_level = int(config.get("bridge_tx_fifo_level", 0))
                cases.append(
                    {
                        "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                        "base_name": "Case2_RuntimeRingBypass",
                        "repeat": repeat,
                        "burst_frames": 64,
                        "burst_gap_us": 0,
                        "settle_ms": 500,
                        "probe_window_id": probe_id,
                        "delta": {
                            "backend_total_cycles": 90_000_000,
                            "backend_accept_cycles": 0,
                            "backend_starvation_cycles": 0,
                            "rollback_event_count": 0,
                            "recovery_active_cycles": 0,
                            "recovery_last_window_cycles": 0,
                            "recovery_max_window_cycles": 0,
                            "high_water_count": 0,
                            "drop_pulse_count": 0,
                        },
                        "pre": {
                            "bridge_tx_fifo_level": 0,
                        },
                        "post": {
                            "netdbg_status": "0x0000CF55",
                            "bridge_tx_fifo_level": bridge_level,
                        },
                        "bridge_data_production_config": config_name,
                        "shadow_control_base": "0x40000000",
                        "dma_csr_base": "0x40001000",
                        "explicit_start_write_addr": "0x40001000",
                        "explicit_start_write_value": "0x00000801",
                        "explicit_start_write_mask_or_wstrb": "0xF",
                        "explicit_start_write_addr_matches_dma_csr_base": True,
                        "dma_ctrl_read_before": "0x00000800",
                        "dma_ctrl_read_after": "0x00000800",
                        "dma_ctrl_changed_bits": "0x00000000",
                        "start_bit_mask": "0x00000001",
                        "bridge_tx_rd_en_cycles": 0,
                        "bridge_tx_accept_cycles": 0,
                        "crypto_dma_in_accept_cycles": 0,
                        **config,
                    }
                )

        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-25T11:40:00+08:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a16_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A16_BridgeDataProductionDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "bridge_data_production",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _build_stage1a17_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        config_overrides: dict[str, dict[str, object]] | None = None,
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        defaults_by_config: dict[str, dict[str, object]] = {
            "CommitReferenceReplay": {
                "stage1a17_snapshot_mode": "normal",
                "pbm_wr_valid_cycles": 0,
                "pbm_wr_ready_high_cycles": 0,
                "pbm_valid_not_ready_cycles": 0,
                "pbm_wr_accept_cycles": 0,
                "pbm_wr_last_accepted_count": 0,
                "pbm_wr_error_accepted_count": 0,
                "pbm_wr_last_error_accepted_count": 0,
                "pbm_alloc_meta_entry_count": 0,
                "pbm_alloc_pbm_entry_count": 0,
                "pbm_commit_entry_count": 0,
                "pbm_rollback_entry_count": 0,
                "pbm_ptr_head_reserve_pre": 0,
                "pbm_ptr_head_reserve": 0,
                "pbm_ptr_head_commit_pre": 0,
                "pbm_ptr_head_commit": 0,
                "pbm_ptr_tail_pre": 0,
                "pbm_ptr_tail": 0,
                "pbm_buffer_usage_pre": 0,
                "pbm_buffer_usage": 0,
            },
            "CommitReplay_WithExtraPBMSnapshots": {
                "stage1a17_snapshot_mode": "extra_snapshots",
                "pbm_wr_valid_cycles": 0,
                "pbm_wr_ready_high_cycles": 0,
                "pbm_valid_not_ready_cycles": 0,
                "pbm_wr_accept_cycles": 0,
                "pbm_wr_last_accepted_count": 0,
                "pbm_wr_error_accepted_count": 0,
                "pbm_wr_last_error_accepted_count": 0,
                "pbm_alloc_meta_entry_count": 0,
                "pbm_alloc_pbm_entry_count": 0,
                "pbm_commit_entry_count": 0,
                "pbm_rollback_entry_count": 0,
                "pbm_ptr_head_reserve_pre": 0,
                "pbm_ptr_head_reserve": 0,
                "pbm_ptr_head_commit_pre": 0,
                "pbm_ptr_head_commit": 0,
                "pbm_ptr_tail_pre": 0,
                "pbm_ptr_tail": 0,
                "pbm_buffer_usage_pre": 0,
                "pbm_buffer_usage": 0,
            },
        }
        if config_overrides:
            for config_name, overrides in config_overrides.items():
                defaults_by_config[config_name].update(overrides)

        cases: list[dict[str, object]] = []
        probe_ids: list[str] = []
        for config_name, config in defaults_by_config.items():
            for repeat in range(1, 4):
                probe_id = (
                    "Stage1A17_PBMCommitReproductionDiagnosis:"
                    f"{config_name}:bf0064:sm0500ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                cases.append(
                    {
                        "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                        "base_name": "Case2_RuntimeRingBypass",
                        "repeat": repeat,
                        "burst_frames": 64,
                        "burst_gap_us": 0,
                        "settle_ms": 500,
                        "probe_window_id": probe_id,
                        "delta": {
                            "backend_total_cycles": 90_000_000,
                            "backend_accept_cycles": 0,
                            "backend_starvation_cycles": 0,
                            "rollback_event_count": 0,
                            "recovery_active_cycles": 0,
                            "recovery_last_window_cycles": 0,
                            "recovery_max_window_cycles": 0,
                            "high_water_count": 0,
                            "drop_pulse_count": 0,
                        },
                        "pre": {
                            "pbm_ptr_head_reserve": config.get("pbm_ptr_head_reserve_pre", 0),
                            "pbm_ptr_head_commit": config.get("pbm_ptr_head_commit_pre", 0),
                            "pbm_ptr_tail": config.get("pbm_ptr_tail_pre", 0),
                            "pbm_buffer_usage": config.get("pbm_buffer_usage_pre", 0),
                        },
                        "post": {
                            "netdbg_status": "0x00043FAA",
                            "pbm_ptr_head_reserve": config.get("pbm_ptr_head_reserve", 0),
                            "pbm_ptr_head_commit": config.get("pbm_ptr_head_commit", 0),
                            "pbm_ptr_tail": config.get("pbm_ptr_tail", 0),
                            "pbm_buffer_usage": config.get("pbm_buffer_usage", 0),
                        },
                        "pbm_commit_reproduction_config": config_name,
                        "runtime_ring_bypass_enabled": True,
                        "fastpath_enabled": True,
                        **config,
                    }
                )

        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-25T13:30:00+08:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a17_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A17_PBMCommitReproductionDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "pbm_commit_reproduction",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    @staticmethod
    def _stage1a18_netdbg_status(
        *,
        stage1_inject_tvalid: int = 0,
        stage1_inject_tready: int = 0,
        aclf_tvalid: int = 0,
        aclf_tready: int = 0,
        classifier_s_tvalid: int = 0,
        classifier_s_tready: int = 0,
        classifier_dma_tvalid: int = 0,
        classifier_dma_tready: int = 0,
        netdbg_stage1_fire_seen: int = 0,
        netdbg_acl_fire_seen: int = 0,
        netdbg_classifier_in_fire_seen: int = 0,
        netdbg_classifier_dma_valid_seen: int = 0,
        netdbg_classifier_dma_fire_seen: int = 0,
        netdbg_classifier_dma_ready_seen: int = 0,
        route_state: int = 0,
        netdbg_acl_drop_pulse: int = 0,
        netdbg_classifier_dma_idle: int = 0,
    ) -> str:
        raw = 0
        raw |= (stage1_inject_tvalid & 1) << 0
        raw |= (stage1_inject_tready & 1) << 1
        raw |= (aclf_tvalid & 1) << 2
        raw |= (aclf_tready & 1) << 3
        raw |= (classifier_s_tvalid & 1) << 4
        raw |= (classifier_s_tready & 1) << 5
        raw |= (classifier_dma_tvalid & 1) << 6
        raw |= (classifier_dma_tready & 1) << 7
        raw |= (netdbg_stage1_fire_seen & 1) << 8
        raw |= (netdbg_acl_fire_seen & 1) << 9
        raw |= (netdbg_classifier_in_fire_seen & 1) << 10
        raw |= (netdbg_classifier_dma_valid_seen & 1) << 11
        raw |= (netdbg_classifier_dma_fire_seen & 1) << 12
        raw |= (netdbg_classifier_dma_ready_seen & 1) << 13
        raw |= (route_state & 0x7) << 14
        raw |= (netdbg_acl_drop_pulse & 1) << 17
        raw |= (netdbg_classifier_dma_idle & 1) << 18
        return f"0x{raw:08X}"

    def _build_stage1a18_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        config_overrides: dict[str, dict[str, object]] | None = None,
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        defaults_by_config: dict[str, dict[str, object]] = {
            "IngressReferenceReplay": {
                "stage1a18_snapshot_mode": "normal",
                "runtime_ring_bypass_enabled": True,
                "fastpath_enabled": False,
                "ring_size_zero": True,
                "source_progress_pre": 0,
                "source_progress_post": 0,
                "sink_progress_pre": 0,
                "sink_progress_post": 0,
                "inj_status_active": "0x00010008",
                "pbm_wr_valid_cycles": 0,
                "pbm_valid_not_ready_cycles": 0,
                "pbm_wr_accept_cycles": 0,
                "pbm_wr_last_accepted_count": 0,
                "pbm_commit_entry_count": 0,
                "crypto_rx_valid_cycles": 0,
                "crypto_rx_accept_cycles": 0,
                "crypto_rx_valid_not_ready_cycles": 0,
                "post_netdbg_status": self._stage1a18_netdbg_status(),
            },
            "IngressReplay_WithExtraSnapshots": {
                "stage1a18_snapshot_mode": "extra_snapshots",
                "stage1a18_extra_snapshots_present": True,
                "runtime_ring_bypass_enabled": True,
                "fastpath_enabled": False,
                "ring_size_zero": True,
                "source_progress_pre": 0,
                "source_progress_post": 0,
                "sink_progress_pre": 0,
                "sink_progress_post": 0,
                "inj_status_active": "0x00010008",
                "pbm_wr_valid_cycles": 0,
                "pbm_valid_not_ready_cycles": 0,
                "pbm_wr_accept_cycles": 0,
                "pbm_wr_last_accepted_count": 0,
                "pbm_commit_entry_count": 0,
                "crypto_rx_valid_cycles": 0,
                "crypto_rx_accept_cycles": 0,
                "crypto_rx_valid_not_ready_cycles": 0,
                "post_netdbg_status": self._stage1a18_netdbg_status(),
                "extra_snapshot_deltas": {
                    "crypto_rx_valid_cycles_delta_at_post_workload": 0,
                    "crypto_rx_valid_cycles_delta_at_050ms": 0,
                    "crypto_rx_valid_cycles_delta_at_250ms": 0,
                    "crypto_rx_valid_cycles_delta_at_500ms": 0,
                    "pbm_wr_valid_cycles_delta_at_post_workload": 0,
                    "pbm_wr_valid_cycles_delta_at_050ms": 0,
                    "pbm_wr_valid_cycles_delta_at_250ms": 0,
                    "pbm_wr_valid_cycles_delta_at_500ms": 0,
                },
            },
        }
        if config_overrides:
            for config_name, overrides in config_overrides.items():
                defaults_by_config[config_name].update(overrides)

        cases: list[dict[str, object]] = []
        probe_ids: list[str] = []
        for config_name, config in defaults_by_config.items():
            for repeat in range(1, 4):
                probe_id = (
                    "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis:"
                    f"{config_name}:bf0064:sm0500ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                cases.append(
                    {
                        "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                        "base_name": "Case2_RuntimeRingBypass",
                        "repeat": repeat,
                        "burst_frames": 64,
                        "burst_gap_us": 0,
                        "settle_ms": 500,
                        "probe_window_id": probe_id,
                        "delta": {
                            "backend_total_cycles": 90_000_000,
                            "backend_accept_cycles": 0,
                            "backend_starvation_cycles": 0,
                            "rollback_event_count": 0,
                            "recovery_active_cycles": 0,
                            "recovery_last_window_cycles": 0,
                            "recovery_max_window_cycles": 0,
                            "high_water_count": 0,
                            "drop_pulse_count": 0,
                        },
                        "pre": {
                            "netdbg_status": "0x00000000",
                            "pbm_ptr_head_reserve": 0,
                            "pbm_ptr_head_commit": 0,
                            "pbm_ptr_tail": 0,
                            "pbm_buffer_usage": 0,
                        },
                        "post": {
                            "netdbg_status": config.get("post_netdbg_status", "0x00000000"),
                            "pbm_ptr_head_reserve": 0,
                            "pbm_ptr_head_commit": 0,
                            "pbm_ptr_tail": 0,
                            "pbm_buffer_usage": 0,
                        },
                        "upstream_ingress_to_pbm_visibility_config": config_name,
                        **config,
                    }
                )

        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-25T14:30:00+08:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a18_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "upstream_ingress_to_pbm_visibility",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _build_stage1a19_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        config_overrides: dict[str, dict[str, object]] | None = None,
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        default_idle_netdbg = self._stage1a18_netdbg_status(
            stage1_inject_tready=1,
            aclf_tready=1,
            classifier_s_tready=1,
            classifier_dma_tready=1,
            netdbg_classifier_dma_ready_seen=1,
            netdbg_classifier_dma_idle=1,
            route_state=0,
        )
        defaults_by_config: dict[str, dict[str, object]] = {
            "EmissionReferenceReplay": {
                "stage1a19_snapshot_mode": "normal",
                "runtime_ring_bypass_enabled": True,
                "fastpath_enabled": False,
                "ring_size_zero": True,
                "source_progress_pre": 0,
                "source_progress_post": 0,
                "sink_progress_pre": 0,
                "sink_progress_post": 0,
                "inj_status_active": "0x00000000",
                "post_netdbg_status": default_idle_netdbg,
            },
            "EmissionReplay_WithExtraSnapshots": {
                "stage1a19_snapshot_mode": "extra_snapshots",
                "stage1a19_extra_snapshots_present": True,
                "runtime_ring_bypass_enabled": True,
                "fastpath_enabled": False,
                "ring_size_zero": True,
                "source_progress_pre": 0,
                "source_progress_post": 0,
                "sink_progress_pre": 0,
                "sink_progress_post": 0,
                "inj_status_active": "0x00000000",
                "post_netdbg_status": default_idle_netdbg,
                "extra_snapshot_deltas": {},
            },
        }
        if config_overrides:
            for config_name, overrides in config_overrides.items():
                defaults_by_config[config_name].update(overrides)

        cases: list[dict[str, object]] = []
        probe_ids: list[str] = []
        for config_name, config in defaults_by_config.items():
            for repeat in range(1, 4):
                probe_id = (
                    "Stage1A19_InjectionSourceEmissionDiagnosis:"
                    f"{config_name}:bf0064:sm0500ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                cases.append(
                    {
                        "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                        "base_name": "Case2_RuntimeRingBypass",
                        "repeat": repeat,
                        "burst_frames": 64,
                        "burst_gap_us": 0,
                        "settle_ms": 500,
                        "probe_window_id": probe_id,
                        "delta": {
                            "backend_total_cycles": 90_000_000,
                            "backend_accept_cycles": 0,
                            "backend_starvation_cycles": 0,
                            "rollback_event_count": 0,
                            "recovery_active_cycles": 0,
                            "recovery_last_window_cycles": 0,
                            "recovery_max_window_cycles": 0,
                            "high_water_count": 0,
                            "drop_pulse_count": 0,
                        },
                        "pre": {"netdbg_status": "0x00000000"},
                        "post": {"netdbg_status": config.get("post_netdbg_status", "0x00000000")},
                        "injection_source_emission_config": config_name,
                        **config,
                    }
                )

        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-25T15:00:00+08:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a19_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A19_InjectionSourceEmissionDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "injection_source_emission",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _build_stage1a20_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        config_overrides: dict[str, dict[str, object]] | None = None,
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        default_idle_netdbg = self._stage1a18_netdbg_status(
            stage1_inject_tready=1,
            aclf_tready=1,
            classifier_s_tready=1,
            classifier_dma_tready=1,
            netdbg_classifier_dma_ready_seen=1,
            netdbg_classifier_dma_idle=1,
            route_state=0,
        )
        defaults_by_config: dict[str, dict[str, object]] = {
            "InjectionArmOnly": {
                "runtime_ring_bypass_enabled": True,
                "fastpath_enabled": False,
                "ring_size_zero": True,
                "configured_burst_frames": 64,
                "configured_frame_word_count": 19,
                "inj_ctrl_read_before": "0x00000000",
                "inj_ctrl_read_after": "0x00130000",
                "inj_frame_length_readback": 19,
                "inj_config_valid": True,
                "inj_ctrl_write_hit_count": 64,
                "inj_clear_write_hit_count": 64,
                "inj_frame_word_write_hit_count": 64 * 19,
                "inj_expected_words_write_hit_count": 64,
                "inj_source_state_raw": 0,
                "inj_fifo_write_count": 0,
                "inj_fifo_level_pre": 0,
                "inj_fifo_level_post": 0,
                "inj_fifo_level_max": 0,
                "inj_source_idle_cycles": 1024,
                "inj_source_armed_cycles": 0,
                "inj_source_active_cycles": 0,
                "inj_source_done_count": 0,
                "inj_source_emitting_cycles": 0,
                "stage1_inject_tvalid_cycles": 0,
                "stage1_inject_tready_cycles": 512,
                "stage1_inject_fire_cycles": 0,
                "stage1_inject_last_seen_count": 0,
                "post_netdbg_status": default_idle_netdbg,
            },
            "InjectionArmWithReadback": {
                "runtime_ring_bypass_enabled": True,
                "fastpath_enabled": False,
                "ring_size_zero": True,
                "configured_burst_frames": 64,
                "configured_frame_word_count": 19,
                "inj_ctrl_read_before": "0x00000000",
                "inj_ctrl_read_after": "0x00130000",
                "inj_frame_length_readback": 19,
                "inj_config_valid": True,
                "inj_ctrl_write_hit_count": 64,
                "inj_clear_write_hit_count": 64,
                "inj_frame_word_write_hit_count": 64 * 19,
                "inj_expected_words_write_hit_count": 64,
                "inj_source_state_raw": 0,
                "inj_fifo_write_count": 0,
                "inj_fifo_level_pre": 0,
                "inj_fifo_level_post": 0,
                "inj_fifo_level_max": 0,
                "inj_source_idle_cycles": 1024,
                "inj_source_armed_cycles": 0,
                "inj_source_active_cycles": 0,
                "inj_source_done_count": 0,
                "inj_source_emitting_cycles": 0,
                "stage1_inject_tvalid_cycles": 0,
                "stage1_inject_tready_cycles": 512,
                "stage1_inject_fire_cycles": 0,
                "stage1_inject_last_seen_count": 0,
                "post_netdbg_status": default_idle_netdbg,
            },
        }
        if config_overrides:
            for config_name, overrides in config_overrides.items():
                defaults_by_config[config_name].update(overrides)

        cases: list[dict[str, object]] = []
        probe_ids: list[str] = []
        for config_name, config in defaults_by_config.items():
            for repeat in range(1, 4):
                probe_id = (
                    "Stage1A20_InjectionSourceArmingDiagnosis:"
                    f"{config_name}:bf0064:sm0500ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                cases.append(
                    {
                        "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                        "base_name": "Case2_RuntimeRingBypass",
                        "repeat": repeat,
                        "burst_frames": 64,
                        "burst_gap_us": 0,
                        "settle_ms": 500,
                        "probe_window_id": probe_id,
                        "delta": {
                            "backend_total_cycles": 90_000_000,
                            "backend_accept_cycles": 0,
                            "backend_starvation_cycles": 0,
                            "rollback_event_count": 0,
                            "recovery_active_cycles": 0,
                            "recovery_last_window_cycles": 0,
                            "recovery_max_window_cycles": 0,
                            "high_water_count": 0,
                            "drop_pulse_count": 0,
                        },
                        "pre": {"netdbg_status": "0x00000000"},
                        "post": {"netdbg_status": config.get("post_netdbg_status", "0x00000000")},
                        "injection_source_arming_config": config_name,
                        **config,
                    }
                )

        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-25T16:30:00+08:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a20_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A20_InjectionSourceArmingDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "injection_source_arming",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _build_stage1a21_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        config_overrides: dict[str, dict[str, object]] | None = None,
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        defaults_by_config: dict[str, dict[str, object]] = {
            "IdleControl": {
                "stage1a21_snapshot_mode": "standard",
                "runtime_ring_bypass_enabled": True,
                "fastpath_enabled": False,
                "ring_size_zero": True,
                "idle_control_quiesce_guard_ms": 10,
                "idle_pre_after_clear_zero": True,
                "idle_residual_activity_seen": False,
                "pbm_state_raw": 0,
                "pbm_wr_valid_cycles": 0,
                "pbm_wr_ready_high_cycles": 0,
                "pbm_valid_not_ready_cycles": 0,
                "pbm_wr_accept_cycles": 0,
                "pbm_wr_last_accepted_count": 0,
                "pbm_wr_last_error_accepted_count": 0,
                "pbm_commit_entry_count": 0,
                "pbm_rollback_entry_count": 0,
                "pbm_ptr_head_reserve_pre": 0,
                "pbm_ptr_head_reserve": 0,
                "pbm_ptr_head_commit_pre": 0,
                "pbm_ptr_head_commit": 0,
                "pbm_ptr_tail_pre": 208,
                "pbm_ptr_tail": 208,
                "pbm_buffer_usage_pre": 32560,
                "pbm_buffer_usage": 32560,
                "pbm_rd_nonempty_cycles": 1024,
                "pbm_committed_available_cycles": 1024,
            },
            "BF64_SM500": {
                "stage1a21_snapshot_mode": "standard",
                "runtime_ring_bypass_enabled": True,
                "fastpath_enabled": False,
                "ring_size_zero": True,
                "pbm_state_raw": 0,
                "pbm_wr_valid_cycles": 250_000_000,
                "pbm_wr_ready_high_cycles": 0,
                "pbm_valid_not_ready_cycles": 250_000_000,
                "pbm_wr_accept_cycles": 0,
                "pbm_wr_last_accepted_count": 0,
                "pbm_wr_last_error_accepted_count": 0,
                "pbm_commit_entry_count": 0,
                "pbm_rollback_entry_count": 0,
                "pbm_ptr_head_reserve_pre": 0,
                "pbm_ptr_head_reserve": 0,
                "pbm_ptr_head_commit_pre": 0,
                "pbm_ptr_head_commit": 0,
                "pbm_ptr_tail_pre": 208,
                "pbm_ptr_tail": 208,
                "pbm_buffer_usage_pre": 32560,
                "pbm_buffer_usage": 32560,
                "pbm_rd_nonempty_cycles": 1024,
                "pbm_committed_available_cycles": 1024,
            },
            "BF64_SM500_ExtraSnapshots": {
                "stage1a21_snapshot_mode": "extra_snapshots",
                "stage1a21_extra_snapshots_present": True,
                "runtime_ring_bypass_enabled": True,
                "fastpath_enabled": False,
                "ring_size_zero": True,
                "pbm_state_raw": 0,
                "pbm_wr_valid_cycles": 250_000_000,
                "pbm_wr_ready_high_cycles": 0,
                "pbm_valid_not_ready_cycles": 250_000_000,
                "pbm_wr_accept_cycles": 0,
                "pbm_wr_last_accepted_count": 0,
                "pbm_wr_last_error_accepted_count": 0,
                "pbm_commit_entry_count": 0,
                "pbm_rollback_entry_count": 0,
                "pbm_ptr_head_reserve_pre": 0,
                "pbm_ptr_head_reserve": 0,
                "pbm_ptr_head_commit_pre": 0,
                "pbm_ptr_head_commit": 0,
                "pbm_ptr_tail_pre": 208,
                "pbm_ptr_tail": 208,
                "pbm_buffer_usage_pre": 32560,
                "pbm_buffer_usage": 32560,
                "pbm_rd_nonempty_cycles": 1024,
                "pbm_committed_available_cycles": 1024,
                "extra_snapshot_deltas": {
                    "pbm_wr_valid_cycles_delta_at_post_injection": 64_000_000,
                    "pbm_wr_valid_cycles_delta_at_050ms": 125_000_000,
                    "pbm_wr_valid_cycles_delta_at_250ms": 190_000_000,
                    "pbm_wr_valid_cycles_delta_at_500ms": 250_000_000,
                    "pbm_valid_not_ready_cycles_delta_at_post_injection": 64_000_000,
                    "pbm_valid_not_ready_cycles_delta_at_050ms": 125_000_000,
                    "pbm_valid_not_ready_cycles_delta_at_250ms": 190_000_000,
                    "pbm_valid_not_ready_cycles_delta_at_500ms": 250_000_000,
                    "pbm_wr_accept_cycles_delta_at_post_injection": 0,
                    "pbm_wr_accept_cycles_delta_at_050ms": 0,
                    "pbm_wr_accept_cycles_delta_at_250ms": 0,
                    "pbm_wr_accept_cycles_delta_at_500ms": 0,
                    "pbm_state_raw_at_post_injection": 0,
                    "pbm_state_raw_at_050ms": 0,
                    "pbm_state_raw_at_250ms": 0,
                    "pbm_state_raw_at_500ms": 0,
                },
            },
        }
        if config_overrides:
            for config_name, overrides in config_overrides.items():
                defaults_by_config[config_name].update(overrides)

        cases: list[dict[str, object]] = []
        probe_ids: list[str] = []
        for config_name, config in defaults_by_config.items():
            for repeat in range(1, 4):
                probe_id = (
                    "Stage1A21_PBMReadyGatingDiagnosis:"
                    f"{config_name}:bf0064:sm0500ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                cases.append(
                    {
                        "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                        "base_name": "Case2_RuntimeRingBypass",
                        "repeat": repeat,
                        "burst_frames": 64 if config_name != "IdleControl" else 0,
                        "burst_gap_us": 0,
                        "settle_ms": 500,
                        "probe_window_id": probe_id,
                        "delta": {
                            "backend_total_cycles": 90_000_000,
                            "backend_accept_cycles": 0,
                            "backend_starvation_cycles": 0,
                            "rollback_event_count": 0,
                            "recovery_active_cycles": 0,
                            "recovery_last_window_cycles": 0,
                            "recovery_max_window_cycles": 0,
                            "high_water_count": 0,
                            "drop_pulse_count": config.get("pbm_valid_not_ready_cycles", 0),
                        },
                        "pre": {
                            "pbm_ptr_head_reserve": config.get("pbm_ptr_head_reserve_pre", 0),
                            "pbm_ptr_head_commit": config.get("pbm_ptr_head_commit_pre", 0),
                            "pbm_ptr_tail": config.get("pbm_ptr_tail_pre", 0),
                            "pbm_buffer_usage": config.get("pbm_buffer_usage_pre", 0),
                        },
                        "post": {
                            "pbm_ptr_head_reserve": config.get("pbm_ptr_head_reserve", 0),
                            "pbm_ptr_head_commit": config.get("pbm_ptr_head_commit", 0),
                            "pbm_ptr_tail": config.get("pbm_ptr_tail", 0),
                            "pbm_buffer_usage": config.get("pbm_buffer_usage", 0),
                        },
                        "pbm_ready_gating_config": config_name,
                        **config,
                    }
                )

        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-25T17:45:00+08:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a21_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A21_PBMReadyGatingDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "pbm_ready_gating",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _build_stage1a22_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        config_overrides: dict[str, dict[str, object]] | None = None,
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        defaults_by_config: dict[str, dict[str, object]] = {
            "IdleControl_NoReset": {
                "stage1a22_reset_mode": "no_reset",
                "runtime_ring_bypass_enabled": True,
                "fastpath_enabled": False,
                "ring_size_zero": True,
                "dma_soft_reset_pulsed": 0,
                "pbm_wr_valid_cycles": 0,
                "pbm_wr_ready_high_cycles": 0,
                "pbm_valid_not_ready_cycles": 0,
                "pbm_wr_accept_cycles": 0,
                "pbm_ptr_head_reserve_pre": 0,
                "pbm_ptr_head_reserve": 0,
                "pbm_ptr_head_commit_pre": 0,
                "pbm_ptr_head_commit": 0,
                "pbm_ptr_tail_pre": 208,
                "pbm_ptr_tail": 208,
                "pbm_buffer_usage_pre": 32560,
                "pbm_buffer_usage": 32560,
                "pbm_committed_available_cycles": 1024,
                "pbm_rd_empty_cycles": 0,
                "pbm_rd_nonempty_cycles": 1024,
                "pbm_rd_en_cycles": 0,
                "pbm_rd_accept_cycles": 0,
            },
            "IdleControl_AfterSoftReset": {
                "stage1a22_reset_mode": "soft_reset",
                "runtime_ring_bypass_enabled": True,
                "fastpath_enabled": False,
                "ring_size_zero": True,
                "dma_soft_reset_pulsed": 1,
                "pbm_wr_valid_cycles": 0,
                "pbm_wr_ready_high_cycles": 0,
                "pbm_valid_not_ready_cycles": 0,
                "pbm_wr_accept_cycles": 0,
                "pbm_ptr_head_reserve_pre": 0,
                "pbm_ptr_head_reserve": 0,
                "pbm_ptr_head_commit_pre": 0,
                "pbm_ptr_head_commit": 0,
                "pbm_ptr_tail_pre": 0,
                "pbm_ptr_tail": 0,
                "pbm_buffer_usage_pre": 0,
                "pbm_buffer_usage": 0,
                "pbm_committed_available_cycles": 0,
                "pbm_rd_empty_cycles": 1024,
                "pbm_rd_nonempty_cycles": 0,
                "pbm_rd_en_cycles": 0,
                "pbm_rd_accept_cycles": 0,
            },
            "BF64_SM500_AfterSoftReset": {
                "stage1a22_reset_mode": "soft_reset",
                "runtime_ring_bypass_enabled": True,
                "fastpath_enabled": False,
                "ring_size_zero": True,
                "dma_soft_reset_pulsed": 1,
                "pbm_wr_valid_cycles": 4096,
                "pbm_wr_ready_high_cycles": 2048,
                "pbm_valid_not_ready_cycles": 0,
                "pbm_wr_accept_cycles": 2048,
                "pbm_ptr_head_reserve_pre": 0,
                "pbm_ptr_head_reserve": 32,
                "pbm_ptr_head_commit_pre": 0,
                "pbm_ptr_head_commit": 0,
                "pbm_ptr_tail_pre": 0,
                "pbm_ptr_tail": 0,
                "pbm_buffer_usage_pre": 0,
                "pbm_buffer_usage": 128,
                "pbm_committed_available_cycles": 0,
                "pbm_rd_empty_cycles": 1024,
                "pbm_rd_nonempty_cycles": 0,
                "pbm_rd_en_cycles": 0,
                "pbm_rd_accept_cycles": 0,
                "pbm_state_raw": 0,
            },
        }
        if config_overrides:
            for config_name, overrides in config_overrides.items():
                defaults_by_config[config_name].update(overrides)

        cases: list[dict[str, object]] = []
        probe_ids: list[str] = []
        for config_name, config in defaults_by_config.items():
            for repeat in range(1, 4):
                probe_id = (
                    "Stage1A22_PBMPointerResetOrDrainDiagnosis:"
                    f"{config_name}:bf{int(config.get('burst_frames', 64)):04d}:sm0500ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                burst_frames = int(config.get("burst_frames", 0 if config_name.startswith("IdleControl") else 64))
                cases.append(
                    {
                        "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                        "base_name": "Case2_RuntimeRingBypass",
                        "repeat": repeat,
                        "burst_frames": burst_frames,
                        "burst_gap_us": 0,
                        "settle_ms": 500,
                        "probe_window_id": probe_id,
                        "delta": {
                            "backend_total_cycles": 90_000_000,
                            "backend_accept_cycles": 0,
                            "backend_starvation_cycles": 0,
                            "rollback_event_count": 0,
                            "recovery_active_cycles": 0,
                            "recovery_last_window_cycles": 0,
                            "recovery_max_window_cycles": 0,
                            "high_water_count": 0,
                            "drop_pulse_count": 0,
                        },
                        "pre": {
                            "pbm_ptr_head_reserve": config.get("pbm_ptr_head_reserve_pre", 0),
                            "pbm_ptr_head_commit": config.get("pbm_ptr_head_commit_pre", 0),
                            "pbm_ptr_tail": config.get("pbm_ptr_tail_pre", 0),
                            "pbm_buffer_usage": config.get("pbm_buffer_usage_pre", 0),
                        },
                        "post": {
                            "pbm_ptr_head_reserve": config.get("pbm_ptr_head_reserve", 0),
                            "pbm_ptr_head_commit": config.get("pbm_ptr_head_commit", 0),
                            "pbm_ptr_tail": config.get("pbm_ptr_tail", 0),
                            "pbm_buffer_usage": config.get("pbm_buffer_usage", 0),
                        },
                        "pbm_pointer_reset_or_drain_config": config_name,
                        **config,
                    }
                )

        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-25T18:40:00+08:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a22_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A22_PBMPointerResetOrDrainDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "pbm_pointer_reset_or_drain",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _build_stage1a23_summary(
        self,
        tmp_path: pathlib.Path,
        *,
        config_overrides: dict[str, dict[str, object]] | None = None,
    ) -> pathlib.Path:
        summary_path = tmp_path / "experiment_summary.json"
        xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
        uart_log = tmp_path / "board_uart.txt"
        xsct_script = tmp_path / "shadow_recovery_probe.tcl"
        defaults_by_config: dict[str, dict[str, object]] = {
            "IdleControl_NoReset": {
                "stage1a23_reset_mode": "no_reset",
                "stage1a23_snapshot_mode": "single_post",
                "runtime_ring_bypass_enabled": True,
                "fastpath_enabled": False,
                "ring_size_zero": True,
                "dma_soft_reset_pulsed": 0,
                "pbm_ptr_head_reserve_pre": 0,
                "pbm_ptr_head_reserve": 0,
                "pbm_ptr_head_commit_pre": 0,
                "pbm_ptr_head_commit": 0,
                "pbm_ptr_tail_pre": 208,
                "pbm_ptr_tail": 208,
                "pbm_buffer_usage_pre": 32560,
                "pbm_buffer_usage": 32560,
                "pbm_state_raw": 0,
                "pbm_committed_available_cycles": 1024,
                "pbm_rd_nonempty_cycles": 1024,
                "pbm_rd_en_cycles": 0,
                "pbm_rd_accept_cycles": 0,
            },
            "IdleControl_AfterSoftReset": {
                "stage1a23_reset_mode": "soft_reset",
                "stage1a23_snapshot_mode": "single_post",
                "runtime_ring_bypass_enabled": True,
                "fastpath_enabled": False,
                "ring_size_zero": True,
                "dma_soft_reset_pulsed": 1,
                "pbm_ptr_head_reserve_pre": 0,
                "pbm_ptr_head_reserve": 0,
                "pbm_ptr_head_commit_pre": 0,
                "pbm_ptr_head_commit": 0,
                "pbm_ptr_tail_pre": 208,
                "pbm_ptr_tail": 208,
                "pbm_buffer_usage_pre": 32560,
                "pbm_buffer_usage": 32560,
                "pbm_state_raw": 0,
                "pbm_committed_available_cycles": 1024,
                "pbm_rd_nonempty_cycles": 1024,
                "pbm_rd_en_cycles": 0,
                "pbm_rd_accept_cycles": 0,
            },
            "IdleControl_AfterSoftReset_ExtraSnapshots": {
                "stage1a23_reset_mode": "soft_reset",
                "stage1a23_snapshot_mode": "extra_snapshots",
                "stage1a23_extra_snapshots_present": True,
                "runtime_ring_bypass_enabled": True,
                "fastpath_enabled": False,
                "ring_size_zero": True,
                "dma_soft_reset_pulsed": 1,
                "pbm_ptr_head_reserve_pre": 0,
                "pbm_ptr_head_reserve": 0,
                "pbm_ptr_head_commit_pre": 0,
                "pbm_ptr_head_commit": 0,
                "pbm_ptr_tail_pre": 208,
                "pbm_ptr_tail": 208,
                "pbm_buffer_usage_pre": 32560,
                "pbm_buffer_usage": 32560,
                "pbm_state_raw": 0,
                "pbm_committed_available_cycles": 1200,
                "pbm_rd_nonempty_cycles": 1200,
                "pbm_rd_en_cycles": 0,
                "pbm_rd_accept_cycles": 0,
                "extra_snapshot_deltas": {
                    "pbm_state_raw_at_post_workload": 0,
                    "pbm_state_raw_at_050ms": 0,
                    "pbm_state_raw_at_250ms": 0,
                    "pbm_state_raw_at_500ms": 0,
                    "pbm_ptr_head_commit_at_post_workload": 0,
                    "pbm_ptr_head_commit_at_050ms": 0,
                    "pbm_ptr_head_commit_at_250ms": 0,
                    "pbm_ptr_head_commit_at_500ms": 0,
                    "pbm_ptr_tail_at_post_workload": 208,
                    "pbm_ptr_tail_at_050ms": 208,
                    "pbm_ptr_tail_at_250ms": 208,
                    "pbm_ptr_tail_at_500ms": 208,
                    "pbm_rd_nonempty_cycles_delta_at_post_workload": 100,
                    "pbm_rd_nonempty_cycles_delta_at_050ms": 300,
                    "pbm_rd_nonempty_cycles_delta_at_250ms": 700,
                    "pbm_rd_nonempty_cycles_delta_at_500ms": 1200,
                    "pbm_committed_available_cycles_delta_at_post_workload": 100,
                    "pbm_committed_available_cycles_delta_at_050ms": 300,
                    "pbm_committed_available_cycles_delta_at_250ms": 700,
                    "pbm_committed_available_cycles_delta_at_500ms": 1200,
                    "pbm_rd_en_cycles_delta_at_post_workload": 0,
                    "pbm_rd_en_cycles_delta_at_050ms": 0,
                    "pbm_rd_en_cycles_delta_at_250ms": 0,
                    "pbm_rd_en_cycles_delta_at_500ms": 0,
                    "pbm_rd_accept_cycles_delta_at_post_workload": 0,
                    "pbm_rd_accept_cycles_delta_at_050ms": 0,
                    "pbm_rd_accept_cycles_delta_at_250ms": 0,
                    "pbm_rd_accept_cycles_delta_at_500ms": 0,
                },
            },
        }
        if config_overrides:
            for config_name, overrides in config_overrides.items():
                defaults_by_config[config_name].update(overrides)

        cases: list[dict[str, object]] = []
        probe_ids: list[str] = []
        for config_name, config in defaults_by_config.items():
            for repeat in range(1, 4):
                probe_id = (
                    "Stage1A23_PBMCommitTailPointerInvariantDiagnosis:"
                    f"{config_name}:bf0000:sm0500ms:r{repeat:02d}:Case2_RuntimeRingBypass"
                )
                probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                cases.append(
                    {
                        "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                        "base_name": "Case2_RuntimeRingBypass",
                        "repeat": repeat,
                        "burst_frames": 0,
                        "burst_gap_us": 0,
                        "settle_ms": 500,
                        "probe_window_id": probe_id,
                        "delta": {
                            "backend_total_cycles": 9_000_000,
                            "backend_accept_cycles": 0,
                            "backend_starvation_cycles": 0,
                            "rollback_event_count": 0,
                            "recovery_active_cycles": 0,
                            "recovery_last_window_cycles": 0,
                            "recovery_max_window_cycles": 0,
                            "high_water_count": 0,
                            "drop_pulse_count": 0,
                        },
                        "pre": {
                            "pbm_ptr_head_reserve": config.get("pbm_ptr_head_reserve_pre", 0),
                            "pbm_ptr_head_commit": config.get("pbm_ptr_head_commit_pre", 0),
                            "pbm_ptr_tail": config.get("pbm_ptr_tail_pre", 0),
                            "pbm_buffer_usage": config.get("pbm_buffer_usage_pre", 0),
                        },
                        "post": {
                            "pbm_ptr_head_reserve": config.get("pbm_ptr_head_reserve", 0),
                            "pbm_ptr_head_commit": config.get("pbm_ptr_head_commit", 0),
                            "pbm_ptr_tail": config.get("pbm_ptr_tail", 0),
                            "pbm_buffer_usage": config.get("pbm_buffer_usage", 0),
                        },
                        "pbm_commit_tail_invariant_config": config_name,
                        **config,
                    }
                )

        xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
        uart_log.write_text("uart placeholder\n", encoding="utf-8")
        xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-04-25T21:00:00+08:00",
                    "xsct_log": str(xsct_log),
                    "uart_log": str(uart_log),
                    "xsct_script": str(xsct_script),
                    "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        return summary_path

    def _run_stage1a23_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A23_PBMCommitTailPointerInvariantDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "pbm_commit_tail_pointer_invariant",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _run_stage1a24_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A24_PBMResetDomainScopeDiagnosis",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "pbm_reset_domain_scope",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def _run_stage1a25_cli(self, tmp_path: pathlib.Path, summary_path: pathlib.Path) -> tuple[dict, str, list[dict[str, str]]]:
        command = [
            sys.executable,
            str(INFRA_SCRIPT),
            "--summary-json",
            str(summary_path),
            "--output-root",
            str(tmp_path),
            "--repo-root",
            str(REPO_ROOT),
            "--probe-script",
            str(PROBE_SCRIPT),
            "--stage",
            "Stage1A25_PBMResetDomainRemediationPlan",
            "--traffic-mode",
            "burst",
            "--repeat-count",
            "3",
            "--burst-frames",
            "64",
            "--burst-gap-us",
            "0",
            "--settle-ms",
            "500",
            "--load-class",
            "pbm_reset_domain_remediation",
        ]
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
        report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
        with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        return stats, report, rows

    def test_metric_semantics_files_define_raw_counters_and_sampling_windows(self):
        self.assertTrue(METRIC_SEMANTICS_MD.exists())
        self.assertTrue(METRICS_SCHEMA_JSON.exists())

        md = METRIC_SEMANTICS_MD.read_text(encoding="utf-8")
        schema = METRICS_SCHEMA_JSON.read_text(encoding="utf-8")

        for token in (
            "metrics_semantics_version",
            "sampling_window_definition",
            "edge_or_level_semantics",
            "missing_unknown_handling",
            "rollback_event_count",
            "recovery_active_cycles",
            "high_water_count",
            "drop_pulse_count",
            "backend_total_cycles",
            "backend_accept_cycles",
            "backend_starvation_cycles",
        ):
            self.assertIn(token, md)
            self.assertIn(token, schema)

        for unit in ("bytes", "ratio", "offset_bytes", "length_delta_bytes", "pattern_code", "null"):
            self.assertIn(unit, schema)

        for frozen_field in (
            "invocation_digest",
            "probe_window_index_map",
            "stage_status",
            "fault_severity_normalized",
            "raw_sample_count",
            "excluded_sample_count",
            "included_in_stats_count",
            "Paper Mapping",
            "Evidence Risk",
        ):
            self.assertIn(frozen_field, schema)

    def test_axil_csr_uses_10bit_decode_for_stage1a12_bridge_window(self):
        text = AXIL_CSR.read_text(encoding="utf-8")
        for token in (
            "case (awaddr_latch[9:0])",
            "case (s_axil_araddr[9:0])",
            "10'h220:",
            "10'h224:",
            "10'h228:",
            "10'h22C:",
        ):
            self.assertIn(token, text)

    def test_probe_script_declares_schema_versions_stage_constants_and_infra_outputs(self):
        text = PROBE_SCRIPT.read_text(encoding="utf-8")

        for token in (
            "$ManifestSchemaVersion",
            "$StatsSchemaVersion",
            "$PlotSchemaVersion",
            "$MetricsSemanticsVersion",
            "$ExperimentPlanVersion",
            "SANITY_CASE0_MIN_PASS",
            "SANITY_CASE1_MIN_PASS",
            "SANITY_CASE2_MIN_PASS",
            "ACTIVITY_GAIN_EPSILON",
            "STARVATION_GAIN_EPSILON",
            "shadow_recovery_experiment_infra.py",
            "run_manifest.json",
            "artifact_hashes.json",
            "case_results.csv",
            "summary_stats.json",
            "stage_report.md",
            "experiment_report.md",
        ):
            self.assertIn(token, text)

    def test_stage_registry_schema_contract_and_required_routes(self):
        self.assertTrue(PIPELINE_REGISTRY_JSON.exists())
        registry = json.loads(PIPELINE_REGISTRY_JSON.read_text(encoding="utf-8"))
        self.assertIsInstance(registry.get("stages"), list)

        required_fields = {
            "stage",
            "action_type",
            "aliases",
            "command",
            "phase",
            "gate",
            "requires_rtl_build",
            "requires_jtag_program",
            "blocks_downstream",
            "expected_artifacts",
            "paper_export_allowed",
            "downstream_gate_unlocked_on_pass",
            "terminal_on_failure",
            "pass_conditions",
            "fail_routes",
            "allowed_autofix",
            "forbidden_autofix",
        }
        allowed_actions = {
            "run_stage",
            "rtl_fix",
            "build",
            "jtag_program",
            "preflight",
            "analysis_only",
            "terminal",
        }
        required_stages = {
            "PBMSoftResetDiagnosticBuild",
            "Stage1A22_PBMPointerResetOrDrainDiagnosis",
            "Stage1A23_PBMCommitTailPointerInvariantDiagnosis",
            "Stage1A24_PBMResetDomainScopeDiagnosis",
            "Stage1A25_PBMResetDomainRemediationPlan",
            "Stage1A20_InjectionSourceArmingDiagnosis",
            "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis",
            "Stage1A21_PBMReadyGatingDiagnosis",
            "Stage1A17_PBMCommitReproductionDiagnosis",
            "Stage1A11_PBMReadSideVisibilityDiagnosis",
            "Stage1A16_BridgeDataProductionDiagnosis",
            "Stage1A15_ExplicitStartBridgeHandoffDiagnosis",
            "TXAxisReadyDefaultReadyBuildFix",
            "Stage1A26_DMARdEnableEquationDiagnosis",
            "Stage1A27_CryptoDMAIngressBackpressureDiagnosis",
            "Stage1A10_CryptoDMAHandoffDiagnosis",
            "Stage1A_EngineeringDataAcquisition",
            "Stage2_ExtremeTraffic",
            "DropRollbackCouplingDiagnosis",
            "PaperDataCandidateExport",
            "PaperDataFinalExport",
        }
        stages = {entry["stage"]: entry for entry in registry["stages"]}
        self.assertTrue(required_stages.issubset(stages), sorted(required_stages - set(stages)))
        self.assertIn("-TrafficMode burst", stages["Stage1A_EngineeringDataAcquisition"]["command"])
        self.assertNotIn("-Stage1A", stages["Stage1A_EngineeringDataAcquisition"]["command"])

        for entry in registry["stages"]:
            self.assertTrue(required_fields.issubset(entry), entry.get("stage"))
            self.assertIn(entry["action_type"], allowed_actions)
            self.assertIsInstance(entry["aliases"], list)
            self.assertIsInstance(entry["fail_routes"], dict)
            self.assertIsInstance(entry["allowed_autofix"], list)
            self.assertIsInstance(entry["forbidden_autofix"], list)
            if entry["stage"] == "PaperDataFinalExport":
                self.assertFalse(entry["paper_export_allowed"])

    def test_stage_registry_alias_normalization_and_fail_routes_resolve(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)

        self.assertEqual(
            gates.normalize_stage_name("PBMReadyGatingDiagnosis", registry)["stage"],
            "Stage1A21_PBMReadyGatingDiagnosis",
        )
        self.assertEqual(
            gates.normalize_stage_name("Stage1A21PBMReadyGatingDiagnosis", registry)["stage"],
            "Stage1A21_PBMReadyGatingDiagnosis",
        )
        self.assertEqual(
            gates.normalize_stage_name("DMARdEnableGatingDiagnosis", registry)["stage"],
            "Stage1A26_DMARdEnableEquationDiagnosis",
        )
        self.assertEqual(
            gates.normalize_stage_name("Stage1A26DMARdEnableEquationDiagnosis", registry)["stage"],
            "Stage1A26_DMARdEnableEquationDiagnosis",
        )
        self.assertEqual(
            gates.normalize_stage_name("TXAxisReadyGatingDiagnosis", registry)["stage"],
            "TXAxisReadyDefaultReadyBuildFix",
        )
        self.assertEqual(
            gates.normalize_stage_name("CryptoDMAIngressBackpressureDiagnosis", registry)["stage"],
            "Stage1A27_CryptoDMAIngressBackpressureDiagnosis",
        )
        self.assertEqual(
            gates.normalize_stage_name("PBMIngressOrCryptoDMADiagnosis", registry)["stage"],
            "Stage1A17_PBMCommitReproductionDiagnosis",
        )
        self.assertEqual(
            gates.normalize_stage_name("PBMReadSideVisibilityDiagnosis", registry)["stage"],
            "Stage1A11_PBMReadSideVisibilityDiagnosis",
        )
        self.assertEqual(
            gates.normalize_stage_name("Stage2_ExtremeTraffic", registry)["stage"],
            "Stage2_ExtremeTraffic",
        )
        self.assertEqual(
            gates.normalize_stage_name("FixSamplingOrAlignment", registry)["stage"],
            "Stage1A22_PBMPointerResetOrDrainDiagnosis",
        )

        all_names = {entry["stage"] for entry in registry["stages"]}
        aliases = {}
        for entry in registry["stages"]:
            for name in [entry["stage"], *entry.get("aliases", [])]:
                self.assertNotIn(name, aliases, f"duplicate alias: {name}")
                aliases[name] = entry["stage"]
            for route in entry.get("fail_routes", {}).values():
                self.assertIn(gates.normalize_stage_name(route, registry)["stage"], all_names)
        stage1a15 = gates.normalize_stage_name("Stage1A15_ExplicitStartBridgeHandoffDiagnosis", registry)
        self.assertEqual(
            gates.normalize_stage_name(stage1a15["fail_routes"]["DMARdEnableGatingDiagnosis"], registry)["stage"],
            "Stage1A26_DMARdEnableEquationDiagnosis",
        )
        stage1a26 = gates.normalize_stage_name("Stage1A26_DMARdEnableEquationDiagnosis", registry)
        self.assertEqual(
            gates.normalize_stage_name(stage1a26["fail_routes"]["TXAxisReadyGatingDiagnosis"], registry)["stage"],
            "TXAxisReadyDefaultReadyBuildFix",
        )

    def test_pipeline_gate_evaluator_is_layer_local_and_does_not_use_stage_level_any_for_dma_gate(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A16_BridgeDataProductionDiagnosis", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": True,
            "bridge_gate_passed": False,
            "dma_gate_passed": False,
            "backend_gate_passed": False,
            "reset_isolation_passed": True,
        }
        summary = {
            "stage": "Stage1A16_BridgeDataProductionDiagnosis",
            "recommended_next_stage": "DMARdEnableGatingDiagnosis",
            "bridge_tx_nonempty_seen_any": True,
            "a15_after_start_explicit_start_verified": True,
            "a15_after_start_bridge_nonempty_seen": False,
            "a15_after_start_dma_start_seen": True,
            "a15_after_start_bridge_tx_rd_en_cycles": 0,
            "active_bit_sha256": "2a4f" * 16,
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertFalse(result["gate_updates"]["dma_gate_passed"])
        self.assertFalse(result["normal_data_acquisition_ready"])
        self.assertNotEqual(result["recommended_next_stage"], "DMARdEnableGatingDiagnosis")
        self.assertEqual(result["recommended_next_stage"], "BridgeDataProductionUnderExplicitStartDiagnosis")

    def test_pipeline_gate_evaluator_blocks_downstream_before_reset_gate_passes(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A20_InjectionSourceArmingDiagnosis", registry)
        current_state = {
            "reset_gate_passed": False,
            "injection_gate_passed": False,
            "pbm_gate_passed": False,
            "bridge_gate_passed": False,
            "dma_gate_passed": False,
            "backend_gate_passed": False,
            "reset_isolation_passed": False,
        }
        summary = {
            "stage": "Stage1A20_InjectionSourceArmingDiagnosis",
            "stage1_inject_fire_cycles": 100,
            "recommended_next_stage": "UpstreamIngressToPBMVisibilityDiagnosis",
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "blocked")
        self.assertEqual(result["recommended_next_stage"], "PBMSoftResetDiagnosticBuild")
        self.assertFalse(result["gate_updates"]["injection_gate_passed"])

    def test_pipeline_gate_evaluator_uses_stage1a22_nested_reset_evidence(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A22_PBMPointerResetOrDrainDiagnosis", registry)
        current_state = {
            "reset_gate_passed": False,
            "injection_gate_passed": False,
            "pbm_gate_passed": False,
            "bridge_gate_passed": False,
            "dma_gate_passed": False,
            "backend_gate_passed": False,
            "reset_isolation_passed": False,
        }
        summary = {
            "stage1a22_pbm_pointer_reset_or_drain_diagnosis": {
                "soft_reset_pulsed_verified": True,
                "idle_after_soft_reset_gap_cleared": True,
                "bf64_after_soft_reset_ready_recovered": True,
                "bf64_after_soft_reset_accept_seen": True,
                "recommended_next_stage": "rerun_stage1a22_due_to_inconclusive",
            }
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "pass")
        self.assertEqual(result["recommended_next_stage"], "Stage1A23_PBMCommitTailPointerInvariantDiagnosis")
        self.assertFalse(result["gate_updates"]["reset_gate_passed"])

    def test_pipeline_gate_evaluator_uses_stage1a23_nested_invariant_evidence(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A23_PBMCommitTailPointerInvariantDiagnosis", registry)
        current_state = {
            "reset_gate_passed": False,
            "injection_gate_passed": False,
            "pbm_gate_passed": False,
            "bridge_gate_passed": False,
            "dma_gate_passed": False,
            "backend_gate_passed": False,
            "reset_isolation_passed": False,
        }
        summary = {
            "stage1a23_pbm_commit_tail_pointer_invariant_diagnosis": {
                "pbm_commit_tail_pointer_invariant_classification": "persistent_pointer_gap_state_counter_invariant",
                "idle_after_soft_reset_pointer_gap_seen": True,
                "extra_state_constant": True,
                "extra_pointer_constant": True,
                "recommended_next_stage": "PBMResetDomainScopeDiagnosis",
            }
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "fail")
        self.assertFalse(result["gate_updates"]["reset_gate_passed"])
        self.assertFalse(result["gate_updates"]["reset_isolation_passed"])
        self.assertEqual(result["recommended_next_stage"], "PBMResetDomainScopeDiagnosis")

    def test_pipeline_gate_evaluator_routes_stage1a24_and_stage1a25_nested_recommendations(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        current_state = {
            "reset_gate_passed": False,
            "injection_gate_passed": False,
            "pbm_gate_passed": False,
            "bridge_gate_passed": False,
            "dma_gate_passed": False,
            "backend_gate_passed": False,
            "reset_isolation_passed": False,
        }

        stage1a24 = gates.evaluate_summary(
            summary={
                "stage1a24_pbm_reset_domain_scope_diagnosis": {
                    "pbm_reset_domain_scope_classification": "pbm_soft_reset_connected_but_invariant_persists",
                    "recommended_next_stage": "PBMSoftResetImplementationDiagnosis",
                }
            },
            current_state=current_state,
            registry_entry=gates.normalize_stage_name("Stage1A24_PBMResetDomainScopeDiagnosis", registry),
        )
        self.assertEqual(stage1a24["recommended_next_stage"], "PBMSoftResetImplementationDiagnosis")

        stage1a25 = gates.evaluate_summary(
            summary={
                "stage1a25_pbm_reset_domain_remediation_plan": {
                    "pbm_reset_domain_remediation_classification": "pbm_soft_reset_implementation_diagnosis_required",
                    "recommended_next_stage": "PBMSoftResetImplementationDiagnosis",
                }
            },
            current_state=current_state,
            registry_entry=gates.normalize_stage_name("Stage1A25_PBMResetDomainRemediationPlan", registry),
        )
        self.assertEqual(stage1a25["recommended_next_stage"], "PBMSoftResetImplementationDiagnosis")

    def test_pipeline_gate_evaluator_uses_stage1a20_nested_injection_evidence(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A20_InjectionSourceArmingDiagnosis", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": False,
            "pbm_gate_passed": False,
            "bridge_gate_passed": False,
            "dma_gate_passed": False,
            "backend_gate_passed": False,
            "reset_isolation_passed": True,
        }
        summary = {
            "injection_source_arming_diagnosis": {
                "stage1_inject_fire_cycles": 704,
                "recommended_next_stage": "UpstreamIngressToPBMVisibilityDiagnosis",
            }
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "pass")
        self.assertTrue(result["gate_updates"]["injection_gate_passed"])
        self.assertEqual(result["recommended_next_stage"], "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis")

    def test_pipeline_gate_evaluator_uses_stage1a18_nested_pbm_valid_evidence(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": False,
            "bridge_gate_passed": False,
            "dma_gate_passed": False,
            "backend_gate_passed": False,
            "reset_isolation_passed": True,
        }
        summary = {
            "upstream_ingress_to_pbm_visibility_diagnosis": {
                "stage1_fire_seen": True,
                "pbm_wr_valid_cycles": 1234,
                "pbm_wr_accept_cycles": 0,
                "recommended_next_stage": "PBMCommitReproductionDiagnosis",
            }
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "pass")
        self.assertEqual(result["recommended_next_stage"], "Stage1A21_PBMReadyGatingDiagnosis")
        self.assertFalse(result["gate_updates"]["pbm_gate_passed"])

    def test_pipeline_gate_evaluator_uses_stage1a21_nested_ready_gating_evidence(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A21_PBMReadyGatingDiagnosis", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": False,
            "bridge_gate_passed": False,
            "dma_gate_passed": False,
            "backend_gate_passed": False,
            "reset_isolation_passed": True,
        }
        summary = {
            "stage1a21_pbm_ready_gating_diagnosis": {
                "pbm_wr_valid_cycles": 223134911,
                "pbm_valid_not_ready_cycles": 223134911,
                "pbm_wr_accept_cycles": 0,
                "preexisting_pointer_gap_seen": True,
                "recommended_next_stage": "PBMPointerResetOrDrainDiagnosis",
            }
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "fail")
        self.assertFalse(result["gate_updates"]["pbm_gate_passed"])
        self.assertFalse(result["gate_updates"]["reset_gate_passed"])
        self.assertFalse(result["gate_updates"]["reset_isolation_passed"])
        self.assertEqual(result["failed_gate"], "reset_gate_passed")
        self.assertEqual(result["recommended_next_stage"], "PBMPointerResetOrDrainDiagnosis")
        self.assertIn("Stage1A21_PBMReadyGatingDiagnosis", result["failure_signature"])
        self.assertIn("pbm_wr_valid_cycles223134911", result["failure_signature"])

    def test_pipeline_gate_evaluator_uses_stage1a17_nested_commit_evidence(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A17_PBMCommitReproductionDiagnosis", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": False,
            "bridge_gate_passed": False,
            "dma_gate_passed": False,
            "backend_gate_passed": False,
            "reset_isolation_passed": True,
        }
        summary = {
            "pbm_commit_reproduction_diagnosis": {
                "pbm_wr_valid_cycles": 3072,
                "pbm_wr_accept_cycles": 3072,
                "pbm_wr_last_accepted_count": 384,
                "pbm_commit_entry_count": 384,
                "pbm_ptr_head_commit_delta_mod": 3072,
                "rollback_recovery_seen": False,
                "recommended_next_stage": "BridgeDataProductionDiagnosis",
            }
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "pass")
        self.assertTrue(result["gate_updates"]["pbm_gate_passed"])
        self.assertEqual(result["recommended_next_stage"], "Stage1A16_BridgeDataProductionDiagnosis")

    def test_pipeline_gate_evaluator_uses_stage1a16_nested_bridge_evidence(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A16_BridgeDataProductionDiagnosis", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": True,
            "bridge_gate_passed": False,
            "dma_gate_passed": False,
            "backend_gate_passed": False,
            "reset_isolation_passed": True,
        }
        summary = {
            "bridge_data_production_diagnosis": {
                "baseline_bridge_reproduced": True,
                "bridge_tx_nonempty_seen_any": True,
                "recommended_next_stage": "ExplicitStartBridgeHandoffDiagnosis",
            }
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "pass")
        self.assertTrue(result["gate_updates"]["bridge_gate_passed"])
        self.assertEqual(result["recommended_next_stage"], "Stage1A15_ExplicitStartBridgeHandoffDiagnosis")

    def test_pipeline_gate_evaluator_uses_stage1a15_nested_dma_handoff_evidence(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A15_ExplicitStartBridgeHandoffDiagnosis", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": True,
            "bridge_gate_passed": True,
            "dma_gate_passed": False,
            "backend_gate_passed": False,
            "reset_isolation_passed": True,
        }
        summary = {
            "explicit_start_bridge_handoff_diagnosis": {
                "explicit_start_verified_by_hardware": True,
                "bridge_tx_rd_en_seen": True,
                "bridge_tx_accept_seen": True,
                "recommended_next_stage": "CryptoDMAHandoffDiagnosis",
            }
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "pass")
        self.assertTrue(result["gate_updates"]["dma_gate_passed"])
        self.assertEqual(result["recommended_next_stage"], "Stage1A10_CryptoDMAHandoffDiagnosis")

    def test_pipeline_gate_evaluator_uses_stage1a26_dma_rd_en_equation_evidence(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A26_DMARdEnableEquationDiagnosis", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": True,
            "bridge_gate_passed": True,
            "dma_gate_passed": False,
            "backend_gate_passed": False,
            "reset_isolation_passed": True,
        }

        def evaluate(section):
            return gates.evaluate_summary(
                summary={
                    "stage": "Stage1A26_DMARdEnableEquationDiagnosis",
                    "dma_rd_en_equation_diagnosis": section,
                },
                current_state=current_state,
                registry_entry=entry,
            )

        self.assertEqual(
            evaluate(
                {
                    "runtime_ring_bypass_enabled": True,
                    "dma_rd_en_loopback_mode_raw": 0,
                    "bridge_tx_rd_en_cycles": 0,
                }
            )["recommended_next_stage"],
            "DMALoopbackModeControlDiagnosis",
        )
        self.assertEqual(
            evaluate(
                {
                    "runtime_ring_bypass_enabled": True,
                    "dma_rd_en_loopback_mode_raw": 2,
                    "dma_rd_en_tx_axis_tready_cycles": 0,
                    "bridge_tx_rd_en_cycles": 0,
                }
            )["recommended_next_stage"],
            "TXAxisReadyGatingDiagnosis",
        )
        self.assertEqual(
            evaluate(
                {
                    "runtime_ring_bypass_enabled": True,
                    "dma_rd_en_loopback_mode_raw": 2,
                    "dma_rd_en_tx_axis_tready_cycles": 10,
                    "dma_rd_en_crypto_to_dma_nonempty_cycles": 10,
                    "dma_rd_en_tx_ready_when_nonempty_cycles": 0,
                    "bridge_tx_rd_en_cycles": 0,
                }
            )["recommended_next_stage"],
            "TXReadyWhileBridgeNonemptyDiagnosis",
        )
        self.assertEqual(
            evaluate(
                {
                    "runtime_ring_bypass_enabled": False,
                    "dma_rd_en_loopback_mode_raw": 0,
                    "dma_rd_en_dma_req_rd_cycles": 0,
                    "bridge_tx_rd_en_cycles": 0,
                }
            )["recommended_next_stage"],
            "DMANormalBranchRdRequestDiagnosis",
        )
        self.assertEqual(
            evaluate(
                {
                    "runtime_ring_bypass_enabled": True,
                    "dma_rd_en_loopback_mode_raw": 2,
                    "dma_rd_en_tx_axis_tready_cycles": 10,
                    "dma_rd_en_crypto_to_dma_nonempty_cycles": 10,
                    "dma_rd_en_tx_ready_when_nonempty_cycles": 10,
                    "dma_rd_en_loopback_branch_candidate_cycles": 10,
                    "bridge_tx_rd_en_cycles": 0,
                }
            )["recommended_next_stage"],
            "DMARdEnableEquationInstrumentationBug",
        )
        bridge_accept = evaluate(
            {
                "runtime_ring_bypass_enabled": True,
                "dma_rd_en_loopback_mode_raw": 2,
                "bridge_tx_rd_en_cycles": 5,
                "bridge_tx_accept_cycles": 0,
            }
        )
        self.assertEqual(bridge_accept["recommended_next_stage"], "BridgeAcceptPathDiagnosis")
        self.assertFalse(bridge_accept["gate_updates"]["dma_gate_passed"])

        crypto_handoff = evaluate(
            {
                "runtime_ring_bypass_enabled": True,
                "dma_rd_en_loopback_mode_raw": 2,
                "bridge_tx_rd_en_cycles": 5,
                "bridge_tx_accept_cycles": 5,
            }
        )
        self.assertEqual(crypto_handoff["stage_status"], "pass")
        self.assertTrue(crypto_handoff["gate_updates"]["dma_gate_passed"])
        self.assertEqual(crypto_handoff["recommended_next_stage"], "Stage1A10_CryptoDMAHandoffDiagnosis")

    def test_pipeline_gate_evaluator_uses_stage1a11_pbm_read_side_evidence(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A11_PBMReadSideVisibilityDiagnosis", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": True,
            "bridge_gate_passed": False,
            "dma_gate_passed": True,
            "backend_gate_passed": False,
            "reset_isolation_passed": True,
        }

        bridge_gap = gates.evaluate_summary(
            summary={
                "stage1a11_pbm_read_side_visibility": {
                    "pbm_commit_seen": True,
                    "bridge_fire_seen": False,
                    "data_without_inst_available_seen": True,
                    "recommended_next_stage": "CryptoBridgeAvailabilityDiagnosis",
                }
            },
            current_state=current_state,
            registry_entry=entry,
        )
        self.assertFalse(bridge_gap["gate_updates"]["bridge_gate_passed"])
        self.assertEqual(bridge_gap["recommended_next_stage"], "CryptoBridgeAvailabilityDiagnosis")

        bridge_fire = gates.evaluate_summary(
            summary={
                "stage1a11_pbm_read_side_visibility": {
                    "pbm_commit_seen": True,
                    "bridge_fire_seen": True,
                    "dma_start_seen": False,
                    "recommended_next_stage": "DMATransferStartDiagnosis",
                }
            },
            current_state=current_state,
            registry_entry=entry,
        )
        self.assertTrue(bridge_fire["gate_updates"]["bridge_gate_passed"])
        self.assertEqual(bridge_fire["recommended_next_stage"], "DMATransferStartDiagnosis")

    def test_pipeline_gate_evaluator_uses_stage1a10_nested_backend_evidence(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A10_CryptoDMAHandoffDiagnosis", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": True,
            "bridge_gate_passed": True,
            "dma_gate_passed": False,
            "backend_gate_passed": False,
            "reset_isolation_passed": True,
        }
        summary = {
            "crypto_dma_handoff_diagnosis": {
                "crypto_dma_ingress_accept_seen": True,
                "backend_activity_seen": True,
                "recommended_next_stage": "Stage1A_EngineeringDataAcquisition",
            }
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "pass")
        self.assertTrue(result["gate_updates"]["dma_gate_passed"])
        self.assertTrue(result["gate_updates"]["backend_gate_passed"])
        self.assertEqual(result["recommended_next_stage"], "Stage1A_EngineeringDataAcquisition")

    def test_pipeline_gate_evaluator_treats_stage1a27_loopback_bridge_accept_as_dma_pass(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A27_CryptoDMAIngressBackpressureDiagnosis", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": True,
            "bridge_gate_passed": True,
            "dma_gate_passed": False,
            "backend_gate_passed": False,
            "reset_isolation_passed": True,
        }
        summary = {
            "crypto_dma_ingress_backpressure_diagnosis": {
                "runtime_ring_bypass_enabled": True,
                "dma_rd_en_loopback_mode_raw": 2,
                "bridge_tx_rd_en_cycles": 1536,
                "bridge_tx_accept_cycles": 1536,
                "crypto_dma_in_valid_cycles": 1536,
                "crypto_dma_in_ready_cycles": 0,
                "crypto_dma_in_accept_cycles": 0,
                "backend_accept_cycles": 768,
                "backend_starvation_cycles": 768,
                "backend_activity_seen": True,
                "recommended_next_stage": "CryptoDMAIngressReadyGatingDiagnosis",
            }
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "pass")
        self.assertTrue(result["gate_updates"]["dma_gate_passed"])
        self.assertTrue(result["gate_updates"]["backend_gate_passed"])
        self.assertTrue(result["normal_data_acquisition_ready"])
        self.assertEqual(result["recommended_next_stage"], "Stage1A_EngineeringDataAcquisition")

    def test_pipeline_gate_evaluator_does_not_unlock_engineering_when_stage1a10_dma_gate_is_false(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A10_CryptoDMAHandoffDiagnosis", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": True,
            "bridge_gate_passed": True,
            "dma_gate_passed": False,
            "backend_gate_passed": False,
            "reset_isolation_passed": True,
        }
        summary = {
            "crypto_dma_handoff_diagnosis": {
                "crypto_dma_ingress_accept_seen": False,
                "crypto_dma_in_accept_cycles": 0,
                "backend_activity_seen": True,
                "recommended_next_stage": "CryptoDMAIngressBackpressureDiagnosis",
            }
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertFalse(result["gate_updates"]["dma_gate_passed"])
        self.assertTrue(result["gate_updates"]["backend_gate_passed"])
        self.assertFalse(result["normal_data_acquisition_ready"])
        self.assertEqual(result["recommended_next_stage"], "Stage1A27_CryptoDMAIngressBackpressureDiagnosis")

    def test_pipeline_gate_evaluator_overrides_stage1a10_sampling_when_tail_gap_is_active(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A10_CryptoDMAHandoffDiagnosis", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": True,
            "bridge_gate_passed": True,
            "dma_gate_passed": True,
            "backend_gate_passed": False,
            "reset_isolation_passed": True,
        }
        summary = {
            "crypto_dma_handoff_diagnosis": {
                "idle_residual_activity_seen": True,
                "pbm_commit_seen": True,
                "pbm_committed_but_tail_not_moved": True,
                "crypto_dma_ingress_accept_seen": False,
                "backend_activity_seen": False,
                "recommended_next_stage": "FixSamplingOrAlignment",
            }
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertFalse(result["gate_updates"]["backend_gate_passed"])
        self.assertEqual(result["recommended_next_stage"], "PBMReadSideVisibilityDiagnosis")

    def test_pipeline_gate_evaluator_marks_stage1a_burst_sweep_as_engineering_data(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A_EngineeringDataAcquisition", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": True,
            "bridge_gate_passed": True,
            "dma_gate_passed": True,
            "backend_gate_passed": True,
            "reset_isolation_passed": True,
        }
        summary = {
            "stage1a_decision": {
                "backend_activity_monotonic": "yes",
                "dominant_backend_mode": "balanced",
                "recommended_next_stage": "Stage2_ExtremeTraffic",
            },
            "paper_ready_throughput_gate": {
                "met": True,
                "requires_backend_stability": True,
            },
            "included_sample_count": 35,
            "metrics": {"backend_accept_ratio": {"max": 0.5}},
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "pass")
        self.assertEqual(result["recommended_next_stage"], "PaperDataCandidateExport")
        self.assertTrue(result["normal_data_acquisition_ready"])

    def test_pipeline_gate_evaluator_routes_stage1a_to_stage2_when_no_paper_gate_is_open(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A_EngineeringDataAcquisition", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": True,
            "bridge_gate_passed": True,
            "dma_gate_passed": True,
            "backend_gate_passed": True,
            "reset_isolation_passed": True,
        }
        summary = {
            "stage1a_decision": {
                "backend_activity_monotonic": "yes",
                "dominant_backend_mode": "balanced",
                "recommended_next_stage": "Stage2_ExtremeTraffic",
            },
            "included_sample_count": 35,
            "metrics": {"backend_accept_ratio": {"max": 0.5}},
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "pass")
        self.assertTrue(result["normal_data_acquisition_ready"])
        self.assertNotEqual(result["recommended_next_stage"], "PaperDataCandidateExport")
        self.assertEqual(result["recommended_next_stage"], "Stage2_ExtremeTraffic")

    def test_pipeline_gate_evaluator_rejects_stage1a_negative_no_backend_activity(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage1A_EngineeringDataAcquisition", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": True,
            "bridge_gate_passed": True,
            "dma_gate_passed": True,
            "backend_gate_passed": True,
            "reset_isolation_passed": True,
        }
        summary = {
            "stage1a_decision": {
                "backend_activity_monotonic": "no",
                "dominant_backend_mode": "none",
                "recommended_next_stage": "PBMIngressOrCryptoDMADiagnosis",
            },
            "included_sample_count": 35,
            "negative_result_types": ["negative_no_backend_activity"],
            "metrics": {
                "backend_accept_ratio": {"max": 0.0},
                "backend_starvation_ratio": {"max": 0.0},
            },
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "fail")
        self.assertEqual(result["failed_gate"], "engineering_data_collected")
        self.assertEqual(result["recommended_next_stage"], "PBMIngressOrCryptoDMADiagnosis")
        self.assertFalse(result["level_readiness"]["level2_engineering_performance_ready"])

    def test_failure_signature_ignores_timestamp_paths_and_uses_key_pattern(self):
        gates = load_pipeline_gates_module()
        base_summary = {
            "stage": "Stage1A21_PBMReadyGatingDiagnosis",
            "recommended_next_stage": "PBMReadyGatingDiagnosis",
            "active_bit_sha256": "abcdef0123456789",
            "pbm_wr_valid_cycles": 10,
            "pbm_wr_accept_cycles": 0,
            "pbm_valid_not_ready_cycles": 10,
            "timestamp": "2026-04-25T01:02:03",
            "output_dir": "D:/run/a",
        }
        changed_noise = dict(base_summary, timestamp="2026-04-25T04:05:06", output_dir="D:/run/b")
        changed_pattern = dict(base_summary, pbm_wr_accept_cycles=1)

        sig_a = gates.make_failure_signature(
            stage="Stage1A21_PBMReadyGatingDiagnosis",
            failed_gate="pbm_gate",
            recommended_next_stage="PBMReadyGatingDiagnosis",
            summary=base_summary,
            manifest={"configuration_hash": "cfg1"},
        )
        sig_b = gates.make_failure_signature(
            stage="Stage1A21_PBMReadyGatingDiagnosis",
            failed_gate="pbm_gate",
            recommended_next_stage="PBMReadyGatingDiagnosis",
            summary=changed_noise,
            manifest={"configuration_hash": "cfg1"},
        )
        sig_c = gates.make_failure_signature(
            stage="Stage1A21_PBMReadyGatingDiagnosis",
            failed_gate="pbm_gate",
            recommended_next_stage="PBMReadyGatingDiagnosis",
            summary=changed_pattern,
            manifest={"configuration_hash": "cfg1"},
        )

        self.assertEqual(sig_a, sig_b)
        self.assertNotEqual(sig_a, sig_c)

    def test_failure_signature_uses_nested_key_pattern(self):
        gates = load_pipeline_gates_module()
        summary = {
            "stage1a21_pbm_ready_gating_diagnosis": {
                "pbm_wr_valid_cycles": 10,
                "pbm_wr_accept_cycles": 0,
                "pbm_valid_not_ready_cycles": 10,
            }
        }

        sig = gates.make_failure_signature(
            stage="Stage1A21_PBMReadyGatingDiagnosis",
            failed_gate="pbm_gate_passed",
            recommended_next_stage="PBMPointerResetOrDrainDiagnosis",
            summary=summary,
            manifest={"configuration_hash": "cfg1"},
        )

        self.assertIn("pbm_wr_valid_cycles10", sig)
        self.assertIn("pbm_wr_accept_cycles0", sig)
        self.assertNotIn("no_key_counters", sig)

    def test_failure_signature_does_not_use_unstable_invocation_digest_as_configuration_hash(self):
        gates = load_pipeline_gates_module()
        summary = {
            "stage": "Stage1A20_InjectionSourceArmingDiagnosis",
            "stage1_inject_fire_cycles": 0,
        }

        sig_a = gates.make_failure_signature(
            stage="Stage1A20_InjectionSourceArmingDiagnosis",
            failed_gate="injection_gate_passed",
            recommended_next_stage="InjectionSourceArmingDiagnosis",
            summary=summary,
            manifest={"invocation_digest": "first-run-only"},
        )
        sig_b = gates.make_failure_signature(
            stage="Stage1A20_InjectionSourceArmingDiagnosis",
            failed_gate="injection_gate_passed",
            recommended_next_stage="InjectionSourceArmingDiagnosis",
            summary=summary,
            manifest={"invocation_digest": "second-run-only"},
        )

        self.assertEqual(sig_a, sig_b)
        self.assertIn("cfg_unknowncfg", sig_a)

    def test_current_state_template_atomic_write_history_and_retry_terminal_blocker(self):
        self.assertTrue(PIPELINE_STATE_TEMPLATE_JSON.exists())
        runner = load_pipeline_runner_module()
        state = json.loads(PIPELINE_STATE_TEMPLATE_JSON.read_text(encoding="utf-8"))
        self.assertEqual(state["recommended_next_stage"], "PBMSoftResetDiagnosticBuild")
        self.assertFalse(state["normal_data_acquisition_ready"])

        local_tmp = REPO_ROOT / ".tmp" / "pipeline_state_contract"
        if local_tmp.exists():
            shutil.rmtree(local_tmp)
        local_tmp.mkdir(parents=True, exist_ok=True)
        state_path = local_tmp / "current_state.json"
        history_path = state_path.with_name("current_state.history.jsonl")
        runner.write_state_atomic(state_path, state, history_path=history_path)
        self.assertEqual(json.loads(state_path.read_text(encoding="utf-8"))["recommended_next_stage"], "PBMSoftResetDiagnosticBuild")
        self.assertFalse(state_path.with_suffix(".json.tmp").exists())
        self.assertEqual(len(history_path.read_text(encoding="utf-8").splitlines()), 1)

        updated = runner.record_attempt(
            state,
            gate="pbm_gate",
            failure_signature="pbm_valid_gt0_accept0_bit_abcd_cfg_1",
            max_retries_per_gate=2,
        )
        self.assertIsNone(updated["terminal_blocker"])
        updated = runner.record_attempt(
            updated,
            gate="pbm_gate",
            failure_signature="pbm_valid_gt0_accept0_bit_abcd_cfg_1",
            max_retries_per_gate=2,
        )
        self.assertEqual(updated["terminal_blocker"], "repeated_same_failure_signature")

    def test_pipeline_runner_does_not_stop_on_unqualified_engineering_artifact(self):
        runner = load_pipeline_runner_module()
        state = {
            "engineering_data_collected": True,
            "normal_data_acquisition_ready": False,
            "level2_engineering_performance_ready": False,
        }

        self.assertFalse(runner.auto_run_target_reached("EngineeringDataCollected", state))

        state["normal_data_acquisition_ready"] = True
        state["level2_engineering_performance_ready"] = True
        self.assertTrue(runner.auto_run_target_reached("EngineeringDataCollected", state))

    def test_pipeline_runner_supports_paper_candidate_target_and_candidate_action_does_not_auto_chain(self):
        runner = load_pipeline_runner_module()
        state = {
            "paper_candidate_collected": False,
        }

        self.assertFalse(runner.auto_run_target_reached("PaperCandidateCollected", state))
        state["paper_candidate_collected"] = True
        self.assertTrue(runner.auto_run_target_reached("PaperCandidateCollected", state))
        self.assertIsNone(runner.next_after_action("PaperDataCandidateExport"))

    def test_pipeline_runner_supports_full_data_target(self):
        runner = load_pipeline_runner_module()
        state = {
            "engineering_data_collected": True,
            "paper_candidate_collected": True,
            "recovery_evidence_collected": False,
        }

        self.assertFalse(runner.auto_run_target_reached("FullDataCollected", state))
        state["recovery_evidence_collected"] = True
        self.assertTrue(runner.auto_run_target_reached("FullDataCollected", state))

    def test_pipeline_runner_reconciles_legacy_paper_candidate_state_to_stage2(self):
        runner = load_pipeline_runner_module()
        state = {
            "paper_candidate_collected": True,
            "paper_data_exported": False,
            "paper_ready_recovery_gate": False,
            "recovery_evidence_collected": False,
            "recommended_next_stage": "PaperDataFinalExport",
            "failed_gate": "paper_data_exported",
        }

        updated = runner.reconcile_runtime_state(dict(state))

        self.assertEqual(updated["recommended_next_stage"], "Stage2_ExtremeTraffic")
        self.assertEqual(updated["failed_gate"], "paper_ready_recovery_gate")

    def test_pipeline_runner_reconciles_legacy_paper_candidate_state_to_drop_rollback(self):
        runner = load_pipeline_runner_module()
        state = {
            "paper_candidate_collected": True,
            "paper_data_exported": False,
            "paper_ready_recovery_gate": True,
            "recovery_evidence_collected": False,
            "recommended_next_stage": "PaperDataFinalExport",
            "failed_gate": "paper_data_exported",
        }

        updated = runner.reconcile_runtime_state(dict(state))

        self.assertEqual(updated["recommended_next_stage"], "DropRollbackCouplingDiagnosis")
        self.assertEqual(updated["failed_gate"], "paper_candidate_collected")

    def test_pipeline_runner_reconciles_stage2_terminal_blocker_to_synthetic_fault_stage(self):
        runner = load_pipeline_runner_module()
        state = {
            "paper_candidate_collected": True,
            "paper_data_exported": False,
            "paper_ready_recovery_gate": False,
            "recovery_evidence_collected": False,
            "last_stage": "Stage2_ExtremeTraffic",
            "recommended_next_stage": "Stage2_ExtremeTraffic",
            "failed_gate": "paper_ready_recovery_gate",
            "terminal_blocker": "repeated_same_failure_signature",
            "last_failure_signature": "Stage2_ExtremeTraffic_paper_ready_recovery_gate_Stage2_ExtremeTraffic_bit_unknownbit_cfg_unknowncfg_no_key_counters",
        }

        updated = runner.reconcile_runtime_state(dict(state))

        self.assertIsNone(updated["terminal_blocker"])
        self.assertEqual(updated["recommended_next_stage"], "Stage2_SyntheticFaultTraffic")
        self.assertEqual(updated["failed_gate"], "paper_ready_recovery_gate")

    def test_paper_candidate_export_writes_candidate_artifacts(self):
        runner = load_pipeline_runner_module()
        local_tmp = REPO_ROOT / ".tmp" / "paper_candidate_contract"
        if local_tmp.exists():
            shutil.rmtree(local_tmp)
        run_dir = local_tmp / "doc" / "reports" / "engineering_evidence" / "shadow_recovery_probe_contract"
        run_dir.mkdir(parents=True, exist_ok=True)
        try:
            (run_dir / "summary_stats.json").write_text(
                json.dumps(
                    {
                        "included_sample_count": 35,
                        "paper_ready_recovery_gate": {"met": False},
                        "stage1a_decision": {
                            "backend_activity_monotonic": "yes",
                            "dominant_backend_mode": "balanced",
                            "recommended_next_stage": "Stage2_ExtremeTraffic",
                        },
                        "grouped_by_burst_frames_ordered": [
                            {"included_count": 5, "activity_stats": {"std": 0.0, "mean": 8.0}},
                            {"included_count": 5, "activity_stats": {"std": 0.0, "mean": 16.0}},
                            {"included_count": 5, "activity_stats": {"std": 0.0, "mean": 32.0}},
                        ],
                        "csr_baseline": {
                            "rollback_event_count": 0,
                            "recovery_active_cycles": 0,
                            "recovery_last_window_cycles": 0,
                            "recovery_max_window_cycles": 0,
                            "error_qualified_packet_count": 0,
                            "backend_total_cycles": 128,
                            "backend_accept_cycles": 64,
                            "backend_starvation_cycles": 64,
                            "high_water_count": 0,
                            "drop_pulse_count": 0,
                        },
                    }
                ),
                encoding="utf-8",
            )
            (run_dir / "run_manifest.json").write_text(
                json.dumps(
                    {
                        "board": {
                            "active_bit_sha256": "b" * 64,
                            "active_xsa_sha256": "c" * 64,
                        },
                        "case_parameters": {
                            "clock_hz": 50_000_000,
                        },
                    }
                ),
                encoding="utf-8",
            )
            (run_dir / "case_results.csv").write_text("probe_window_id\ncontract\n", encoding="utf-8")
            (run_dir / "stage_report.md").write_text("contract report\n", encoding="utf-8")

            payload = runner.export_paper_candidate(
                local_tmp,
                {
                    "last_run_dir": str(run_dir),
                    "paper_ready_recovery_gate": False,
                },
            )

            self.assertEqual(payload["status"], "pass")
            self.assertEqual(payload["recommended_next_stage"], "Stage2_ExtremeTraffic")
            candidate_dir = pathlib.Path(payload["output_dir"])
            self.assertTrue((candidate_dir / "hardware_counters_snapshot.json").exists())
            self.assertTrue((candidate_dir / "fig5_recovery_counters.csv").exists())
            self.assertTrue((candidate_dir / "fig7_backend_utilization.csv").exists())
            self.assertTrue((candidate_dir / "summary_stats.json").exists())
            self.assertTrue((candidate_dir / "candidate_export_manifest.json").exists())
        finally:
            shutil.rmtree(local_tmp, ignore_errors=True)

    def test_paper_candidate_export_routes_recovery_gate_to_drop_rollback(self):
        runner = load_pipeline_runner_module()
        local_tmp = REPO_ROOT / ".tmp" / "paper_candidate_recovery_contract"
        if local_tmp.exists():
            shutil.rmtree(local_tmp)
        run_dir = local_tmp / "doc" / "reports" / "engineering_evidence" / "shadow_recovery_probe_contract"
        run_dir.mkdir(parents=True, exist_ok=True)
        try:
            (run_dir / "summary_stats.json").write_text(
                json.dumps(
                    {
                        "included_sample_count": 12,
                        "paper_ready_recovery_gate": {"met": True},
                        "rollback_recovery_seen": True,
                        "csr_baseline": {
                            "rollback_event_count": 3,
                            "recovery_active_cycles": 9,
                            "recovery_last_window_cycles": 3,
                            "recovery_max_window_cycles": 3,
                            "error_qualified_packet_count": 0,
                            "backend_total_cycles": 128,
                            "backend_accept_cycles": 64,
                            "backend_starvation_cycles": 64,
                            "high_water_count": 0,
                            "drop_pulse_count": 0,
                        },
                    }
                ),
                encoding="utf-8",
            )
            (run_dir / "run_manifest.json").write_text(
                json.dumps(
                    {
                        "board": {
                            "active_bit_sha256": "d" * 64,
                            "active_xsa_sha256": "e" * 64,
                        },
                        "case_parameters": {
                            "clock_hz": 50_000_000,
                        },
                    }
                ),
                encoding="utf-8",
            )
            (run_dir / "case_results.csv").write_text("probe_window_id\ncontract\n", encoding="utf-8")
            (run_dir / "stage_report.md").write_text("contract report\n", encoding="utf-8")

            payload = runner.export_paper_candidate(
                local_tmp,
                {
                    "last_run_dir": str(run_dir),
                    "paper_ready_recovery_gate": True,
                },
            )

            self.assertEqual(payload["status"], "pass")
            self.assertEqual(payload["recommended_next_stage"], "DropRollbackCouplingDiagnosis")
            self.assertTrue(payload["recovery_gate_met"])
        finally:
            shutil.rmtree(local_tmp, ignore_errors=True)

    def test_drop_rollback_coupling_diagnosis_marks_recovery_evidence_and_routes_candidate_export(self):
        runner = load_pipeline_runner_module()
        local_tmp = REPO_ROOT / ".tmp" / "drop_rollback_contract"
        if local_tmp.exists():
            shutil.rmtree(local_tmp)
        run_dir = local_tmp / "doc" / "reports" / "engineering_evidence" / "shadow_recovery_probe_contract"
        run_dir.mkdir(parents=True, exist_ok=True)
        try:
            (run_dir / "summary_stats.json").write_text(
                json.dumps(
                    {
                        "included_sample_count": 12,
                        "rollback_recovery_seen": True,
                        "paper_ready_recovery_gate": {"met": True},
                        "metrics": {"backend_accept_ratio": {"max": 0.5}},
                        "rollback_event_count": 3,
                        "recovery_active_cycles": 9,
                    }
                ),
                encoding="utf-8",
            )
            (run_dir / "run_manifest.json").write_text(json.dumps({}), encoding="utf-8")

            payload = runner.run_drop_rollback_coupling_diagnosis(
                local_tmp,
                {
                    "last_run_dir": str(run_dir),
                    "paper_ready_recovery_gate": True,
                },
            )

            self.assertEqual(payload["status"], "pass")
            self.assertTrue(payload["recovery_gate_met"])
            self.assertTrue(payload["rollback_recovery_seen"])
            self.assertEqual(payload["recommended_next_stage"], "PaperDataCandidateExport")
        finally:
            shutil.rmtree(local_tmp, ignore_errors=True)

    def test_diagnostic_feature_mask_preflight_parses_xsct_output_and_requires_features(self):
        runner = load_pipeline_runner_module()
        tcl_text = runner.render_diagnostic_feature_mask_preflight_tcl()
        self.assertIn("proc select_ps_access_target", tcl_text)
        self.assertIn('"*ARM Cortex-A9 MPCore #0*"', tcl_text)
        self.assertIn('"*APU*"', tcl_text)
        self.assertIn("mrd -force -value 0x40000090", tcl_text)
        self.assertIn("select_ps_access_target", tcl_text)
        for addr in ("0x40001270", "0x40001274", "0x40001278", "0x4000127C"):
            self.assertIn(f"rd32 {addr}", tcl_text)
            self.assertIn("mrd -force -value $addr", tcl_text)

        xsct_output = "\n".join(
            [
                "0x40001270:   534D4447",
                "0x40001274:   000003FF",
                "0x40001278:   89ABCDEF",
                "0x4000127C:   01234567",
            ]
        )
        parsed = runner.parse_diagnostic_feature_mask_preflight_output(xsct_output)
        self.assertEqual(parsed["diagnostic_build_id"], "0x534D4447")
        self.assertEqual(parsed["diagnostic_feature_mask"], "0x000003FF")
        self.assertEqual(parsed["diagnostic_registry_hash_low"], "0x89ABCDEF")
        self.assertEqual(parsed["diagnostic_registry_hash_high"], "0x01234567")
        self.assertTrue(parsed["feature_mask_bits"]["PBM_SOFT_RESET"])
        self.assertTrue(parsed["feature_mask_bits"]["INJECTION_SOURCE_DIAG"])
        self.assertTrue(parsed["feature_mask_bits"]["DMA_RD_EN_EQUATION_DIAG"])
        self.assertTrue(parsed["feature_mask_bits"]["INJECTION_ERROR_DIAG"])

        verdict = runner.evaluate_diagnostic_feature_mask_preflight(parsed)
        self.assertEqual(verdict["status"], "pass")
        self.assertTrue(verdict["diagnostic_feature_mask_required_bits_present"])

        missing = runner.parse_diagnostic_feature_mask_preflight_output(xsct_output.replace("000003FF", "000001FF"))
        missing_verdict = runner.evaluate_diagnostic_feature_mask_preflight(missing)
        self.assertEqual(missing_verdict["status"], "fail")
        self.assertIn("INJECTION_ERROR_DIAG", missing_verdict["missing_required_features"])

    def test_diagnostic_feature_mask_preflight_writes_machine_artifact(self):
        runner = load_pipeline_runner_module()
        local_tmp = REPO_ROOT / ".tmp" / "feature_mask_preflight_contract"
        if local_tmp.exists():
            shutil.rmtree(local_tmp)
        local_tmp.mkdir(parents=True, exist_ok=True)
        try:
            artifact_path = local_tmp / "diagnostic_feature_mask_preflight.json"
            rc = runner.write_diagnostic_feature_mask_preflight_artifact(
                artifact_path,
                xsct_output="\n".join(
                    [
                        "40001270: 534D4447",
                        "40001274: 000001FF",
                        "40001278: 00000000",
                        "4000127C: 00000000",
                    ]
                ),
                xsct_returncode=0,
            )
            self.assertEqual(rc, 0)
            artifact = json.loads(artifact_path.read_text(encoding="utf-8"))
            self.assertEqual(artifact["status"], "pass")
            self.assertTrue(artifact["feature_mask_bits"]["BRIDGE_FIFO_DIAG"])
            self.assertEqual(artifact["diagnostic_csr_base"], "0x40001270")
        finally:
            shutil.rmtree(local_tmp, ignore_errors=True)

    def test_pipeline_wrapper_exposes_safe_modes_and_locks_final_paper_export_by_default(self):
        self.assertTrue(PIPELINE_WRAPPER.exists())
        text = PIPELINE_WRAPPER.read_text(encoding="utf-8")
        for token in (
            "[switch]$PlanOnly",
            "[switch]$DryRun",
            "[switch]$AllowPaperCandidate",
            "[object]$AllowPaperExport",
            "[object]$ManualFinalExportAck",
            'ValidateSet("EngineeringDataCollected", "PaperCandidateCollected", "FullDataCollected")',
            "ConvertTo-PipelineBool",
            "-AllowPaperExport:$false",
            "-ManualFinalExportAck:$false",
            "shadow_full_data_acquisition_pipeline.py",
        ):
            self.assertIn(token, text)

    def test_export_xsa_wrapper_defaults_shadow_build_to_non_direct_flow(self):
        self.assertTrue(EXPORT_XSA_WRAPPER.exists())
        text = EXPORT_XSA_WRAPPER.read_text(encoding="utf-8")
        self.assertIn("UDP_GATEWAY_SHADOW_MIRROR_DIRECT_SCRIPT_FLOW", text)
        self.assertIn("$env:UDP_GATEWAY_SHADOW_MIRROR_DIRECT_SCRIPT_FLOW = \"0\"", text)

    def test_stage2_registry_uses_real_stage_switch_not_burst_placeholder(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage2_ExtremeTraffic", registry)

        self.assertEqual(entry["action_type"], "run_stage")
        self.assertIn("-Stage2ExtremeTraffic", entry["command"])
        self.assertNotIn("-TrafficMode burst", entry["command"])

    def test_stage2_gate_evaluator_requires_recovery_not_candidate_export(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage2_ExtremeTraffic", registry)
        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": True,
            "bridge_gate_passed": True,
            "dma_gate_passed": True,
            "backend_gate_passed": True,
            "reset_isolation_passed": True,
            "paper_candidate_collected": True,
            "paper_ready_recovery_gate": False,
        }
        summary = {
            "included_sample_count": 12,
            "paper_ready_throughput_gate": {"met": True},
            "paper_ready_recovery_gate": {"met": False},
            "negative_result_types": ["negative_backend_activity_only"],
            "trigger_rate": 0.0,
            "recommended_next_stage": "Stage2_ExtremeTraffic",
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "partial")
        self.assertEqual(result["failed_gate"], "paper_ready_recovery_gate")
        self.assertEqual(result["recommended_next_stage"], "Stage2_SyntheticFaultTraffic")

    def test_stage2_synthetic_fault_registry_and_gate_hold_recovery_gate_until_counters_fire(self):
        gates = load_pipeline_gates_module()
        registry = gates.load_stage_registry(PIPELINE_REGISTRY_JSON)
        entry = gates.normalize_stage_name("Stage2_SyntheticFaultTraffic", registry)

        self.assertEqual(entry["action_type"], "run_stage")
        self.assertIn("-Stage2SyntheticFaultTraffic", entry["command"])

        current_state = {
            "reset_gate_passed": True,
            "injection_gate_passed": True,
            "pbm_gate_passed": True,
            "bridge_gate_passed": True,
            "dma_gate_passed": True,
            "backend_gate_passed": True,
            "reset_isolation_passed": True,
            "paper_candidate_collected": True,
            "paper_ready_recovery_gate": False,
        }
        summary = {
            "included_sample_count": 14,
            "paper_ready_throughput_gate": {"met": True},
            "paper_ready_recovery_gate": {"met": False},
            "negative_result_types": ["negative_backend_activity_only"],
            "trigger_rate": 0.0,
            "recommended_next_stage": "Stage2_SyntheticFaultTraffic",
        }

        result = gates.evaluate_summary(summary=summary, current_state=current_state, registry_entry=entry)

        self.assertEqual(result["stage_status"], "partial")
        self.assertEqual(result["failed_gate"], "paper_ready_recovery_gate")
        self.assertEqual(result["recommended_next_stage"], "Stage2_SyntheticFaultTraffic")

    def test_infra_script_exports_reproducibility_and_report_fields(self):
        text = INFRA_SCRIPT.read_text(encoding="utf-8")

        for token in (
            "invocation_digest",
            "manifest_schema_version",
            "stats_schema_version",
            "plot_schema_version",
            "metrics_semantics_version",
            "experiment_plan_version",
            "script_commit_hash",
            "probe_window_id",
            "probe_window_index_map",
            "stage_status",
            "validation_status",
            "negative_result_type",
            "fault_severity_normalized",
            "fault_severity_value",
            "fault_severity_unit",
            "fault_severity_note",
            "raw_sample_count",
            "excluded_sample_count",
            "included_in_stats_count",
            "candidate_for_paper_evidence",
            "why_it_is_or_is_not_candidate",
            "Evidence Risk",
            "Paper Mapping",
            "Relevant paper claim",
            "Allowed use in paper",
            "artifact_hashes.json",
            "size_bytes",
            "created_at",
            "relative_path",
        ):
            self.assertIn(token, text)

    def test_generated_pack_contains_frozen_fields_and_probe_window_map(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            summary_path = tmp_path / "experiment_summary.json"
            xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
            uart_log = tmp_path / "board_uart.txt"
            xsct_script = tmp_path / "shadow_recovery_probe.tcl"
            xsct_log.write_text("probe-window placeholder\n", encoding="utf-8")
            uart_log.write_text("uart placeholder\n", encoding="utf-8")
            xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
            summary_path.write_text(
                json.dumps(
                    {
                        "timestamp": "2026-04-23T20:43:28+00:00",
                        "xsct_log": str(xsct_log),
                        "uart_log": str(uart_log),
                        "xsct_script": str(xsct_script),
                        "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                        "cases": [
                            {
                                "name": "Case2_RuntimeRingBypass",
                                "inj_status_active": "0x00000000",
                                "delta": {
                                    "backend_total_cycles": 100,
                                    "backend_accept_cycles": 4,
                                    "backend_starvation_cycles": 4,
                                    "rollback_event_count": 0,
                                    "recovery_active_cycles": 0,
                                    "high_water_count": 0,
                                    "drop_pulse_count": 0,
                                },
                                "post": {"netdbg_status": "0x000521A5"},
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )

            command = [
                sys.executable,
                str(INFRA_SCRIPT),
                "--summary-json",
                str(summary_path),
                "--output-root",
                str(tmp_path),
                "--repo-root",
                str(REPO_ROOT),
                "--probe-script",
                str(PROBE_SCRIPT),
                "--repeat-count",
                "5",
                "--burst-frames",
                "7",
                "--fault-severity-value",
                "0.25",
                "--fault-severity-unit",
                "ratio",
            ]
            completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertEqual(completed.returncode, 0, completed.stdout)

            manifest = json.loads((tmp_path / "run_manifest.json").read_text(encoding="utf-8"))
            stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
            report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
            with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
                rows = list(csv.DictReader(handle))

            self.assertRegex(manifest["invocation_digest"], r"^[0-9a-f]{64}$")
            probe_window_id = rows[0]["probe_window_id"]
            self.assertIn(probe_window_id, manifest["probe_window_index_map"])
            self.assertIn("xsct_log", manifest["probe_window_index_map"][probe_window_id])
            self.assertEqual(rows[0]["stage_status"], "pass")
            self.assertEqual(rows[0]["fault_severity_normalized"], "0.25")
            self.assertEqual(stats["raw_sample_count"], 1)
            self.assertEqual(stats["excluded_sample_count"], 0)
            self.assertEqual(stats["included_in_stats_count"], 1)
            self.assertIn("Paper Mapping", report)
            self.assertIn("Relevant paper claim", report)
            self.assertIn("Allowed use in paper", report)

            second_output = tmp_path / "second"
            second_output.mkdir()
            second_command = list(command)
            second_command[second_command.index("--output-root") + 1] = str(second_output)
            second_command[second_command.index("--burst-frames") + 1] = "8"
            second_completed = subprocess.run(second_command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertEqual(second_completed.returncode, 0, second_completed.stdout)
            second_manifest = json.loads((second_output / "run_manifest.json").read_text(encoding="utf-8"))
            self.assertNotEqual(manifest["invocation_digest"], second_manifest["invocation_digest"])

    def test_fault_sequence_digest_is_seed_reproducible_and_seed_sensitive(self):
        module = load_infra_module()

        sequence_a = module.build_fault_sequence(
            repeat_count=8,
            fault_ratio=0.25,
            fault_mode="wrong_port",
            noise_pattern="random",
            seed=1234,
        )
        sequence_b = module.build_fault_sequence(
            repeat_count=8,
            fault_ratio=0.25,
            fault_mode="wrong_port",
            noise_pattern="random",
            seed=1234,
        )
        sequence_c = module.build_fault_sequence(
            repeat_count=8,
            fault_ratio=0.25,
            fault_mode="wrong_port",
            noise_pattern="random",
            seed=5678,
        )

        self.assertEqual(sequence_a, sequence_b)
        self.assertNotEqual(sequence_a, sequence_c)
        self.assertEqual(module.digest_fault_sequence(sequence_a), module.digest_fault_sequence(sequence_b))
        self.assertNotEqual(module.digest_fault_sequence(sequence_a), module.digest_fault_sequence(sequence_c))

    def test_stage1a_grouped_stats_and_decision_rules_are_emitted(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            summary_path = tmp_path / "experiment_summary.json"
            xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
            uart_log = tmp_path / "board_uart.txt"
            xsct_script = tmp_path / "shadow_recovery_probe.tcl"
            xsct_log.write_text(
                "\n".join(
                    [
                        "PROBE_WINDOW_ID=Stage1A_BurstSweep:bf0001:bg0000us:sm0500ms:r01:Case2_RuntimeRingBypass",
                        "PROBE_WINDOW_ID=Stage1A_BurstSweep:bf0008:bg0000us:sm0500ms:r01:Case2_RuntimeRingBypass",
                        "PROBE_WINDOW_ID=Stage1A_BurstSweep:bf0064:bg0000us:sm0500ms:r01:Case2_RuntimeRingBypass",
                    ]
                ),
                encoding="utf-8",
            )
            uart_log.write_text("uart placeholder\n", encoding="utf-8")
            xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
            cases = []
            for burst_frames, accept, starvation in (
                (1, 4, 4),
                (8, 24, 24),
                (64, 80, 80),
            ):
                cases.append(
                    {
                        "name": f"bf{burst_frames:04d}.r01.Case2_RuntimeRingBypass",
                        "base_name": "Case2_RuntimeRingBypass",
                        "repeat": 1,
                        "burst_frames": burst_frames,
                        "burst_gap_us": 0,
                        "settle_ms": 500,
                        "probe_window_id": f"Stage1A_BurstSweep:bf{burst_frames:04d}:bg0000us:sm0500ms:r01:Case2_RuntimeRingBypass",
                        "inj_status_active": "0x00000000",
                        "delta": {
                            "backend_total_cycles": 1000,
                            "backend_accept_cycles": accept,
                            "backend_starvation_cycles": starvation,
                            "rollback_event_count": 0,
                            "recovery_active_cycles": 0,
                            "high_water_count": 0,
                            "drop_pulse_count": 0,
                        },
                        "post": {"netdbg_status": "0x000521A5"},
                    }
                )
            summary_path.write_text(
                json.dumps(
                    {
                        "timestamp": "2026-04-23T22:00:00+00:00",
                        "xsct_log": str(xsct_log),
                        "uart_log": str(uart_log),
                        "xsct_script": str(xsct_script),
                        "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                        "cases": cases,
                    }
                ),
                encoding="utf-8",
            )

            command = [
                sys.executable,
                str(INFRA_SCRIPT),
                "--summary-json",
                str(summary_path),
                "--output-root",
                str(tmp_path),
                "--repo-root",
                str(REPO_ROOT),
                "--probe-script",
                str(PROBE_SCRIPT),
                "--stage",
                "Stage1A_BurstSweep",
                "--traffic-mode",
                "burst",
                "--repeat-count",
                "1",
                "--burst-frames",
                "64",
                "--burst-gap-us",
                "0",
                "--settle-ms",
                "500",
                "--load-class",
                "stage1_staircase",
                "--stage1a-baseline-source",
                "full_run_bf1_group",
                "--stage1a-run-kind",
                "full_run",
            ]
            completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertEqual(completed.returncode, 0, completed.stdout)

            artifact_hashes = json.loads((tmp_path / "artifact_hashes.json").read_text(encoding="utf-8"))
            with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
                rows = list(csv.DictReader(handle))
            stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
            report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")

            self.assertIn("grouped_by_burst_frames_ordered", stats)
            self.assertEqual([group["burst_frames"] for group in stats["grouped_by_burst_frames_ordered"]], [1, 8, 64])
            for group in stats["grouped_by_burst_frames_ordered"]:
                for key in (
                    "burst_frames",
                    "raw_sample_count",
                    "included_count",
                    "excluded_count",
                    "backend_accept_cycles_stats",
                    "backend_starvation_cycles_stats",
                    "effective_work_ratio_stats",
                    "recovery_counters_nonzero_any",
                ):
                    self.assertIn(key, group)
            for token in (
                "backend_activity_monotonic",
                "dominant_backend_mode",
                "effective_work_ratio_trend",
                "recovery_counters_still_zero",
                "recommended_next_stage",
                "stage1a_run_kind: full_run",
                "stage1a_baseline_source: full_run_bf1_group",
                "candidate_for_paper_evidence: no",
                "Allowed use in paper: engineering evidence only",
            ):
                self.assertIn(token, report)
            self.assertNotIn("candidate figure", report)
            self.assertFalse(stats["paper_ready_recovery_gate"]["met"])
            self.assertTrue(rows)
            for row in rows:
                self.assertEqual(row["candidate_for_paper_evidence"], "no")
                self.assertIn("paper-ready recovery gate", row["why_it_is_or_is_not_candidate"])
            self.assertEqual(stats["stage1a_decision"]["stage1a_run_kind"], "full_run")
            self.assertEqual(stats["stage1a_decision"]["backend_activity_monotonic"], "yes")
            self.assertEqual(stats["stage1a_decision"]["dominant_backend_mode"], "balanced")
            self.assertEqual(stats["stage1a_decision"]["effective_work_ratio_trend"], "stable_around_0_5")
            self.assertTrue(stats["stage1a_decision"]["recovery_counters_still_zero"])
            self.assertEqual(stats["stage1a_decision"]["recommended_next_stage"], "Stage2_ExtremeTraffic")
            for artifact in artifact_hashes["artifacts"]:
                self.assertNotIn("paper_plot_data", artifact["relative_path"])

    def test_stage1a_drop_pulse_audit_stats_report_and_paper_guard(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            summary_path = tmp_path / "experiment_summary.json"
            xsct_log = tmp_path / "shadow_recovery_probe_xsct.txt"
            uart_log = tmp_path / "board_uart.txt"
            xsct_script = tmp_path / "shadow_recovery_probe.tcl"
            configs = [
                ("IdleControl", 0, 500, 0),
                ("Settle_BF1_SM10", 1, 10, 500),
                ("Settle_BF1_SM50", 1, 50, 2500),
                ("Settle_BF1_SM100", 1, 100, 5000),
                ("Shared_BF1_SM500", 1, 500, 25000),
                ("Burst_BF8_SM500", 8, 500, 26000),
                ("Burst_BF64_SM500", 64, 500, 27000),
            ]
            cases = []
            probe_ids = []
            for config_name, burst_frames, settle_ms, drop_delta in configs:
                for repeat in range(1, 4):
                    probe_id = (
                        f"Stage1A_DropPulseAudit:{config_name}:"
                        f"bf{burst_frames:04d}:sm{settle_ms:04d}ms:"
                        f"r{repeat:02d}:Case2_RuntimeRingBypass"
                    )
                    probe_ids.append(f"PROBE_WINDOW_ID={probe_id}")
                    cases.append(
                        {
                            "name": f"{config_name}.r{repeat:02d}.Case2_RuntimeRingBypass",
                            "base_name": "Case2_RuntimeRingBypass",
                            "audit_config": config_name,
                            "repeat": repeat,
                            "burst_frames": burst_frames,
                            "burst_gap_us": 0,
                            "settle_ms": settle_ms,
                            "probe_window_id": probe_id,
                            "audit_pre_snapshot_after_clear_nonzero": False,
                            "source_progress_pre": 0,
                            "source_progress_post": 0 if burst_frames == 0 else burst_frames,
                            "sink_progress_pre": 0,
                            "sink_progress_post": 0,
                            "inj_status_active": "0x00000000",
                            "delta": {
                                "backend_total_cycles": settle_ms * 50_000,
                                "backend_accept_cycles": 0,
                                "backend_starvation_cycles": 0,
                                "rollback_event_count": 0,
                                "recovery_active_cycles": 0,
                                "high_water_count": 0,
                                "drop_pulse_count": drop_delta,
                            },
                            "post": {"netdbg_status": "0x000521A5"},
                        }
                    )

            xsct_log.write_text("\n".join(probe_ids), encoding="utf-8")
            uart_log.write_text("uart placeholder\n", encoding="utf-8")
            xsct_script.write_text("# tcl placeholder\n", encoding="utf-8")
            summary_path.write_text(
                json.dumps(
                    {
                        "timestamp": "2026-04-24T00:30:00+00:00",
                        "xsct_log": str(xsct_log),
                        "uart_log": str(uart_log),
                        "xsct_script": str(xsct_script),
                        "baseline": {"pre": {"net_cfg0": "0x00000007"}},
                        "cases": cases,
                    }
                ),
                encoding="utf-8",
            )

            command = [
                sys.executable,
                str(INFRA_SCRIPT),
                "--summary-json",
                str(summary_path),
                "--output-root",
                str(tmp_path),
                "--repo-root",
                str(REPO_ROOT),
                "--probe-script",
                str(PROBE_SCRIPT),
                "--stage",
                "Stage1A_DropPulseAudit",
                "--traffic-mode",
                "burst",
                "--repeat-count",
                "3",
                "--burst-frames",
                "64",
                "--burst-gap-us",
                "0",
                "--settle-ms",
                "500",
                "--load-class",
                "drop_pulse_audit",
            ]
            completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertEqual(completed.returncode, 0, completed.stdout)

            stats = json.loads((tmp_path / "summary_stats.json").read_text(encoding="utf-8"))
            report = (tmp_path / "stage_report.md").read_text(encoding="utf-8")
            with (tmp_path / "case_results.csv").open(encoding="utf-8", newline="") as handle:
                rows = list(csv.DictReader(handle))

            self.assertEqual(stats["raw_sample_count"], 21)
            self.assertIn("drop_pulse_audit", stats)
            audit = stats["drop_pulse_audit"]
            for key in (
                "drop_pulse_idle_nonzero",
                "drop_pulse_idle_nonzero_reason",
                "drop_pulse_settle_linear_like",
                "drop_pulse_settle_rate_per_ms",
                "drop_pulse_burst_scaled",
                "drop_pulse_backend_activity_coupled",
                "drop_pulse_nonzero_rate",
                "drop_pulse_semantics_classification",
                "recommended_next_stage",
            ):
                self.assertIn(key, audit)
            self.assertFalse(audit["drop_pulse_idle_nonzero"])
            self.assertTrue(audit["drop_pulse_settle_linear_like"])
            self.assertFalse(audit["drop_pulse_burst_scaled"])
            self.assertFalse(audit["drop_pulse_backend_activity_coupled"])
            self.assertEqual(audit["drop_pulse_semantics_classification"], "active_level_or_sustained_backpressure")
            self.assertEqual(audit["recommended_next_stage"], "PBMIngressOrCryptoDMADiagnosis")

            for token in (
                "## Monitored diagnostic counters",
                "Nonzero front-end pressure counters: drop_pulse_count",
                "Nonzero rollback/recovery counters: none",
                "Nonzero backend service counters: none",
                "drop_pulse_nonzero_rate",
                "drop_pulse_semantics_classification: active_level_or_sustained_backpressure",
                "recommended_next_stage: PBMIngressOrCryptoDMADiagnosis",
                "Interpretation: drop_pulse_count is interpreted as active_level_or_sustained_backpressure",
                "candidate_for_paper_evidence: no",
                "Allowed use in paper: engineering evidence only",
            ):
                self.assertIn(token, report)
            self.assertNotIn("Trigger rate:", report)
            self.assertFalse(stats["paper_ready_recovery_gate"]["met"])
            self.assertTrue(rows)
            idle_rows = [row for row in rows if row["audit_config"] == "IdleControl"]
            self.assertEqual(len(idle_rows), 3)
            self.assertTrue(all(row["BurstFrames"] == "0" for row in idle_rows))
            for row in rows:
                self.assertEqual(row["candidate_for_paper_evidence"], "no")

    def test_stage1a6_prior_drop_pulse_reproduction_reports_not_reproduced_under_controlled_sampling(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            boot_file = tmp_path / "BOOT.BIN"
            bit_file = tmp_path / "design.bit"
            xsa_file = tmp_path / "design.xsa"
            boot_file.write_bytes(b"boot")
            bit_file.write_bytes(b"bit")
            xsa_file.write_bytes(b"xsa")
            full_dir, audit_dir = self._write_reference_stage1a6_dirs(tmp_path, boot_file, bit_file, xsa_file)
            summary_path = self._build_stage1a6_summary(
                tmp_path,
                drop_by_config={"BF1_SM500": 0, "BF8_SM500": 0, "BF64_SM500": 0},
            )

            stats, report = self._run_stage1a6_cli(
                tmp_path,
                summary_path,
                full_dir,
                audit_dir,
                boot_file,
                bit_file,
                xsa_file,
            )

            reproduction = stats["prior_drop_pulse_reproduction"]
            self.assertEqual(reproduction["raw_sample_count"], 9)
            self.assertEqual(reproduction["excluded_sample_count"], 0)
            self.assertEqual(reproduction["reproduction_mode"], "controlled_sampling_replay")
            self.assertEqual(
                reproduction["artifact_hash_match"],
                {"boot_bin": True, "bit": True, "xsa": True, "csr_map": "unknown"},
            )
            self.assertEqual(
                reproduction["old_median_drop_pulse_by_config"],
                {"BF1_SM500": 26000000.0, "BF8_SM500": 27000000.0, "BF64_SM500": 28000000.0},
            )
            self.assertEqual(
                reproduction["old_vs_replay_drop_ratio_by_config"],
                {"BF1_SM500": 0.0, "BF8_SM500": 0.0, "BF64_SM500": 0.0},
            )
            self.assertFalse(reproduction["reproduced_prior_drop_pulse"])
            self.assertEqual(
                reproduction["drop_pulse_reproduction_classification"],
                "not_reproduced_under_controlled_sampling",
            )
            self.assertEqual(reproduction["recommended_next_stage"], "PBMIngressOrCryptoDMADiagnosis")
            for token in (
                "## Stage 1A.6 Prior-DropPulse Reproduction Check",
                "Controlled replay invariants",
                "Allowed changes",
                "artifact_hash_match",
                "boot_bin: true",
                "csr_map: unknown",
                "old_vs_replay_drop_ratio_by_config",
                "recommended_next_stage: PBMIngressOrCryptoDMADiagnosis",
                "candidate_for_paper_evidence: no",
                "Allowed use in paper: engineering evidence only",
                "The prior nonzero drop_pulse_count observation is evaluated only as an engineering diagnostic.",
                "The prior nonzero drop_pulse_count was not reproduced under controlled sampling replay.",
                "Known unrelated release-test failures: legacy/handoff assets and existing py.exe contract assumptions.",
            ):
                self.assertIn(token, report)

    def test_stage1a6_prior_drop_pulse_reproduction_routes_sampling_issues_to_counter_fix(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            boot_file = tmp_path / "BOOT.BIN"
            bit_file = tmp_path / "design.bit"
            xsa_file = tmp_path / "design.xsa"
            boot_file.write_bytes(b"boot")
            bit_file.write_bytes(b"bit")
            xsa_file.write_bytes(b"xsa")
            full_dir, audit_dir = self._write_reference_stage1a6_dirs(tmp_path, boot_file, bit_file, xsa_file)
            summary_path = self._build_stage1a6_summary(
                tmp_path,
                drop_by_config={"BF1_SM500": 0, "BF8_SM500": 0, "BF64_SM500": 0},
                pre_after_clear_nonzero_configs={"BF8_SM500"},
            )

            stats, report = self._run_stage1a6_cli(
                tmp_path,
                summary_path,
                full_dir,
                audit_dir,
                boot_file,
                bit_file,
                xsa_file,
            )

            reproduction = stats["prior_drop_pulse_reproduction"]
            self.assertEqual(reproduction["pre_after_clear_nonzero_count"], 3)
            self.assertEqual(len(reproduction["pre_after_clear_nonzero_windows"]), 3)
            self.assertEqual(
                reproduction["drop_pulse_reproduction_classification"],
                "sampling_or_clear_artifact",
            )
            self.assertEqual(reproduction["recommended_next_stage"], "FixCounterSamplingAndRerunStage1A")
            self.assertIn("recommended_next_stage: FixCounterSamplingAndRerunStage1A", report)

    def test_stage1a6_prior_drop_pulse_reproduction_routes_nonzero_replay_to_condition_diff(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            boot_file = tmp_path / "BOOT.BIN"
            bit_file = tmp_path / "design.bit"
            xsa_file = tmp_path / "design.xsa"
            boot_file.write_bytes(b"boot")
            bit_file.write_bytes(b"bit")
            xsa_file.write_bytes(b"xsa")
            full_dir, audit_dir = self._write_reference_stage1a6_dirs(tmp_path, boot_file, bit_file, xsa_file)
            summary_path = self._build_stage1a6_summary(
                tmp_path,
                drop_by_config={"BF1_SM500": 3000000, "BF8_SM500": 15000000, "BF64_SM500": 20000000},
            )

            stats, report = self._run_stage1a6_cli(
                tmp_path,
                summary_path,
                full_dir,
                audit_dir,
                boot_file,
                bit_file,
                xsa_file,
            )

            reproduction = stats["prior_drop_pulse_reproduction"]
            self.assertTrue(reproduction["reproduced_prior_drop_pulse"])
            self.assertEqual(
                reproduction["drop_pulse_reproduction_classification"],
                "reproduced_prior_drop_pulse",
            )
            self.assertEqual(reproduction["recommended_next_stage"], "DropPulseConditionDiffDiagnosis")
            self.assertGreaterEqual(reproduction["old_vs_replay_drop_ratio_by_config"]["BF1_SM500"], 0.1)
            self.assertGreaterEqual(reproduction["old_vs_replay_drop_ratio_by_config"]["BF8_SM500"], 0.5)
            self.assertGreaterEqual(reproduction["old_vs_replay_drop_ratio_by_config"]["BF64_SM500"], 0.5)
            self.assertIn("recommended_next_stage: DropPulseConditionDiffDiagnosis", report)

    def test_stage1a7_condition_diff_uses_bucketed_counters_and_bf8_negative_control(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            summary_path = self._build_stage1a7_summary(tmp_path)

            stats, report, rows = self._run_stage1a7_cli(tmp_path, summary_path)

            self.assertIn("stage1a7_condition_diff", stats)
            decision = stats["stage1a7_condition_diff"]
            self.assertFalse(stats["paper_ready_recovery_gate"]["met"])
            self.assertTrue(decision["frontend_pressure_seen"])
            self.assertFalse(decision["rollback_recovery_seen"])
            self.assertFalse(decision["backend_activity_seen"])
            self.assertTrue(decision["negative_control_valid"])
            self.assertEqual(
                decision["negative_control_violation_reason"],
                "BF8_SM500 remained a clean negative control under the current board run",
            )
            self.assertFalse(decision["bf8_observed_stall"])
            self.assertTrue(decision["bf64_observed_stall"])
            self.assertEqual(decision["condition_diff_status"], "clean_negative_control")
            self.assertTrue(decision["frontend_valid_not_ready_stall_strong"])
            self.assertFalse(decision["frontend_valid_not_ready_stall_partial"])
            self.assertTrue(decision["ingress_progress_stalled"])
            self.assertFalse(decision["drop_pulse_window_scaled"])
            self.assertTrue(decision["drop_pulse_window_short_no_trigger"])
            self.assertEqual(decision["recommended_next_stage"], "PBMIngressVisibilityDiagnosis")
            self.assertEqual(decision["bf8_negative_control_netdbg"]["hex"], "0x00043FAA")
            self.assertEqual(decision["bf64_positive_condition_netdbg"]["hex"], "0x0000CF55")

            for token in (
                "## Stage 1A.7 DropPulse Condition-Diff Diagnosis",
                "planned_negative_control: BF8_SM500",
                "planned_positive_condition: BF64_SM500",
                "negative_control_valid: true",
                "negative_control_violation_reason: BF8_SM500 remained a clean negative control under the current board run",
                "bf8_observed_stall: false",
                "bf64_observed_stall: true",
                "condition_diff_status: clean_negative_control",
                "frontend_pressure_seen: true",
                "rollback_recovery_seen: false",
                "backend_activity_seen: false",
                "frontend_valid_not_ready_stall_strong: true",
                "ingress_progress_stalled: true",
                "drop_pulse_window_short_no_trigger: true",
                "recommended_next_stage: PBMIngressVisibilityDiagnosis",
                "## Monitored diagnostic counters",
                "Nonzero front-end pressure counters: drop_pulse_count",
                "Nonzero rollback/recovery counters: none",
                "Nonzero backend service counters: none",
                "candidate_for_paper_evidence: no",
                "Allowed use in paper: engineering evidence only",
            ):
                self.assertIn(token, report)

            self.assertTrue(rows)
            bf8_rows = [row for row in rows if row["condition_diff_config"] == "BF8_SM500"]
            bf64_rows = [row for row in rows if row["condition_diff_config"] == "BF64_SM500"]
            bf64_sm100_rows = [row for row in rows if row["condition_diff_config"] == "BF64_SM100"]
            bf64_extra_rows = [row for row in rows if row["condition_diff_config"] == "BF64_SM500_ExtraSnapshots"]
            self.assertEqual({row["stage_status"] for row in bf8_rows}, {"negative_control_pass"})
            self.assertEqual({row["stage_status"] for row in bf64_rows}, {"positive_reproduction_condition"})
            self.assertEqual({row["stage_status"] for row in bf64_sm100_rows}, {"window_short_no_trigger"})
            self.assertEqual({row["stage_status"] for row in bf64_extra_rows}, {"extra_snapshot_observation"})
            for row in bf64_rows + bf64_sm100_rows + bf64_extra_rows:
                self.assertEqual(row["inj_status_hex"], "0x00010008")
                self.assertEqual(row["inj_status_decode_source"], "current RTL/CSR definition")
                self.assertEqual(row["inj_fifo_nonempty"], "1")
                self.assertEqual(row["inj_fifo_count"], "8")
                self.assertEqual(row["netdbg_status_hex"], "0x0000CF55")
            for row in bf8_rows:
                self.assertEqual(row["netdbg_status_hex"], "0x00043FAA")
                self.assertEqual(row["netdbg_status_xor_vs_bf8_baseline_hex"], "0x00000000")
            for row in bf64_rows + bf64_sm100_rows + bf64_extra_rows:
                self.assertEqual(row["netdbg_status_xor_vs_bf8_baseline_hex"], "0x0004F0FF")

    def test_stage1a8_pbm_ingress_visibility_routes_ready_gating_without_backend_or_recovery(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            summary_path = self._build_stage1a8_summary(tmp_path)

            stats, report, rows = self._run_stage1a8_cli(tmp_path, summary_path)

            self.assertIn("stage1a8_pbm_ingress_visibility", stats)
            decision = stats["stage1a8_pbm_ingress_visibility"]
            self.assertFalse(stats["paper_ready_recovery_gate"]["met"])
            self.assertTrue(decision["frontend_pressure_seen"])
            self.assertFalse(decision["backend_activity_seen"])
            self.assertFalse(decision["rollback_recovery_seen"])
            self.assertFalse(decision["pbm_diag_csr_collision"])
            self.assertEqual(decision["diagnostic_csr_address_range"], "0x154-0x190")
            self.assertTrue(decision["pbm_ingress_valid_not_ready_stall"])
            self.assertFalse(decision["pbm_accept_without_packet_end"])
            self.assertFalse(decision["pbm_commit_without_backend_service"])
            self.assertFalse(decision["pbm_rollback_trigger_candidate_seen"])
            self.assertFalse(decision["pbm_rollback_path_observed"])
            self.assertEqual(decision["recommended_next_stage"], "PBMReadyGatingDiagnosis")

            for token in (
                "## Stage 1A.8 PBM Ingress Visibility Diagnosis",
                "diagnostic_csr_address_range: 0x154-0x190",
                "pbm_diag_csr_collision: false",
                "idle_control_quiesce_guard_ms",
                "pbm_ingress_valid_not_ready_stall: true",
                "pbm_accept_without_packet_end: false",
                "pbm_commit_without_backend_service: false",
                "pbm_rollback_trigger_candidate_seen: false",
                "pbm_rollback_path_observed: false",
                "recommended_next_stage: PBMReadyGatingDiagnosis",
                "Nonzero front-end pressure counters: drop_pulse_count",
                "Nonzero rollback/recovery counters: none",
                "Nonzero backend service counters: none",
                "candidate_for_paper_evidence: no",
                "Allowed use in paper: engineering evidence only",
            ):
                self.assertIn(token, report)

            self.assertTrue(rows)
            bf64_rows = [row for row in rows if row["pbm_visibility_config"] == "BF64_SM500"]
            idle_rows = [row for row in rows if row["pbm_visibility_config"] == "IdleControl"]
            self.assertEqual({row["stage_status"] for row in idle_rows}, {"negative_control_pass"})
            self.assertEqual({row["stage_status"] for row in bf64_rows}, {"ingress_ready_gating_observed"})
            for row in bf64_rows:
                self.assertEqual(row["pbm_wr_accept_cycles"], "0")
                self.assertGreater(int(row["pbm_valid_not_ready_cycles"]), 0)
                self.assertEqual(row["pbm_state_decoded"], "ALLOC_META")

    def test_stage1a8_pbm_ingress_visibility_prioritizes_rollback_trigger_candidate(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            summary_path = self._build_stage1a8_summary(
                tmp_path,
                bf64_accept_cycles=4,
                bf64_last_accepted_count=1,
                bf64_last_error_accepted_count=1,
            )

            stats, report, _ = self._run_stage1a8_cli(tmp_path, summary_path)

            decision = stats["stage1a8_pbm_ingress_visibility"]
            self.assertTrue(decision["pbm_rollback_trigger_candidate_seen"])
            self.assertFalse(decision["pbm_rollback_path_observed"])
            self.assertEqual(decision["recommended_next_stage"], "DropRollbackCouplingDiagnosis")
            self.assertIn("pbm_rollback_trigger_candidate_seen: true", report)
            self.assertIn("pbm_rollback_path_observed: false", report)
            self.assertIn("recommended_next_stage: DropRollbackCouplingDiagnosis", report)

    def test_stage1a9_crypto_ingress_handoff_detects_crypto_rx_activity_without_pbm_activity(self):
        tmp_path = REPO_ROOT / "stage1a9_contract_tmp_rx_without_pbm"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a9_summary(tmp_path)

            stats, report, rows = self._run_stage1a9_cli(tmp_path, summary_path)

            self.assertIn("stage1a9_crypto_ingress_handoff_visibility", stats)
            decision = stats["stage1a9_crypto_ingress_handoff_visibility"]
            self.assertFalse(stats["paper_ready_recovery_gate"]["met"])
            self.assertEqual(decision["diagnostic_csr_address_range"], "0x194-0x1B0")
            self.assertFalse(decision["crypto_ingress_diag_csr_collision"])
            self.assertTrue(decision["crypto_rx_valid_not_ready_seen"])
            self.assertFalse(decision["pbm_activity_seen"])
            self.assertTrue(decision["crypto_rx_without_pbm_activity"])
            self.assertFalse(decision["crypto_rx_accept_without_pbm_accept"])
            self.assertEqual(decision["recommended_next_stage"], "CryptoIngressToPBMBindingDiagnosis")

            for token in (
                "## Stage 1A.9 Crypto Ingress Handoff Visibility Diagnosis",
                "diagnostic_csr_address_range: 0x194-0x1B0",
                "crypto_rx_valid_not_ready_seen: true",
                "pbm_activity_seen: false",
                "crypto_rx_without_pbm_activity: true",
                "crypto_rx_accept_without_pbm_accept: false",
                "recommended_next_stage: CryptoIngressToPBMBindingDiagnosis",
                "candidate_for_paper_evidence: no",
                "Allowed use in paper: engineering evidence only",
            ):
                self.assertIn(token, report)

            bf64_rows = [row for row in rows if row["crypto_ingress_config"] == "BF64_SM500"]
            idle_rows = [row for row in rows if row["crypto_ingress_config"] == "IdleControl"]
            self.assertEqual({row["stage_status"] for row in idle_rows}, {"negative_control_pass"})
            self.assertEqual({row["stage_status"] for row in bf64_rows}, {"crypto_rx_without_pbm_activity_observed"})
            for row in bf64_rows:
                self.assertGreater(int(row["crypto_rx_valid_not_ready_cycles"]), 0)
                self.assertEqual(row["crypto_rx_accept_cycles"], "0")
                self.assertEqual(row["pbm_wr_valid_cycles"], "0")
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a9_crypto_ingress_handoff_routes_to_crypto_dma_handoff_after_pbm_commit(self):
        tmp_path = REPO_ROOT / "stage1a9_contract_tmp_pbm_commit_backend_intermittent"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a9_summary(
                tmp_path,
                crypto_rx_backpressured=False,
                pbm_accept_seen=True,
                pbm_commit_seen=True,
                backend_activity_pattern="intermittent",
            )

            stats, report, rows = self._run_stage1a9_cli(tmp_path, summary_path)

            decision = stats["stage1a9_crypto_ingress_handoff_visibility"]
            self.assertTrue(decision["crypto_rx_valid_seen"])
            self.assertFalse(decision["crypto_rx_valid_not_ready_seen"])
            self.assertTrue(decision["pbm_accept_seen"])
            self.assertTrue(decision["pbm_commit_seen"])
            self.assertGreater(decision["pbm_commit_rows_seen"], 0)
            self.assertTrue(decision["backend_activity_seen"])
            self.assertFalse(decision["backend_activity_stable"])
            self.assertTrue(decision["backend_activity_intermittent"])
            self.assertTrue(decision["pbm_commit_without_backend_service"])
            self.assertEqual(decision["recommended_next_stage"], "CryptoDMAHandoffDiagnosis")

            for token in (
                "pbm_accept_seen: true",
                "pbm_commit_seen: true",
                "backend_activity_intermittent: true",
                "pbm_commit_without_backend_service: true",
                "recommended_next_stage: CryptoDMAHandoffDiagnosis",
            ):
                self.assertIn(token, report)

            active_commit_rows = [
                row
                for row in rows
                if row["crypto_ingress_config"] != "IdleControl" and int(row["pbm_commit_entry_count"]) > 0
            ]
            self.assertTrue(active_commit_rows)
            self.assertIn("pbm_commit_without_backend_service_observed", {row["stage_status"] for row in active_commit_rows})
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a9_crypto_ingress_handoff_routes_to_wrapper_boundary_when_crypto_rx_is_absent(self):
        tmp_path = REPO_ROOT / "stage1a9_contract_tmp_rx_absent"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a9_summary(tmp_path, crypto_rx_seen=False)

            stats, report, _ = self._run_stage1a9_cli(tmp_path, summary_path)

            decision = stats["stage1a9_crypto_ingress_handoff_visibility"]
            self.assertFalse(decision["crypto_rx_valid_seen"])
            self.assertEqual(decision["recommended_next_stage"], "WrapperClassifierDMABoundaryDiagnosis")
            self.assertIn("recommended_next_stage: WrapperClassifierDMABoundaryDiagnosis", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a10_crypto_dma_handoff_routes_commit_without_tail_to_pbm_read_visibility(self):
        tmp_path = REPO_ROOT / "stage1a10_contract_tmp_tail_gap"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a10_summary(tmp_path)

            stats, report, rows = self._run_stage1a10_cli(tmp_path, summary_path)

            self.assertIn("crypto_dma_handoff_diagnosis", stats)
            decision = stats["crypto_dma_handoff_diagnosis"]
            self.assertFalse(stats["paper_ready_recovery_gate"]["met"])
            self.assertEqual(decision["diagnostic_csr_address_range"], "0x1B4-0x1DC")
            self.assertFalse(decision["crypto_dma_handoff_diag_csr_collision"])
            self.assertTrue(decision["pbm_commit_seen"])
            self.assertTrue(decision["pbm_committed_but_tail_not_moved"])
            self.assertFalse(decision["crypto_dma_ingress_accept_seen"])
            self.assertEqual(decision["handoff_gap_classification"], "pbm_read_visibility_gap")
            self.assertEqual(decision["recommended_next_stage"], "PBMReadSideVisibilityDiagnosis")

            for token in (
                "## Stage 1A.10 Crypto DMA Handoff Diagnosis",
                "diagnostic_csr_address_range: 0x1B4-0x1DC",
                "pbm_committed_but_tail_not_moved: true",
                "handoff_gap_classification: pbm_read_visibility_gap",
                "recommended_next_stage: PBMReadSideVisibilityDiagnosis",
                "candidate_for_paper_evidence: no",
            ):
                self.assertIn(token, report)

            active_rows = [row for row in rows if row["crypto_dma_handoff_config"] != "IdleControl"]
            self.assertTrue(active_rows)
            self.assertIn("pbm_read_visibility_gap_observed", {row["stage_status"] for row in active_rows})
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a10_crypto_dma_handoff_routes_crypto_accept_with_intermittent_backend_to_backend_gating(self):
        tmp_path = REPO_ROOT / "stage1a10_contract_tmp_backend_gap"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a10_summary(
                tmp_path,
                tail_moves=True,
                crypto_dma_accept_seen=True,
                backend_activity_pattern="intermittent",
            )

            stats, report, _ = self._run_stage1a10_cli(tmp_path, summary_path)

            decision = stats["crypto_dma_handoff_diagnosis"]
            self.assertTrue(decision["pbm_rd_accept_seen"])
            self.assertTrue(decision["crypto_dma_ingress_accept_seen"])
            self.assertTrue(decision["backend_activity_seen"])
            self.assertFalse(decision["backend_activity_stable"])
            self.assertEqual(decision["handoff_gap_classification"], "backend_input_gating")
            self.assertEqual(decision["recommended_next_stage"], "BackendInputGatingDiagnosis")
            self.assertIn("recommended_next_stage: BackendInputGatingDiagnosis", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a10_crypto_dma_handoff_idle_crypto_residual_forces_sampling_fix(self):
        tmp_path = REPO_ROOT / "stage1a10_contract_tmp_idle_residual"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a10_summary(
                tmp_path,
                idle_crypto_dma_residual_seen=True,
                active_commit_seen=False,
            )

            stats, report, rows = self._run_stage1a10_cli(tmp_path, summary_path)

            decision = stats["crypto_dma_handoff_diagnosis"]
            self.assertTrue(decision["idle_residual_activity_seen"])
            self.assertEqual(decision["handoff_gap_classification"], "inconclusive")
            self.assertEqual(decision["recommended_next_stage"], "FixSamplingOrAlignment")

            idle_rows = [row for row in rows if row["crypto_dma_handoff_config"] == "IdleControl"]
            self.assertEqual({row["stage_status"] for row in idle_rows}, {"negative_control_unstable"})
            for row in idle_rows:
                self.assertGreater(int(row["crypto_dma_in_valid_cycles"]), 0)
                self.assertEqual(row["idle_residual_activity_seen"], "False")

            self.assertIn("idle_residual_activity_seen: true", report)
            self.assertIn("recommended_next_stage: FixSamplingOrAlignment", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a10_crypto_dma_handoff_prefers_active_tail_gap_over_idle_residual(self):
        tmp_path = REPO_ROOT / "stage1a10_contract_tmp_tail_gap_with_idle_residual"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a10_summary(
                tmp_path,
                idle_crypto_dma_residual_seen=True,
            )

            stats, report, _ = self._run_stage1a10_cli(tmp_path, summary_path)

            decision = stats["crypto_dma_handoff_diagnosis"]
            self.assertTrue(decision["idle_residual_activity_seen"])
            self.assertTrue(decision["pbm_commit_seen"])
            self.assertTrue(decision["pbm_committed_but_tail_not_moved"])
            self.assertEqual(decision["handoff_gap_classification"], "pbm_read_visibility_gap")
            self.assertEqual(decision["recommended_next_stage"], "PBMReadSideVisibilityDiagnosis")
            self.assertIn("recommended_next_stage: PBMReadSideVisibilityDiagnosis", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a11_pbm_read_side_routes_commit_without_bridge_rd_en_to_bridge_gap(self):
        tmp_path = REPO_ROOT / "stage1a11_contract_tmp_bridge_gap"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a11_summary(
                tmp_path,
                data_without_inst_available_seen=True,
            )

            stats, report, rows = self._run_stage1a11_cli(tmp_path, summary_path)

            decision = stats["stage1a11_pbm_read_side_visibility"]
            self.assertFalse(stats["paper_ready_recovery_gate"]["met"])
            self.assertEqual(decision["diagnostic_csr_address_range"], "0x1E0-0x21C")
            self.assertFalse(decision["pbm_read_side_diag_csr_collision"])
            self.assertTrue(decision["pbm_commit_seen"])
            self.assertFalse(decision["bridge_rd_en_seen"])
            self.assertTrue(decision["data_without_inst_available_seen"])
            self.assertEqual(decision["read_side_gap_classification"], "crypto_bridge_availability_gap")
            self.assertEqual(decision["recommended_next_stage"], "CryptoBridgeAvailabilityDiagnosis")

            for token in (
                "## Stage 1A.11 PBM Read-Side Visibility Diagnosis",
                "diagnostic_csr_address_range: 0x1E0-0x21C",
                "bridge_rd_en_seen: false",
                "data_without_inst_available_seen: true",
                "recommended_next_stage: CryptoBridgeAvailabilityDiagnosis",
            ):
                self.assertIn(token, report)

            active_rows = [row for row in rows if row["pbm_read_side_config"] != "IdleControl"]
            self.assertTrue(active_rows)
            self.assertIn("crypto_bridge_availability_gap_observed", {row["stage_status"] for row in active_rows})
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a11_pbm_read_side_routes_bridge_fire_without_dma_start_to_dma_start_gap(self):
        tmp_path = REPO_ROOT / "stage1a11_contract_tmp_dma_start_gap"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a11_summary(
                tmp_path,
                bridge_rd_en_seen=True,
                bridge_fire_seen=True,
            )

            stats, report, rows = self._run_stage1a11_cli(tmp_path, summary_path)

            decision = stats["stage1a11_pbm_read_side_visibility"]
            self.assertTrue(decision["bridge_rd_en_seen"])
            self.assertTrue(decision["bridge_fire_seen"])
            self.assertFalse(decision["dma_start_seen"])
            self.assertEqual(decision["read_side_gap_classification"], "dma_transfer_start_gap")
            self.assertEqual(decision["recommended_next_stage"], "DMATransferStartDiagnosis")
            self.assertIn("recommended_next_stage: DMATransferStartDiagnosis", report)

            active_rows = [row for row in rows if row["pbm_read_side_config"] != "IdleControl"]
            self.assertTrue(active_rows)
            self.assertIn("dma_transfer_start_gap_observed", {row["stage_status"] for row in active_rows})
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a12_bridge_output_fifo_idle_nonempty_routes_to_residual_diagnosis(self):
        tmp_path = REPO_ROOT / "stage1a12_contract_tmp_idle_residual"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a12_summary(
                tmp_path,
                idle_bridge_residual_seen=True,
            )

            stats, report, rows = self._run_stage1a12_cli(tmp_path, summary_path)

            decision = stats["stage1a12_bridge_output_fifo_visibility"]
            self.assertEqual(decision["diagnostic_csr_address_range"], "0x220-0x22C")
            self.assertFalse(decision["bridge_output_fifo_diag_csr_collision"])
            self.assertTrue(decision["idle_bridge_output_fifo_residual_seen"])
            self.assertTrue(decision["bridge_output_fifo_nonempty_seen"])
            self.assertFalse(decision["bridge_output_fifo_accept_seen"])
            self.assertEqual(decision["bridge_output_fifo_classification"], "bridge_output_fifo_residual")
            self.assertEqual(decision["recommended_next_stage"], "BridgeOutputFIFOResidualDiagnosis")

            idle_rows = [row for row in rows if row["bridge_output_fifo_config"] == "IdleControl"]
            self.assertEqual({row["stage_status"] for row in idle_rows}, {"negative_control_unstable"})
            self.assertIn("recommended_next_stage: BridgeOutputFIFOResidualDiagnosis", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a12_bridge_output_fifo_active_nonempty_without_dma_start_routes_to_start_path_diagnosis(self):
        tmp_path = REPO_ROOT / "stage1a12_contract_tmp_start_gap"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a12_summary(tmp_path)

            stats, report, rows = self._run_stage1a12_cli(tmp_path, summary_path)

            decision = stats["stage1a12_bridge_output_fifo_visibility"]
            self.assertTrue(decision["bridge_output_fifo_nonempty_seen"])
            self.assertFalse(decision["dma_start_seen"])
            self.assertFalse(decision["bridge_output_fifo_rd_en_seen"])
            self.assertFalse(decision["bridge_output_fifo_accept_seen"])
            self.assertEqual(decision["bridge_output_fifo_classification"], "dma_start_path_absent")
            self.assertEqual(decision["recommended_next_stage"], "DMAStartPathDiagnosis")

            active_rows = [row for row in rows if row["bridge_output_fifo_config"] != "IdleControl"]
            self.assertTrue(active_rows)
            self.assertIn("dma_start_path_absent_observed", {row["stage_status"] for row in active_rows})
            self.assertIn("recommended_next_stage: DMAStartPathDiagnosis", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a12_bridge_output_fifo_active_nonempty_without_rd_en_after_dma_start_routes_to_dma_rd_enable_gating(self):
        tmp_path = REPO_ROOT / "stage1a12_contract_tmp_rd_enable_gap"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a12_summary(
                tmp_path,
                dma_start_seen=True,
            )

            stats, report, rows = self._run_stage1a12_cli(tmp_path, summary_path)

            decision = stats["stage1a12_bridge_output_fifo_visibility"]
            self.assertTrue(decision["bridge_output_fifo_nonempty_seen"])
            self.assertTrue(decision["dma_start_seen"])
            self.assertFalse(decision["bridge_output_fifo_rd_en_seen"])
            self.assertFalse(decision["bridge_output_fifo_accept_seen"])
            self.assertEqual(decision["bridge_output_fifo_classification"], "dma_rd_enable_gating")
            self.assertEqual(decision["recommended_next_stage"], "DMARdEnableGatingDiagnosis")

            active_rows = [row for row in rows if row["bridge_output_fifo_config"] != "IdleControl"]
            self.assertTrue(active_rows)
            self.assertIn("dma_rd_enable_gating_observed", {row["stage_status"] for row in active_rows})
            self.assertIn("recommended_next_stage: DMARdEnableGatingDiagnosis", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a13_dma_start_path_routes_missing_start_source_to_probe_control_fix(self):
        tmp_path = REPO_ROOT / "stage1a13_contract_tmp_probe_control_fix"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a13_summary(tmp_path)

            stats, report, rows = self._run_stage1a13_cli(tmp_path, summary_path)

            decision = stats["stage1a13_dma_start_path_diagnosis"]
            self.assertTrue(decision["current_bridge_tx_nonempty_seen"])
            self.assertFalse(decision["current_dma_start_seen"])
            self.assertTrue(decision["explicit_csr_start_seen"])
            self.assertTrue(decision["explicit_final_start_seen"])
            self.assertTrue(decision["explicit_dma_start_seen"])
            self.assertEqual(decision["dma_start_path_classification"], "start_source_absent")
            self.assertEqual(decision["recommended_next_stage"], "StartPulseInjectionOrProbeControlFix")

            current_rows = [row for row in rows if row["dma_start_path_config"] == "Current_Bypass_NoExplicitStart"]
            explicit_rows = [row for row in rows if row["dma_start_path_config"] == "Bypass_WithExplicitCSRStart"]
            self.assertIn("start_source_absent_observed", {row["stage_status"] for row in current_rows})
            self.assertIn("explicit_start_chain_observed", {row["stage_status"] for row in explicit_rows})
            self.assertIn("recommended_next_stage: StartPulseInjectionOrProbeControlFix", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a13_dma_start_path_routes_csr_start_without_final_start_to_selection_logic(self):
        tmp_path = REPO_ROOT / "stage1a13_contract_tmp_final_start_logic"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a13_summary(
                tmp_path,
                explicit_overrides={
                    "final_start_pulse_count": 0,
                    "dma_start_seen_count": 0,
                    "dma_busy_cycles": 0,
                    "bridge_tx_rd_en_cycles": 0,
                    "bridge_tx_accept_cycles": 0,
                    "crypto_dma_in_accept_cycles": 0,
                },
            )

            stats, report, rows = self._run_stage1a13_cli(tmp_path, summary_path)

            decision = stats["stage1a13_dma_start_path_diagnosis"]
            self.assertTrue(decision["explicit_csr_start_seen"])
            self.assertFalse(decision["explicit_final_start_seen"])
            self.assertEqual(decision["dma_start_path_classification"], "csr_start_seen_but_final_start_absent")
            self.assertEqual(decision["recommended_next_stage"], "FinalStartSelectionLogicDiagnosis")

            explicit_rows = [row for row in rows if row["dma_start_path_config"] == "Bypass_WithExplicitCSRStart"]
            self.assertIn(
                "csr_start_without_final_start_observed",
                {row["stage_status"] for row in explicit_rows},
            )
            self.assertIn("recommended_next_stage: FinalStartSelectionLogicDiagnosis", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a13_dma_start_path_routes_final_start_without_dma_activation_to_source_reader_latch(self):
        tmp_path = REPO_ROOT / "stage1a13_contract_tmp_source_reader_latch"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a13_summary(
                tmp_path,
                explicit_overrides={
                    "dma_start_seen_count": 0,
                    "dma_busy_cycles": 0,
                    "bridge_tx_rd_en_cycles": 0,
                    "bridge_tx_accept_cycles": 0,
                    "crypto_dma_in_accept_cycles": 0,
                },
            )

            stats, report, rows = self._run_stage1a13_cli(tmp_path, summary_path)

            decision = stats["stage1a13_dma_start_path_diagnosis"]
            self.assertTrue(decision["explicit_final_start_seen"])
            self.assertFalse(decision["explicit_dma_start_seen"])
            self.assertEqual(decision["dma_start_path_classification"], "final_start_seen_but_dma_not_active")
            self.assertEqual(decision["recommended_next_stage"], "SourceReaderStartLatchDiagnosis")

            explicit_rows = [row for row in rows if row["dma_start_path_config"] == "Bypass_WithExplicitCSRStart"]
            self.assertIn(
                "final_start_without_dma_activation_observed",
                {row["stage_status"] for row in explicit_rows},
            )
            self.assertIn("recommended_next_stage: SourceReaderStartLatchDiagnosis", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a13_dma_start_path_routes_dma_active_without_rd_en_to_rd_enable_gating(self):
        tmp_path = REPO_ROOT / "stage1a13_contract_tmp_rd_enable_gap"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a13_summary(
                tmp_path,
                explicit_overrides={
                    "bridge_tx_rd_en_cycles": 0,
                    "bridge_tx_accept_cycles": 0,
                    "crypto_dma_in_accept_cycles": 0,
                },
            )

            stats, report, rows = self._run_stage1a13_cli(tmp_path, summary_path)

            decision = stats["stage1a13_dma_start_path_diagnosis"]
            self.assertTrue(decision["explicit_dma_start_seen"])
            self.assertTrue(decision["explicit_dma_busy_seen"])
            self.assertFalse(decision["explicit_bridge_tx_rd_en_seen"])
            self.assertEqual(decision["dma_start_path_classification"], "dma_active_but_no_rd_en")
            self.assertEqual(decision["recommended_next_stage"], "DMARdEnableGatingDiagnosis")

            explicit_rows = [row for row in rows if row["dma_start_path_config"] == "Bypass_WithExplicitCSRStart"]
            self.assertIn("dma_active_but_no_rd_en_observed", {row["stage_status"] for row in explicit_rows})
            self.assertIn("recommended_next_stage: DMARdEnableGatingDiagnosis", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a14_start_pulse_injection_routes_control_hit_without_start_to_start_condition_fix(self):
        tmp_path = REPO_ROOT / "stage1a14_contract_tmp_control_hit_no_start"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a14_summary(tmp_path)

            stats, report, rows = self._run_stage1a14_cli(tmp_path, summary_path)

            decision = stats["start_pulse_injection_diagnosis"]
            self.assertEqual(decision["diagnostic_csr_address_range"], "0x24C-0x254")
            self.assertTrue(decision["explicit_csr_start_pulsed_by_probe"])
            self.assertEqual(decision["explicit_start_write_addr"], "0x40001000")
            self.assertTrue(decision["axil_write_hit_control_seen"])
            self.assertFalse(decision["axil_write_hit_start_seen"])
            self.assertEqual(decision["start_pulse_injection_classification"], "probe_write_observed_but_no_csr_start")
            self.assertEqual(decision["recommended_next_stage"], "StartWriteValueOrWSTRBDiagnosis")
            self.assertTrue(rows)
            self.assertIn("axil_write_hit_control_count", rows[0])
            self.assertIn("explicit_start_readback_before", rows[0])
            self.assertIn("recommended_next_stage: StartWriteValueOrWSTRBDiagnosis", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a14_start_pulse_injection_routes_csr_start_without_final_start(self):
        tmp_path = REPO_ROOT / "stage1a14_contract_tmp_final_start"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a14_summary(
                tmp_path,
                overrides={
                    "axil_write_hit_control_count": 1,
                    "axil_write_hit_start_count": 1,
                    "csr_start_pulse_count": 1,
                    "final_start_pulse_count": 0,
                },
            )

            stats, report, rows = self._run_stage1a14_cli(tmp_path, summary_path)

            decision = stats["start_pulse_injection_diagnosis"]
            self.assertTrue(decision["csr_start_seen"])
            self.assertFalse(decision["final_start_seen"])
            self.assertEqual(decision["start_pulse_injection_classification"], "csr_start_seen_but_no_final_start")
            self.assertEqual(decision["recommended_next_stage"], "FinalStartSelectionLogicDiagnosis")
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a15_no_start_baseline_does_not_trigger_start_failure(self):
        tmp_path = REPO_ROOT / "stage1a15_contract_tmp_baseline"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a15_summary(tmp_path)

            stats, report, rows = self._run_stage1a15_cli(tmp_path, summary_path)

            decision = stats["explicit_start_bridge_handoff_diagnosis"]
            self.assertTrue(decision["baseline_bridge_tx_nonempty_seen"])
            self.assertFalse(decision["baseline_dma_start_seen"])
            self.assertNotEqual(decision["recommended_next_stage"], "StartPulseInjectionOrProbeControlFix")
            baseline_rows = [
                row for row in rows
                if row["explicit_start_bridge_handoff_config"] == "Current_Bypass_NoExplicitStart"
            ]
            self.assertTrue(baseline_rows)
            self.assertEqual({row["explicit_start_timing"] for row in baseline_rows}, {"none"})
            self.assertIn("Current_Bypass_NoExplicitStart is a baseline and is not a start-failure test.", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a15_valid_start_without_bridge_data_routes_to_bridge_data_production(self):
        tmp_path = REPO_ROOT / "stage1a15_contract_tmp_bridge_data"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a15_summary(tmp_path)

            stats, report, rows = self._run_stage1a15_cli(tmp_path, summary_path)

            decision = stats["explicit_start_bridge_handoff_diagnosis"]
            self.assertTrue(decision["explicit_start_verified_by_hardware"])
            self.assertFalse(decision["row_level_start_and_bridge_nonempty_seen"])
            self.assertEqual(decision["handoff_classification"], "explicit_start_valid_but_bridge_not_nonempty")
            self.assertEqual(decision["recommended_next_stage"], "BridgeDataProductionDiagnosis")
            self.assertIn("row-level approximation", report)
            self.assertIn("explicit_start_verified_by_hardware: true", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a15_start_and_bridge_nonempty_without_rd_en_routes_to_rd_enable_gating(self):
        tmp_path = REPO_ROOT / "stage1a15_contract_tmp_rd_enable"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a15_summary(
                tmp_path,
                config_overrides={
                    "Bypass_ExplicitStart_AfterWorkload": {
                        "bridge_tx_nonempty_cycles": 4096,
                        "bridge_tx_rd_en_cycles": 0,
                        "bridge_tx_accept_cycles": 0,
                    }
                },
            )

            stats, report, rows = self._run_stage1a15_cli(tmp_path, summary_path)

            decision = stats["explicit_start_bridge_handoff_diagnosis"]
            self.assertTrue(decision["row_level_start_and_bridge_nonempty_seen"])
            self.assertTrue(decision["dma_or_source_reader_busy_seen"])
            self.assertEqual(decision["handoff_classification"], "dma_active_bridge_nonempty_but_no_rd_en")
            self.assertEqual(decision["recommended_next_stage"], "DMARdEnableGatingDiagnosis")
            after_rows = [
                row for row in rows
                if row["explicit_start_timing"] == "after_workload_50ms"
            ]
            self.assertIn("dma_rd_enable_gating_observed", {row["stage_status"] for row in after_rows})
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a15_rd_en_without_accept_routes_to_bridge_accept_path(self):
        tmp_path = REPO_ROOT / "stage1a15_contract_tmp_bridge_accept"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a15_summary(
                tmp_path,
                config_overrides={
                    "Bypass_ExplicitStart_AfterWorkload": {
                        "bridge_tx_nonempty_cycles": 4096,
                        "bridge_tx_rd_en_cycles": 7,
                        "bridge_tx_accept_cycles": 0,
                    }
                },
            )

            stats, report, rows = self._run_stage1a15_cli(tmp_path, summary_path)

            decision = stats["explicit_start_bridge_handoff_diagnosis"]
            self.assertTrue(decision["bridge_tx_rd_en_seen"])
            self.assertFalse(decision["bridge_tx_accept_seen"])
            self.assertEqual(decision["handoff_classification"], "rd_en_seen_but_no_bridge_accept")
            self.assertEqual(decision["recommended_next_stage"], "BridgeAcceptPathDiagnosis")
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a16_uses_two_of_three_baseline_gate_and_config_level_fields(self):
        tmp_path = REPO_ROOT / "stage1a16_contract_tmp_baseline"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a16_summary(
                tmp_path,
                config_overrides={
                    "A12_NoStart_Replay": {
                        "bridge_tx_nonempty_cycles": 0,
                    }
                },
            )
            # Restore two repeats to nonempty by editing the generated JSON so the threshold is exactly 2/3.
            data = json.loads(summary_path.read_text(encoding="utf-8"))
            seen = 0
            for case in data["cases"]:
                if case["bridge_data_production_config"] == "A12_NoStart_Replay":
                    seen += 1
                    case["bridge_tx_nonempty_cycles"] = 1024 if seen <= 2 else 0
            summary_path.write_text(json.dumps(data), encoding="utf-8")

            stats, report, rows = self._run_stage1a16_cli(tmp_path, summary_path)

            decision = stats["bridge_data_production_diagnosis"]
            self.assertTrue(decision["baseline_bridge_reproduced"])
            self.assertEqual(decision["baseline_bridge_reproduced_repeats"], 2)
            self.assertEqual(decision["baseline_bridge_reproduced_threshold"], "2/3")
            self.assertTrue(decision["a12_no_start_replay_bridge_nonempty_seen"])
            self.assertFalse(decision["a15_after_start_bridge_nonempty_seen"])
            self.assertTrue(decision["bridge_tx_nonempty_seen_any"])
            self.assertEqual(decision["bridge_data_production_classification"], "explicit_start_config_lost_bridge_data")
            self.assertEqual(decision["recommended_next_stage"], "BridgeDataProductionUnderExplicitStartDiagnosis")
            self.assertIn("bridge_tx_nonempty_seen_any is stage overview only", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a16_stage_level_any_does_not_trigger_rd_enable_gating(self):
        tmp_path = REPO_ROOT / "stage1a16_contract_tmp_no_any_rd_gating"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a16_summary(tmp_path)

            stats, report, rows = self._run_stage1a16_cli(tmp_path, summary_path)

            decision = stats["bridge_data_production_diagnosis"]
            self.assertTrue(decision["a12_no_start_replay_bridge_nonempty_seen"])
            self.assertFalse(decision["a15_after_start_bridge_nonempty_seen"])
            self.assertTrue(decision["bridge_tx_nonempty_seen_any"])
            self.assertFalse(decision["explicit_start_and_bridge_nonempty_same_row_seen"])
            self.assertEqual(decision["explicit_start_and_bridge_nonempty_rows_count"], 0)
            self.assertNotEqual(decision["recommended_next_stage"], "DMARdEnableGatingDiagnosis")
            after_rows = [
                row for row in rows
                if row["bridge_data_production_config"] == "A15_AfterWorkloadStart_Replay"
            ]
            self.assertTrue(after_rows)
            self.assertEqual({row["a15_after_start_bridge_nonempty_seen"] for row in after_rows}, {"False"})
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a16_explicit_start_nonempty_same_config_routes_to_rd_enable_gating(self):
        tmp_path = REPO_ROOT / "stage1a16_contract_tmp_rd_enable"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a16_summary(
                tmp_path,
                config_overrides={
                    "A15_AfterWorkloadStart_Replay": {
                        "bridge_tx_nonempty_cycles": 4096,
                        "bridge_tx_wr_en_cycles": 64,
                        "bridge_tx_fifo_level": 1,
                        "bridge_tx_fifo_level_max": 4,
                        "bridge_tx_rd_en_cycles": 0,
                    }
                },
            )

            stats, report, rows = self._run_stage1a16_cli(tmp_path, summary_path)

            decision = stats["bridge_data_production_diagnosis"]
            self.assertTrue(decision["a15_after_start_explicit_start_verified"])
            self.assertTrue(decision["a15_after_start_bridge_nonempty_seen"])
            self.assertTrue(decision["a15_after_start_dma_start_seen"])
            self.assertTrue(decision["explicit_start_and_bridge_nonempty_same_row_seen"])
            self.assertEqual(decision["bridge_data_production_classification"], "bridge_nonempty_with_dma_start_but_no_rd_en")
            self.assertEqual(decision["recommended_next_stage"], "DMARdEnableGatingDiagnosis")
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a16_control_side_effect_routes_to_csr_side_effect_diagnosis(self):
        tmp_path = REPO_ROOT / "stage1a16_contract_tmp_control_side_effect"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a16_summary(
                tmp_path,
                config_overrides={
                    "A15_AfterWorkloadStart_Replay": {
                        "dma_ctrl_read_before": "0x00000800",
                        "dma_ctrl_read_after": "0x00000804",
                        "dma_ctrl_changed_bits": "0x00000004",
                    }
                },
            )

            stats, report, rows = self._run_stage1a16_cli(tmp_path, summary_path)

            decision = stats["bridge_data_production_diagnosis"]
            self.assertEqual(decision["start_bit_mask"], "0x00000001")
            self.assertTrue(decision["explicit_start_changed_control_state"])
            self.assertEqual(decision["bridge_data_production_classification"], "explicit_start_config_lost_bridge_data")
            self.assertEqual(decision["recommended_next_stage"], "CSRControlSideEffectDiagnosis")
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a17_pbm_no_valid_routes_to_upstream_ingress(self):
        tmp_path = REPO_ROOT / "stage1a17_contract_tmp_no_valid"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a17_summary(tmp_path)

            stats, report, rows = self._run_stage1a17_cli(tmp_path, summary_path)

            decision = stats["pbm_commit_reproduction_diagnosis"]
            self.assertEqual(stats["raw_sample_count"], 6)
            self.assertEqual(stats["included_sample_count"], 6)
            self.assertEqual(decision["commit_reference_replay_rows"], 3)
            self.assertEqual(decision["extra_snapshot_replay_rows"], 3)
            self.assertEqual(decision["pbm_commit_reproduction_classification"], "pbm_no_valid_seen")
            self.assertEqual(decision["recommended_next_stage"], "UpstreamIngressToPBMVisibilityDiagnosis")
            self.assertFalse(decision["commit_reference_replay_commit_seen"])
            self.assertFalse(decision["extra_snapshot_replay_commit_seen"])
            self.assertIn("Extra snapshots are sub-snapshots within the same probe window", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a17_commit_reproduced_takes_priority_over_ready_gating(self):
        tmp_path = REPO_ROOT / "stage1a17_contract_tmp_commit_priority"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a17_summary(
                tmp_path,
                config_overrides={
                    "CommitReferenceReplay": {
                        "pbm_wr_valid_cycles": 512,
                        "pbm_valid_not_ready_cycles": 100,
                        "pbm_wr_accept_cycles": 512,
                        "pbm_wr_last_accepted_count": 64,
                        "pbm_commit_entry_count": 64,
                        "pbm_ptr_head_reserve": 512,
                        "pbm_ptr_head_commit": 512,
                        "pbm_buffer_usage": 512,
                    },
                    "CommitReplay_WithExtraPBMSnapshots": {
                        "pbm_wr_valid_cycles": 512,
                        "pbm_valid_not_ready_cycles": 100,
                        "pbm_wr_accept_cycles": 512,
                        "pbm_wr_last_accepted_count": 64,
                        "pbm_commit_entry_count": 64,
                        "pbm_ptr_head_reserve": 512,
                        "pbm_ptr_head_commit": 512,
                        "pbm_buffer_usage": 512,
                    },
                },
            )

            stats, report, rows = self._run_stage1a17_cli(tmp_path, summary_path)

            decision = stats["pbm_commit_reproduction_diagnosis"]
            self.assertEqual(decision["pbm_commit_reproduction_classification"], "pbm_commit_reproduced")
            self.assertEqual(decision["recommended_next_stage"], "BridgeDataProductionDiagnosis")
            self.assertTrue(decision["commit_reference_replay_commit_seen"])
            self.assertTrue(decision["extra_snapshot_replay_commit_seen"])
            self.assertGreater(decision["pbm_valid_not_ready_cycles"], 0)
            self.assertIn("pbm_wr_last_clean_accepted_count", decision)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a17_clean_last_without_commit_routes_to_commit_transition(self):
        tmp_path = REPO_ROOT / "stage1a17_contract_tmp_clean_last"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a17_summary(
                tmp_path,
                config_overrides={
                    "CommitReferenceReplay": {
                        "pbm_wr_valid_cycles": 64,
                        "pbm_wr_accept_cycles": 64,
                        "pbm_wr_last_accepted_count": 8,
                        "pbm_wr_last_error_accepted_count": 0,
                        "pbm_commit_entry_count": 0,
                        "pbm_rollback_entry_count": 0,
                    }
                },
            )

            stats, report, rows = self._run_stage1a17_cli(tmp_path, summary_path)

            decision = stats["pbm_commit_reproduction_diagnosis"]
            self.assertEqual(decision["pbm_commit_reproduction_classification"], "pbm_clean_last_without_commit")
            self.assertEqual(decision["recommended_next_stage"], "PBMCommitTransitionDiagnosis")
            self.assertEqual(decision["pbm_wr_last_clean_accepted_count"], 24)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a17_error_last_without_rollback_routes_to_rollback_coupling(self):
        tmp_path = REPO_ROOT / "stage1a17_contract_tmp_error_last"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a17_summary(
                tmp_path,
                config_overrides={
                    "CommitReferenceReplay": {
                        "pbm_wr_valid_cycles": 64,
                        "pbm_wr_accept_cycles": 64,
                        "pbm_wr_last_accepted_count": 8,
                        "pbm_wr_last_error_accepted_count": 8,
                        "pbm_commit_entry_count": 0,
                        "pbm_rollback_entry_count": 0,
                    }
                },
            )

            stats, report, rows = self._run_stage1a17_cli(tmp_path, summary_path)

            decision = stats["pbm_commit_reproduction_diagnosis"]
            self.assertEqual(decision["pbm_commit_reproduction_classification"], "pbm_last_error_without_rollback")
            self.assertEqual(decision["recommended_next_stage"], "DropRollbackCouplingDiagnosis")
            self.assertEqual(decision["pbm_wr_last_error_accepted_count"], 24)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a17_invalid_clean_last_derivation_is_inconclusive(self):
        tmp_path = REPO_ROOT / "stage1a17_contract_tmp_invalid_clean_last"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a17_summary(
                tmp_path,
                config_overrides={
                    "CommitReferenceReplay": {
                        "pbm_wr_valid_cycles": 64,
                        "pbm_wr_accept_cycles": 64,
                        "pbm_wr_last_accepted_count": 1,
                        "pbm_wr_last_error_accepted_count": 2,
                    }
                },
            )

            stats, report, rows = self._run_stage1a17_cli(tmp_path, summary_path)

            decision = stats["pbm_commit_reproduction_diagnosis"]
            self.assertEqual(decision["pbm_commit_reproduction_classification"], "inconclusive")
            self.assertEqual(decision["recommended_next_stage"], "rerun_stage1a17_due_to_inconclusive")
            self.assertGreater(decision["invalid_clean_last_rows"], 0)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a18_no_stage1_fire_routes_to_injection_source(self):
        tmp_path = REPO_ROOT / "stage1a18_contract_tmp_no_stage1_fire"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a18_summary(tmp_path)
            stats, report, rows = self._run_stage1a18_cli(tmp_path, summary_path)
            decision = stats["upstream_ingress_to_pbm_visibility_diagnosis"]
            self.assertEqual(stats["raw_sample_count"], 6)
            self.assertEqual(stats["included_sample_count"], 6)
            self.assertEqual(decision["upstream_ingress_to_pbm_classification"], "no_stage1_fire_seen")
            self.assertEqual(decision["recommended_next_stage"], "InjectionSourceEmissionDiagnosis")
            self.assertFalse(decision["stage1_fire_seen"])
            self.assertIn("must not interpret bridge, DMA, backend, or Stage 2 behavior", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a18_classifier_input_without_dma_valid_routes_to_classifier_payload(self):
        tmp_path = REPO_ROOT / "stage1a18_contract_tmp_classifier_payload"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a18_summary(
                tmp_path,
                config_overrides={
                    "IngressReferenceReplay": {
                        "post_netdbg_status": self._stage1a18_netdbg_status(
                            stage1_inject_tvalid=1,
                            stage1_inject_tready=1,
                            aclf_tvalid=1,
                            aclf_tready=1,
                            classifier_s_tvalid=1,
                            classifier_s_tready=1,
                            netdbg_stage1_fire_seen=1,
                            netdbg_acl_fire_seen=1,
                            netdbg_classifier_in_fire_seen=1,
                            route_state=3,
                        )
                    }
                },
            )
            stats, report, rows = self._run_stage1a18_cli(tmp_path, summary_path)
            decision = stats["upstream_ingress_to_pbm_visibility_diagnosis"]
            self.assertEqual(decision["upstream_ingress_to_pbm_classification"], "classifier_input_fire_without_classifier_dma_valid")
            self.assertEqual(decision["recommended_next_stage"], "ClassifierPayloadAdmissionDiagnosis")
            self.assertTrue(decision["classifier_in_fire_seen"])
            self.assertFalse(decision["classifier_dma_valid_seen"])
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a18_classifier_dma_valid_without_crypto_rx_routes_to_subsystem_visibility(self):
        tmp_path = REPO_ROOT / "stage1a18_contract_tmp_classifier_dma_only"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a18_summary(
                tmp_path,
                config_overrides={
                    "IngressReferenceReplay": {
                        "post_netdbg_status": self._stage1a18_netdbg_status(
                            stage1_inject_tvalid=1,
                            stage1_inject_tready=1,
                            aclf_tvalid=1,
                            aclf_tready=1,
                            classifier_s_tvalid=1,
                            classifier_s_tready=1,
                            classifier_dma_tvalid=1,
                            classifier_dma_tready=1,
                            netdbg_stage1_fire_seen=1,
                            netdbg_acl_fire_seen=1,
                            netdbg_classifier_in_fire_seen=1,
                            netdbg_classifier_dma_valid_seen=1,
                            netdbg_classifier_dma_fire_seen=1,
                            netdbg_classifier_dma_ready_seen=1,
                            route_state=3,
                        )
                    }
                },
            )
            stats, report, rows = self._run_stage1a18_cli(tmp_path, summary_path)
            decision = stats["upstream_ingress_to_pbm_visibility_diagnosis"]
            self.assertEqual(decision["upstream_ingress_to_pbm_classification"], "classifier_dma_valid_without_crypto_rx")
            self.assertEqual(decision["recommended_next_stage"], "ClassifierToSubsystemVisibilityDiagnosis")
            self.assertTrue(decision["classifier_dma_valid_seen"])
            self.assertEqual(decision["crypto_rx_valid_cycles"], 0)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a18_classifier_dma_ready_only_does_not_skip_to_subsystem_visibility(self):
        tmp_path = REPO_ROOT / "stage1a18_contract_tmp_classifier_dma_ready_only"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a18_summary(
                tmp_path,
                config_overrides={
                    "IngressReferenceReplay": {
                        "post_netdbg_status": self._stage1a18_netdbg_status(
                            classifier_dma_tready=1,
                            netdbg_classifier_dma_ready_seen=1,
                            route_state=0,
                        )
                    }
                },
            )
            stats, report, rows = self._run_stage1a18_cli(tmp_path, summary_path)
            decision = stats["upstream_ingress_to_pbm_visibility_diagnosis"]
            self.assertEqual(
                decision["upstream_ingress_to_pbm_classification"],
                "no_stage1_fire_seen",
            )
            self.assertEqual(
                decision["recommended_next_stage"],
                "InjectionSourceEmissionDiagnosis",
            )
            self.assertFalse(decision["stage1_fire_seen"])
            self.assertFalse(decision["classifier_dma_valid_seen"])
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a18_crypto_rx_without_pbm_valid_routes_to_pbm_input_binding(self):
        tmp_path = REPO_ROOT / "stage1a18_contract_tmp_crypto_rx_only"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a18_summary(
                tmp_path,
                config_overrides={
                    "IngressReferenceReplay": {
                        "post_netdbg_status": self._stage1a18_netdbg_status(
                            stage1_inject_tvalid=1,
                            stage1_inject_tready=1,
                            aclf_tvalid=1,
                            aclf_tready=1,
                            classifier_s_tvalid=1,
                            classifier_s_tready=1,
                            classifier_dma_tvalid=1,
                            classifier_dma_tready=1,
                            netdbg_stage1_fire_seen=1,
                            netdbg_acl_fire_seen=1,
                            netdbg_classifier_in_fire_seen=1,
                            netdbg_classifier_dma_valid_seen=1,
                            netdbg_classifier_dma_fire_seen=1,
                            netdbg_classifier_dma_ready_seen=1,
                            route_state=3,
                        ),
                        "crypto_rx_valid_cycles": 128,
                        "crypto_rx_accept_cycles": 128,
                    }
                },
            )
            stats, report, rows = self._run_stage1a18_cli(tmp_path, summary_path)
            decision = stats["upstream_ingress_to_pbm_visibility_diagnosis"]
            self.assertEqual(decision["upstream_ingress_to_pbm_classification"], "crypto_rx_without_pbm_valid")
            self.assertEqual(decision["recommended_next_stage"], "PBMInputBindingDiagnosis")
            self.assertEqual(decision["crypto_rx_valid_cycles"], 384)
            self.assertEqual(decision["pbm_wr_valid_cycles"], 0)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a18_pbm_valid_reestablished_routes_back_to_commit_reproduction(self):
        tmp_path = REPO_ROOT / "stage1a18_contract_tmp_pbm_valid"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a18_summary(
                tmp_path,
                config_overrides={
                    "IngressReferenceReplay": {
                        "post_netdbg_status": self._stage1a18_netdbg_status(
                            stage1_inject_tvalid=1,
                            stage1_inject_tready=1,
                            aclf_tvalid=1,
                            aclf_tready=1,
                            classifier_s_tvalid=1,
                            classifier_s_tready=1,
                            classifier_dma_tvalid=1,
                            classifier_dma_tready=1,
                            netdbg_stage1_fire_seen=1,
                            netdbg_acl_fire_seen=1,
                            netdbg_classifier_in_fire_seen=1,
                            netdbg_classifier_dma_valid_seen=1,
                            netdbg_classifier_dma_fire_seen=1,
                            netdbg_classifier_dma_ready_seen=1,
                            route_state=3,
                        ),
                        "crypto_rx_valid_cycles": 128,
                        "crypto_rx_accept_cycles": 128,
                        "pbm_wr_valid_cycles": 128,
                        "pbm_wr_accept_cycles": 128,
                    }
                },
            )
            stats, report, rows = self._run_stage1a18_cli(tmp_path, summary_path)
            decision = stats["upstream_ingress_to_pbm_visibility_diagnosis"]
            self.assertEqual(decision["upstream_ingress_to_pbm_classification"], "pbm_valid_reestablished")
            self.assertEqual(decision["recommended_next_stage"], "PBMCommitReproductionDiagnosis")
            self.assertGreater(decision["pbm_wr_valid_cycles"], 0)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a19_no_injection_source_activity_routes_to_source_arming(self):
        tmp_path = REPO_ROOT / "stage1a19_contract_tmp_no_injection_activity"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a19_summary(tmp_path)
            stats, report, rows = self._run_stage1a19_cli(tmp_path, summary_path)
            decision = stats["injection_source_emission_diagnosis"]
            self.assertEqual(stats["raw_sample_count"], 6)
            self.assertEqual(stats["included_sample_count"], 6)
            self.assertEqual(decision["injection_source_emission_classification"], "no_injection_source_activity_seen")
            self.assertEqual(decision["recommended_next_stage"], "InjectionSourceArmingDiagnosis")
            self.assertFalse(decision["stage1_fire_seen"])
            self.assertFalse(decision["inj_fifo_nonempty_seen"])
            self.assertIn("must not interpret ACL, classifier, PBM, bridge, DMA, backend, or Stage 2 behavior", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a19_inj_fifo_nonempty_without_stage1_valid_routes_to_binding(self):
        tmp_path = REPO_ROOT / "stage1a19_contract_tmp_fifo_nonempty"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a19_summary(
                tmp_path,
                config_overrides={
                    "EmissionReferenceReplay": {
                        "inj_status_active": "0x00010008",
                    }
                },
            )
            stats, report, rows = self._run_stage1a19_cli(tmp_path, summary_path)
            decision = stats["injection_source_emission_diagnosis"]
            self.assertEqual(
                decision["injection_source_emission_classification"],
                "inj_fifo_nonempty_without_stage1_valid",
            )
            self.assertEqual(
                decision["recommended_next_stage"],
                "InjectionToStage1BindingDiagnosis",
            )
            self.assertTrue(decision["inj_fifo_nonempty_seen"])
            self.assertFalse(decision["stage1_inject_tvalid_seen"])
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a19_stage1_valid_not_ready_without_fire_routes_to_ready_gating(self):
        tmp_path = REPO_ROOT / "stage1a19_contract_tmp_stage1_valid_not_ready"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a19_summary(
                tmp_path,
                config_overrides={
                    "EmissionReferenceReplay": {
                        "post_netdbg_status": self._stage1a18_netdbg_status(
                            stage1_inject_tvalid=1,
                            stage1_inject_tready=0,
                            route_state=0,
                        )
                    }
                },
            )
            stats, report, rows = self._run_stage1a19_cli(tmp_path, summary_path)
            decision = stats["injection_source_emission_diagnosis"]
            self.assertEqual(
                decision["injection_source_emission_classification"],
                "stage1_valid_not_ready_without_fire",
            )
            self.assertEqual(
                decision["recommended_next_stage"],
                "Stage1InjectReadyGatingDiagnosis",
            )
            self.assertTrue(decision["stage1_inject_tvalid_seen"])
            self.assertTrue(decision["stage1_valid_not_ready_seen"])
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a19_stage1_fire_reestablished_routes_to_acl_filter_ingress(self):
        tmp_path = REPO_ROOT / "stage1a19_contract_tmp_stage1_fire"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a19_summary(
                tmp_path,
                config_overrides={
                    "EmissionReferenceReplay": {
                        "post_netdbg_status": self._stage1a18_netdbg_status(
                            stage1_inject_tvalid=1,
                            stage1_inject_tready=1,
                            netdbg_stage1_fire_seen=1,
                            route_state=1,
                        )
                    }
                },
            )
            stats, report, rows = self._run_stage1a19_cli(tmp_path, summary_path)
            decision = stats["injection_source_emission_diagnosis"]
            self.assertEqual(
                decision["injection_source_emission_classification"],
                "stage1_fire_reestablished",
            )
            self.assertEqual(
                decision["recommended_next_stage"],
                "ACLFilterIngressDiagnosis",
            )
            self.assertTrue(decision["stage1_fire_seen"])
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a20_no_injection_csr_hits_routes_to_address_or_decode_diagnosis(self):
        tmp_path = REPO_ROOT / "stage1a20_contract_tmp_no_csr_hits"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a20_summary(
                tmp_path,
                config_overrides={
                    "InjectionArmOnly": {
                        "inj_ctrl_write_hit_count": 0,
                        "inj_clear_write_hit_count": 0,
                        "inj_frame_word_write_hit_count": 0,
                        "inj_expected_words_write_hit_count": 0,
                        "inj_ctrl_read_after": "0x00000000",
                        "inj_frame_length_readback": 0,
                        "inj_config_valid": False,
                    },
                    "InjectionArmWithReadback": {
                        "inj_ctrl_write_hit_count": 0,
                        "inj_clear_write_hit_count": 0,
                        "inj_frame_word_write_hit_count": 0,
                        "inj_expected_words_write_hit_count": 0,
                        "inj_ctrl_read_after": "0x00000000",
                        "inj_frame_length_readback": 0,
                        "inj_config_valid": False,
                    },
                },
            )
            stats, report, rows = self._run_stage1a20_cli(tmp_path, summary_path)
            decision = stats["injection_source_arming_diagnosis"]
            self.assertEqual(stats["raw_sample_count"], 6)
            self.assertEqual(stats["included_sample_count"], 6)
            self.assertEqual(
                decision["injection_source_arming_classification"],
                "probe_write_not_observed_by_injection_csr",
            )
            self.assertEqual(
                decision["recommended_next_stage"],
                "InjectionCSRAddressOrDecodeDiagnosis",
            )
            self.assertFalse(decision["inj_ctrl_write_hit_seen"])
            self.assertFalse(decision["inj_frame_word_write_hit_seen"])
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a20_valid_config_without_fifo_load_routes_to_fifo_load_diagnosis(self):
        tmp_path = REPO_ROOT / "stage1a20_contract_tmp_fifo_load"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a20_summary(
                tmp_path,
                config_overrides={
                    "InjectionArmWithReadback": {
                        "inj_fifo_write_count": 0,
                        "inj_fifo_level_max": 0,
                        "inj_source_active_cycles": 0,
                        "stage1_inject_tvalid_cycles": 0,
                    }
                },
            )
            stats, report, rows = self._run_stage1a20_cli(tmp_path, summary_path)
            decision = stats["injection_source_arming_diagnosis"]
            self.assertEqual(
                decision["injection_source_arming_classification"],
                "config_valid_but_fifo_not_loaded",
            )
            self.assertEqual(
                decision["recommended_next_stage"],
                "InjectionFIFOLoadDiagnosis",
            )
            self.assertTrue(decision["inj_config_valid_seen"])
            self.assertEqual(decision["inj_fifo_write_count"], 0)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a20_fifo_loaded_without_source_active_routes_to_fsm_arming(self):
        tmp_path = REPO_ROOT / "stage1a20_contract_tmp_fsm_arming"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a20_summary(
                tmp_path,
                config_overrides={
                    "InjectionArmWithReadback": {
                        "inj_fifo_write_count": 64 * 19,
                        "inj_fifo_level_max": 19,
                        "inj_source_state_raw": 1,
                        "inj_source_active_cycles": 0,
                        "stage1_inject_tvalid_cycles": 0,
                    }
                },
            )
            stats, report, rows = self._run_stage1a20_cli(tmp_path, summary_path)
            decision = stats["injection_source_arming_diagnosis"]
            self.assertEqual(
                decision["injection_source_arming_classification"],
                "fifo_loaded_but_source_not_active",
            )
            self.assertEqual(
                decision["recommended_next_stage"],
                "InjectionSourceFSMArmingDiagnosis",
            )
            self.assertGreater(decision["inj_fifo_level_max"], 0)
            self.assertEqual(decision["inj_source_active_cycles"], 0)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a20_fire_seen_routes_back_to_upstream_ingress_visibility(self):
        tmp_path = REPO_ROOT / "stage1a20_contract_tmp_fire_seen"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a20_summary(
                tmp_path,
                config_overrides={
                    "InjectionArmWithReadback": {
                        "inj_fifo_write_count": 64 * 19,
                        "inj_fifo_level_max": 19,
                        "inj_source_state_raw": 3,
                        "inj_source_active_cycles": 256,
                        "inj_source_emitting_cycles": 256,
                        "stage1_inject_tvalid_cycles": 256,
                        "stage1_inject_tready_cycles": 256,
                        "stage1_inject_fire_cycles": 256,
                        "stage1_inject_last_seen_count": 64,
                        "post_netdbg_status": self._stage1a18_netdbg_status(
                            stage1_inject_tvalid=1,
                            stage1_inject_tready=1,
                            netdbg_stage1_fire_seen=1,
                            route_state=0,
                        ),
                    }
                },
            )
            stats, report, rows = self._run_stage1a20_cli(tmp_path, summary_path)
            decision = stats["injection_source_arming_diagnosis"]
            self.assertEqual(
                decision["injection_source_arming_classification"],
                "stage1_fire_reestablished",
            )
            self.assertEqual(
                decision["recommended_next_stage"],
                "UpstreamIngressToPBMVisibilityDiagnosis",
            )
            self.assertGreater(decision["stage1_inject_fire_cycles"], 0)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a21_ready_low_due_to_full_pointer_gap_routes_to_pointer_reset_or_drain(self):
        tmp_path = REPO_ROOT / "stage1a21_contract_tmp_full_pointer_gap"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a21_summary(tmp_path)
            stats, report, rows = self._run_stage1a21_cli(tmp_path, summary_path)
            decision = stats["stage1a21_pbm_ready_gating_diagnosis"]
            self.assertEqual(stats["raw_sample_count"], 9)
            self.assertEqual(stats["included_sample_count"], 9)
            self.assertEqual(decision["idle_rows_seen"], 3)
            self.assertEqual(decision["bf64_rows_seen"], 3)
            self.assertEqual(decision["bf64_extra_rows_seen"], 3)
            self.assertTrue(decision["ready_low_due_to_full_inferred"])
            self.assertTrue(decision["idle_commit_tail_gap_seen"])
            self.assertTrue(decision["idle_pbm_read_side_nonempty_seen"])
            self.assertTrue(decision["preexisting_pointer_gap_seen"])
            self.assertEqual(
                decision["pbm_ready_gating_classification"],
                "ready_low_due_to_full_pointer_gap_inferred",
            )
            self.assertEqual(decision["recommended_next_stage"], "PBMPointerResetOrDrainDiagnosis")
            self.assertIn("preexisting before workload", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a21_state_blocked_ready_routes_to_state_gating(self):
        tmp_path = REPO_ROOT / "stage1a21_contract_tmp_state_gating"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a21_summary(
                tmp_path,
                config_overrides={
                    "IdleControl": {
                        "pbm_ptr_tail_pre": 0,
                        "pbm_ptr_tail": 0,
                        "pbm_buffer_usage_pre": 0,
                        "pbm_buffer_usage": 0,
                        "pbm_rd_nonempty_cycles": 0,
                        "pbm_committed_available_cycles": 0,
                    },
                    "BF64_SM500": {"pbm_state_raw": 2},
                    "BF64_SM500_ExtraSnapshots": {"pbm_state_raw": 2},
                },
            )
            stats, report, rows = self._run_stage1a21_cli(tmp_path, summary_path)
            decision = stats["stage1a21_pbm_ready_gating_diagnosis"]
            self.assertFalse(decision["ready_low_due_to_full_inferred"])
            self.assertTrue(decision["ready_low_due_to_state_inferred"])
            self.assertEqual(
                decision["pbm_ready_gating_classification"],
                "ready_low_due_to_state_inferred",
            )
            self.assertEqual(decision["recommended_next_stage"], "PBMStateGatingDiagnosis")
            self.assertIn("PBM ready is blocked by state", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a22_soft_reset_clears_gap_and_recovers_ready(self):
        tmp_path = REPO_ROOT / "stage1a22_contract_tmp_reset_recovers"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a22_summary(tmp_path)
            stats, report, rows = self._run_stage1a22_cli(tmp_path, summary_path)
            decision = stats["stage1a22_pbm_pointer_reset_or_drain_diagnosis"]
            self.assertEqual(stats["raw_sample_count"], 9)
            self.assertEqual(stats["included_sample_count"], 9)
            self.assertEqual(decision["idle_no_reset_rows_seen"], 3)
            self.assertEqual(decision["idle_after_soft_reset_rows_seen"], 3)
            self.assertEqual(decision["bf64_after_soft_reset_rows_seen"], 3)
            self.assertTrue(decision["idle_no_reset_pointer_gap_seen"])
            self.assertTrue(decision["idle_after_soft_reset_gap_cleared"])
            self.assertTrue(decision["bf64_after_soft_reset_ready_recovered"])
            self.assertEqual(
                decision["pbm_pointer_reset_or_drain_classification"],
                "soft_reset_clears_gap_and_ready_recovers",
            )
            self.assertEqual(decision["recommended_next_stage"], "PBMResetOrRestorePathDiagnosis")
            self.assertIn("soft reset cleared the preexisting pointer gap", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a22_pointer_gap_persists_after_soft_reset_routes_to_invariant(self):
        tmp_path = REPO_ROOT / "stage1a22_contract_tmp_persistent_gap"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a22_summary(
                tmp_path,
                config_overrides={
                    "IdleControl_AfterSoftReset": {
                        "pbm_ptr_tail_pre": 208,
                        "pbm_ptr_tail": 208,
                        "pbm_buffer_usage_pre": 32560,
                        "pbm_buffer_usage": 32560,
                        "pbm_committed_available_cycles": 1024,
                        "pbm_rd_empty_cycles": 0,
                        "pbm_rd_nonempty_cycles": 1024,
                        "pbm_rd_en_cycles": 0,
                        "pbm_rd_accept_cycles": 0,
                    },
                    "BF64_SM500_AfterSoftReset": {
                        "pbm_wr_ready_high_cycles": 0,
                        "pbm_valid_not_ready_cycles": 4096,
                        "pbm_wr_accept_cycles": 0,
                    },
                },
            )
            stats, report, rows = self._run_stage1a22_cli(tmp_path, summary_path)
            decision = stats["stage1a22_pbm_pointer_reset_or_drain_diagnosis"]
            self.assertFalse(decision["idle_after_soft_reset_gap_cleared"])
            self.assertFalse(decision["idle_after_soft_reset_read_drain_seen"])
            self.assertEqual(
                decision["pbm_pointer_reset_or_drain_classification"],
                "pointer_gap_persists_after_soft_reset",
            )
            self.assertEqual(decision["recommended_next_stage"], "PBMCommitTailPointerInvariantDiagnosis")
            self.assertIn("pointer gap persisted after soft reset", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a23_persistent_pointer_gap_invariant_routes_to_reset_domain_scope(self):
        tmp_path = REPO_ROOT / "stage1a23_contract_tmp_invariant"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a23_summary(tmp_path)
            stats, report, rows = self._run_stage1a23_cli(tmp_path, summary_path)
            decision = stats["stage1a23_pbm_commit_tail_pointer_invariant_diagnosis"]
            self.assertEqual(stats["raw_sample_count"], 9)
            self.assertEqual(stats["included_sample_count"], 9)
            self.assertEqual(
                decision["pbm_commit_tail_pointer_invariant_classification"],
                "persistent_pointer_gap_state_counter_invariant",
            )
            self.assertEqual(decision["recommended_next_stage"], "PBMResetDomainScopeDiagnosis")
            self.assertTrue(decision["extra_pointer_constant"])
            self.assertTrue(decision["extra_state_constant"])
            self.assertTrue(decision["extra_read_nonempty_accumulates"])
            self.assertFalse(decision["extra_read_drain_seen"])
            self.assertEqual(len(rows), 9)
            self.assertIn("## Stage 1A.23 PBM Commit-Tail Pointer Invariant Diagnosis", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a23_state_or_pointer_change_routes_to_consistency_diagnosis(self):
        tmp_path = REPO_ROOT / "stage1a23_contract_tmp_inconsistent"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a23_summary(
                tmp_path,
                config_overrides={
                    "IdleControl_AfterSoftReset_ExtraSnapshots": {
                        "extra_snapshot_deltas": {
                            "pbm_state_raw_at_post_workload": 0,
                            "pbm_state_raw_at_050ms": 1,
                            "pbm_state_raw_at_250ms": 1,
                            "pbm_state_raw_at_500ms": 1,
                            "pbm_ptr_head_commit_at_post_workload": 0,
                            "pbm_ptr_head_commit_at_050ms": 4,
                            "pbm_ptr_head_commit_at_250ms": 4,
                            "pbm_ptr_head_commit_at_500ms": 4,
                            "pbm_ptr_tail_at_post_workload": 208,
                            "pbm_ptr_tail_at_050ms": 208,
                            "pbm_ptr_tail_at_250ms": 208,
                            "pbm_ptr_tail_at_500ms": 208,
                            "pbm_rd_nonempty_cycles_delta_at_post_workload": 100,
                            "pbm_rd_nonempty_cycles_delta_at_050ms": 100,
                            "pbm_rd_nonempty_cycles_delta_at_250ms": 100,
                            "pbm_rd_nonempty_cycles_delta_at_500ms": 100,
                            "pbm_committed_available_cycles_delta_at_post_workload": 100,
                            "pbm_committed_available_cycles_delta_at_050ms": 100,
                            "pbm_committed_available_cycles_delta_at_250ms": 100,
                            "pbm_committed_available_cycles_delta_at_500ms": 100,
                            "pbm_rd_en_cycles_delta_at_post_workload": 0,
                            "pbm_rd_en_cycles_delta_at_050ms": 0,
                            "pbm_rd_en_cycles_delta_at_250ms": 0,
                            "pbm_rd_en_cycles_delta_at_500ms": 0,
                            "pbm_rd_accept_cycles_delta_at_post_workload": 0,
                            "pbm_rd_accept_cycles_delta_at_050ms": 0,
                            "pbm_rd_accept_cycles_delta_at_250ms": 0,
                            "pbm_rd_accept_cycles_delta_at_500ms": 0,
                        },
                    }
                },
            )
            stats, report, rows = self._run_stage1a23_cli(tmp_path, summary_path)
            decision = stats["stage1a23_pbm_commit_tail_pointer_invariant_diagnosis"]
            self.assertEqual(
                decision["pbm_commit_tail_pointer_invariant_classification"],
                "state_or_pointer_changed_across_idle_snapshots",
            )
            self.assertEqual(decision["recommended_next_stage"], "PBMStatePointerConsistencyDiagnosis")
            self.assertFalse(decision["extra_pointer_constant"])
            self.assertFalse(decision["extra_state_constant"])
            self.assertEqual(len(rows), 9)
            self.assertIn("PBMStatePointerConsistencyDiagnosis", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a24_static_reset_scope_routes_to_remediation_plan(self):
        tmp_path = REPO_ROOT / "stage1a24_contract_tmp_reset_scope"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a23_summary(tmp_path)
            stats, report, rows = self._run_stage1a24_cli(tmp_path, summary_path)
            decision = stats["stage1a24_pbm_reset_domain_scope_diagnosis"]
            self.assertEqual(stats["raw_sample_count"], 9)
            self.assertEqual(stats["included_sample_count"], 9)
            self.assertEqual(
                decision["stage1a23_prior_classification"],
                "persistent_pointer_gap_state_counter_invariant",
            )
            self.assertTrue(decision["dma_soft_reset_generated_by_axil_csr"])
            self.assertTrue(decision["pbm_controller_has_soft_reset_port"])
            self.assertTrue(decision["dma_soft_reset_connected_to_pbm"])
            self.assertFalse(decision["pbm_state_pointer_reset_requires_global_rst_n"])
            self.assertTrue(decision["pbm_diag_clear_resets_diag_counters_only"])
            self.assertEqual(
                decision["pbm_reset_domain_scope_classification"],
                "pbm_soft_reset_connected_but_invariant_persists",
            )
            self.assertEqual(decision["recommended_next_stage"], "PBMSoftResetImplementationDiagnosis")
            self.assertEqual(len(rows), 9)
            self.assertIn("## Stage 1A.24 PBM Reset-Domain Scope Diagnosis", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_stage1a25_remediation_plan_prefers_pbm_soft_reset_diagnostic_build(self):
        tmp_path = REPO_ROOT / "stage1a25_contract_tmp_remediation"
        shutil.rmtree(tmp_path, ignore_errors=True)
        tmp_path.mkdir()
        try:
            summary_path = self._build_stage1a23_summary(tmp_path)
            stats, report, rows = self._run_stage1a25_cli(tmp_path, summary_path)
            decision = stats["stage1a25_pbm_reset_domain_remediation_plan"]
            self.assertEqual(stats["raw_sample_count"], 9)
            self.assertEqual(stats["included_sample_count"], 9)
            self.assertEqual(decision["stage1a24_prior_classification"], "pbm_soft_reset_connected_but_invariant_persists")
            self.assertEqual(
                decision["selected_remediation"],
                "inspect_existing_pbm_soft_reset_implementation",
            )
            self.assertFalse(decision["requires_rtl_change"])
            self.assertFalse(decision["diagnostic_build_required"])
            self.assertFalse(decision["paper_ready_recovery_gate_may_open"])
            self.assertIn("PBM soft reset is already connected", decision["implementation_notes"])
            self.assertIn("add_duplicate_pbm_soft_reset_without_coverage_audit", decision["rejected_remediations"])
            self.assertEqual(decision["recommended_next_stage"], "PBMSoftResetImplementationDiagnosis")
            self.assertEqual(len(rows), 9)
            self.assertIn("## Stage 1A.25 PBM Reset-Domain Remediation Plan", report)
        finally:
            shutil.rmtree(tmp_path, ignore_errors=True)

    def test_pbm_soft_reset_diagnostic_build_rtl_contract(self):
        pbm_text = (REPO_ROOT / "rtl" / "core" / "pbm" / "pbm_controller.sv").read_text(encoding="utf-8")
        bridge_text = (REPO_ROOT / "rtl" / "core" / "crypto" / "crypto_bridge_top.sv").read_text(encoding="utf-8")
        crypto_text = (REPO_ROOT / "rtl" / "top" / "crypto_dma_subsystem.sv").read_text(encoding="utf-8")
        dma_text = (REPO_ROOT / "rtl" / "top" / "dma_subsystem.sv").read_text(encoding="utf-8")
        net_text = (REPO_ROOT / "rtl" / "top" / "network_stage1_path.sv").read_text(encoding="utf-8")
        axil_text = AXIL_CSR.read_text(encoding="utf-8")

        self.assertIn("input  logic                    i_soft_reset", pbm_text)
        self.assertIn("if (!rst_n || i_soft_reset) begin", pbm_text)
        self.assertIn("pbm_wr_cmd_q <= 1'b0;", pbm_text)
        self.assertIn("ptr_head_commit <= '0;", pbm_text)
        self.assertIn("ptr_head_reserve <= '0;", pbm_text)
        self.assertIn("ptr_tail <= '0;", pbm_text)
        self.assertIn("pbm_rd_pending <= 1'b0;", pbm_text)
        diag_clear_start = pbm_text.index("end else if (i_diag_clear) begin")
        diag_clear_end = pbm_text.index("end else begin", diag_clear_start)
        diag_clear_block = pbm_text[diag_clear_start:diag_clear_end]
        for forbidden in ("ptr_head_commit <=", "ptr_head_reserve <=", "ptr_tail <=", "state <="):
            self.assertNotIn(forbidden, diag_clear_block)

        self.assertIn(".i_soft_reset(csr_soft_reset)", crypto_text)
        self.assertIn("input  logic         i_soft_reset", bridge_text)
        self.assertIn("logic        bridge_reset_n;", bridge_text)
        self.assertIn("assign bridge_reset_n = rst_n && !i_soft_reset;", bridge_text)
        self.assertIn("if (!rst_n || i_soft_reset) begin", bridge_text)
        self.assertIn(".reset_n(bridge_reset_n)", bridge_text)
        self.assertIn(".rst_n(bridge_reset_n)", bridge_text)
        bridge_diag_clear_start = bridge_text.index("end else if (i_diag_clear) begin")
        bridge_diag_clear_end = bridge_text.index("end else begin", bridge_diag_clear_start)
        bridge_diag_clear_block = bridge_text[bridge_diag_clear_start:bridge_diag_clear_end]
        for forbidden in ("input_state <=", "output_seq_expected <=", "input_seq_counter <=", "inst_busy"):
            self.assertNotIn(forbidden, bridge_diag_clear_block)
        self.assertIn(".i_soft_reset(csr_soft_reset)", crypto_text[crypto_text.index("u_crypto_bridge") :])
        self.assertIn(".i_soft_reset(1'b0)", dma_text)
        self.assertIn(".i_soft_reset(1'b0)", net_text)
        for token in (
            "parameter [31:0] DIAGNOSTIC_BUILD_ID",
            "parameter [31:0] DIAGNOSTIC_FEATURE_MASK = 32'h0000_01FF",
            "10'h270: s_axil_rdata <= DIAGNOSTIC_BUILD_ID;",
            "10'h274: s_axil_rdata <= DIAGNOSTIC_FEATURE_MASK;",
            "10'h278: s_axil_rdata <= DIAGNOSTIC_REGISTRY_HASH_LOW;",
            "10'h27C: s_axil_rdata <= DIAGNOSTIC_REGISTRY_HASH_HIGH;",
            "10'h280: s_axil_rdata <= i_counter_dma_rd_en_loopback_mode_raw;",
            "10'h284: s_axil_rdata <= i_counter_dma_rd_en_tx_axis_tready_cycles;",
            "10'h288: s_axil_rdata <= i_counter_dma_rd_en_crypto_to_dma_nonempty_cycles;",
            "10'h28C: s_axil_rdata <= i_counter_dma_rd_en_tx_ready_when_nonempty_cycles;",
            "10'h290: s_axil_rdata <= i_counter_dma_rd_en_dma_req_rd_cycles;",
            "10'h294: s_axil_rdata <= i_counter_dma_rd_en_loopback_branch_selected_cycles;",
            "10'h298: s_axil_rdata <= i_counter_dma_rd_en_normal_branch_selected_cycles;",
            "10'h29C: s_axil_rdata <= i_counter_dma_rd_en_loopback_branch_candidate_cycles;",
            "10'h2A0: s_axil_rdata <= i_counter_dma_rd_en_equation_true_but_rd_en_low_cycles;",
        ):
            self.assertIn(token, axil_text)


if __name__ == "__main__":
    unittest.main()
