import pathlib
import re
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"
LEGACY_ROOT = HCS_SOC / "legacy"
LEGACY_WORKSPACES = LEGACY_ROOT / "workspaces"
LEGACY_APPS = LEGACY_ROOT / "apps"
LEGACY_SCRIPTS = LEGACY_ROOT / "scripts"
LEGACY_SD_BOOT = LEGACY_ROOT / "sd_boot"
GATEWAY_C = LEGACY_WORKSPACES / "vitis_2023_udp_gateway_ws_2" / "ax7020_udp_gateway_app" / "src" / "udp_crypto_gateway.c"
GATEWAY_H = LEGACY_WORKSPACES / "vitis_2023_udp_gateway_ws_2" / "ax7020_udp_gateway_app" / "src" / "udp_crypto_gateway.h"

APP_MAIN = HCS_SOC / "ax7020_udp_gateway_shadow_mirror_app" / "src" / "main.c"
APP_LSCRIPT = HCS_SOC / "ax7020_udp_gateway_shadow_mirror_app" / "src" / "lscript.ld"
BUILD_APP = HCS_SOC / "build_ax7020_udp_gateway_shadow_mirror_app.ps1"
BUILD_BOOT = HCS_SOC / "build_ax7020_udp_gateway_shadow_mirror_boot.ps1"
GENERATE_PLATFORM = HCS_SOC / "generate_ax7020_standalone_platform.ps1"
EXPORT_XSA = HCS_SOC / "export_udp_gateway_shadow_mirror_xsa.ps1"
EXPORT_TCL = HCS_SOC / "export_udp_gateway_shadow_mirror_xsa.tcl"
EVIDENCE_EXPORT = HCS_SOC / "export_ax7020_udp_gateway_shadow_mirror_evidence_pack.ps1"
EVIDENCE_EXPORT_TCL = HCS_SOC / "export_udp_gateway_shadow_mirror_evidence_pack.tcl"
SHADOW_PHASEC_XDC = REPO_ROOT / "constraints" / "shadow_mirror_phasec_constraints.xdc"
DEPLOY = HCS_SOC / "deploy_ax7020_udp_gateway_shadow_mirror_to_sd.ps1"
PERF_CHECK = HCS_SOC / "run_ax7020_udp_gateway_shadow_mirror_performance_check.ps1"
BENCH_MATRIX_CHECK = HCS_SOC / "run_ax7020_udp_gateway_shadow_mirror_bench_matrix.ps1"
ACL_CHECK = HCS_SOC / "run_ax7020_udp_gateway_shadow_mirror_acl_check.ps1"
FASTPATH_CHECK = HCS_SOC / "run_ax7020_udp_gateway_shadow_mirror_fastpath_board_check.ps1"
SECURITY_CHECK = HCS_SOC / "run_ax7020_udp_gateway_shadow_mirror_security_check.ps1"
BOARD_CHECK = HCS_SOC / "run_ax7020_udp_gateway_shadow_mirror_board_check.ps1"
SOAK_CHECK = HCS_SOC / "run_ax7020_udp_gateway_shadow_mirror_soak_check.ps1"
CAPTURE_UART = HCS_SOC / "capture_uart_boot_log.ps1"
HYBRID_PROOF_APP = LEGACY_APPS / "ax7020_dma_gateway_hybrid_perf_proof_app" / "src" / "main.c"
HYBRID_PROOF_BUILD_APP = LEGACY_SCRIPTS / "build_ax7020_dma_gateway_hybrid_perf_proof_app.ps1"
HYBRID_PROOF_BUILD_BOOT = LEGACY_SCRIPTS / "build_ax7020_dma_gateway_hybrid_perf_proof_boot.ps1"
HYBRID_PROOF_DEPLOY = LEGACY_SCRIPTS / "deploy_ax7020_dma_gateway_hybrid_perf_proof_to_sd.ps1"
HYBRID_PROOF_RUN = LEGACY_SCRIPTS / "run_ax7020_dma_gateway_hybrid_perf_proof_board_check.ps1"
HYBRID_PROOF_RELEASE_DIR = LEGACY_SD_BOOT / "ax7020_dma_gateway_hybrid_perf_proof"
RELEASE_DIR = HCS_SOC / "sd_boot" / "ax7020_udp_gateway_shadow_mirror"
BOOT_BIN = RELEASE_DIR / "BOOT.BIN"
BOOT_BIF = RELEASE_DIR / "boot.bif"
READ_ME = RELEASE_DIR / "readme.txt"
BOOTGEN_READ = RELEASE_DIR / "bootgen_read.txt"
STAGED_FSBL = RELEASE_DIR / "fsbl.elf"
STAGED_BIT = RELEASE_DIR / "udp_gateway_shadow_mirror_wrapper.bit"
STAGED_APP = RELEASE_DIR / "ax7020_udp_gateway_shadow_mirror_app.elf"
BENCH_SCRIPT = REPO_ROOT / "scripts" / "day21_performance_benchmark.py"
BENCH_MATRIX_SCRIPT = REPO_ROOT / "scripts" / "day21_benchmark_matrix.py"
SEND_UDP_TEST = REPO_ROOT / "handoff" / "robeieda_porting_pack" / "tools" / "send_udp_crypto_test.py"
THESIS_DATA = REPO_ROOT / "doc" / "reports" / "THESIS_DATA_TABLE.md"


def _extract_boot_payload(boot_bif: pathlib.Path) -> list[str]:
    lines = [
        line.strip()
        for line in boot_bif.read_text(encoding="ascii").splitlines()
        if line.strip() and not line.strip().startswith("//")
    ]
    return lines[2:-1]


def _extract_function_block(text: str, signature: str) -> str:
    match = re.search(re.escape(signature), text)
    if match is None:
        raise AssertionError(f"Function signature not found: {signature}")

    open_brace = text.find("{", match.end())
    if open_brace < 0:
        raise AssertionError(f"Opening brace not found for function: {signature}")

    depth = 0
    for index in range(open_brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[match.start() : index + 1]

    raise AssertionError(f"Closing brace not found for function: {signature}")


def _extract_shadow_job_struct(text: str) -> str:
    match = re.search(
        r"typedef struct \{\n\s*gateway_algo_t algo;\n\s*uint16_t local_port;\n.*?\} gateway_shadow_job_t;",
        text,
        re.S,
    )
    if match is None:
        raise AssertionError("Shadow job struct signature not found")
    return match.group(0)


def _extract_powershell_array_assignment(text: str, variable_name: str) -> str:
    pattern = re.compile(rf"\${re.escape(variable_name)}\s*=\s*@\((.*?)\n\)", re.S)
    match = pattern.search(text)
    if match is None:
        raise AssertionError(f"PowerShell array assignment not found: ${variable_name}")
    return match.group(1)


def _extract_control_invocation_expression(text: str, label: str) -> str:
    pattern = re.compile(
        rf'Invoke-ControlCommand\s+-Label\s+"{re.escape(label)}"\s+-Arguments\s+\((.*?)\)\s*\nif\s+\(',
        re.S,
    )
    match = pattern.search(text)
    if match is None:
        raise AssertionError(f"Invoke-ControlCommand block not found for label: {label}")
    return match.group(1)


class TestUdpGatewayShadowMirrorRelease(unittest.TestCase):
    def test_shadow_export_tcl_explicitly_keeps_inactive_shadow_security_extras_disabled(self):
        export_tcl = EXPORT_TCL.read_text(encoding="ascii")

        for token in (
            "proc keep_shadow_inactive_sources_disabled {}",
            '"rtl/security/config_packet_auth.sv"',
            '"rtl/security/key_vault.sv"',
            '"rtl/core/crypto/crypto_engine.sv"',
            '"rtl/security/five_tuple_extractor.sv"',
            "set_property is_enabled false $file_obj",
            "set_property used_in_synthesis false $file_obj",
            "set_property used_in_implementation false $file_obj",
            "keep_shadow_inactive_sources_disabled",
        ):
            self.assertIn(token, export_tcl)

    def test_shadow_mirror_assets_exist(self):
        for required in (
            APP_MAIN,
            APP_LSCRIPT,
            BUILD_APP,
            BUILD_BOOT,
            GENERATE_PLATFORM,
            EXPORT_XSA,
            EXPORT_TCL,
            EVIDENCE_EXPORT,
            EVIDENCE_EXPORT_TCL,
            SHADOW_PHASEC_XDC,
            DEPLOY,
            PERF_CHECK,
            BENCH_MATRIX_CHECK,
            ACL_CHECK,
            FASTPATH_CHECK,
            SECURITY_CHECK,
            SOAK_CHECK,
            HYBRID_PROOF_APP,
            HYBRID_PROOF_BUILD_APP,
            HYBRID_PROOF_BUILD_BOOT,
            HYBRID_PROOF_DEPLOY,
            HYBRID_PROOF_RUN,
            HYBRID_PROOF_RELEASE_DIR,
            BENCH_SCRIPT,
            SEND_UDP_TEST,
            THESIS_DATA,
            RELEASE_DIR,
            BOOT_BIN,
            BOOT_BIF,
            READ_ME,
            BOOTGEN_READ,
            STAGED_FSBL,
            STAGED_BIT,
            STAGED_APP,
        ):
            self.assertTrue(required.exists(), f"Expected shadow mirror asset missing: {required}")

    def test_shadow_export_tcl_keeps_module_ref_auto_compile_support(self):
        export_tcl = EXPORT_TCL.read_text(encoding="ascii")

        self.assertIn("proc run_manual_shadow_top_flow {workspace_root runs_root out_xsa} {", export_tcl)
        self.assertIn('set_property source_mgmt_mode All [current_project]', export_tcl)
        self.assertNotIn('set_property source_mgmt_mode None [current_project]', export_tcl)
        self.assertIn("update_compile_order -fileset sources_1", export_tcl)
        self.assertIn("lock_shadow_wrapper_top", export_tcl)
        self.assertNotIn('launch_runs synth_1 -scripts_only', export_tcl)
        self.assertNotIn('launch_runs impl_1 -to_step write_bitstream -scripts_only', export_tcl)
        self.assertIn('set direct_ooc_runs [create_ip_run $raw_bd_obj]', export_tcl)
        self.assertIn('launch_runs $shadow_run_name -scripts_only', export_tcl)
        self.assertIn('run_manual_shadow_top_flow $workspace_root $runs_root $out_xsa', export_tcl)
        for token in (
            "open_bd_design $raw_bd",
            "validate_bd_design",
            "save_bd_design",
            "generate_target all $raw_bd_obj",
            "export_ip_user_files -of_objects $raw_bd_obj -sync -force -quiet",
            "ZERO_COPY_FASTPATH_EGRESS_STEP1",
        ):
            self.assertIn(token, export_tcl)

    def test_shadow_export_tcl_defaults_fastpath_tx_port_exposure_off_for_board_bitstreams(self):
        export_tcl = EXPORT_TCL.read_text(encoding="ascii")

        for token in (
            "set expose_fastpath_tx_ports 0",
            "if {[info exists ::env(UDP_GATEWAY_SHADOW_MIRROR_EXPOSE_FASTPATH_TX_PORTS)]}",
            'set expose_fastpath_tx_ports [expr {$::env(UDP_GATEWAY_SHADOW_MIRROR_EXPOSE_FASTPATH_TX_PORTS) eq "1"}]',
            "if {$expose_fastpath_tx_ports} {",
            "ensure_shadow_fastpath_tx_pins_external",
            'puts "Skipping fastpath TX external port exposure for board export."',
        ):
            self.assertIn(token, export_tcl)

    def test_shadow_diag_ctrl_csr_does_not_expose_forced_dma_override_or_ext_status_windows(self):
        text = (REPO_ROOT / "rtl" / "top" / "udp_gateway_shadow_ctrl_csr.sv").read_text(encoding="ascii")

        for token in (
            "output logic                   o_diag_force_shadow_hit_to_dma,",
            "input  logic [31:0]            i_netdbg_ext0,",
            "input  logic [31:0]            i_netdbg_ext1,",
            "logic [31:0] reg_diag_ctrl;",
            "reg_diag_ctrl <= 32'd0;",
            "8'hEC: reg_diag_ctrl <= apply_wstrb(reg_diag_ctrl, s_axil_wdata, s_axil_wstrb);",
            "8'hEC: s_axil_rdata <= reg_diag_ctrl;",
            "8'hF0: s_axil_rdata <= i_netdbg_ext0;",
            "8'hF4: s_axil_rdata <= i_netdbg_ext1;",
            "assign o_diag_force_shadow_hit_to_dma = reg_diag_ctrl[0];",
        ):
            self.assertNotIn(token, text)

    def test_shadow_wrapper_does_not_include_forced_dma_route_or_extended_netdbg_signals(self):
        text = (REPO_ROOT / "rtl" / "top" / "dma_gateway_hybrid_board_wrapper.v").read_text(encoding="ascii")

        for token in (
            "wire [31:0]           netdbg_ext0;",
            "wire [31:0]           netdbg_ext1;",
            "wire                  ctrl_diag_force_shadow_hit_to_dma;",
            "reg                   shadow_dbg_dst_port_match_seen_q;",
            "reg                   shadow_dbg_payload_len_valid_seen_q;",
            "reg                   shadow_dbg_fastpath_hit_branch_seen_q;",
            "reg                   shadow_dbg_force_dma_taken_seen_q;",
            "reg                   shadow_dbg_route_replay_seen_q;",
            "reg                   shadow_dbg_route_dma_seen_q;",
            "reg                   shadow_dbg_route_egress_replay_seen_q;",
            "reg                   shadow_dbg_route_egress_dma_seen_q;",
            "reg                   shadow_dbg_tx_ready_seen_q;",
            "assign netdbg_ext0",
            "assign netdbg_ext1",
            ".o_diag_force_shadow_hit_to_dma(ctrl_diag_force_shadow_hit_to_dma)",
            ".i_netdbg_ext0(netdbg_ext0)",
            ".i_netdbg_ext1(netdbg_ext1)",
            "shadow_dbg_force_dma_taken_seen_q <= 1'b1;",
            "shadow_dbg_route_egress_replay_seen_q <= 1'b1;",
            "shadow_dbg_route_dma_seen_q <= 1'b1;",
        ):
            self.assertNotIn(token, text)

        self.assertIn("fastpath_route_state_q <= FASTPATH_ROUTE_EGRESS_REPLAY;", text)

    def test_shadow_wrapper_inject_clear_resets_shadow_fastpath_route_state(self):
        text = (REPO_ROOT / "rtl" / "top" / "dma_gateway_hybrid_board_wrapper.v").read_text(encoding="ascii")
        bookkeeping = text.split("// Keep TXCAP bookkeeping", 1)[1].split("udp_dma_ingress_classifier u_classifier", 1)[0]

        self.assertIn("end else if (inj_clear) begin", bookkeeping)
        for token in (
            "fastpath_route_state_q <= FASTPATH_ROUTE_IDLE;",
            "fastpath_header_count_q <= 4'd0;",
            "fastpath_replay_idx_q <= 4'd0;",
            "fastpath_frame_ended_in_header_q <= 1'b0;",
            "payload_words_q <= 16'd0;",
            "txcap_payload_rd_pending_q <= 1'b0;",
        ):
            self.assertIn(token, bookkeeping)

    def test_shadow_export_ps1_avoids_project_xml_surgery(self):
        export_ps1 = EXPORT_XSA.read_text(encoding="utf-8")

        self.assertNotIn("function Repair-ShadowMirrorProjectTop", export_ps1)
        self.assertNotIn("Set-Content -Path $ProjectPath", export_ps1)
        self.assertNotIn("Repair-ShadowMirrorProjectTop -ProjectPath $projectFile", export_ps1)

    def test_shadow_mirror_app_contract(self):
        text = APP_MAIN.read_text(encoding="ascii")

        for token in (
            "UDP gateway shadow mirror image",
            "echo_netif",
            "g_original_netif_input",
            "debug_netif_input",
            "shadow-main: netif wrapped flags=",
            "start_application()",
            "transfer_data();",
            "xemacif_input(echo_netif)",
            "platform_enable_interrupts();",
        ):
            self.assertIn(token, text)

        self.assertIn("struct netif *echo_netif;", text)
        self.assertIn("static struct netif server_netif;", text)

    def test_shadow_counter_uart_formats_use_xil_printf_safe_specifiers(self):
        text = APP_MAIN.read_text(encoding="ascii")

        for token in (
            'xil_printf("shadow-counter: init csr_base=0x%08x\\r\\n"',
            'xil_printf("shadow-counter tag=%u %s=0x%08x%08x\\r\\n"',
            'xil_printf("shadow-counter meta tag=%u reason=%s rx_batches=%u rx_packets=%u\\r\\n"',
            'xil_printf("shadow-counter end tag=%u\\r\\n"',
        ):
            self.assertIn(token, text)

        for token in ("%lu", "%08lx"):
            self.assertNotIn(token, text)

    def test_shadow_counter_probe_uses_dma_axil_baseaddr_not_wrapper_ctrl_base(self):
        text = APP_MAIN.read_text(encoding="ascii")

        for token in (
            "#if defined(XPAR_DMA_GATEWAY_HYBRID_0_BASEADDR)",
            "#define SHADOW_COUNTER_DMA_CSR_BASE XPAR_DMA_GATEWAY_HYBRID_0_BASEADDR",
            "#elif defined(XPAR_DMA_GATEWAY_HYBRID_BOARD_WRAPPER_0_BASEADDR)",
            "#define SHADOW_COUNTER_DMA_CSR_BASE XPAR_DMA_GATEWAY_HYBRID_BOARD_WRAPPER_0_BASEADDR",
            "#define SHADOW_COUNTER_DMA_CSR_BASE 0x40001000u",
            "g_counter_probe_ctx.csr_base = (uintptr_t)SHADOW_COUNTER_DMA_CSR_BASE;",
            'xil_printf("shadow-counter: init csr_base=0x%08x\\r\\n", (unsigned int)SHADOW_COUNTER_DMA_CSR_BASE);',
        ):
            self.assertIn(token, text)

        self.assertNotIn("#define SHADOW_COUNTER_WRAPPER_CSR_BASE 0x40000000u", text)

    def test_shadow_counter_probe_emits_one_time_raw_dma_csr_dump(self):
        text = APP_MAIN.read_text(encoding="ascii")

        for token in (
            '#include "xil_io.h"',
            "static uint8_t g_counter_probe_raw_dumped;",
            "static void counter_probe_emit_raw32(",
            'xil_printf("shadow-counter raw tag=%u %s=0x%08x\\r\\n"',
            "Xil_In32((UINTPTR)(g_counter_probe_ctx.csr_base + offset))",
            'counter_probe_emit_raw32(tag, "debug_status", DMA_CSR_DEBUG_STATUS);',
            'counter_probe_emit_raw32(tag, "debug_source_progress", DMA_CSR_DEBUG_SOURCE_PROGRESS);',
            'counter_probe_emit_raw32(tag, "debug_sink_progress", DMA_CSR_DEBUG_SINK_PROGRESS);',
            'counter_probe_emit_raw32(tag, "backend_total_lo", DMA_CSR_BACKEND_TOTAL_CYCLES_LO);',
            'counter_probe_emit_raw32(tag, "backend_total_hi", DMA_CSR_BACKEND_TOTAL_CYCLES_HI);',
            'counter_probe_emit_raw32(tag, "drop_pulse_lo", DMA_CSR_DROP_PULSE_COUNT_LO);',
            'counter_probe_emit_raw32(tag, "drop_pulse_hi", DMA_CSR_DROP_PULSE_COUNT_HI);',
            "if (g_counter_probe_raw_dumped == 0U) {",
            "g_counter_probe_raw_dumped = 1U;",
        ):
            self.assertIn(token, text)

    def test_axil_csr_exposes_stage1a8_pbm_diag_window_without_address_collision(self):
        text = (REPO_ROOT / "rtl" / "core" / "axil_csr.sv").read_text(encoding="ascii")

        for token in (
            "i_counter_pbm_wr_valid_cycles",
            "i_counter_pbm_wr_ready_high_cycles",
            "i_counter_pbm_valid_not_ready_cycles",
            "i_counter_pbm_wr_accept_cycles",
            "i_counter_pbm_wr_last_accepted_count",
            "i_counter_pbm_wr_error_accepted_count",
            "i_counter_pbm_wr_last_error_accepted_count",
            "i_counter_pbm_alloc_meta_entry_count",
            "i_counter_pbm_alloc_pbm_entry_count",
            "i_counter_pbm_commit_entry_count",
            "i_counter_pbm_rollback_entry_count",
            "i_counter_pbm_state_raw",
            "i_counter_pbm_ptr_head_reserve",
            "i_counter_pbm_ptr_head_commit",
            "i_counter_pbm_ptr_tail",
            "i_counter_pbm_buffer_usage",
            "9'h154: s_axil_rdata <= i_counter_pbm_wr_valid_cycles[31:0];",
            "9'h158: s_axil_rdata <= i_counter_pbm_wr_ready_high_cycles[31:0];",
            "9'h15C: s_axil_rdata <= i_counter_pbm_valid_not_ready_cycles[31:0];",
            "9'h160: s_axil_rdata <= i_counter_pbm_wr_accept_cycles[31:0];",
            "9'h164: s_axil_rdata <= i_counter_pbm_wr_last_accepted_count[31:0];",
            "9'h168: s_axil_rdata <= i_counter_pbm_wr_error_accepted_count[31:0];",
            "9'h16C: s_axil_rdata <= i_counter_pbm_wr_last_error_accepted_count[31:0];",
            "9'h170: s_axil_rdata <= i_counter_pbm_alloc_meta_entry_count[31:0];",
            "9'h174: s_axil_rdata <= i_counter_pbm_alloc_pbm_entry_count[31:0];",
            "9'h178: s_axil_rdata <= i_counter_pbm_commit_entry_count[31:0];",
            "9'h17C: s_axil_rdata <= i_counter_pbm_rollback_entry_count[31:0];",
            "9'h180: s_axil_rdata <= i_counter_pbm_state_raw[31:0];",
            "9'h184: s_axil_rdata <= i_counter_pbm_ptr_head_reserve[31:0];",
            "9'h188: s_axil_rdata <= i_counter_pbm_ptr_head_commit[31:0];",
            "9'h18C: s_axil_rdata <= i_counter_pbm_ptr_tail[31:0];",
            "9'h190: s_axil_rdata <= i_counter_pbm_buffer_usage[31:0];",
        ):
            self.assertIn(token, text)

        for addr in (
            "9'h154:",
            "9'h158:",
            "9'h15C:",
            "9'h160:",
            "9'h164:",
            "9'h168:",
            "9'h16C:",
            "9'h170:",
            "9'h174:",
            "9'h178:",
            "9'h17C:",
            "9'h180:",
            "9'h184:",
            "9'h188:",
            "9'h18C:",
            "9'h190:",
        ):
            self.assertEqual(text.count(addr), 1, f"CSR address must appear exactly once: {addr}")

    def test_pbm_controller_and_crypto_dma_subsystem_expose_stage1a8_diagnostic_observability(self):
        pbm_text = (REPO_ROOT / "rtl" / "core" / "pbm" / "pbm_controller.sv").read_text(encoding="ascii")
        subsystem_text = (REPO_ROOT / "rtl" / "top" / "crypto_dma_subsystem.sv").read_text(encoding="ascii")

        for token in (
            "o_diag_wr_valid_cycles",
            "o_diag_wr_ready_high_cycles",
            "o_diag_valid_not_ready_cycles",
            "o_diag_wr_accept_cycles",
            "o_diag_wr_last_accepted_count",
            "o_diag_wr_error_accepted_count",
            "o_diag_wr_last_error_accepted_count",
            "o_diag_alloc_meta_entry_count",
            "o_diag_alloc_pbm_entry_count",
            "o_diag_commit_entry_count",
            "o_diag_rollback_entry_count",
            "o_diag_state_raw",
            "o_diag_ptr_head_reserve",
            "o_diag_ptr_head_commit",
            "o_diag_ptr_tail",
            "o_diag_buffer_usage",
            "i_wr_valid && !o_wr_ready",
            "i_wr_valid && o_wr_ready",
            "i_wr_valid && o_wr_ready && i_wr_last",
            "i_wr_valid && o_wr_ready && i_wr_error",
            "i_wr_valid && o_wr_ready && i_wr_last && i_wr_error",
            "state != ALLOC_META && next_state == ALLOC_META",
            "state != ALLOC_PBM && next_state == ALLOC_PBM",
            "state != COMMIT && next_state == COMMIT",
            "state != ROLLBACK && next_state == ROLLBACK",
        ):
            self.assertIn(token, pbm_text)

        for token in (
            "counter_pbm_wr_valid_cycles_q",
            "counter_pbm_wr_ready_high_cycles_q",
            "counter_pbm_valid_not_ready_cycles_q",
            "counter_pbm_wr_accept_cycles_q",
            "counter_pbm_wr_last_accepted_count_q",
            "counter_pbm_wr_error_accepted_count_q",
            "counter_pbm_wr_last_error_accepted_count_q",
            "counter_pbm_alloc_meta_entry_count_q",
            "counter_pbm_alloc_pbm_entry_count_q",
            "counter_pbm_commit_entry_count_q",
            "counter_pbm_rollback_entry_count_q",
            "counter_pbm_wr_valid_cycles_shadow_q",
            "counter_pbm_buffer_usage_shadow_q",
            ".o_diag_wr_valid_cycles(",
            ".o_diag_wr_ready_high_cycles(",
            ".o_diag_valid_not_ready_cycles(",
            ".o_diag_wr_accept_cycles(",
            ".o_diag_wr_last_accepted_count(",
            ".o_diag_wr_error_accepted_count(",
            ".o_diag_wr_last_error_accepted_count(",
            ".o_diag_alloc_meta_entry_count(",
            ".o_diag_alloc_pbm_entry_count(",
            ".o_diag_commit_entry_count(",
            ".o_diag_rollback_entry_count(",
            ".o_diag_state_raw(",
            ".o_diag_ptr_head_reserve(",
            ".o_diag_ptr_head_commit(",
            ".o_diag_ptr_tail(",
            ".o_diag_buffer_usage(",
            ".i_counter_pbm_wr_valid_cycles(",
            ".i_counter_pbm_buffer_usage(",
        ):
            self.assertIn(token, subsystem_text)

    def test_shadow_mirror_release_contract(self):
        build_app = BUILD_APP.read_text(encoding="ascii")
        build_boot = BUILD_BOOT.read_text(encoding="ascii")
        generate_platform = GENERATE_PLATFORM.read_text(encoding="ascii")
        export_tcl = EXPORT_TCL.read_text(encoding="ascii")
        deploy = DEPLOY.read_text(encoding="ascii")
        readme = READ_ME.read_text(encoding="ascii")
        gateway_text = GATEWAY_C.read_text(encoding="ascii")
        gateway_header = GATEWAY_H.read_text(encoding="ascii")

        for token in (
            "ax7020_udp_gateway_shadow_mirror_app",
            "UDP_GATEWAY_ENABLE_SHADOW_MIRROR=1",
            "udp_crypto_gateway.c",
            "platform.c",
            "dma_mvp_ps_driver_ref.c",
            "export_udp_gateway_shadow_mirror_xsa.ps1",
            "udp_gateway_shadow_mirror_wrapper.xsa",
            "udp_gateway_shadow_mirror_wrapper.bit",
            "ax7020_udp_gateway_shadow_mirror_app.elf",
            "ax7020_udp_gateway_shadow_mirror",
            "legacyGatewayBspDir",
            "legacyGatewayLwipSrcDir",
            "legacyGatewayBspProcessorRoot",
            "legacyGatewayBspIncludeDir",
            "legacyGatewayBspLibDir",
            "legacyGatewayExportLwipLib",
            "Resolve-GnuMakePath",
            "Update-LegacyLwipLibrary",
            'Join-Path $VitisRoot "gnuwin\\bin\\make.exe"',
            '$makeArgs[3] = "clean"',
            '$makeArgs[3] = "libs"',
            'Failed to clean legacy lwIP objects under $LegacyGatewayLwipSrcDir',
            'Failed to rebuild legacy lwIP BSP library under $LegacyGatewayLwipSrcDir',
            'Copy-Item -Path $lwipLib -Destination $LegacyGatewayExportLwipLib -Force',
            "liblwip4.a",
        ):
            self.assertIn(token, build_app + build_boot)

        self.assertNotIn("dma_gateway_hybrid_wrapper.xsa", build_boot)
        self.assertNotIn("dma_gateway_hybrid_wrapper.bit", build_boot)
        for token in (
            "ax7020_udp_gateway_shadow_mirror_platform_xsct\\workspace",
            'PlatformName = "ax7020_udp_gateway_shadow_mirror_platform"',
            "Env:\\UDP_GATEWAY_SHADOW_MIRROR_EXPORT_DRY_RUN",
            "Shadow mirror XSA export returned without generating",
            "function Resolve-ShadowFsblFallback",
            "Resolve-ShadowFsblFallback -Workspace $workspace",
            "function Resolve-ShadowBitstream",
            'Join-Path $Workspace "HCS_SOC.runs\\impl_1\\udp_gateway_shadow_mirror_wrapper.bit"',
            'Join-Path $Workspace "udp_gateway_shadow_mirror_wrapper.bit"',
            "Resolve-ShadowBitstream -XsaExtractDir $xsaExtractDir -Workspace $workspace",
        ):
            self.assertIn(token, build_boot)

        for token in (
            'Join-Path $workspace "ax7020_udp_gateway_shadow_mirror_platform_xsct\\workspace"',
            "platform create -name $platform_name -hw $xsa_path -proc ps7_cortexa9_0 -os standalone",
            "platform generate",
            '"$PlatformName\\zynq_fsbl\\zynq_fsbl_bsp\\ps7_cortexa9_0"',
            "zynq_fsbl_bsp",
            "make.exe",
            "Makefile",
            "include\\xparameters.h",
            "libxil.a",
            "fsbl.elf",
        ):
            self.assertIn(token, generate_platform)
        for token in (
            "crypto_accel_axi",
            "rtl/core/crypto_axi/crypto_accel_axi.v",
            "rtl/core/crypto_axi/crypto_accel_axi_slave_lite_v1_0_S00_AXI.v",
            "rtl/top/udp_gateway_shadow_ctrl_csr.sv",
            "rtl/top/udp_gateway_shadow_inject_path.sv",
            "udp_gateway_shadow_mirror_wrapper",
            'set source_bd_name "dma_gateway_hybrid"',
            "CONFIG.NUM_MI {3}",
            "CONFIG.SHADOW_INJECT_ONLY {1}",
        ):
            self.assertIn(token, export_tcl)

        self.assertNotIn("force_auto_compile_order", export_tcl)
        self.assertNotIn("proc enable_shadow_wrapper_manual_compile_order {}", export_tcl)
        self.assertNotIn("set_property source_mgmt_mode None [current_project]", export_tcl)
        self.assertIn("update_compile_order -fileset sources_1", export_tcl)
        self.assertIn("lock_shadow_wrapper_top", export_tcl)
        self.assertIn("bootgen -read", build_boot)
        self.assertIn('Join-Path $workspace "sd_boot\\ax7020_udp_gateway_shadow_mirror"', build_boot)
        self.assertIn('ax7020_udp_gateway_shadow_mirror_app.elf', build_boot)
        self.assertIn('Join-Path $workspace "sd_boot\\ax7020_udp_gateway_shadow_mirror"', deploy)
        self.assertIn('Join-Path $sdDriveRoot "BOOT.BIN"', deploy)

        for token in (
            "UDP gateway shadow mirror image",
            "Shadow First",
            "PS Mirror",
            "Sticky Halt",
            "Board performance capture:",
            "board_bench_report.json",
            "board_bench_summary.md",
            "BENCH capture is control-plane only.",
            "UDP crypto gateway started @ ports 4660(AES) 4661(SM4) 4662(CTRL)",
            "Combined live direct crypto + hybrid DMA shadow hardware line.",
            "C85DDC649E523FB03863CB2B9C842E434E173EE546BDB1FCADC56EB467507AD3",
            "Expected UART pass criteria:",
            "LIVE_CTRL PASS",
            "LIVE_AES PASS",
            "LIVE_SM4 PASS",
            "SHADOW_AES PASS",
            "SHADOW_SM4 PASS",
            "SHADOW_INVALID_SKIP PASS",
            "Shadow DMA poll timeout enters HALTED.",
            "UDP gateway shadow mirror PASS",
        ):
            self.assertIn(token, readme)

        for token in (
            "g_shadow_payload_pool",
            "GATEWAY_SHADOW_RUN_HALTED",
            "GATEWAY_SHADOW_HALT_REASON_POLL_TIMEOUT",
            "memcpy(g_shadow_payload_pool[payload_slot_idx], payload_src, payload_len);",
            "gateway_shadow_submit_live_mirror(",
            "gateway_shadow_service();",
            "SHADOW_INVALID_SKIP PASS",
            "SHADOW_TIMEOUT_HALT PASS",
            "LIVE_CTRL PASS",
            "LIVE_AES PASS",
            "LIVE_SM4 PASS",
            "UDP gateway shadow mirror PASS",
        ):
            self.assertIn(token, gateway_text)

        self.assertIn("int start_application(void);", gateway_header)
        self.assertIn("int transfer_data(void);", gateway_header)

        job_block = _extract_shadow_job_struct(gateway_text)
        self.assertNotIn("struct pbuf *", job_block)
        self.assertNotIn("const uint8_t *payload;", job_block)

    def test_shadow_mirror_build_scripts_default_to_classic_capable_2023_1_vitis(self):
        build_app = BUILD_APP.read_text(encoding="ascii")
        build_boot = BUILD_BOOT.read_text(encoding="ascii")
        generate_platform = GENERATE_PLATFORM.read_text(encoding="ascii")

        for token in (
            '[string]$VitisRoot = "D:\\VIVADO\\Vitis\\2023.1"',
            '[string]$XsctBat = "D:\\VIVADO\\Vitis\\2023.1\\bin\\xsct.bat"',
        ):
            self.assertIn(token, build_boot)

        self.assertIn('[string]$VitisRoot = "D:\\VIVADO\\Vitis\\2023.1"', build_app)
        self.assertIn('[string]$XsctBat = "D:\\VIVADO\\Vitis\\2023.1\\bin\\xsct.bat"', generate_platform)
        self.assertIn('data\\embeddedsw-sdt\\scripts\\specs\\arm\\Xilinx.spec', build_app)

        for script_text in (build_app, build_boot, generate_platform):
            self.assertNotIn("D:\\Xilinx\\Vitis\\2024.1", script_text)

        self.assertIn('[string]$VivadoBat = "D:\\Xilinx\\Vivado\\2024.1\\bin\\vivado.bat"', build_boot)

    def test_shadow_export_reopens_project_after_direct_ooc_runs_before_top_flow(self):
        export_tcl = EXPORT_TCL.read_text(encoding="ascii")

        for token in (
            "proc reopen_shadow_project {project_file}",
            "open_project -quiet $project_file",
            "set current_proj [current_project -quiet]",
            'error "failed to reopen project after direct OOC runs: $project_file"',
            "reopen_shadow_project $project_file",
            "run_manual_shadow_top_flow $workspace_root $runs_root $out_xsa",
        ):
            self.assertIn(token, export_tcl)

        self.assertLess(
            export_tcl.index("reopen_shadow_project $project_file"),
            export_tcl.index("run_manual_shadow_top_flow $workspace_root $runs_root $out_xsa"),
        )

    def test_shadow_mirror_release_includes_cbc_readiness_notes(self):
        text = READ_ME.read_text(encoding="ascii")

        self.assertIn("IV[16B] + DATA[16B * N]", text)
        self.assertIn("No AXI-Lite per-packet IV programming", text)
        self.assertIn("CBC single-flow theoretical ceiling", text)

    def test_shadow_app_build_prefers_legacy_uart_headers_before_toolchain_fsbl_headers(self):
        build_app = BUILD_APP.read_text(encoding="ascii")

        legacy_include_index = build_app.index(
            'if ((Test-Path $legacyGatewayBspIncludeDir) -and (Test-Path (Join-Path $legacyGatewayBspIncludeDir "netif\\xadapter.h"))) {'
        )
        toolchain_include_index = build_app.index(
            'if ((Test-Path $libraryIncludeDir) -and ($libraryIncludeDir -ne $includeDir)) {'
        )

        self.assertLess(
            legacy_include_index,
            toolchain_include_index,
            "Legacy BSP headers should be added before toolchain/FSBL headers so UART driver headers do not come from zynq_fsbl_bsp first",
        )

    def test_shadow_app_build_supports_direct_platform_lwip_header_roots(self):
        build_app = BUILD_APP.read_text(encoding="ascii")

        for token in (
            "function Get-ShadowLwipIncludeDirs",
            'Get-ChildItem -Path (Join-Path $ApiBspRoot "libsrc") -Directory -Filter "lwip213_v*"',
            'Join-Path $lwipRoot.FullName "src\\contrib\\ports\\xilinx\\include"',
            'Join-Path $lwipRoot.FullName "src\\lwip-2.1.3\\src\\include"',
            '$platformLwipIncludeDirs = Get-ShadowLwipIncludeDirs -ApiBspRoot $PlatformSwDir',
            '$includeDirs += $platformLwipIncludeDir',
            'Join-Path $workspace "tmp_hsi_standalone_bsp_lwip\\ps7_cortexa9_0"',
            '$fallbackShadowLwipIncludeDirs = Get-ShadowLwipIncludeDirs -ApiBspRoot $fallbackShadowLwipApiBspRoot',
            '$includeDirs += $fallbackShadowLwipIncludeDir',
        ):
            self.assertIn(token, build_app)

    def test_shadow_mirror_security_check_contract(self):
        text = SECURITY_CHECK.read_text(encoding="ascii")

        timeout_status_args = _extract_control_invocation_expression(text, "STATUS_TIMEOUT_OLD_SESSION")

        for token in (
            "$sessionTimeoutIdleSeconds = 11",
            "$timeoutDataPort = 54223",
            '$replaySeenAfterReplay = [uint32](Get-ControlValue -Output $statusLocked.Output -Key "replay_seen")',
            'throw "Expected replay_seen to latch after replay detection"',
            'Start-Sleep -Seconds $sessionTimeoutIdleSeconds',
            '$replyAfterTimeout = Send-TestUdpPacket -LocalPort $timeoutDataPort -RemotePort 4660',
            'throw "Timed-out session unexpectedly received data-plane reply"',
            'throw "Expected STATUS_TIMEOUT_OLD_SESSION to return NO_SESSION"',
            '$timeoutSeenAfterTimeoutReauth = [uint32](Get-ControlValue -Output $statusAfterTimeoutReauth.Output -Key "timeout_seen")',
            '$reauthSeenAfterTimeoutReauth = [uint32](Get-ControlValue -Output $statusAfterTimeoutReauth.Output -Key "reauth_seen")',
            'throw "Expected timeout_seen to clear after timeout reauthorization"',
            'throw "Expected reauth_seen to latch after timeout reauthorization"',
            'Write-Host ("replay_seen_after_replay={0}" -f $replaySeenAfterReplay)',
            'Write-Host ("timeout_seen_after_timeout_reauth={0}" -f $timeoutSeenAfterTimeoutReauth)',
            'Write-Host ("reauth_seen_after_timeout_reauth={0}" -f $reauthSeenAfterTimeoutReauth)',
        ):
            self.assertIn(token, text)

        self.assertIn('@("--expect-status", "8")', timeout_status_args)
        self.assertIn('@("status")', timeout_status_args)
        self.assertIn("$timedOutSessionBindingArgs", timeout_status_args)

    def test_shadow_mirror_acl_check_contract(self):
        text = ACL_CHECK.read_text(encoding="ascii")

        for token in (
            '$aclHitSeenAfterSend = [uint32](Get-ControlValue -Output $statusAfterSend.Output -Key "acl_hit_seen")',
            '$aclHitSeenAfterDrop = [uint32](Get-ControlValue -Output $statusAfterDrop.Output -Key "acl_hit_seen")',
            'Expected acl_hit_seen=1 when last_drop_reason reports ACL drop',
            'Write-Host ("acl_hit_seen_after_send={0}" -f $aclHitSeenAfterSend)',
            'Write-Host ("acl_hit_seen_after_drop={0}" -f $aclHitSeenAfterDrop)',
        ):
            self.assertIn(token, text)

    def test_shadow_mirror_boot_image_is_three_stage(self):
        payload = _extract_boot_payload(BOOT_BIF)
        bootgen_read = BOOTGEN_READ.read_text(encoding="ascii")

        self.assertEqual(len(payload), 3)
        self.assertTrue(payload[0].startswith("[bootloader] "))
        self.assertIn("udp_gateway_shadow_mirror_wrapper.bit", payload[1])
        self.assertIn("ax7020_udp_gateway_shadow_mirror_app.elf", payload[2])
        self.assertIn("fsbl.elf", bootgen_read)
        self.assertIn("udp_gateway_shadow_mirror_wrapper.bit", bootgen_read)
        self.assertIn("ax7020_udp_gateway_shadow_mirror_app.elf", bootgen_read)

    def test_shadow_mirror_performance_closure_assets(self):
        perf_check = PERF_CHECK.read_text(encoding="ascii")
        acl_check = ACL_CHECK.read_text(encoding="ascii")
        hybrid_proof_app = HYBRID_PROOF_APP.read_text(encoding="ascii")
        hybrid_proof_build = HYBRID_PROOF_BUILD_BOOT.read_text(encoding="ascii")
        hybrid_proof_run = HYBRID_PROOF_RUN.read_text(encoding="ascii")
        bench_script = BENCH_SCRIPT.read_text(encoding="utf-8")
        thesis_data = THESIS_DATA.read_text(encoding="utf-8")
        gateway_text = GATEWAY_C.read_text(encoding="ascii")

        for token in (
            "run_ax7020_udp_gateway_shadow_mirror_performance_check.ps1",
            "day21_performance_benchmark.py",
            "--bench-ip",
            "--source-ip",
            "--repeats",
            "doc\\reports\\board_benchmarks",
            "UART capture started. Log path:",
            "LIVE_CTRL PASS",
            "$requiredPassLines",
            "$missingPassLines",
            "ConvertFrom-Json",
            "avg_speedup",
            "Performance target not met",
            'Write-Warning ("UART log is missing supplemental performance evidence lines:',
        ):
            self.assertIn(token, perf_check)

        self.assertNotIn('"SHADOW_AES PASS"', perf_check)
        self.assertNotIn('"SHADOW_SM4 PASS"', perf_check)
        self.assertNotIn('"UDP gateway shadow mirror PASS"', perf_check)
        self.assertNotIn('throw ("UART log is missing required performance evidence lines:', perf_check)
        self.assertNotIn(
            '"UDP crypto gateway started @ ports 4660(AES) 4661(SM4) 4662(CTRL)",' + "\n    \"LIVE_CTRL PASS\"",
            perf_check,
        )

        for token in (
            "run_ax7020_udp_gateway_shadow_mirror_acl_check.ps1",
            "udp_crypto_control.py",
            "hello",
            "set-key",
            "acl-clear",
            "acl-write",
            "acl-status",
            "status",
            "acl_drop_count",
            "ACL counter did not increase after sending a blocked packet",
            "UART capture started. Log path:",
            "LIVE_CTRL PASS",
            "ACL board check completed",
        ):
            self.assertIn(token, acl_check)

        for token in (
            "HYBRID_RING_ENTRY_COUNT 2048u",
            "HYBRID_DEFAULT_BENCH_REPEATS 1000u",
            "HYBRID_BENCH_LENGTH_COUNT 5u",
            "g_hybrid_bench_lengths[HYBRID_BENCH_LENGTH_COUNT] = { 16u, 32u, 128u, 512u, 1472u }",
            "PROOF_CONFIG repeats=",
            "PROOF_ROW algo=%s length=%u repeats=%u sw_us=%u hw_us=%u",
            "PROOF_TIMEOUT_DIAG algo=%s length=%u",
            "PROOF_AES PASS records=%u",
            "PROOF_SM4 PASS records=%u",
            "DMA gateway hybrid perf proof PASS",
        ):
            self.assertIn(token, hybrid_proof_app)

        for token in (
            "ax7020_dma_gateway_hybrid_perf_proof_app",
            "ax7020_dma_gateway_hybrid_perf_proof",
            "$readmeDest = Join-Path $OutputDir \"readme.txt\"",
            "[System.String]::Equals",
            "StringComparison]::OrdinalIgnoreCase",
        ):
            self.assertIn(token, hybrid_proof_build)

        for token in (
            "board_bench_report.json",
            "board_bench_summary.md",
            "--proof-uart-log",
            "PROOF_AES PASS",
            "PROOF_SM4 PASS",
            "DMA gateway hybrid perf proof PASS",
            "UART proof log is missing required PASS lines",
        ):
            self.assertIn(token, hybrid_proof_run)
        self.assertNotIn("--bench-ip", hybrid_proof_run)
        self.assertNotIn("--control-port", hybrid_proof_run)

        for token in (
            "def calculate_board_bench_metrics(",
            "def render_board_bench_markdown(",
            "def write_board_bench_artifacts(",
            "DEFAULT_BENCH_REPEATS = 1000",
            "def parse_stage2_proof_uart_log(",
            "def run_proof_uart_mode(",
            "single_launch_used",
            "doorbell_count",
            "batch_descriptor_count",
            "--proof-uart-log",
            "--algos",
            "board_bench_report.json",
            "board_bench_summary.md",
        ):
            self.assertIn(token, bench_script)

        for token in (
            "Board-first acceptance source:",
            "Current baseline board capture",
            "PS software baseline",
            "Hardware speedup vs PS software",
            "avg_speedup >= 1.0x",
            "16 B / 32 B short-payload rows may remain below 1.0x",
            "Stage 2 SG proof",
            "single-launch",
            "1000 repeats",
        ):
            self.assertIn(token, thesis_data)

        for token in (
            "GATEWAY_CTRL_MSG_BENCH",
            "gateway_run_bench(",
            "gateway_sw_encrypt_buffer(",
            "gateway_hw_encrypt_buffer_sync(",
            "gateway_store_be16(&record[0], current_len);",
            "gateway_store_be_word(&record[4], sw_us);",
            "gateway_store_be_word(&record[8], hw_us);",
        ):
            self.assertIn(token, gateway_text)

    def test_shadow_bench_matrix_board_check_contract(self):
        self.assertTrue(
            BENCH_MATRIX_CHECK.exists(),
            f"Expected benchmark matrix board-check script missing: {BENCH_MATRIX_CHECK}",
        )
        bench_matrix_check = BENCH_MATRIX_CHECK.read_text(encoding="ascii")

        for token in (
            "run_ax7020_udp_gateway_shadow_mirror_bench_matrix.ps1",
            '[switch]$AssumeRunning',
            '[string]$Port = "COM9"',
            '[int]$Baud = 115200',
            '[string]$TargetIp = "192.168.1.20"',
            '[string]$SourceIp = "192.168.1.11"',
            '[int]$BootLeadSeconds = 20',
            '[int]$RequestsPerScenario = 200',
            '[int]$BenchRepeats = 1000',
            'Join-Path $workspace "capture_uart_boot_log.ps1"',
            'Join-Path $repoRoot "scripts\\day21_benchmark_matrix.py"',
            'Join-Path $repoRoot ("doc\\reports\\board_bench_matrix\\shadow_mirror_{0}" -f $stamp)',
            'Start-Process -FilePath "powershell"',
            'Start-Process -FilePath "py.exe"',
            'UART capture started. Log path:',
            'Assuming board is already running; skipping power-cycle prompt and boot wait.',
            'Power-cycle the board now: turn power off for 3 seconds, then power it back on.',
            'Start-Sleep -Seconds $BootLeadSeconds',
            '"--target-ip", $TargetIp',
            '"--source-ip", $SourceIp',
            '"--requests-per-scenario", "$RequestsPerScenario"',
            '"--repeats", "$BenchRepeats"',
            '"--output-dir", $reportDir',
            'bench_matrix_report.json',
            'bench_matrix_summary.md',
            'bench_matrix_results.csv',
        ):
            self.assertIn(token, bench_matrix_check)

    def test_shadow_bench_matrix_board_check_logs_artifact_paths(self):
        bench_matrix_check = BENCH_MATRIX_CHECK.read_text(encoding="ascii")

        for token in (
            '$summaryPath = Join-Path $reportDir "bench_matrix_summary.md"',
            '$jsonPath = Join-Path $reportDir "bench_matrix_report.json"',
            '$csvPath = Join-Path $reportDir "bench_matrix_results.csv"',
            'Write-Host "==== BENCH MATRIX ARTIFACTS ===="',
            'Write-Host ("bench_matrix_report.json: {0}" -f $jsonPath)',
            'Write-Host ("bench_matrix_summary.md: {0}" -f $summaryPath)',
            'Write-Host ("bench_matrix_results.csv: {0}" -f $csvPath)',
        ):
            self.assertIn(token, bench_matrix_check)

    def test_shadow_bench_matrix_board_check_uart_hard_fail_contract(self):
        bench_matrix_check = BENCH_MATRIX_CHECK.read_text(encoding="ascii")
        uart_hard_fail_patterns = _extract_powershell_array_assignment(
            bench_matrix_check,
            "uartHardFailPatterns",
        )

        self.assertIn('"shadow compare fail"', uart_hard_fail_patterns)
        self.assertIn('"SHADOW_FASTPATH FALLBACK"', uart_hard_fail_patterns)
        for token in (
            "UDP gateway shadow mirror image",
            "UDP crypto gateway started @ ports 4660(AES) 4661(SM4) 4662(CTRL)",
            "LIVE_CTRL PASS",
            "LIVE_AES PASS",
            "LIVE_SM4 PASS",
            "SHADOW_AES PASS",
            "SHADOW_SM4 PASS",
            "SHADOW_INVALID_SKIP PASS",
            "UDP gateway shadow mirror PASS",
        ):
            self.assertNotIn(token, uart_hard_fail_patterns)

        self.assertIn('$bootBannerLines = @(', bench_matrix_check)
        self.assertIn('Write-Warning ("UART log is missing supplemental boot banner lines:', bench_matrix_check)
        self.assertNotIn('throw ("UART log is missing required boot banner lines:', bench_matrix_check)
        self.assertIn('throw ("UART log contains hard-fail lines: {0}" -f ($uartHardFailHits -join ", "))', bench_matrix_check)

    def test_shadow_acl_board_check_places_session_binding_args_after_subcommand(self):
        acl_check = ACL_CHECK.read_text(encoding="ascii")
        global_args = _extract_powershell_array_assignment(acl_check, "globalArgs")
        session_binding_args = _extract_powershell_array_assignment(acl_check, "sessionBindingArgs")

        for token in (
            '"--ip"',
            "$TargetIp",
            '"--source-ip"',
            "$SourceIp",
        ):
            self.assertIn(token, global_args)

        for token in (
            '"--session-id"',
            "$sessionId",
            '"--binding-id"',
            "$bindingId",
        ):
            self.assertIn(token, session_binding_args)

        expected_invocations = (
            ("SET_KEY", '"set-key"'),
            ("STATUS", '"status"'),
            ("ACL_CLEAR", '"acl-clear"'),
            ("ACL_WRITE", '"acl-write"'),
            ("ACL_STATUS_BEFORE", '"acl-status"'),
            ("ACL_STATUS_AFTER", '"acl-status"'),
            ("ACL_STATUS", '"acl-status"'),
        )
        for label, command_token in expected_invocations:
            expression = _extract_control_invocation_expression(acl_check, label)
            self.assertLess(expression.index("$globalArgs"), expression.index(command_token))
            self.assertLess(expression.index(command_token), expression.index("$sessionBindingArgs"))

        self.assertNotIn("Blocked ACL packet unexpectedly received a reply", acl_check)

    def test_shadow_board_checks_use_monotonic_control_seq_ids(self):
        for script_path in (ACL_CHECK, FASTPATH_CHECK, SECURITY_CHECK):
            script_text = script_path.read_text(encoding="ascii")
            self.assertIn('$script:ControlSeqId = 0', script_text)
            self.assertIn('function New-SeqArgs', script_text)
            self.assertIn('$script:ControlSeqId += 1', script_text)
            self.assertIn('"--seq-id"', script_text)

    def test_shadow_board_checks_retry_hello_after_boot(self):
        for script_path in (ACL_CHECK, FASTPATH_CHECK, SECURITY_CHECK):
            script_text = script_path.read_text(encoding="ascii")
            self.assertIn('function Invoke-ControlCommandWithRetry', script_text)
            self.assertIn('-RetryCount 10', script_text)
            self.assertIn('-RetryDelaySeconds 1', script_text)
            self.assertIn('-Label "HELLO"', script_text)

    def test_shadow_board_checks_do_not_abort_on_python_stderr(self):
        for script_path in (ACL_CHECK, FASTPATH_CHECK, SECURITY_CHECK, BOARD_CHECK):
            script_text = script_path.read_text(encoding="ascii")
            self.assertIn('Start-Process -FilePath "py.exe"', script_text)
            self.assertIn('-RedirectStandardOutput', script_text)
            self.assertIn('-RedirectStandardError', script_text)
            self.assertNotIn('& py -3 $controlScript @Arguments 2>&1', script_text)

    def test_shadow_acl_board_check_uses_dedicated_blocked_source_port(self):
        acl_check = ACL_CHECK.read_text(encoding="ascii")
        self.assertIn("$blockedSourcePort = 54060", acl_check)
        self.assertIn('"--src-port", "$blockedSourcePort"', acl_check)
        self.assertIn("-LocalPort $blockedSourcePort", acl_check)
        self.assertNotIn("0x1234", acl_check)

    def test_shadow_acl_board_check_collects_status_and_uart_before_throwing(self):
        acl_check = ACL_CHECK.read_text(encoding="ascii")
        self.assertIn('$aclFailureReason = $null', acl_check)
        self.assertIn('-Label "STATUS_AFTER_SEND"', acl_check)
        self.assertIn('acl_counter_delta=', acl_check)
        self.assertIn('if ($aclFailureReason) {', acl_check)
        self.assertIn('throw $aclFailureReason', acl_check)
        self.assertLess(
            acl_check.index('Wait-Process -Id $captureProc.Id'),
            acl_check.index('throw $aclFailureReason'),
        )
        self.assertIn('$requiredPassLines = @(', acl_check)
        self.assertIn('"LIVE_CTRL PASS"', acl_check)
        self.assertNotIn(
            '"UDP crypto gateway started @ ports 4660(AES) 4661(SM4) 4662(CTRL)",' + "\n    \"LIVE_CTRL PASS\"",
            acl_check,
        )

    def test_shadow_acl_board_check_does_not_require_uart_pass_lines_as_hard_gate(self):
        acl_check = ACL_CHECK.read_text(encoding="ascii")

        self.assertIn('$requiredPassLines = @(', acl_check)
        self.assertIn('"LIVE_CTRL PASS"', acl_check)
        self.assertIn('Write-Warning ("UART log is missing supplemental ACL evidence lines:', acl_check)
        self.assertNotIn('throw ("UART log is missing required ACL evidence lines:', acl_check)

    def test_shadow_acl_board_check_asserts_last_drop_reason_acl(self):
        acl_check = ACL_CHECK.read_text(encoding="ascii")

        for token in (
            'Get-ControlValue -Output $statusAfterSend.Output -Key "last_drop_reason"',
            "Expected last_drop_reason to report ACL drop",
        ):
            self.assertIn(token, acl_check)

    def test_shadow_perf_board_check_does_not_require_boot_banner_in_partial_uart_capture(self):
        perf_check = PERF_CHECK.read_text(encoding="ascii")
        self.assertIn('$requiredPassLines = @(', perf_check)
        self.assertIn('"LIVE_CTRL PASS"', perf_check)
        self.assertIn('Write-Warning ("UART log is missing supplemental performance evidence lines:', perf_check)
        self.assertNotIn('throw ("UART log is missing required performance evidence lines:', perf_check)
        self.assertNotIn(
            '"UDP crypto gateway started @ ports 4660(AES) 4661(SM4) 4662(CTRL)",' + "\n    \"LIVE_CTRL PASS\"",
            perf_check,
        )

    def test_shadow_perf_board_check_does_not_abort_on_python_stderr(self):
        perf_check = PERF_CHECK.read_text(encoding="ascii")

        self.assertIn('Start-Process -FilePath "py.exe"', perf_check)
        self.assertIn('-RedirectStandardOutput', perf_check)
        self.assertIn('-RedirectStandardError', perf_check)
        self.assertNotIn('& py -3 @Arguments 2>&1', perf_check)

    def test_hybrid_perf_proof_board_check_does_not_abort_on_python_stderr(self):
        hybrid_proof_run = HYBRID_PROOF_RUN.read_text(encoding="ascii")

        self.assertIn('Start-Process -FilePath "py.exe"', hybrid_proof_run)
        self.assertIn('-RedirectStandardOutput', hybrid_proof_run)
        self.assertIn('-RedirectStandardError', hybrid_proof_run)
        self.assertNotIn('& py -3 $benchScript', hybrid_proof_run)

    def test_shadow_fastpath_board_check_contract(self):
        self.assertTrue(
            FASTPATH_CHECK.exists(),
            f"Expected FastPath board-check script missing: {FASTPATH_CHECK}",
        )
        fastpath_check = FASTPATH_CHECK.read_text(encoding="ascii")

        for token in (
            "run_ax7020_udp_gateway_shadow_mirror_fastpath_board_check.ps1",
            'handoff\\robeieda_porting_pack\\tools\\udp_crypto_control.py',
            "send_udp_crypto_test.py",
            "hello",
            "set-key",
            "LIVE_AES PASS",
            "LIVE_SM4 PASS",
            "SHADOW_FASTPATH PASS",
            "SHADOW_FASTPATH FALLBACK",
            "SHADOW_AES PASS",
            "SHADOW_SM4 PASS",
            "FASTPATH_HIT_COUNT",
            "FASTPATH_FALLBACK_COUNT",
            "TXCAP words=",
            "UART capture started. Log path:",
            "fastpath board check completed",
            "FASTPATH_EVIDENCE_MODE",
            "xsct.bat",
            "mrd -value",
            "--expect-any-reply",
        ):
            self.assertIn(token, fastpath_check)
        self.assertNotIn("--skip-control-session", fastpath_check)

        self.assertNotIn("SHADOW_FASTPATH HIT", fastpath_check)
        self.assertNotIn("derive_binding_aware_expected", fastpath_check)

    def test_shadow_fastpath_board_check_uses_udp_helper_for_live_probes(self):
        fastpath_check = FASTPATH_CHECK.read_text(encoding="ascii")

        for token in (
            '$controlScript = Join-Path $repoRoot "handoff\\robeieda_porting_pack\\tools\\udp_crypto_control.py"',
            '$sendTool = Join-Path $repoRoot "handoff\\robeieda_porting_pack\\tools\\send_udp_crypto_test.py"',
            'Invoke-PythonLogged -Label "AES"',
            'Invoke-PythonLogged -Label "SM4"',
            '"--expect-any-reply"',
            'throw "AES helper failed with exit code $($aesProbe.ExitCode)"',
            'throw "SM4 helper failed with exit code $($sm4Probe.ExitCode)"',
        ):
            self.assertIn(token, fastpath_check)
        self.assertNotIn('"--skip-control-session"', fastpath_check)

    def test_shadow_fastpath_board_check_reports_empty_uart_capture_clearly(self):
        fastpath_check = FASTPATH_CHECK.read_text(encoding="ascii")

        self.assertIn('$uartLines = @(Get-Content $uartLogPath)', fastpath_check)
        self.assertIn("if ($uartLines.Count -eq 0) {", fastpath_check)
        self.assertIn('throw "UART log captured no data; fastpath evidence unavailable"', fastpath_check)

    def test_shadow_fastpath_board_check_supports_xsct_fallback_when_uart_is_unusable(self):
        fastpath_check = FASTPATH_CHECK.read_text(encoding="ascii")

        for token in (
            '[string]$XsctPath = "D:\\Xilinx\\Vitis\\2024.1\\bin\\xsct.bat"',
            'function Invoke-XsctScript',
            'function Get-FastpathCsrSnapshot',
            'FASTPATH_EVIDENCE_MODE=xsct_csr_fallback',
            'if ($AssumeRunning -and $baselineFastpathSnapshot) {',
            'if ($txcapStorageEnabled -and ($hitDelta -ge 2) -and ($fallbackDelta -eq 0)) {',
            'Write-Host ("TXCAP_WORDS_AFTER={0}" -f $txcapWordsAfter)',
        ):
            self.assertIn(token, fastpath_check)

    def test_shadow_security_board_check_contract(self):
        self.assertTrue(
            SECURITY_CHECK.exists(),
            f"Expected security board-check script missing: {SECURITY_CHECK}",
        )
        security_check = SECURITY_CHECK.read_text(encoding="ascii")

        for token in (
            "run_ax7020_udp_gateway_shadow_mirror_security_check.ps1",
            "udp_crypto_control.py",
            "hello",
            "set-key",
            "status",
            "unlock",
            "--expect-status",
            "SECURITY_REPLAY_1",
            "SECURITY_REPLAY_2",
            "SECURITY_REPLAY_3",
            "SET_KEY_LOCKED",
            "STATUS_LOCKED",
            "STATUS_AFTER_LOCKED_DATA",
            "STATUS_AFTER_UNLOCK",
            "SET_KEY_REAUTH",
            "DATA_BEFORE_REAUTH",
            "DATA_AFTER_REAUTH",
            "drop_replay",
            "lock_events",
            "drop_unauthorized",
            'Get-ControlValue -Output $replayResult.Output -Key "status_code"',
            'Get-ControlValue -Output $setKeyLocked.Output -Key "status_code"',
            'Get-ControlValue -Output $statusLocked.Output -Key "locked"',
            'Get-ControlValue -Output $statusAfterUnlock.Output -Key "locked"',
            'Get-ControlValue -Output $statusAfterReauth.Output -Key "authorized_mask"',
            "security board check completed",
        ):
            self.assertIn(token, security_check)

    def test_shadow_security_board_check_places_expect_status_before_subcommand(self):
        security_check = SECURITY_CHECK.read_text(encoding="ascii")

        for label, command_token in (
            ("SECURITY_REPLAY_1", '"status"'),
            ("SECURITY_REPLAY_2", '"status"'),
            ("SECURITY_REPLAY_3", '"status"'),
            ("SET_KEY_LOCKED", '"set-key"'),
        ):
            expression = _extract_control_invocation_expression(security_check, label)
            self.assertLess(expression.index("$globalArgs"), expression.index('"--expect-status"'))
            self.assertLess(expression.index('"--expect-status"'), expression.index(command_token))
            self.assertLess(expression.index(command_token), expression.index("$sessionBindingArgs"))

    def test_shadow_security_board_check_does_not_require_uart_pass_lines_as_hard_gate(self):
        security_check = SECURITY_CHECK.read_text(encoding="ascii")

        self.assertIn('$requiredPassLines = @(', security_check)
        self.assertIn('"LIVE_CTRL PASS"', security_check)
        self.assertIn('"LIVE_AES PASS"', security_check)
        self.assertIn('Write-Warning ("UART log is missing supplemental security evidence lines:', security_check)
        self.assertNotIn('throw ("UART log is missing required security evidence lines:', security_check)

    def test_shadow_security_board_check_asserts_packed_reason_fields(self):
        security_check = SECURITY_CHECK.read_text(encoding="ascii")

        for token in (
            'Get-ControlValue -Output $statusLocked.Output -Key "last_lock_reason"',
            'Get-ControlValue -Output $statusAfterLockedData.Output -Key "last_drop_reason"',
            "Expected last_lock_reason to report replay-threshold lock",
            "Expected last_drop_reason to report unauthorized drop while locked",
        ):
            self.assertIn(token, security_check)

    def test_shadow_security_board_check_can_lock_uart_baud(self):
        security_check = SECURITY_CHECK.read_text(encoding="ascii")

        for token in (
            '[switch]$LockBaud',
            'if ($LockBaud) {',
            '$captureArgs += "-LockBaud"',
        ):
            self.assertIn(token, security_check)

    def test_shadow_board_checks_support_assume_running_mode(self):
        for script_path in (ACL_CHECK, FASTPATH_CHECK, SECURITY_CHECK, PERF_CHECK, BOARD_CHECK):
            script_text = script_path.read_text(encoding="ascii")

            self.assertIn('[switch]$AssumeRunning', script_text)
            self.assertIn('if ($AssumeRunning)', script_text)
            self.assertIn(
                'Assuming board is already running; skipping power-cycle prompt and boot wait.',
                script_text,
            )
        self.assertIn(
            'Power-cycle the board now: turn power off for 3 seconds, then power it back on.',
            script_text,
        )
        self.assertIn('Start-Sleep -Seconds $BootLeadSeconds', script_text)

    def test_shadow_board_check_fails_on_helper_nonzero_exit(self):
        board_check = BOARD_CHECK.read_text(encoding="ascii")

        self.assertIn('$helperFailures = @($results | Where-Object {', board_check)
        self.assertIn("$_.Label -ne 'HELLO'", board_check)
        self.assertIn("$_.ExitCode -ne 0", board_check)
        self.assertIn('if ($helperFailures.Count -gt 0) {', board_check)
        self.assertIn('throw ("Board data-plane helper failed:', board_check)

    def test_shadow_board_check_uses_5s_timeout_for_cold_boot_aes_sm4_probes(self):
        board_check = BOARD_CHECK.read_text(encoding="ascii")

        self.assertGreaterEqual(board_check.count('"--timeout", "5"'), 2)
        self.assertIn('$results += Invoke-PythonLogged -Label "AES"', board_check)
        self.assertIn('$results += Invoke-PythonLogged -Label "SM4"', board_check)

    def test_shadow_soak_check_contract(self):
        self.assertTrue(
            SOAK_CHECK.exists(),
            f"Expected soak board-check script missing: {SOAK_CHECK}",
        )
        soak_check = SOAK_CHECK.read_text(encoding="ascii")

        for token in (
            "run_ax7020_udp_gateway_shadow_mirror_soak_check.ps1",
            '[switch]$AssumeRunning',
            '[switch]$ColdStart',
            '[int]$DurationMinutes = 30',
            '[int]$CycleIntervalSeconds = 15',
            'doc\\reports\\board_soak\\shadow_mirror_',
            'soak_report.json',
            'soak_summary.md',
            'udp_crypto_control.py',
            'send_udp_crypto_test.py',
            '--expect-any-reply',
            'hello',
            'set-key',
            'acl-write',
            'acl-clear',
            'acl-status',
            '--expect-status',
            'Start-Process -FilePath "py.exe"',
            '-RedirectStandardOutput',
            '-RedirectStandardError',
            'Assuming board is already running; skipping power-cycle prompt and boot wait.',
            'if ($ColdStart -and $AssumeRunning)',
            'boot_evidence_found',
            'boot_evidence_mode',
            'boot_evidence_lines',
            'first_control_success_utc',
            'first_data_success_utc',
            'SOAK_RESULT=PASS',
            'SOAK_RESULT=FAIL',
        ):
            self.assertIn(token, soak_check)

    def test_shadow_soak_check_cold_start_prefers_uart_boot_evidence_and_falls_back_to_control_data(self):
        soak_check = SOAK_CHECK.read_text(encoding="ascii")

        self.assertIn('if ($ColdStart) {', soak_check)
        self.assertIn('Power-cycle the board now: turn power off for 3 seconds, then power it back on.', soak_check)
        self.assertIn('UDP gateway shadow mirror image', soak_check)
        self.assertIn('UDP crypto gateway started @ ports 4660(AES) 4661(SM4) 4662(CTRL)', soak_check)
        self.assertIn('Board IP: 192.168.1.20', soak_check)
        self.assertIn('Cold-start UART boot capture was empty; will require control/data fallback evidence.', soak_check)
        self.assertIn('Cold-start UART boot capture missed required boot lines:', soak_check)
        self.assertIn('Finalize-ColdStartEvidence', soak_check)
        self.assertIn('control_data_after_manual_power_cycle', soak_check)
        self.assertIn('throw "Cold-start soak missing both UART boot evidence and post-boot control/data fallback evidence."', soak_check)

    def test_capture_uart_boot_log_tolerates_power_cycle_port_reenumeration(self):
        capture_uart = CAPTURE_UART.read_text(encoding="ascii")

        for token in (
            "function New-UartSerialPort",
            "function Close-UartSerialPort",
            "$serialOpenStopwatch = $null",
            "if (($null -eq $serial) -or (-not $serial.IsOpen)) {",
            "if (($bytes.Count -eq 0) -and $serialOpenStopwatch -and ($serialOpenStopwatch.Elapsed.TotalSeconds -ge 1.0)) {",
            "catch [System.InvalidOperationException]",
            "catch [System.IO.IOException]",
            "catch [System.UnauthorizedAccessException]",
            "Close-UartSerialPort -SerialRef ([ref]$serial)",
        ):
            self.assertIn(token, capture_uart)
        self.assertNotIn('Switching UART capture baud from {0} to {1} after empty probe.', capture_uart)
        self.assertIn("reopen the port so we can latch onto the re-enumerated boot stream.", capture_uart)

    def test_capture_uart_boot_log_auto_detects_baud_and_rejects_gibberish(self):
        capture_uart = CAPTURE_UART.read_text(encoding="ascii")

        for token in (
            "function Get-UartBaudCandidates",
            "function Test-UartCaptureLooksSane",
            "$captureLooksSane = Test-UartCaptureLooksSane -Data $bytes",
            "$sampleCount = [Math]::Min($bytes.Count, 256)",
            "$printableCount = 0",
            "$printableRatio = if ($sampleCount -gt 0)",
            "$baudCandidates = Get-UartBaudCandidates -PreferredBaud $Baud",
            "$activeBaud = $baudCandidates[$currentBaudIndex]",
            "Switching UART capture baud from",
            "DetectedBaud={2} Bytes={3} CaptureLooksSane={4} PrintableRatio={5}",
            '$printableThreshold = 0.85',
            'Write-Warning "Captured UART bytes did not decode as sane printable text; treat UART evidence as unreliable."',
        ):
            self.assertIn(token, capture_uart)

    def test_capture_uart_boot_log_supports_locking_known_baud(self):
        capture_uart = CAPTURE_UART.read_text(encoding="ascii")

        for token in (
            '[switch]$LockBaud',
            'if ($LockBaud) {',
            'return @($PreferredBaud)',
            '$baudCandidates = Get-UartBaudCandidates -PreferredBaud $Baud -LockBaud:$LockBaud',
        ):
            self.assertIn(token, capture_uart)

    def test_capture_uart_boot_log_program_board_uses_shadow_mirror_jtag_runner(self):
        capture_uart = CAPTURE_UART.read_text(encoding="ascii")

        for token in (
            'Join-Path $workspace "run_ax7020_udp_gateway_shadow_mirror_jtag.ps1"',
            'function Resolve-CaptureProgrammerXsctPath',
            '-XsctPath', '$programmerXsctPath',
        ):
            self.assertIn(token, capture_uart)

        self.assertNotIn('Join-Path $workspace "run_board_smoke.ps1"', capture_uart)

    def test_capture_uart_boot_log_normalizes_path_environment_before_program_board_spawn(self):
        capture_uart = CAPTURE_UART.read_text(encoding="ascii")

        for token in (
            'function Normalize-PathEnvironment',
            "$processEnv = [System.Environment]::GetEnvironmentVariables('Process')",
            "[System.Environment]::SetEnvironmentVariable('PATH', $null, 'Process')",
            'Normalize-PathEnvironment',
            '$programProc = Start-Process -FilePath "powershell"',
        ):
            self.assertIn(token, capture_uart)

    def test_capture_uart_boot_log_starts_serial_capture_before_program_board(self):
        capture_uart = CAPTURE_UART.read_text(encoding="ascii")

        for token in (
            '$programProc = $null',
            '$programLaunchStarted = $false',
            'if ($ProgramBoard -and (-not $programLaunchStarted) -and $serial -and $serial.IsOpen) {',
            'Start-Process -FilePath "powershell"',
            'Wait-Process -Id $programProc.Id',
            '==== PROGRAM SCRIPT OUTPUT ====',
        ):
            self.assertIn(token, capture_uart)

    def test_capture_uart_boot_log_refreshes_program_process_before_exit_code_check(self):
        capture_uart = CAPTURE_UART.read_text(encoding="ascii")

        for token in (
            '$programProc.Refresh()',
            '$programExitCode = $programProc.ExitCode',
            '$programSucceeded = ($programOutput -match "JTAG_RUN_DONE")',
            'throw "ProgramBoard runner did not report JTAG_RUN_DONE"',
        ):
            self.assertIn(token, capture_uart)

    def test_send_udp_crypto_test_supports_expect_any_reply_mode(self):
        send_udp_test = SEND_UDP_TEST.read_text(encoding="utf-8")

        for token in (
            '--expect-any-reply',
            'expected_mode = "any_reply"',
            'if args.expect_any_reply:',
            'print("result=PASS")',
        ):
            self.assertIn(token, send_udp_test)

    def test_send_udp_crypto_test_drains_stale_replies_before_send(self):
        send_udp_test = SEND_UDP_TEST.read_text(encoding="utf-8")

        for token in (
            'def drain_stale_replies(',
            'sock.setblocking(False)',
            'sock.recvfrom(4096)',
            'sock.setblocking(True)',
            'drained_packets = drain_stale_replies(sock)',
            'print(f"drained_stale_packets={drained_packets}")',
        ):
            self.assertIn(token, send_udp_test)

    def test_send_udp_crypto_test_only_uses_legacy_expected_without_control_session_or_explicit_expected(self):
        send_udp_test = SEND_UDP_TEST.read_text(encoding="utf-8")

        self.assertIn('if args.expected_reply_hex is not None:', send_udp_test)
        self.assertIn('elif args.expect_timeout:', send_udp_test)
        self.assertIn('elif args.expect_any_reply:', send_udp_test)
        self.assertIn('elif control_client is not None:', send_udp_test)
        self.assertIn('expected_mode = "auto_session_reply"', send_udp_test)
        self.assertIn('elif args.skip_control_session:', send_udp_test)
        self.assertIn('expected_mode = "auto_default_legacy"', send_udp_test)

    def test_send_udp_crypto_test_prefers_binding_aware_expectation_and_drains_stale_udp(self):
        send_udp_test = SEND_UDP_TEST.read_text(encoding="utf-8")

        for token in (
            "def _resolve_expected_reply(",
            "def _drain_socket(",
            "expected_mode = \"auto_session_reply\"",
            "_drain_socket(sock)",
            "reply_from_expected_endpoint=",
            "reply_len_match=",
            "elif args.expected_reply_hex is not None:",
        ):
            self.assertIn(token, send_udp_test)

    def test_shadow_board_check_fails_on_helper_exit_code_and_uses_longer_data_probe_timeout(self):
        board_check = BOARD_CHECK.read_text(encoding="ascii")

        for token in (
            '$results += Invoke-PythonLogged -Label "AES"',
            '$results += Invoke-PythonLogged -Label "SM4"',
            '"--timeout", "5"',
            "if ($results | Where-Object { $_.Label -ne \"HELLO\" -and $_.ExitCode -ne 0 })",
            "throw \"One or more data-plane probes failed.\"",
        ):
            self.assertIn(token, board_check)

    def test_shadow_soak_check_supports_cold_start_mode(self):
        soak_check = SOAK_CHECK.read_text(encoding="ascii")

        for token in (
            '[switch]$ColdStart',
            'if ($ColdStart -and $AssumeRunning)',
            'cold_start',
            'boot_evidence_found',
            'boot_evidence_lines',
            'first_control_success_utc',
            'first_data_success_utc',
            'UDP gateway shadow mirror image',
            'UDP crypto gateway started @ ports 4660(AES) 4661(SM4) 4662(CTRL)',
            'Board IP: 192.168.1.20',
        ):
            self.assertIn(token, soak_check)

    def test_shadow_engineering_evidence_export_contract(self):
        self.assertTrue(
            EVIDENCE_EXPORT.exists(),
            f"Expected engineering evidence exporter missing: {EVIDENCE_EXPORT}",
        )
        self.assertTrue(
            EVIDENCE_EXPORT_TCL.exists(),
            f"Expected engineering evidence Tcl missing: {EVIDENCE_EXPORT_TCL}",
        )

        exporter = EVIDENCE_EXPORT.read_text(encoding="ascii")
        exporter_tcl = EVIDENCE_EXPORT_TCL.read_text(encoding="ascii")

        for token in (
            "export_ax7020_udp_gateway_shadow_mirror_evidence_pack.ps1",
            "export_udp_gateway_shadow_mirror_evidence_pack.tcl",
            'doc\\reports\\engineering_evidence\\shadow_mirror_',
            "engineering_evidence_manifest.json",
            "engineering_evidence_summary.md",
            '[switch]$SkipVivado',
            "udp_gateway_shadow_mirror_wrapper_postroute_physopt.dcp",
            "udp_gateway_shadow_mirror_wrapper_routed.dcp",
            "udp_gateway_shadow_mirror_wrapper_power_routed.rpt",
            "udp_gateway_shadow_mirror_wrapper_timing_summary_postroute_physopted.rpt",
            "udp_gateway_shadow_mirror_wrapper_clock_utilization_routed.rpt",
            "read_vivado_timing_summary.ps1",
            "Get-FileHash -Algorithm SHA256",
            "Engineering evidence pack exported:",
        ):
            self.assertIn(token, exporter)

        for token in (
            "report_utilization",
            "report_timing_summary",
            "report_power",
            "report_clock_utilization",
            "report_route_status",
            "report_drc",
            "report_methodology",
            "report_cdc",
            "report_clock_interaction",
            "Pblock Summary",
            "get_pblocks",
            "report_property -return_string",
        ):
            self.assertIn(token, exporter_tcl)

    def test_shadow_export_tcl_loads_phasec_constraints(self):
        export_tcl = EXPORT_TCL.read_text(encoding="ascii")
        phasec_xdc = SHADOW_PHASEC_XDC.read_text(encoding="ascii")

        self.assertIn("ensure_constraint_source", export_tcl)
        self.assertIn("shadow_mirror_phasec_constraints.xdc", export_tcl)
        self.assertIn("add_files -fileset constrs_1 -norecurse", export_tcl)
        self.assertIn("set_property used_in_synthesis false", export_tcl)
        self.assertIn("set_property used_in_implementation true", export_tcl)

        for token in (
            "create_generated_clock",
            "create_pblock shadow_data_region",
            "create_pblock shadow_ctrl_region",
            "udp_gateway_shadow_mirror_i/crypto_accel_axi_0/inst",
            "udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/i_hybrid_dma",
            "udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_shadow_acl_filter",
            "udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_classifier",
            "udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/gen_shadow_ctrl_csr.u_shadow_ctrl_csr",
            "udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/gen_shadow_inject_only.u_shadow_inject",
            "udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader/s_axil_rdata*",
            "NAME !~ udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader/s_axil_rdata*",
            "set_property IS_SOFT TRUE [get_pblocks shadow_data_region]",
            "set_property IS_SOFT TRUE [get_pblocks shadow_ctrl_region]",
        ):
            self.assertIn(token, phasec_xdc)
        self.assertNotIn("create_pblock live_crypto_region", phasec_xdc)
        self.assertNotIn("set_property IS_SOFT TRUE [get_pblocks live_crypto_region]", phasec_xdc)
        self.assertNotIn("shadow_core_region", phasec_xdc)

    def test_shadow_export_tcl_cleans_stale_raw_bd_artifacts(self):
        export_tcl = EXPORT_TCL.read_text(encoding="ascii")

        for token in (
            "proc remove_orphan_project_file {abs_path}",
            'remove_orphan_project_file [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" "dma_gateway_hybrid_axi3_probe" "dma_gateway_hybrid_axi3_probe.bd"]',
            "set raw_designs [get_bd_designs -quiet $raw_bd_name]",
            "catch {close_bd_design $raw_designs}",
            "catch {remove_files [get_files -quiet $raw_bd]}",
            'set stale_raw_project_files [concat \\',
            '[get_files -quiet [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" $raw_bd_name *]] \\',
            '[get_files -quiet [file join $workspace_root "HCS_SOC.gen" "sources_1" "bd" $raw_bd_name *]] \\',
            'foreach stale_raw_fileset [get_filesets -quiet "${raw_bd_name}_*"] {',
            'catch {delete_fileset $stale_raw_fileset}',
            'foreach stale_raw_run [get_runs -quiet "${raw_bd_name}_*"] {',
            'catch {delete_run $stale_raw_run}',
            'foreach stale_crypto_fileset [get_filesets -quiet "${raw_bd_name}_crypto_accel_axi_0_0*"] {',
            'catch {delete_fileset $stale_crypto_fileset}',
            "set stale_crypto_ip_files [concat \\",
            "[get_files -quiet [file join $workspace_root \"HCS_SOC.gen\" \"sources_1\" \"bd\" $raw_bd_name \"ip\" \"${raw_bd_name}_crypto_accel_axi_0_0*\" *]] \\",
            "catch {remove_files $stale_crypto_ip_files}",
            "[file dirname $raw_bd]",
            "[file join $workspace_root \"HCS_SOC.gen\" \"sources_1\" \"bd\" $raw_bd_name]",
            "file delete -force $stale_path",
        ):
            self.assertIn(token, export_tcl)

    def test_shadow_export_tcl_detaches_inactive_system_bd_and_wrapper_runs(self):
        export_tcl = EXPORT_TCL.read_text(encoding="ascii")

        for token in (
            'remove_orphan_project_file [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" "system" "system.bd"]',
            'set stale_system_bd_files [get_files -quiet [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" "system" *]]',
            'catch {remove_files $stale_system_bd_files}',
            'foreach stale_system_fileset [get_filesets -quiet "system_dma_subsystem_v2_wra_0_0*"] {',
            'catch {delete_fileset $stale_system_fileset}',
            'foreach stale_system_run [get_runs -quiet "system_dma_subsystem_v2_wra_0_0*"] {',
            'catch {delete_run $stale_system_run}',
        ):
            self.assertIn(token, export_tcl)

    def test_shadow_export_tcl_registers_generated_crypto_module_ref_for_synthesis(self):
        export_tcl = EXPORT_TCL.read_text(encoding="ascii")

        for token in (
            'set crypto_ref_synth_wrapper_pattern [file join $workspace_root "HCS_SOC.gen" "sources_1" "bd" $raw_bd_name "ip" "*crypto_accel_axi_0_0*" "synth" "${raw_bd_name}_crypto_accel_axi_0_0.v"]',
            'set stale_crypto_ip_files [concat \\',
            'set crypto_ref_synth_wrappers [glob -nocomplain $crypto_ref_synth_wrapper_pattern]',
            'foreach crypto_ref_synth_wrapper $crypto_ref_synth_wrappers {',
            'add_files -norecurse $crypto_ref_synth_wrapper',
            'set_property used_in_synthesis true $crypto_wrapper_files',
            'set_property used_in_implementation true $crypto_wrapper_files',
            'set_property used_in_simulation false $crypto_wrapper_files',
        ):
            self.assertIn(token, export_tcl)

    def test_shadow_export_tcl_reopens_project_after_generate_target_before_registering_generated_wrappers(self):
        export_tcl = EXPORT_TCL.read_text(encoding="ascii")

        generate_target_idx = export_tcl.index("generate_target all $raw_bd_obj")
        export_ip_idx = export_tcl.index("export_ip_user_files -of_objects $raw_bd_obj -sync -force -quiet")
        reopen_close_idx = export_tcl.index("close_project", export_ip_idx)
        reopen_open_idx = export_tcl.index("open_project -quiet $project_file", reopen_close_idx)
        crypto_wrapper_idx = export_tcl.index("set crypto_ref_synth_wrappers [glob -nocomplain $crypto_ref_synth_wrapper_pattern]")
        reopen_raw_bd_idx = export_tcl.index("set raw_bd_obj [lindex [get_files -quiet $raw_bd] 0]", reopen_open_idx)
        reopen_bd_design_idx = export_tcl.index("open_bd_design $raw_bd", reopen_open_idx)

        self.assertLess(generate_target_idx, export_ip_idx)
        self.assertLess(export_ip_idx, reopen_close_idx)
        self.assertLess(reopen_close_idx, reopen_open_idx)
        self.assertLess(reopen_open_idx, reopen_raw_bd_idx)
        self.assertLess(reopen_raw_bd_idx, reopen_bd_design_idx)
        self.assertLess(reopen_bd_design_idx, crypto_wrapper_idx)

    def test_shadow_export_tcl_cleans_shadow_run_dirs_and_generates_scripts_before_launch(self):
        export_tcl = EXPORT_TCL.read_text(encoding="ascii")

        for token in (
            'set runs_root [file join $workspace_root "HCS_SOC.runs"]',
            'proc lock_shadow_wrapper_top {} {',
            'proc run_manual_shadow_top_flow {workspace_root runs_root out_xsa} {',
            'foreach stale_run_dir [glob -nocomplain [file join $runs_root "${raw_bd_name}_*"]] {',
            'file delete -force $stale_run_dir',
            'set src_fileset [get_filesets sources_1]',
            'set_property top_auto_set 0 $src_fileset',
            'set_property top udp_gateway_shadow_mirror_wrapper $src_fileset',
            'lock_shadow_wrapper_top',
            'set direct_ooc_runs [create_ip_run $raw_bd_obj]',
            'create_ip_run did not return any shadow-mirror OOC runs',
            'launch_runs $shadow_run_name -scripts_only',
            'set run_script [find_single_run_tcl [file join $runs_root $shadow_run_name]]',
            'write_checkpoint -force $synth_dcp',
            'write_checkpoint -force $routed_dcp',
            'write_bitstream -force $bit_path',
            'file copy -force $bit_path $root_bit',
            'write_hw_platform -fixed -force -file $out_xsa',
            'run_manual_shadow_top_flow $workspace_root $runs_root $out_xsa',
        ):
            self.assertIn(token, export_tcl)

        self.assertNotIn('set shadow_child_runs [get_runs -quiet "${raw_bd_name}_*_synth_1"]', export_tcl)
        self.assertNotIn('launch_runs $shadow_child_runs -scripts_only', export_tcl)
        self.assertNotIn('launch_runs synth_1 -scripts_only', export_tcl)
        self.assertIn('close_project', export_tcl)
        self.assertIn('open_project -quiet $project_file', export_tcl)
        self.assertLess(
            export_tcl.index('foreach stale_raw_run [get_runs -quiet "${raw_bd_name}_*"] {'),
            export_tcl.index('close_project'),
        )
        self.assertLess(
            export_tcl.index('close_project'),
            export_tcl.index('foreach src_info {'),
        )
        self.assertLess(
            export_tcl.index('open_project -quiet $project_file', export_tcl.index('close_project') + 1),
            export_tcl.index('foreach src_info {'),
        )
        self.assertLess(
            export_tcl.index('close_project'),
            export_tcl.index('open_bd_design $source_bd'),
        )
        self.assertLess(
            export_tcl.index('export_ip_user_files -of_objects $raw_bd_obj -sync -force -quiet'),
            export_tcl.index('close_project', export_tcl.index('export_ip_user_files -of_objects $raw_bd_obj -sync -force -quiet')),
        )
        self.assertLess(
            export_tcl.index('close_project', export_tcl.index('export_ip_user_files -of_objects $raw_bd_obj -sync -force -quiet')),
            export_tcl.index('open_project -quiet $project_file', export_tcl.index('close_project', export_tcl.index('export_ip_user_files -of_objects $raw_bd_obj -sync -force -quiet'))),
        )
        self.assertLess(
            export_tcl.index('open_project -quiet $project_file', export_tcl.index('close_project', export_tcl.index('export_ip_user_files -of_objects $raw_bd_obj -sync -force -quiet'))),
            export_tcl.index('set crypto_ref_synth_wrappers [glob -nocomplain $crypto_ref_synth_wrapper_pattern]'),
        )


if __name__ == "__main__":
    unittest.main()
