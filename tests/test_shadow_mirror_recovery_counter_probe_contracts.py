import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "HCS_SOC" / "run_ax7020_udp_gateway_shadow_mirror_recovery_counter_probe.ps1"


class TestShadowMirrorRecoveryCounterProbeContracts(unittest.TestCase):
    def test_board_probe_defaults_to_xsct_2024_1_toolchain(self):
        text = SCRIPT.read_text(encoding="utf-8")

        self.assertIn('[string]$XsctPath = "D:\\Xilinx\\Vitis\\2024.1\\bin\\xsct.bat"', text)
        self.assertNotIn('[string]$XsctPath = "D:\\VIVADO\\Vitis\\2023.1\\bin\\xsct.bat"', text)

    def test_board_probe_script_uses_runtime_first_cases_and_probe_window(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "capture_uart_boot_log.ps1",
            "day21_uart_counter_extract.py",
            "day21_counter_snapshot_export.py",
            "doc\\reports\\engineering_evidence",
            "Case0_OriginalWrongPort",
            "Case1_HeaderAccepted",
            "Case2_RuntimeRingBypass",
            "mrd -force -value",
            "mwr -force",
            "0x40000090",
            "0x400000A8",
            "0x400000B8",
            "0x400000CC",
            "0x400000D0",
            "0x40001048",
            "0x40001050",
            "0x40001054",
            "0x40001058",
            "0x4000105C",
            "0x400010D4",
            "0x400010D8",
            "0x400010DC",
            "0x40001100",
            "0x40001150",
            "0x00000001",
            "0x00000002",
        ):
            self.assertIn(token, text)

        for forbidden in (
            "Case3_ForcedDmaRoute",
            "diag_ctrl",
            "netdbg_ext0",
            "netdbg_ext1",
        ):
            self.assertNotIn(forbidden, text)

    def test_board_probe_script_keeps_probe_frames_and_runtime_ring_restore_sequence(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "0xDEADBEEF",
            "0xAAAA1122",
            "0x33445566",
            "0x08000000",
            "0x00001234",
            "0x56780028",
            "0x12340000",
            "0x00000028",
            "0x11223344",
            "0x55667788",
            "rollback_event_count",
            "recovery_active_cycles",
            "high_water_count",
            "drop_pulse_count",
            "negative_result_summary.md",
        ):
            self.assertIn(token, text)

        self.assertIn("set ring_base_orig [mrd -force -value 0x40001050]", text)
        self.assertIn("set ring_size_orig [mrd -force -value 0x4000105C]", text)
        self.assertIn("set sw_tail_orig [mrd -force -value 0x40001058]", text)
        self.assertIn("mwr -force 0x40001058 0x00000000", text)
        self.assertIn("mwr -force 0x4000105C 0x00000000", text)
        self.assertIn("mwr -force 0x40001050 $ring_base_orig", text)
        self.assertIn("mwr -force 0x4000105C $ring_size_orig", text)
        self.assertIn("mwr -force 0x40001058 $sw_tail_orig", text)

    def test_board_probe_script_case2_guard_checks_idle_descriptor_source_before_bypass(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "proc clear_inject_path {prefix settle_ms}",
            'clear_inject_path "baseline" 10',
            "clear_inject_path $case0_prefix 10",
            "clear_inject_path $case1_prefix 10",
            "clear_inject_path $case2_prefix 10",
            "%s.guard_ring_size=0x%08X",
            "%s.guard_hw_head=0x%08X",
            "%s.guard_sw_tail=0x%08X",
            "%s.guard_debug_status=0x%08X",
            "($ring_size_val == 0) || (($ring_size_val > 0) && ($sw_tail_val == $hw_head_val) && ($debug_status_val == 0))",
            "netdbg_status",
        ):
            self.assertIn(token, text)

    def test_board_probe_script_repeat_count_creates_probe_window_instances(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "$caseBaseNames",
            "for ($repeatIndex = 1; $repeatIndex -le $effectiveRepeatCount; $repeatIndex++)",
            '"r{0:D2}.{1}"',
            "set repeat_count __REPEAT_COUNT__",
            'for {set repeat 1} {$repeat <= $repeat_count} {incr repeat}',
            'set repeat_prefix [format "r%02d" $repeat]',
            'set case0_prefix [format "%s.Case0_OriginalWrongPort" $repeat_prefix]',
            'set case1_prefix [format "%s.Case1_HeaderAccepted" $repeat_prefix]',
            'set case2_prefix [format "%s.Case2_RuntimeRingBypass" $repeat_prefix]',
            '$tclScript = $tclScript.Replace("__REPEAT_COUNT__", "$effectiveRepeatCount")',
            "base_name = $caseBaseName",
            "repeat = $caseRepeatIndex",
        ):
            self.assertIn(token, text)

    def test_board_probe_script_case2_temporarily_disables_fastpath_before_dma_probe(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "set ctrl_orig [mrd -force -value 0x40000000]",
            "set ctrl_no_fastpath [expr {$ctrl_orig & ~0x00000800}]",
            "mwr -force 0x40000000 $ctrl_no_fastpath",
            "mwr -force 0x40000000 $ctrl_orig",
            "%s.guard_ctrl=0x%08X",
            "%s.restore_ctrl=0x%08X",
        ):
            self.assertIn(token, text)

    def test_board_probe_soft_reset_targets_dma_csr_base(self):
        text = SCRIPT.read_text(encoding="utf-8")
        start = text.index("proc pulse_dma_soft_reset {prefix ctrl_value}")
        block = text[start : start + 900]

        self.assertIn("set dma_soft_reset_ctrl_addr 0x40001000", block)
        self.assertIn("set dma_ctrl_orig [mrd -force -value $dma_soft_reset_ctrl_addr]", block)
        self.assertIn("mwr -force $dma_soft_reset_ctrl_addr [expr {$dma_ctrl_orig | 0x00000400}]", block)
        self.assertIn("mwr -force $dma_soft_reset_ctrl_addr $dma_ctrl_orig", block)
        self.assertNotIn("mwr -force 0x40000000 [expr {$ctrl_value | 0x00000400}]", block)

    def test_board_probe_script_accepts_csr_readable_jtag_when_targets_text_is_empty(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "proc ensure_jtag_targets_visible {}",
            "mrd -force -value 0x40000090",
            "jtag_csr_readable",
            "no JTAG targets visible or CSR-readable to XSCT after retry",
        ):
            self.assertIn(token, text)

    def test_board_probe_script_declares_stage1a_burst_sweep_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A_BurstSweep",
            "Stage1ADryRun",
            "$Stage1ADryRunBurstFrames = @(1, 8, 64)",
            "$Stage1AFullBurstFrames = @(1, 2, 4, 8, 16, 32, 64)",
            "$Stage1ASettleMs = 500",
            "stage1_staircase",
            "Case2_RuntimeRingBypass",
            "Stage1A dry run disables early stop rules",
            "Stage 1A only runs Case2_RuntimeRingBypass",
            "Stage1A_BurstSweep:bf%04d:bg%04dus:sm%04dms:r%02d:Case2_RuntimeRingBypass",
            "puts [format \"PROBE_WINDOW_ID=%s\" $case2_probe_window_id]",
            "--stage", "Stage1A_BurstSweep",
            "--stage1a-baseline-source", "full_run_bf1_group",
            "--stage1a-run-kind", "$stage1aRunKind",
            'if ($Stage1ADryRun) { "dry_run" } else { "full_run" }',
        ):
            self.assertIn(token, text)

        self.assertNotIn("Case0_OriginalWrongPort\" $case2_probe_window_id", text)
        self.assertNotIn("Case1_HeaderAccepted\" $case2_probe_window_id", text)

    def test_stage1a_full_run_contract_requires_engineering_evidence_lane(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "$isStage1A = (($TrafficMode -eq \"burst\") -and (-not $isStage1ADropPulseAudit) -and (-not $isStage1A6) -and (-not $isStage1A7) -and (-not $isStage1A8) -and (-not $isStage1A9) -and (-not $isStage1A10) -and (-not $isStage1A11))",
            "doc\\reports\\engineering_evidence",
            "summary_stats.json",
            "stage_report.md",
            "experiment_report.md",
        ):
            self.assertIn(token, text)

        paper_semantics_tokens = (
            "doc\\reports\\paper_plot_data",
            "paper_ready_artifacts = $paperReadyArtifacts",
            'Write-Host ("paper_ready_dir={0}" -f $paperReadyDir)',
            "Invoke-CounterExport -SnapshotJsonPath $positiveSnapshotPath -OutputDir $paperReadyDir",
        )
        stage1a_guard_fragments = (
            "if (($null -ne $positiveCase) -and (-not $isStage1A))",
            "if ((-not $isStage1A) -and ($null -ne $positiveCase))",
            "if (($null -ne $positiveCase) -and ($stageName -ne \"Stage1A_BurstSweep\"))",
            "if (($stageName -ne \"Stage1A_BurstSweep\") -and ($null -ne $positiveCase))",
            "if (($null -ne $positiveCase) -and (-not $isStage1A) -and (-not $isStage1ADropPulseAudit))",
            "if (($null -ne $positiveCase) -and (-not $isStage1A) -and (-not $isStage1ADropPulseAudit) -and (-not $isStage1A6))",
            "if (($null -ne $positiveCase) -and (-not $isStage1A) -and (-not $isStage1ADropPulseAudit) -and (-not $isStage1A6) -and (-not $isStage1A7))",
            "if (($null -ne $positiveCase) -and (-not $isStage1A) -and (-not $isStage1ADropPulseAudit) -and (-not $isStage1A6) -and (-not $isStage1A7) -and (-not $isStage1A8) -and (-not $isStage1A9) -and (-not $isStage1A10) -and (-not $isStage1A11))",
        )

        if any(token in text for token in paper_semantics_tokens):
            self.assertTrue(
                any(fragment in text for fragment in stage1a_guard_fragments),
                "Stage1A full run must stay on engineering-evidence outputs and never flow into paper_plot_data export.",
            )

    def test_board_probe_script_declares_stage1a_drop_pulse_audit_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A_DropPulseAudit",
            "$Stage1ADropPulseAuditRepeatCount = 3",
            "$Stage1ADropPulseAuditConfigs",
            "IdleControl",
            "Settle_BF1_SM10",
            "Settle_BF1_SM50",
            "Settle_BF1_SM100",
            "Shared_BF1_SM500",
            "Burst_BF8_SM500",
            "Burst_BF64_SM500",
            "Stage1A_DropPulseAudit:%s:bf%04d:sm%04dms:r%02d:Case2_RuntimeRingBypass",
            "proc run_case2_runtime_ring_bypass_audit",
            "audit_pre_snapshot_after_clear_nonzero",
            "audit_idle_no_frame_injection",
            "source_progress_pre",
            "source_progress_post",
            "sink_progress_pre",
            "sink_progress_post",
            "clear_counter_block",
            "snapshot_probe_state",
            "inject_burst",
            "puts [format \"PROBE_WINDOW_ID=%s\" $case2_probe_window_id]",
            "--stage", "Stage1A_DropPulseAudit",
        ):
            self.assertIn(token, text)

        idle_branch = text[text.index("proc run_case2_runtime_ring_bypass_audit") :]
        self.assertIn("if {$burst_frames > 0}", idle_branch)
        self.assertIn("inject_burst", idle_branch)

    def test_board_probe_script_declares_stage1a6_prior_drop_pulse_reproduction_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A6_PriorDropPulseReproduction",
            "Stage1A6PriorDropPulseReproduction",
            "Stage1A6ClearDisabledDiagnostic",
            "$Stage1A6RepeatCount = 3",
            "$Stage1A6Configs",
            "BF1_SM500",
            "BF8_SM500",
            "BF64_SM500",
            "controlled_sampling_replay",
            "clear_disabled_diagnostic",
            "proc run_case2_runtime_ring_bypass_controlled_replay",
            "Stage1A6_PriorDropPulseReproduction:%s:bf%04d:sm%04dms:r%02d:Case2_RuntimeRingBypass",
            "puts [format \"PROBE_WINDOW_ID=%s\" $case2_probe_window_id]",
            "--stage", "Stage1A6_PriorDropPulseReproduction",
            "--reproduction-mode", "$reproductionMode",
            "--stage1a6-reference-stage1a-full-dir",
            "--stage1a6-reference-stage1a5-audit-dir",
        ):
            self.assertIn(token, text)

        self.assertIn(
            "if (($null -ne $positiveCase) -and (-not $isStage1A) -and (-not $isStage1ADropPulseAudit) -and (-not $isStage1A6) -and (-not $isStage1A7) -and (-not $isStage1A8) -and (-not $isStage1A9) -and (-not $isStage1A10) -and (-not $isStage1A11))",
            text,
        )
        self.assertNotIn("Case0_OriginalWrongPort\" $case2_probe_window_id", text)
        self.assertNotIn("Case1_HeaderAccepted\" $case2_probe_window_id", text)

    def test_board_probe_script_declares_stage1a7_drop_pulse_condition_diff_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A7_DropPulseConditionDiffDiagnosis",
            "Stage1A7DropPulseConditionDiffDiagnosis",
            "$Stage1A7RepeatCount = 3",
            "$Stage1A7Configs",
            "BF8_SM500",
            "BF64_SM500",
            "BF64_SM100",
            "BF64_SM500_ExtraSnapshots",
            "proc run_case2_runtime_ring_bypass_condition_diff",
            "Stage1A7_DropPulseConditionDiffDiagnosis:%s:bf%04d:sm%04dms:r%02d:Case2_RuntimeRingBypass",
            "puts [format \"PROBE_WINDOW_ID=%s\" $case2_probe_window_id]",
            "post_injection_immediate",
            "mid_050ms",
            "mid_250ms",
            "post_500ms",
            "stage1a7_snapshot_mode",
            "source_progress_pre",
            "source_progress_post",
            "sink_progress_pre",
            "sink_progress_post",
            "--stage", "Stage1A7_DropPulseConditionDiffDiagnosis",
        ):
            self.assertIn(token, text)

        self.assertNotIn("Case0_OriginalWrongPort\" $case2_probe_window_id", text)
        self.assertNotIn("Case1_HeaderAccepted\" $case2_probe_window_id", text)

    def test_stage1a7_keeps_engineering_evidence_lane_and_extra_snapshot_no_mid_clear(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "$isStage1A7 = [bool]$Stage1A7DropPulseConditionDiffDiagnosis",
            "$isStage1A = (($TrafficMode -eq \"burst\") -and (-not $isStage1ADropPulseAudit) -and (-not $isStage1A6) -and (-not $isStage1A7) -and (-not $isStage1A8) -and (-not $isStage1A9) -and (-not $isStage1A10) -and (-not $isStage1A11))",
            "if (($null -ne $positiveCase) -and (-not $isStage1A) -and (-not $isStage1ADropPulseAudit) -and (-not $isStage1A6) -and (-not $isStage1A7) -and (-not $isStage1A8) -and (-not $isStage1A9) -and (-not $isStage1A10) -and (-not $isStage1A11))",
        ):
            self.assertIn(token, text)

        condition_diff_start = text.index("proc run_case2_runtime_ring_bypass_condition_diff")
        condition_diff_block = text[condition_diff_start : condition_diff_start + 4000]
        self.assertIn('if {$snapshot_mode eq "extra_snapshots"} {', condition_diff_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post_injection_immediate"', condition_diff_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_050ms"', condition_diff_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_250ms"', condition_diff_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', condition_diff_block)
        self.assertEqual(condition_diff_block.count("clear_counter_block"), 1)

    def test_board_probe_script_declares_stage1a8_pbm_ingress_visibility_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A8_PBMIngressVisibilityDiagnosis",
            "Stage1A8PBMIngressVisibilityDiagnosis",
            "$Stage1A8RepeatCount = 3",
            "$Stage1A8Configs",
            "IdleControl",
            "BF8_SM500",
            "BF64_SM500",
            "BF8_SM500_ExtraSnapshots",
            "BF64_SM500_ExtraSnapshots",
            "Stage1A8_PBMIngressVisibilityDiagnosis:%s:bf%04d:sm%04dms:r%02d:Case2_RuntimeRingBypass",
            "puts [format \"PROBE_WINDOW_ID=%s\" $case2_probe_window_id]",
            "idle_control_quiesce_guard_ms",
            "idle_pre_after_clear_zero",
            "idle_residual_activity_seen",
            "post_injection_immediate",
            "mid_050ms",
            "mid_250ms",
            "post_500ms",
            "0x40001154",
            "0x40001158",
            "0x4000115C",
            "0x40001160",
            "0x40001164",
            "0x40001168",
            "0x4000116C",
            "0x40001170",
            "0x40001174",
            "0x40001178",
            "0x4000117C",
            "0x40001180",
            "0x40001184",
            "0x40001188",
            "0x4000118C",
            "0x40001190",
            "--stage", "Stage1A8_PBMIngressVisibilityDiagnosis",
        ):
            self.assertIn(token, text)

        stage1a8_start = text.index("proc run_case2_runtime_ring_bypass_pbm_visibility")
        stage1a8_block = text[stage1a8_start : stage1a8_start + 5000]
        self.assertIn('if {$config_name eq "IdleControl"} {', stage1a8_block)
        self.assertIn("after $idle_control_quiesce_guard_ms", stage1a8_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.pre"', stage1a8_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post_injection_immediate"', stage1a8_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_050ms"', stage1a8_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_250ms"', stage1a8_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', stage1a8_block)
        self.assertIn('set bypass_guard_ok [expr {($ring_size_val == 0) || (($ring_size_val > 0) && ($sw_tail_val == $hw_head_val) && ($debug_status_val == 0))}]', stage1a8_block)
        self.assertEqual(stage1a8_block.count("clear_counter_block"), 1)

        self.assertNotIn("Case0_OriginalWrongPort\" $case2_probe_window_id", text)
        self.assertNotIn("Case1_HeaderAccepted\" $case2_probe_window_id", text)

    def test_board_probe_script_declares_stage1a9_crypto_ingress_handoff_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis",
            "Stage1A9CryptoIngressHandoffVisibilityDiagnosis",
            "$Stage1A9RepeatCount = 3",
            "$Stage1A9Configs",
            "IdleControl",
            "BF8_SM500",
            "BF64_SM500",
            "BF8_SM500_ExtraSnapshots",
            "BF64_SM500_ExtraSnapshots",
            "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis:%s:bf%04d:sm%04dms:r%02d:Case2_RuntimeRingBypass",
            "puts [format \"PROBE_WINDOW_ID=%s\" $case2_probe_window_id]",
            "crypto_ingress_config",
            "stage1a9_snapshot_mode",
            "crypto_rx_valid_cycles",
            "crypto_rx_ready_high_cycles",
            "crypto_rx_valid_not_ready_cycles",
            "crypto_rx_accept_cycles",
            "crypto_rx_last_accepted_count",
            "crypto_rx_error_accepted_count",
            "crypto_rx_last_error_accepted_count",
            "crypto_rx_pkt_end_accepted_count",
            "0x40001194",
            "0x40001198",
            "0x4000119C",
            "0x400011A0",
            "0x400011A4",
            "0x400011A8",
            "0x400011AC",
            "0x400011B0",
            "--stage", "Stage1A9_CryptoIngressHandoffVisibilityDiagnosis",
        ):
            self.assertIn(token, text)

        stage1a9_start = text.index("proc run_case2_runtime_ring_bypass_crypto_ingress_visibility")
        stage1a9_block = text[stage1a9_start : stage1a9_start + 5000]
        self.assertIn('if {$config_name eq "IdleControl"} {', stage1a9_block)
        self.assertIn("after $idle_control_quiesce_guard_ms", stage1a9_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.pre"', stage1a9_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post_injection_immediate"', stage1a9_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_050ms"', stage1a9_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_250ms"', stage1a9_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', stage1a9_block)
        self.assertEqual(stage1a9_block.count("clear_counter_block"), 1)

        self.assertNotIn("Case0_OriginalWrongPort\" $case2_probe_window_id", text)
        self.assertNotIn("Case1_HeaderAccepted\" $case2_probe_window_id", text)

    def test_board_probe_script_declares_stage1a10_crypto_dma_handoff_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A10_CryptoDMAHandoffDiagnosis",
            "Stage1A10CryptoDMAHandoffDiagnosis",
            "$Stage1A10RepeatCount = 3",
            "$Stage1A10Configs",
            "IdleControl",
            "BF8_SM500",
            "BF64_SM500",
            "BF8_SM500_ExtraSnapshots",
            "BF64_SM500_ExtraSnapshots",
            "Stage1A10_CryptoDMAHandoffDiagnosis:%s:bf%04d:sm%04dms:r%02d:Case2_RuntimeRingBypass",
            "crypto_dma_handoff_config",
            "stage1a10_snapshot_mode",
            "pbm_committed_available_cycles",
            "pbm_rd_empty_cycles",
            "pbm_rd_nonempty_cycles",
            "pbm_rd_en_cycles",
            "pbm_rd_accept_cycles",
            "crypto_dma_in_valid_cycles",
            "crypto_dma_in_ready_cycles",
            "crypto_dma_in_accept_cycles",
            "crypto_dma_backpressure_cycles",
            "crypto_dma_in_last_seen_count",
            "crypto_dma_completion_count",
            "0x400011B4",
            "0x400011B8",
            "0x400011BC",
            "0x400011C0",
            "0x400011C4",
            "0x400011C8",
            "0x400011CC",
            "0x400011D0",
            "0x400011D4",
            "0x400011D8",
            "0x400011DC",
            "--stage", "Stage1A10_CryptoDMAHandoffDiagnosis",
        ):
            self.assertIn(token, text)

        stage1a10_start = text.index("proc run_case2_runtime_ring_bypass_crypto_dma_handoff_visibility")
        stage1a10_block = text[stage1a10_start : stage1a10_start + 5000]
        self.assertIn("proc pulse_dma_soft_reset {prefix ctrl_value}", text)
        self.assertIn('if {$config_name eq "IdleControl"} {', stage1a10_block)
        self.assertIn("pulse_dma_soft_reset $case2_prefix $ctrl_orig", stage1a10_block)
        self.assertIn("after $idle_control_quiesce_guard_ms", stage1a10_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.pre"', stage1a10_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post_injection_immediate"', stage1a10_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_050ms"', stage1a10_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_250ms"', stage1a10_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', stage1a10_block)
        self.assertIn('set force_runtime_bypass [expr {(!$bypass_guard_ok) && ($debug_status_val == 0)}]', stage1a10_block)
        self.assertIn('puts [format "%s.crypto_dma_handoff_runtime_bypass_forced=%d"', stage1a10_block)
        self.assertIn('if {$bypass_guard_ok || $force_runtime_bypass}', stage1a10_block)
        self.assertEqual(stage1a10_block.count("clear_counter_block"), 1)
        self.assertIn('set idle_residual_activity_seen [expr {!$pre_nonzero}]', stage1a10_block)
        self.assertIn('puts [format "%s.idle_residual_activity_seen=%d" $case2_prefix $idle_residual_activity_seen]', stage1a10_block)

        self.assertNotIn("Case0_OriginalWrongPort\" $case2_probe_window_id", text)
        self.assertNotIn("Case1_HeaderAccepted\" $case2_probe_window_id", text)

    def test_board_probe_script_declares_stage1a27_crypto_dma_ingress_backpressure_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A27_CryptoDMAIngressBackpressureDiagnosis",
            "Stage1A27CryptoDMAIngressBackpressureDiagnosis",
            "$Stage1A27RepeatCount = 3",
            "$Stage1A27Configs",
            "CryptoDMAIngressBackpressure_BF64",
            "Stage1A27_CryptoDMAIngressBackpressureDiagnosis:%s:bf%04d:sm%04dms:r%02d:Case2_RuntimeRingBypass",
            "crypto_dma_ingress_backpressure_config",
            "--stage", "Stage1A27_CryptoDMAIngressBackpressureDiagnosis",
        ):
            self.assertIn(token, text)

        stage1a27_start = text.index("run_case2_runtime_ring_bypass_crypto_dma_ingress_backpressure_diagnosis")
        stage1a27_block = text[stage1a27_start : stage1a27_start + 1800]
        self.assertIn("run_case2_runtime_ring_bypass_explicit_start_bridge_handoff_diagnosis", stage1a27_block)
        stage1a27_loop = text[text.index('$stage_name eq "Stage1A27_CryptoDMAIngressBackpressureDiagnosis"') :]
        self.assertIn("$crypto_dma_ingress_backpressure_config_name", stage1a27_loop)

    def test_board_probe_script_declares_stage2_extreme_traffic_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage2_ExtremeTraffic",
            "Stage2ExtremeTraffic",
            "$Stage2ExtremeTrafficRepeatCount = 2",
            "$Stage2ExtremeTrafficBurstFrames = $Stage1AFullBurstFrames",
            "$Stage2ExtremeTraffic",
            'elseif {$stage_name eq "Stage2_ExtremeTraffic"}',
            'Stage2_ExtremeTraffic:bf%04d:bg%04dus:sm%04dms:r%02d:Case2_RuntimeRingBypass',
            "--stage",
            "Stage2_ExtremeTraffic",
        ):
            self.assertIn(token, text)

        stage2_start = text.index('elseif {$stage_name eq "Stage2_ExtremeTraffic"}')
        stage2_end = text.index("} else {", stage2_start)
        stage2_block = text[stage2_start:stage2_end]
        self.assertIn("foreach burst_frames $stage2_extreme_burst_frames", stage2_block)
        self.assertIn("run_case2_runtime_ring_bypass", stage2_block)
        self.assertNotIn("Case0_OriginalWrongPort", stage2_block)

    def test_board_probe_script_declares_stage2_synthetic_fault_traffic_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage2_SyntheticFaultTraffic",
            "Stage2SyntheticFaultTraffic",
            "$Stage2SyntheticFaultTrafficRepeatCount = 2",
            "$Stage2SyntheticFaultTrafficBurstFrames = $Stage1AFullBurstFrames",
            "$Stage2SyntheticFaultTraffic",
            'elseif {$stage_name eq "Stage2_SyntheticFaultTraffic"}',
            'Stage2_SyntheticFaultTraffic:bf%04d:bg%04dus:sm%04dms:r%02d:Case2_RuntimeRingBypass',
            "proc inject_frame {expected_words words {inj_ctrl_flags 0}}",
            "proc inject_burst {expected_words words burst_frames burst_gap_us {inj_ctrl_flags 0}}",
            "0x00000002",
        ):
            self.assertIn(token, text)

        stage2_start = text.index('elseif {$stage_name eq "Stage2_SyntheticFaultTraffic"}')
        stage2_end = text.index("} else {", stage2_start)
        stage2_block = text[stage2_start:stage2_end]
        self.assertIn("foreach burst_frames $stage2_synthetic_fault_burst_frames", stage2_block)
        self.assertIn("run_case2_runtime_ring_bypass_synthetic_fault_recovery", stage2_block)
        self.assertIn("inject_burst [llength $classifier_header_words] $classifier_header_words $burst_frames $burst_gap_us 0x00000002", text)
        self.assertNotIn("Case0_OriginalWrongPort", stage2_block)

        proc_start = text.index("proc run_case2_runtime_ring_bypass_synthetic_fault_recovery")
        proc_end = text.index("proc run_case2_runtime_ring_bypass_audit", proc_start)
        proc_block = text[proc_start:proc_end]
        self.assertIn("pulse_dma_soft_reset $case2_prefix $ctrl_orig", proc_block)
        self.assertIn("synthetic_fault_runtime_bypass_forced", proc_block)
        self.assertIn("if {$bypass_guard_ok || $force_runtime_bypass}", proc_block)

    def test_board_probe_script_programs_net_cfg0_with_stable_double_write_helper(self):
        text = SCRIPT.read_text(encoding="utf-8")

        self.assertIn("proc program_shadow_net_cfg0_stable {value {settle_ms 2}}", text)
        self.assertIn("mwr -force 0x40000090 $value", text)
        self.assertIn("after $settle_ms", text)
        self.assertIn("program_shadow_net_cfg0_stable 0x00000007 2", text)
        self.assertNotIn("mwr -force 0x40000090 0x00000007\nafter 2", text)

    def test_board_probe_script_programs_inj_ctrl_with_stable_double_write_helper(self):
        text = SCRIPT.read_text(encoding="utf-8")

        self.assertIn("proc program_shadow_inj_ctrl_stable {value {settle_ms 1}}", text)
        self.assertIn("mwr -force 0x400000A0 $value", text)
        self.assertIn("set inj_ctrl_value [expr {($expected_words << 16) | ($inj_ctrl_flags & 0x0000FFFE)}]", text)
        self.assertIn("program_shadow_inj_ctrl_stable $inj_ctrl_value $settle_ms", text)

    def test_board_probe_script_programs_inj_data_with_stable_primed_push_sequence(self):
        text = SCRIPT.read_text(encoding="utf-8")

        self.assertIn("proc program_shadow_inj_words_stable {inj_ctrl_value words {settle_ms 1}}", text)
        self.assertIn("set first_word [lindex $words 0]", text)
        self.assertIn("mwr -force 0x400000A4 $first_word", text)
        self.assertIn("mwr -force 0x400000A0 0x00000001", text)
        self.assertIn("program_shadow_inj_ctrl_stable $inj_ctrl_value $settle_ms", text)
        self.assertIn("foreach word [lrange $words 1 end]", text)
        self.assertIn("mwr -force 0x400000A4 [lindex $words end]", text)
        self.assertIn("set inj_ctrl_value [expr {($expected_words << 16) | ($inj_ctrl_flags & 0x0000FFFE)}]", text)
        self.assertIn("program_shadow_inj_words_stable $inj_ctrl_value $words 1", text)

    def test_board_probe_script_declares_stage1a11_pbm_read_side_visibility_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A11_PBMReadSideVisibilityDiagnosis",
            "Stage1A11PBMReadSideVisibilityDiagnosis",
            "$Stage1A11RepeatCount = 3",
            "$Stage1A11Configs",
            "IdleControl",
            "BF8_SM500",
            "BF64_SM500",
            "BF8_SM500_ExtraSnapshots",
            "BF64_SM500_ExtraSnapshots",
            "Stage1A11_PBMReadSideVisibilityDiagnosis:%s:bf%04d:sm%04dms:r%02d:Case2_RuntimeRingBypass",
            "pbm_read_side_config",
            "stage1a11_snapshot_mode",
            "bridge_pbm_rd_en_cycles",
            "bridge_pbm_fire_count",
            "bridge_inst_available_cycles",
            "bridge_data_available_no_inst_available_cycles",
            "bridge_mid_fifo_full_cycles",
            "bridge_out_fifo_full_cycles",
            "bridge_input_state_raw",
            "dma_start_seen_count",
            "dma_addr_cycles",
            "dma_data_cycles",
            "dma_resp_cycles",
            "dma_aw_handshake_count",
            "dma_w_handshake_count",
            "dma_b_handshake_count",
            "dma_wready_low_cycles",
            "dma_state_raw",
            "0x400011E0",
            "0x400011E4",
            "0x400011E8",
            "0x400011EC",
            "0x400011F0",
            "0x400011F4",
            "0x400011F8",
            "0x400011FC",
            "0x40001200",
            "0x40001204",
            "0x40001208",
            "0x4000120C",
            "0x40001210",
            "0x40001214",
            "0x40001218",
            "0x4000121C",
            "--stage", "Stage1A11_PBMReadSideVisibilityDiagnosis",
        ):
            self.assertIn(token, text)

        stage1a11_start = text.index("proc run_case2_runtime_ring_bypass_pbm_read_side_visibility")
        stage1a11_block = text[stage1a11_start : stage1a11_start + 5500]
        self.assertIn('if {$config_name eq "IdleControl"} {', stage1a11_block)
        self.assertIn("pulse_dma_soft_reset $case2_prefix $ctrl_orig", stage1a11_block)
        self.assertIn("after $idle_control_quiesce_guard_ms", stage1a11_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.pre"', stage1a11_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post_injection_immediate"', stage1a11_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_050ms"', stage1a11_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_250ms"', stage1a11_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', stage1a11_block)
        self.assertEqual(stage1a11_block.count("clear_counter_block"), 1)
        self.assertIn('set idle_residual_activity_seen [expr {!$pre_nonzero}]', stage1a11_block)
        self.assertIn('puts [format "%s.idle_residual_activity_seen=%d" $case2_prefix $idle_residual_activity_seen]', stage1a11_block)

    def test_board_probe_script_declares_stage1a12_bridge_output_fifo_visibility_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis",
            "Stage1A12BridgeOutputFIFOVisibilityDiagnosis",
            "$Stage1A12RepeatCount = 3",
            "$Stage1A12Configs",
            "IdleControl",
            "BF8_SM500",
            "BF64_SM500",
            "BF8_SM500_ExtraSnapshots",
            "BF64_SM500_ExtraSnapshots",
            "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis:%s:bf%04d:sm%04dms:r%02d:Case2_RuntimeRingBypass",
            "bridge_output_fifo_config",
            "stage1a12_snapshot_mode",
            "bridge_tx_nonempty_cycles",
            "bridge_tx_rd_en_cycles",
            "bridge_tx_accept_cycles",
            "bridge_tx_last_seen_count",
            "0x40001220",
            "0x40001224",
            "0x40001228",
            "0x4000122C",
            "--stage", "Stage1A12_BridgeOutputFIFOVisibilityDiagnosis",
        ):
            self.assertIn(token, text)

        stage1a12_start = text.index("proc run_case2_runtime_ring_bypass_bridge_output_fifo_visibility")
        stage1a12_block = text[stage1a12_start : stage1a12_start + 5000]
        self.assertIn('if {$config_name eq "IdleControl"} {', stage1a12_block)
        self.assertIn("pulse_dma_soft_reset $case2_prefix $ctrl_orig", stage1a12_block)
        self.assertIn("after $idle_control_quiesce_guard_ms", stage1a12_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.pre"', stage1a12_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post_injection_immediate"', stage1a12_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_050ms"', stage1a12_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_250ms"', stage1a12_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', stage1a12_block)
        self.assertEqual(stage1a12_block.count("clear_counter_block"), 1)
        self.assertIn('set idle_residual_activity_seen [expr {!$pre_nonzero}]', stage1a12_block)
        self.assertIn('puts [format "%s.idle_residual_activity_seen=%d" $case2_prefix $idle_residual_activity_seen]', stage1a12_block)

    def test_board_probe_script_declares_stage1a13_dma_start_path_diagnosis_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A13_DMAStartPathDiagnosis",
            "Stage1A13DMAStartPathDiagnosis",
            "$Stage1A13RepeatCount = 3",
            "$Stage1A13Configs",
            "Current_Bypass_NoExplicitStart",
            "Bypass_WithExplicitCSRStart",
            "Stage1A13_DMAStartPathDiagnosis:%s:bf%04d:sm%04dms:r%02d:Case2_RuntimeRingBypass",
            "dma_start_path_config",
            "stage1a13_explicit_csr_start",
            "csr_start_pulse_count",
            "ring_doorbell_pulse_count",
            "fetcher_start_pulse_count",
            "final_start_pulse_count",
            "source_reader_start_pulse_count",
            "dma_busy_cycles",
            "source_reader_busy_cycles",
            "0x40001230",
            "0x40001234",
            "0x40001238",
            "0x4000123C",
            "0x40001240",
            "0x40001244",
            "0x40001248",
            "--stage", "Stage1A13_DMAStartPathDiagnosis",
        ):
            self.assertIn(token, text)

        stage1a13_start = text.index("proc run_case2_runtime_ring_bypass_dma_start_path_diagnosis")
        stage1a13_block = text[stage1a13_start : stage1a13_start + 5000]
        self.assertIn("pulse_dma_soft_reset $case2_prefix $ctrl_orig", stage1a13_block)
        self.assertIn("clear_counter_block", stage1a13_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.pre"', stage1a13_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', stage1a13_block)
        self.assertIn('if {$config_name eq "Bypass_WithExplicitCSRStart"} {', stage1a13_block)
        self.assertIn('puts [format "%s.stage1a13_explicit_csr_start=%d" $case2_prefix $explicit_csr_start]', stage1a13_block)

    def test_board_probe_script_declares_stage1a14_start_pulse_injection_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A14_StartPulseInjectionOrProbeControlFix",
            "Stage1A14StartPulseInjectionDiagnosis",
            "$Stage1A14RepeatCount = 3",
            "$Stage1A14Configs",
            "ExplicitStartWrite_Readback",
            "Stage1A14_StartPulseInjectionOrProbeControlFix:%s:bf%04d:sm%04dms:r%02d:Case2_RuntimeRingBypass",
            "start_pulse_injection_config",
            "explicit_start_write_addr",
            "explicit_start_write_value",
            "explicit_start_readback_before",
            "explicit_start_readback_after",
            "csr_control_reg_addr_expected",
            "csr_start_bit_expected",
            "axil_write_hit_control_count",
            "axil_write_hit_start_count",
            "axil_write_hit_doorbell_count",
            "0x4000124C",
            "0x40001250",
            "0x40001254",
            "--stage", "Stage1A14_StartPulseInjectionOrProbeControlFix",
        ):
            self.assertIn(token, text)

        stage1a14_start = text.index("proc run_case2_runtime_ring_bypass_start_pulse_injection_diagnosis")
        stage1a14_block = text[stage1a14_start : stage1a14_start + 5000]
        self.assertIn("proc sanitize_dma_ctrl_pulse_bits", text)
        self.assertIn("proc compute_explicit_start_write_value", text)
        self.assertIn("clear_counter_block", stage1a14_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.pre"', stage1a14_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', stage1a14_block)
        self.assertIn('set explicit_start_write_addr 0x40001000', stage1a14_block)
        self.assertIn('set explicit_start_write_value [compute_explicit_start_write_value $dma_ctrl_orig]', stage1a14_block)
        self.assertIn('puts [format "%s.explicit_start_readback_before=0x%08X" $case2_prefix $explicit_start_readback_before]', stage1a14_block)
        self.assertIn('puts [format "%s.explicit_start_readback_after=0x%08X" $case2_prefix $explicit_start_readback_after]', stage1a14_block)

    def test_board_probe_script_declares_stage1a15_explicit_start_bridge_handoff_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A15_ExplicitStartBridgeHandoffDiagnosis",
            "Stage1A15ExplicitStartBridgeHandoffDiagnosis",
            "$Stage1A15RepeatCount = 3",
            "$Stage1A15StartDelayMs = 50",
            "Current_Bypass_NoExplicitStart",
            "Bypass_ExplicitStart_BeforeWorkload",
            "Bypass_ExplicitStart_AfterWorkload",
            "after_workload_50ms",
            "explicit_start_timing",
            "start_delay_ms",
            "row_level_start_and_bridge_nonempty_seen",
            "dma_or_source_reader_busy_seen",
            "--stage", "Stage1A15_ExplicitStartBridgeHandoffDiagnosis",
        ):
            self.assertIn(token, text)

        stage1a15_start = text.index("proc run_case2_runtime_ring_bypass_explicit_start_bridge_handoff_diagnosis")
        stage1a15_block = text[stage1a15_start : stage1a15_start + 7000]
        self.assertIn("set shadow_control_base 0x40000000", stage1a15_block)
        self.assertIn("set dma_csr_base 0x40001000", stage1a15_block)
        self.assertIn("set explicit_start_write_addr $dma_csr_base", stage1a15_block)
        self.assertIn("set explicit_start_write_value [compute_explicit_start_write_value $dma_ctrl_orig]", stage1a15_block)
        self.assertIn('if {$explicit_start_timing eq "before_workload"}', stage1a15_block)
        self.assertIn('if {$explicit_start_timing eq "after_workload_50ms"}', stage1a15_block)
        self.assertIn("after $start_delay_ms", stage1a15_block)
        self.assertIn('puts [format "%s.explicit_start_write_addr_matches_dma_csr_base=%d"', stage1a15_block)
        self.assertIn('puts [format "%s.dma_ctrl_read_before=0x%08X"', stage1a15_block)
        self.assertIn('puts [format "%s.dma_ctrl_read_after=0x%08X"', stage1a15_block)
        self.assertIn('puts [format "%s.guard_loopback_mode=0x%08X"', stage1a15_block)
        self.assertIn('set force_runtime_bypass [expr {(!$bypass_guard_ok) && ($debug_status_val == 0)}]', stage1a15_block)
        self.assertIn('puts [format "%s.explicit_start_bridge_runtime_bypass_forced=%d"', stage1a15_block)
        self.assertIn('if {$bypass_guard_ok || $force_runtime_bypass}', stage1a15_block)
        self.assertIn("clear_counter_block", stage1a15_block)
        self.assertEqual(stage1a15_block.count("clear_counter_block"), 1)

    def test_board_probe_script_declares_stage1a16_bridge_data_production_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A16_BridgeDataProductionDiagnosis",
            "Stage1A16BridgeDataProductionDiagnosis",
            "$Stage1A16RepeatCount = 3",
            "$Stage1A16StartDelayMs = 50",
            "A12_NoStart_Replay",
            "A15_AfterWorkloadStart_Replay",
            "bridge_data_production_config",
            "after_workload_50ms",
            "--stage", "Stage1A16_BridgeDataProductionDiagnosis",
            "__STAGE1A16_CONFIG_LIST__",
        ):
            self.assertIn(token, text)

        stage1a16_start = text.index("proc run_case2_runtime_ring_bypass_bridge_data_production_diagnosis")
        stage1a16_block = text[stage1a16_start : stage1a16_start + 7000]
        self.assertIn("set dma_csr_base 0x40001000", stage1a16_block)
        self.assertIn("set start_bit_mask 0x00000001", stage1a16_block)
        self.assertIn("set loopback_mode_orig [mrd -force -value 0x40001048]", stage1a16_block)
        self.assertIn("set explicit_start_write_addr $dma_csr_base", stage1a16_block)
        self.assertIn("set explicit_start_write_value [compute_explicit_start_write_value $dma_ctrl_orig]", stage1a16_block)
        self.assertIn('if {$explicit_start_timing eq "after_workload_50ms"}', stage1a16_block)
        self.assertIn("after $start_delay_ms", stage1a16_block)
        self.assertIn('puts [format "%s.dma_ctrl_changed_bits=0x%08X"', stage1a16_block)
        self.assertIn('puts [format "%s.start_bit_mask=0x%08X"', stage1a16_block)
        self.assertIn('puts [format "%s.guard_loopback_mode=0x%08X"', stage1a16_block)
        self.assertIn('set force_runtime_bypass [expr {(!$bypass_guard_ok) && ($debug_status_val == 0)}]', stage1a16_block)
        self.assertIn('puts [format "%s.bridge_data_runtime_bypass_forced=%d"', stage1a16_block)
        self.assertIn('if {$bypass_guard_ok || $force_runtime_bypass}', stage1a16_block)
        self.assertIn("clear_counter_block", stage1a16_block)
        self.assertEqual(stage1a16_block.count("clear_counter_block"), 1)

    def test_board_probe_script_declares_stage1a26_dma_rd_en_equation_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A26_DMARdEnableEquationDiagnosis",
            "Stage1A26DMARdEnableEquationDiagnosis",
            "$Stage1A26RepeatCount = 3",
            "$Stage1A26StartDelayMs = 50",
            "DMARdEnableEquation_AfterWorkload",
            "dma_rd_en_equation_config",
            "after_workload_50ms",
            "set dma_csr_base 0x40001000",
            "set loopback_mode_orig [mrd -force -value 0x40001048]",
            "set explicit_start_write_addr $dma_csr_base",
            "--stage", "Stage1A26_DMARdEnableEquationDiagnosis",
            "0x40001280",
            "0x40001284",
            "0x40001288",
            "0x4000128C",
            "0x40001290",
            "0x40001294",
            "0x40001298",
            "0x4000129C",
            "0x400012A0",
        ):
            self.assertIn(token, text)

        stage1a26_start = text.index("proc run_case2_runtime_ring_bypass_dma_rd_en_equation_diagnosis")
        stage1a26_block = text[stage1a26_start : stage1a26_start + 7000]
        self.assertIn("clear_counter_block", stage1a26_block)
        self.assertEqual(stage1a26_block.count("clear_counter_block"), 1)
        self.assertIn('snapshot_probe_state "$case2_prefix.pre"', stage1a26_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', stage1a26_block)
        self.assertIn('if {$explicit_start_timing eq "after_workload_50ms"}', stage1a26_block)
        self.assertIn("after $start_delay_ms", stage1a26_block)
        self.assertIn("set explicit_start_write_value [compute_explicit_start_write_value $dma_ctrl_orig]", stage1a26_block)
        self.assertIn('puts [format "%s.guard_loopback_mode=0x%08X"', stage1a26_block)
        self.assertIn('set force_runtime_bypass [expr {(!$bypass_guard_ok) && ($debug_status_val == 0)}]', stage1a26_block)
        self.assertIn('puts [format "%s.dma_rd_en_equation_runtime_bypass_forced=%d"', stage1a26_block)
        self.assertIn('if {$bypass_guard_ok || $force_runtime_bypass}', stage1a26_block)

    def test_runtime_ring_bypass_paths_force_pbm_passthrough_loopback_mode(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for proc_name in (
            "proc run_case2_runtime_ring_bypass_crypto_dma_handoff_visibility",
            "proc run_case2_runtime_ring_bypass {",
            "proc run_case2_runtime_ring_bypass_explicit_start_bridge_handoff_diagnosis",
            "proc run_case2_runtime_ring_bypass_bridge_data_production_diagnosis",
            "proc run_case2_runtime_ring_bypass_dma_rd_en_equation_diagnosis",
        ):
            start = text.index(proc_name)
            block = text[start : start + 9000]
            self.assertIn("set loopback_mode_orig [mrd -force -value 0x40001048]", block)
            self.assertIn('puts [format "%s.guard_loopback_mode=0x%08X"', block)

    def test_shadow_export_ties_tx_axis_tready_high_when_tx_port_is_not_externalized(self):
        tcl = (REPO_ROOT / "HCS_SOC" / "export_udp_gateway_shadow_mirror_xsa.tcl").read_text(encoding="utf-8")

        for token in (
            "proc ensure_shadow_tx_tready_default_ready",
            "shadow_tx_tready_const",
            "CONFIG.CONST_WIDTH {1}",
            "CONFIG.CONST_VAL {1}",
            "connect_bd_net",
            "ensure_shadow_tx_tready_default_ready",
            "tying shadow TX ready high",
        ):
            self.assertIn(token, tcl)

        self.assertIn("if {$expose_fastpath_tx_ports}", tcl)
        self.assertIn("ensure_shadow_fastpath_tx_pins_external", tcl)

    def test_stage1a16_bridge_fifo_rtl_diagnostics_are_read_only_and_mapped(self):
        axil_csr = (REPO_ROOT / "rtl" / "core" / "axil_csr.sv").read_text(encoding="utf-8")
        subsystem = (REPO_ROOT / "rtl" / "top" / "crypto_dma_subsystem.sv").read_text(encoding="utf-8")
        bridge = (REPO_ROOT / "rtl" / "core" / "crypto" / "crypto_bridge_top.sv").read_text(encoding="utf-8")

        for port in (
            "i_counter_bridge_tx_wr_en_cycles",
            "i_counter_bridge_tx_fifo_level",
            "i_counter_bridge_tx_fifo_level_max",
            "i_counter_bridge_tx_empty_cycles",
            "i_counter_bridge_tx_full_cycles",
            "i_counter_bridge_tx_overflow_count",
        ):
            self.assertIn(port, axil_csr)
            self.assertIn(port, subsystem)

        for addr in ("10'h258", "10'h25C", "10'h260", "10'h264", "10'h268", "10'h26C"):
            self.assertEqual(axil_csr.count(addr), 1)

        for signal in (
            "o_diag_tx_wr_en_cycles",
            "o_diag_tx_fifo_level",
            "o_diag_tx_fifo_level_max",
            "o_diag_tx_empty_cycles",
            "o_diag_tx_full_cycles",
            "o_diag_tx_overflow_count",
            "tx_fifo_write_fire = gb_dout_valid && !out_fifo_full",
            "tx_fifo_read_fire = i_tx_rd_en && !o_tx_empty",
            "diag_tx_fifo_level_q <= tx_fifo_level_next",
        ):
            self.assertIn(signal, bridge)

        for signal in (
            "counter_bridge_tx_wr_en_cycles_q <= 32'd0",
            "counter_bridge_tx_fifo_level_q <= 32'd0",
            "counter_bridge_tx_fifo_level_max_q <= 32'd0",
            "counter_bridge_tx_empty_cycles_q <= 32'd0",
            "counter_bridge_tx_full_cycles_q <= 32'd0",
            "counter_bridge_tx_overflow_count_q <= 32'd0",
            "counter_bridge_tx_wr_en_cycles_shadow_q <= counter_bridge_tx_wr_en_cycles_q",
            "counter_bridge_tx_fifo_level_shadow_q <= counter_bridge_tx_fifo_level_q",
            "counter_bridge_tx_fifo_level_max_shadow_q <= counter_bridge_tx_fifo_level_max_q",
        ):
            self.assertIn(signal, subsystem)

    def test_board_probe_script_declares_stage1a17_pbm_commit_reproduction_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A17_PBMCommitReproductionDiagnosis",
            "Stage1A17PBMCommitReproductionDiagnosis",
            "$Stage1A17RepeatCount = 3",
            "CommitReferenceReplay",
            "CommitReplay_WithExtraPBMSnapshots",
            "pbm_commit_reproduction_config",
            "stage1a17_snapshot_mode",
            "stage1a17_extra_snapshots_present",
            "stage1a17_extra_snapshots_missing_reason",
            "bypass_not_allowed_post_only",
            "Test-SnapshotPrefixPresentInMap",
            "extra_snapshots",
            "--stage", "Stage1A17_PBMCommitReproductionDiagnosis",
            "__STAGE1A17_CONFIG_LIST__",
        ):
            self.assertIn(token, text)

        stage1a17_start = text.index("proc run_case2_runtime_ring_bypass_pbm_commit_reproduction_diagnosis")
        stage1a17_block = text[stage1a17_start : stage1a17_start + 7000]
        self.assertIn('puts [format "%s.pbm_commit_reproduction_config=%s"', stage1a17_block)
        self.assertIn('puts [format "%s.stage1a17_snapshot_mode=%s"', stage1a17_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.pre"', stage1a17_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post_workload_immediate"', stage1a17_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_050ms"', stage1a17_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_250ms"', stage1a17_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', stage1a17_block)
        self.assertIn('set bypass_guard_ok [expr {($ring_size_val == 0) || (($ring_size_val > 0) && ($sw_tail_val == $hw_head_val) && ($debug_status_val == 0))}]', stage1a17_block)
        self.assertIn('set force_runtime_bypass [expr {(!$bypass_guard_ok) && ($debug_status_val == 0)}]', stage1a17_block)
        self.assertIn('puts [format "%s.pbm_commit_runtime_bypass_forced=%d"', stage1a17_block)
        self.assertIn('if {$bypass_guard_ok || $force_runtime_bypass}', stage1a17_block)
        self.assertIn("runtime_ring_bypass_enabled=1", stage1a17_block)
        self.assertIn("clear_counter_block", stage1a17_block)
        self.assertEqual(stage1a17_block.count("clear_counter_block"), 1)
        self.assertNotIn("explicit_start_write_addr", stage1a17_block)

    def test_board_probe_script_declares_stage1a18_upstream_ingress_to_pbm_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis",
            "Stage1A18UpstreamIngressToPBMVisibilityDiagnosis",
            "$Stage1A18RepeatCount = 3",
            "IngressReferenceReplay",
            "IngressReplay_WithExtraSnapshots",
            "upstream_ingress_to_pbm_visibility_config",
            "stage1a18_snapshot_mode",
            "stage1a18_extra_snapshots_present",
            "stage1a18_extra_snapshots_missing_reason",
            "--stage", "Stage1A18_UpstreamIngressToPBMVisibilityDiagnosis",
            "__STAGE1A18_CONFIG_LIST__",
        ):
            self.assertIn(token, text)

        stage1a18_start = text.index("proc run_case2_runtime_ring_bypass_upstream_ingress_to_pbm_visibility")
        stage1a18_block = text[stage1a18_start : stage1a18_start + 7000]
        self.assertIn('puts [format "%s.upstream_ingress_to_pbm_visibility_config=%s"', stage1a18_block)
        self.assertIn('puts [format "%s.stage1a18_snapshot_mode=%s"', stage1a18_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.pre"', stage1a18_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post_workload_immediate"', stage1a18_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_050ms"', stage1a18_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_250ms"', stage1a18_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', stage1a18_block)
        self.assertIn('set bypass_guard_ok [expr {($ring_size_val == 0) || (($ring_size_val > 0) && ($sw_tail_val == $hw_head_val) && ($debug_status_val == 0))}]', stage1a18_block)
        self.assertIn('set force_runtime_bypass [expr {(!$bypass_guard_ok) && ($debug_status_val == 0)}]', stage1a18_block)
        self.assertIn('puts [format "%s.upstream_ingress_runtime_bypass_forced=%d"', stage1a18_block)
        self.assertIn('if {$bypass_guard_ok || $force_runtime_bypass}', stage1a18_block)
        self.assertEqual(stage1a18_block.count("clear_counter_block"), 1)

    def test_board_probe_script_declares_stage1a19_injection_source_emission_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A19_InjectionSourceEmissionDiagnosis",
            "Stage1A19InjectionSourceEmissionDiagnosis",
            "$Stage1A19RepeatCount = 3",
            "EmissionReferenceReplay",
            "EmissionReplay_WithExtraSnapshots",
            "injection_source_emission_config",
            "stage1a19_snapshot_mode",
            "stage1a19_extra_snapshots_present",
            "stage1a19_extra_snapshots_missing_reason",
            "--stage", "Stage1A19_InjectionSourceEmissionDiagnosis",
            "__STAGE1A19_CONFIG_LIST__",
        ):
            self.assertIn(token, text)

        stage1a19_start = text.index("proc run_case2_runtime_ring_bypass_injection_source_emission_diagnosis")
        stage1a19_block = text[stage1a19_start : stage1a19_start + 7000]
        self.assertIn('puts [format "%s.injection_source_emission_config=%s"', stage1a19_block)
        self.assertIn('puts [format "%s.stage1a19_snapshot_mode=%s"', stage1a19_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.pre"', stage1a19_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post_workload_immediate"', stage1a19_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_050ms"', stage1a19_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_250ms"', stage1a19_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', stage1a19_block)
        self.assertIn('set force_runtime_bypass [expr {(!$bypass_guard_ok) && ($debug_status_val == 0)}]', stage1a19_block)
        self.assertIn('puts [format "%s.injection_source_emission_runtime_bypass_forced=%d"', stage1a19_block)
        self.assertIn('if {$bypass_guard_ok || $force_runtime_bypass}', stage1a19_block)
        self.assertEqual(stage1a19_block.count("clear_counter_block"), 1)

    def test_board_probe_script_declares_stage1a20_injection_source_arming_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A20_InjectionSourceArmingDiagnosis",
            "Stage1A20InjectionSourceArmingDiagnosis",
            "$Stage1A20RepeatCount = 3",
            "InjectionArmOnly",
            "InjectionArmWithReadback",
            "injection_source_arming_config",
            "configured_burst_frames",
            "configured_frame_word_count",
            "inj_ctrl_read_before",
            "inj_ctrl_read_after",
            "inj_frame_length_readback",
            "--stage", "Stage1A20_InjectionSourceArmingDiagnosis",
            "__STAGE1A20_CONFIG_LIST__",
        ):
            self.assertIn(token, text)

        stage1a20_start = text.index("proc run_case2_runtime_ring_bypass_injection_source_arming_diagnosis")
        stage1a20_block = text[stage1a20_start : stage1a20_start + 8000]
        self.assertIn('puts [format "%s.injection_source_arming_config=%s"', stage1a20_block)
        self.assertIn('puts [format "%s.configured_burst_frames=%d"', stage1a20_block)
        self.assertIn('puts [format "%s.configured_frame_word_count=%d"', stage1a20_block)
        self.assertIn('puts [format "%s.inj_ctrl_read_before=0x%08X"', stage1a20_block)
        self.assertIn('puts [format "%s.inj_ctrl_read_after=0x%08X"', stage1a20_block)
        self.assertIn('puts [format "%s.inj_frame_length_readback=%d"', stage1a20_block)
        self.assertIn('set bypass_guard_ok [expr {($ring_size_val == 0) || (($ring_size_val > 0) && ($sw_tail_val == $hw_head_val) && ($debug_status_val == 0))}]', stage1a20_block)
        self.assertIn('set force_runtime_bypass [expr {(!$bypass_guard_ok) && ($debug_status_val == 0)}]', stage1a20_block)
        self.assertIn('puts [format "%s.injection_source_arming_runtime_bypass_forced=%d"', stage1a20_block)
        self.assertIn('if {$bypass_guard_ok || $force_runtime_bypass}', stage1a20_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.pre"', stage1a20_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', stage1a20_block)
        self.assertEqual(stage1a20_block.count("clear_counter_block"), 1)

    def test_board_probe_script_declares_stage1a21_pbm_ready_gating_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A21_PBMReadyGatingDiagnosis",
            "Stage1A21PBMReadyGatingDiagnosis",
            "$Stage1A21RepeatCount = 3",
            "IdleControl",
            "BF64_SM500",
            "BF64_SM500_ExtraSnapshots",
            "pbm_ready_gating_config",
            "stage1a21_snapshot_mode",
            "stage1a21_extra_snapshots_present",
            "stage1a21_extra_snapshots_missing_reason",
            "--stage", "Stage1A21_PBMReadyGatingDiagnosis",
            "__STAGE1A21_CONFIG_LIST__",
        ):
            self.assertIn(token, text)

        stage1a21_loop_start = text.index('if {$stage_name eq "Stage1A21_PBMReadyGatingDiagnosis"} {')
        stage1a21_loop_block = text[stage1a21_loop_start : stage1a21_loop_start + 2500]
        self.assertIn("run_case2_runtime_ring_bypass_pbm_visibility", stage1a21_loop_block)
        self.assertIn('set case2_probe_window_id [format "Stage1A21_PBMReadyGatingDiagnosis:%s:bf%04d:sm%04dms:r%02d:Case2_RuntimeRingBypass"', stage1a21_loop_block)

        stage1a8_start = text.index("proc run_case2_runtime_ring_bypass_pbm_visibility")
        stage1a8_block = text[stage1a8_start : stage1a8_start + 5000]
        self.assertIn('if {$config_name eq "IdleControl"} {', stage1a8_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.pre"', stage1a8_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post_injection_immediate"', stage1a8_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_050ms"', stage1a8_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_250ms"', stage1a8_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', stage1a8_block)
        self.assertIn('set bypass_guard_ok [expr {($ring_size_val == 0) || (($ring_size_val > 0) && ($sw_tail_val == $hw_head_val) && ($debug_status_val == 0))}]', stage1a8_block)
        self.assertIn('set force_runtime_bypass [expr {(!$bypass_guard_ok) && ($debug_status_val == 0)}]', stage1a8_block)
        self.assertIn('puts [format "%s.pbm_visibility_runtime_bypass_forced=%d"', stage1a8_block)
        self.assertIn('if {$bypass_guard_ok || $force_runtime_bypass}', stage1a8_block)
        self.assertEqual(stage1a8_block.count("clear_counter_block"), 1)

    def test_board_probe_script_declares_stage1a22_pbm_pointer_reset_or_drain_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A22_PBMPointerResetOrDrainDiagnosis",
            "Stage1A22PBMPointerResetOrDrainDiagnosis",
            "$Stage1A22RepeatCount = 3",
            "IdleControl_NoReset",
            "IdleControl_AfterSoftReset",
            "BF64_SM500_AfterSoftReset",
            "pbm_pointer_reset_or_drain_config",
            "stage1a22_reset_mode",
            "--stage", "Stage1A22_PBMPointerResetOrDrainDiagnosis",
            "__STAGE1A22_CONFIG_LIST__",
        ):
            self.assertIn(token, text)

        stage1a22_loop_start = text.index('if {$stage_name eq "Stage1A22_PBMPointerResetOrDrainDiagnosis"} {')
        stage1a22_loop_block = text[stage1a22_loop_start : stage1a22_loop_start + 2500]
        self.assertIn("run_case2_runtime_ring_bypass_pbm_pointer_reset_or_drain_diagnosis", stage1a22_loop_block)
        self.assertIn('set case2_probe_window_id [format "Stage1A22_PBMPointerResetOrDrainDiagnosis:%s:bf%04d:sm%04dms:r%02d:Case2_RuntimeRingBypass"', stage1a22_loop_block)

        stage1a22_proc_start = text.index("proc run_case2_runtime_ring_bypass_pbm_pointer_reset_or_drain_diagnosis")
        stage1a22_proc_end = text.index("\nproc ", stage1a22_proc_start + 1)
        stage1a22_proc_block = text[stage1a22_proc_start:stage1a22_proc_end]
        self.assertIn('puts [format "%s.pbm_pointer_reset_or_drain_config=%s"', stage1a22_proc_block)
        self.assertIn('puts [format "%s.stage1a22_reset_mode=%s"', stage1a22_proc_block)
        self.assertIn('if {$reset_mode eq "soft_reset"} {', stage1a22_proc_block)
        self.assertIn('pulse_dma_soft_reset $case2_prefix $ctrl_orig', stage1a22_proc_block)
        self.assertIn('puts [format "%s.dma_soft_reset_pulsed=0" $case2_prefix]', stage1a22_proc_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.pre"', stage1a22_proc_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', stage1a22_proc_block)
        self.assertIn('set bypass_guard_ok [expr {($ring_size_val == 0) || (($ring_size_val > 0) && ($sw_tail_val == $hw_head_val) && ($debug_status_val == 0))}]', stage1a22_proc_block)
        self.assertEqual(stage1a22_proc_block.count("clear_counter_block"), 1)

    def test_board_probe_script_declares_stage1a23_pbm_commit_tail_pointer_invariant_contract(self):
        text = SCRIPT.read_text(encoding="utf-8")

        for token in (
            "Stage1A23_PBMCommitTailPointerInvariantDiagnosis",
            "Stage1A23PBMCommitTailPointerInvariantDiagnosis",
            "$Stage1A23RepeatCount = 3",
            "IdleControl_NoReset",
            "IdleControl_AfterSoftReset",
            "IdleControl_AfterSoftReset_ExtraSnapshots",
            "pbm_commit_tail_invariant_config",
            "stage1a23_reset_mode",
            "stage1a23_snapshot_mode",
            "--stage", "Stage1A23_PBMCommitTailPointerInvariantDiagnosis",
            "__STAGE1A23_CONFIG_LIST__",
        ):
            self.assertIn(token, text)

        stage1a23_loop_start = text.index('if {$stage_name eq "Stage1A23_PBMCommitTailPointerInvariantDiagnosis"} {')
        stage1a23_loop_block = text[stage1a23_loop_start : stage1a23_loop_start + 2500]
        self.assertIn("run_case2_runtime_ring_bypass_pbm_commit_tail_pointer_invariant_diagnosis", stage1a23_loop_block)
        self.assertIn('set case2_probe_window_id [format "Stage1A23_PBMCommitTailPointerInvariantDiagnosis:%s:bf%04d:sm%04dms:r%02d:Case2_RuntimeRingBypass"', stage1a23_loop_block)

        stage1a23_proc_start = text.index("proc run_case2_runtime_ring_bypass_pbm_commit_tail_pointer_invariant_diagnosis")
        stage1a23_proc_end = text.index("\nproc ", stage1a23_proc_start + 1)
        stage1a23_proc_block = text[stage1a23_proc_start:stage1a23_proc_end]
        self.assertIn('puts [format "%s.pbm_commit_tail_invariant_config=%s"', stage1a23_proc_block)
        self.assertIn('puts [format "%s.stage1a23_reset_mode=%s"', stage1a23_proc_block)
        self.assertIn('puts [format "%s.stage1a23_snapshot_mode=%s"', stage1a23_proc_block)
        self.assertIn('if {$reset_mode eq "soft_reset"} {', stage1a23_proc_block)
        self.assertIn('pulse_dma_soft_reset $case2_prefix $ctrl_orig', stage1a23_proc_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.pre"', stage1a23_proc_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post"', stage1a23_proc_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.post_workload_immediate"', stage1a23_proc_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_050ms"', stage1a23_proc_block)
        self.assertIn('snapshot_probe_state "$case2_prefix.mid_250ms"', stage1a23_proc_block)
        self.assertEqual(stage1a23_proc_block.count("clear_counter_block"), 1)

    def test_shadow_injection_rtl_diagnostics_are_read_only_and_mapped_for_stage1a20(self):
        shadow_ctrl = (REPO_ROOT / "rtl" / "top" / "udp_gateway_shadow_ctrl_csr.sv").read_text(encoding="utf-8")
        wrapper = (REPO_ROOT / "rtl" / "top" / "dma_gateway_hybrid_board_wrapper.v").read_text(encoding="utf-8")
        shadow_inject = (REPO_ROOT / "rtl" / "top" / "udp_gateway_shadow_inject_path.sv").read_text(encoding="utf-8")
        network_stage1 = (REPO_ROOT / "rtl" / "top" / "network_stage1_path.sv").read_text(encoding="utf-8")
        classifier = (REPO_ROOT / "rtl" / "core" / "dma" / "udp_dma_ingress_classifier.sv").read_text(encoding="utf-8")
        probe_text = SCRIPT.read_text(encoding="utf-8")

        for port in (
            "i_diag_inj_ctrl_write_hit_count",
            "i_diag_inj_clear_write_hit_count",
            "i_diag_inj_frame_word_write_hit_count",
            "i_diag_inj_expected_words_write_hit_count",
            "i_diag_inj_source_state_raw",
            "i_diag_inj_fifo_write_count",
            "i_diag_inj_fifo_level",
            "i_diag_inj_fifo_level_max",
            "i_diag_inj_source_idle_cycles",
            "i_diag_inj_source_armed_cycles",
            "i_diag_inj_source_active_cycles",
            "i_diag_inj_source_done_count",
            "i_diag_inj_source_emitting_cycles",
            "i_diag_stage1_inject_tvalid_cycles",
            "i_diag_stage1_inject_tready_cycles",
            "i_diag_stage1_inject_fire_cycles",
            "i_diag_stage1_inject_last_seen_count",
        ):
            self.assertIn(port, shadow_ctrl)
            self.assertIn(port, wrapper)

        for addr in (
            "10'h0EC",
            "10'h0F0",
            "10'h0F4",
            "10'h0F8",
            "10'h0FC",
            "10'h100",
            "10'h104",
            "10'h108",
            "10'h10C",
            "10'h110",
            "10'h114",
            "10'h118",
            "10'h11C",
            "10'h120",
            "10'h124",
            "10'h128",
            "10'h12C",
            "10'h130",
            "10'h134",
            "10'h138",
            "10'h13C",
            "10'h140",
            "10'h144",
            "10'h148",
        ):
            self.assertEqual(shadow_ctrl.count(addr), 1)

        for signal in (
            "o_diag_inj_source_state_raw",
            "o_diag_inj_fifo_write_count",
            "o_diag_inj_fifo_level",
            "o_diag_inj_fifo_level_max",
            "o_diag_inj_source_idle_cycles",
            "o_diag_inj_source_armed_cycles",
            "o_diag_inj_source_active_cycles",
            "o_diag_inj_source_done_count",
            "o_diag_inj_source_emitting_cycles",
            "o_diag_stage1_inject_tvalid_cycles",
            "o_diag_stage1_inject_tready_cycles",
            "o_diag_stage1_inject_fire_cycles",
            "o_diag_stage1_inject_last_seen_count",
        ):
            self.assertIn(signal, shadow_inject)
            self.assertIn(signal, network_stage1)

        for port in (
            "i_diag_classifier_state_raw",
            "i_diag_classifier_word_index",
            "i_diag_classifier_flags",
            "i_diag_classifier_udp_dst_port",
            "i_diag_classifier_last_ethertype_word",
            "i_diag_classifier_last_udp_ports_word",
            "i_diag_classifier_last_udp_meta_word",
        ):
            self.assertIn(port, shadow_ctrl)
            self.assertIn(port, wrapper)

        for signal in (
            "o_diag_classifier_state_raw",
            "o_diag_classifier_word_index",
            "o_diag_classifier_flags",
            "o_diag_classifier_udp_dst_port",
            "o_diag_classifier_last_ethertype_word",
            "o_diag_classifier_last_udp_ports_word",
            "o_diag_classifier_last_udp_meta_word",
        ):
            self.assertIn(signal, classifier)

        for token in (
            'puts [format "%s.classifier_state_raw=0x%08X" $prefix [mrd -force -value 0x40000130]]',
            'puts [format "%s.classifier_word_index=0x%08X" $prefix [mrd -force -value 0x40000134]]',
            'puts [format "%s.classifier_flags=0x%08X" $prefix [mrd -force -value 0x40000138]]',
            'puts [format "%s.classifier_udp_dst_port=0x%08X" $prefix [mrd -force -value 0x4000013C]]',
            'puts [format "%s.classifier_last_ethertype_word=0x%08X" $prefix [mrd -force -value 0x40000140]]',
            'puts [format "%s.classifier_last_udp_ports_word=0x%08X" $prefix [mrd -force -value 0x40000144]]',
            'puts [format "%s.classifier_last_udp_meta_word=0x%08X" $prefix [mrd -force -value 0x40000148]]',
        ):
            self.assertIn(token, probe_text)

    def test_board_probe_script_fixes_idle_residual_activity_polarity_for_stage1a8_to_stage1a11(self):
        text = SCRIPT.read_text(encoding="utf-8")

        self.assertNotIn('puts [format "%s.idle_residual_activity_seen=%d" $case2_prefix [expr {!$pre_nonzero}]]', text)
        self.assertGreaterEqual(text.count('set idle_residual_activity_seen [expr {!$pre_nonzero}]'), 4)


if __name__ == "__main__":
    unittest.main()
