import pathlib
import re
import unittest
import importlib.util


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
GATEWAY_C = (
    REPO_ROOT
    / "HCS_SOC"
    / "vitis_2023_udp_gateway_ws_2"
    / "ax7020_udp_gateway_app"
    / "src"
    / "udp_crypto_gateway.c"
)
SHADOW_MAIN_C = (
    REPO_ROOT
    / "HCS_SOC"
    / "ax7020_udp_gateway_shadow_mirror_app"
    / "src"
    / "main.c"
)
DMA_DRIVER_H = REPO_ROOT / "HCS_SOC" / "dma_mvp_ps_driver_ref.h"
DMA_DRIVER_C = REPO_ROOT / "HCS_SOC" / "dma_mvp_ps_driver_ref.c"
CRYPTO_DMA_SUBSYSTEM = REPO_ROOT / "rtl" / "top" / "crypto_dma_subsystem.sv"
DMA_FETCHER_SV = REPO_ROOT / "rtl" / "core" / "dma" / "dma_desc_fetcher.sv"
DMA_MASTER_ENGINE = REPO_ROOT / "rtl" / "core" / "dma" / "dma_master_engine.sv"
DMA_CRYPTO_SOURCE_READER = REPO_ROOT / "rtl" / "core" / "dma" / "dma_crypto_source_reader.sv"
DMA_RAW_COPY_ENGINE = REPO_ROOT / "rtl" / "core" / "dma" / "dma_raw_copy_engine.sv"
DMA_AXIS_FIFO_WRAPPER = REPO_ROOT / "rtl" / "core" / "dma" / "dma_axis_fifo_wrapper.sv"
AXIS_PACKET_FIFO_BRAM = REPO_ROOT / "rtl" / "core" / "dma" / "axis_packet_fifo_bram.sv"
SHADOW_CTRL_CSR = REPO_ROOT / "rtl" / "top" / "udp_gateway_shadow_ctrl_csr.sv"
SHADOW_WRAPPER = REPO_ROOT / "rtl" / "top" / "dma_gateway_hybrid_board_wrapper.v"
DEVICE_DNA_READER = REPO_ROOT / "rtl" / "security" / "device_dna_reader.sv"
ACL_PACKET_FILTER = REPO_ROOT / "rtl" / "security" / "acl_packet_filter.sv"
SHADOW_EXPORT_TCL = REPO_ROOT / "HCS_SOC" / "export_udp_gateway_shadow_mirror_xsa.tcl"
SHADOW_PHASEC_XDC = REPO_ROOT / "constraints" / "shadow_mirror_phasec_constraints.xdc"
UDP_CONTROL_PY = REPO_ROOT / "HCS_SOC" / "udp_crypto_control.py"
SEND_UDP_TEST = (
    REPO_ROOT
    / "handoff"
    / "robeieda_porting_pack"
    / "tools"
    / "send_udp_crypto_test.py"
)
HANDOFF_UDP_CONTROL_PY = REPO_ROOT / "handoff" / "robeieda_porting_pack" / "tools" / "udp_crypto_control.py"
LEGACY_LWIP_XADAPTER_C = (
    REPO_ROOT
    / "HCS_SOC"
    / "vitis_2023_udp_gateway_ws_2"
    / "ax7020_udp_gateway_platform"
    / "ps7_cortexa9_0"
    / "standalone_domain"
    / "bsp"
    / "ps7_cortexa9_0"
    / "libsrc"
    / "lwip213_v1_0"
    / "src"
    / "contrib"
    / "ports"
    / "xilinx"
    / "netif"
    / "xadapter.c"
)


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


def _load_python_module(module_path: pathlib.Path, module_name: str):
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"Unable to load module from {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestUdpGatewayShadowRuntimeContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = GATEWAY_C.read_text(encoding="ascii")
        cls.shadow_main_text = SHADOW_MAIN_C.read_text(encoding="ascii")
        cls.dma_driver_h = DMA_DRIVER_H.read_text(encoding="ascii")
        cls.dma_driver_c = DMA_DRIVER_C.read_text(encoding="ascii")
        cls.crypto_dma_subsystem = CRYPTO_DMA_SUBSYSTEM.read_text(encoding="ascii")
        cls.dma_fetcher = DMA_FETCHER_SV.read_text(encoding="ascii")
        cls.dma_master_engine = (
            DMA_MASTER_ENGINE.read_text(encoding="ascii")
            if DMA_MASTER_ENGINE.exists()
            else ""
        )
        cls.dma_crypto_source_reader = (
            DMA_CRYPTO_SOURCE_READER.read_text(encoding="ascii")
            if DMA_CRYPTO_SOURCE_READER.exists()
            else ""
        )
        cls.dma_raw_copy_engine = (
            DMA_RAW_COPY_ENGINE.read_text(encoding="ascii")
            if DMA_RAW_COPY_ENGINE.exists()
            else ""
        )
        cls.dma_axis_fifo_wrapper = (
            DMA_AXIS_FIFO_WRAPPER.read_text(encoding="ascii")
            if DMA_AXIS_FIFO_WRAPPER.exists()
            else ""
        )
        cls.axis_packet_fifo_bram = (
            AXIS_PACKET_FIFO_BRAM.read_text(encoding="ascii")
            if AXIS_PACKET_FIFO_BRAM.exists()
            else ""
        )
        cls.shadow_ctrl_csr = SHADOW_CTRL_CSR.read_text(encoding="ascii")
        cls.shadow_wrapper = SHADOW_WRAPPER.read_text(encoding="ascii")
        cls.device_dna_reader = (
            DEVICE_DNA_READER.read_text(encoding="ascii")
            if DEVICE_DNA_READER.exists()
            else ""
        )
        cls.acl_packet_filter = (
            ACL_PACKET_FILTER.read_text(encoding="ascii")
            if ACL_PACKET_FILTER.exists()
            else ""
        )
        cls.shadow_export_tcl = SHADOW_EXPORT_TCL.read_text(encoding="ascii")
        cls.shadow_phasec_xdc = (
            SHADOW_PHASEC_XDC.read_text(encoding="ascii")
            if SHADOW_PHASEC_XDC.exists()
            else ""
        )
        cls.udp_control_py = UDP_CONTROL_PY.read_text(encoding="utf-8")
        cls.send_udp_test = SEND_UDP_TEST.read_text(encoding="utf-8")
        cls.handoff_udp_control_py = HANDOFF_UDP_CONTROL_PY.read_text(encoding="utf-8")

    def test_uart_gateway_uses_driver_header_without_reincluding_hw_header(self):
        self.assertIn('#include "xuartps.h"', self.text)
        self.assertNotIn('#include "xuartps_hw.h"', self.text)

    def test_legacy_lwip_eth_link_detect_handles_all_known_xemac_types(self):
        xadapter_text = LEGACY_LWIP_XADAPTER_C.read_text(encoding="ascii")
        link_detect = _extract_function_block(xadapter_text, "void eth_link_detect(struct netif *netif)")

        self.assertIn("case xemac_type_unknown:", link_detect)
        self.assertIn("case xemac_type_xps_ll_temac:", link_detect)

    def test_shadow_job_uses_slot_metadata_not_raw_pointers(self):
        text = self.text
        pattern = re.compile(
            r"typedef\s+struct\s*\{.*?\}\s*gateway_shadow_job_t;",
            re.S,
        )
        match = pattern.search(text)
        self.assertIsNotNone(match, "gateway_shadow_job_t definition missing")
        block = match.group(0)

        for token in (
            "const uint8_t *payload",
            "uint8_t *payload",
            "struct pbuf *",
            "pbuf->payload",
            "local_payload",
        ):
            self.assertNotIn(token, block)

        for token in (
            "payload_slot_idx",
            "payload_len",
            "expected_actual_len",
            "state",
            "status",
        ):
            self.assertIn(token, block)

    def test_shadow_payload_pool_is_static_and_bounded(self):
        text = self.text
        for token in (
            "static uint8_t g_shadow_payload_pool[",
            "[GATEWAY_SHADOW_QUEUE_DEPTH][GATEWAY_MAX_PAYLOAD_BYTES]",
            "static gateway_shadow_job_t g_shadow_queue[",
            "GATEWAY_SHADOW_QUEUE_DEPTH",
            "GATEWAY_MAX_PAYLOAD_BYTES",
        ):
            self.assertIn(token, text)

    def test_shadow_submit_mirror_deep_copies_payload(self):
        text = self.text
        block = _extract_function_block(text, "static int gateway_shadow_submit_live_mirror(")

        for token in (
            "memcpy(g_shadow_payload_pool",
            "payload_src",
            "payload_len",
            "payload_slot_idx",
        ):
            self.assertIn(token, block)

        for token in (
            "struct pbuf *",
            "local_payload",
            "pbuf->payload",
        ):
            self.assertNotIn(token, block)

    def test_shadow_submit_mirror_captures_live_remote_tuple(self):
        text = self.text
        submit_block = _extract_function_block(text, "static int gateway_shadow_submit_live_mirror(")
        frame_block = _extract_function_block(text, "static int gateway_shadow_build_frame(")
        rx_block = _extract_function_block(text, "static void udp_rx_callback(")
        struct_match = re.search(
            r"typedef\s+struct\s*\{.*?\}\s*gateway_shadow_job_t;",
            text,
            re.S,
        )
        self.assertIsNotNone(struct_match, "gateway_shadow_job_t definition missing")
        struct_block = struct_match.group(0)

        for token in (
            "uint32_t remote_ip;",
            "uint16_t remote_port;",
            "job->remote_ip",
            "job->remote_port",
            "remote_ip",
            "remote_port",
            "g_shadow_frame_words[7] = remote_ip;",
            "g_shadow_frame_words[9] = ((uint32_t)local_port << 16) | remote_port;",
        ):
            self.assertIn(token, struct_block + submit_block + frame_block)

        self.assertIn(
            "job->remote_ip = lwip_ntohl(ip4_addr_get_u32(ip_2_ip4(remote_ip)));",
            submit_block,
        )
        self.assertNotIn(
            "job->remote_ip = ip4_addr_get_u32(ip_2_ip4(remote_ip));",
            submit_block,
        )

        self.assertIn("gateway_shadow_submit_live_mirror(", rx_block)
        self.assertIn("addr,", rx_block)
        self.assertIn("port,", rx_block)

    def test_udp_rx_callback_only_submits_shadow_after_queue_accept(self):
        text = self.text
        block = _extract_function_block(text, "static void udp_rx_callback(")

        queue_if_idx = block.index("if (queue_push(")
        shadow_submit_idx = block.index("gateway_shadow_submit_live_mirror(")
        else_idx = block.index("} else {", shadow_submit_idx)

        self.assertLess(queue_if_idx, shadow_submit_idx)
        self.assertIn("== 0", block[queue_if_idx:shadow_submit_idx])
        self.assertLess(shadow_submit_idx, else_idx)

    def test_timeout_branch_sticks_shadow_state_to_halted(self):
        text = self.text
        for token in (
            "g_shadow_run_state = GATEWAY_SHADOW_RUN_HALTED",
            "g_shadow_halt_reason = GATEWAY_SHADOW_HALT_REASON_POLL_TIMEOUT",
            "g_shadow_stats.timeout_halt_count++",
        ):
            self.assertIn(token, text)

    def test_halted_state_does_not_reuse_dma_ring_or_submit(self):
        text = self.text
        halted_block = _extract_function_block(text, "static void gateway_shadow_service(")

        self.assertIn("GATEWAY_SHADOW_RUN_HALTED", halted_block)
        self.assertIn("skip_busy", text)
        self.assertIn("halted", text.lower())

        halted_section_match = re.search(
            r"GATEWAY_SHADOW_RUN_HALTED.*?(?:case|return|break)",
            halted_block,
            re.S,
        )
        self.assertIsNotNone(
            halted_section_match,
            "HALTED state branch missing from gateway_shadow_service()",
        )
        halted_section = halted_section_match.group(0)

        for token in (
            "dma_ring_submit",
            "ring_doorbell",
        ):
            self.assertNotIn(token, halted_section)

    def test_uart_diagnostics_do_not_use_xil_printf_long_formats(self):
        long_printf = re.compile(r'xil_printf\s*\(\s*"[^"\n]*%[0-9]*l[duxX][^"\n]*"', re.S)
        xemacpsif_text = (
            REPO_ROOT
            / "HCS_SOC"
            / "vitis_2023_udp_gateway_ws_2"
            / "ax7020_udp_gateway_platform"
            / "ps7_cortexa9_0"
            / "standalone_domain"
            / "bsp"
            / "ps7_cortexa9_0"
            / "libsrc"
            / "lwip213_v1_0"
            / "src"
            / "contrib"
            / "ports"
            / "xilinx"
            / "netif"
            / "xemacpsif.c"
        ).read_text(encoding="utf-8")

        self.assertIsNone(
            long_printf.search(self.text),
            "udp_crypto_gateway.c still uses xil_printf long-width formats",
        )
        self.assertIsNone(
            long_printf.search(self.shadow_main_text),
            "shadow mirror main.c still uses xil_printf long-width formats",
        )
        self.assertIsNotNone(
            re.search(r"static unsigned long g_xemacpsif_dbg_pkt_count = 0;", xemacpsif_text),
            "xemacpsif.c no longer keeps packet counters in unsigned long form",
        )
        self.assertIsNotNone(
            re.search(r'xil_printf\("xemacpsif_input: pkt=%lu ethertype=0x%04x len=%u', xemacpsif_text),
            "xemacpsif.c no longer emits the board-proven %lu packet diagnostic",
        )

    def test_shadow_wrapper_axi_master_interfaces_cap_burst_and_outstanding_depth(self):
        wrapper = self.shadow_wrapper
        expected_params = {
            "M_AXI_DMA_WR": (
                "AWADDR",
                "PROTOCOL AXI3",
                "READ_WRITE_MODE WRITE_ONLY",
                "MAX_BURST_LENGTH 16",
                "NUM_WRITE_OUTSTANDING 1",
                "SUPPORTS_NARROW_BURST 0",
            ),
            "M_AXI_FETCHER": (
                "ARADDR",
                "PROTOCOL AXI3",
                "READ_WRITE_MODE READ_ONLY",
                "MAX_BURST_LENGTH 16",
                "NUM_READ_OUTSTANDING 1",
                "SUPPORTS_NARROW_BURST 0",
            ),
            "M_AXI_S2MM": (
                "AWADDR",
                "PROTOCOL AXI3",
                "READ_WRITE_MODE READ_WRITE",
                "MAX_BURST_LENGTH 16",
                "NUM_READ_OUTSTANDING 1",
                "NUM_WRITE_OUTSTANDING 1",
                "SUPPORTS_NARROW_BURST 0",
            ),
        }

        for if_name, tokens in expected_params.items():
            info_port, *param_tokens = tokens
            match = re.search(
                rf'X_INTERFACE_INFO\s*=\s*"xilinx\.com:interface:aximm:1\.0\s+{if_name}\s+{info_port}"\s*\*\)\s*\n\s*\(\*\s*X_INTERFACE_PARAMETER\s*=\s*"([^"]*XIL_INTERFACENAME\s+{if_name}[^"]*)"',
                wrapper,
                re.S,
            )
            self.assertIsNotNone(match, f"{if_name} interface parameter annotation missing on {info_port}")
            block = match.group(1)
            for token in param_tokens:
                self.assertIn(token, block, f"{if_name} missing {token}")

    def test_dma_axi_bursts_are_capped_to_axi3_limit(self):
        for text in (self.dma_master_engine, self.dma_crypto_source_reader):
            self.assertIn("localparam integer MAX_BURST_BEATS = 16;", text)
            self.assertIn("localparam integer MAX_BURST_BYTES = MAX_BURST_BEATS * BYTES_PER_BEAT;", text)
            self.assertIn(
                "limit = (dist_to_4k < MAX_BURST_BYTES) ? dist_to_4k : MAX_BURST_BYTES;",
                text,
            )
            self.assertNotIn("1024", text)

    def test_shadow_inject_sequence_matches_board_proven_backend_timing(self):
        block = _extract_function_block(self.text, "static int gateway_shadow_inject_frame(")

        for token in (
            "gateway_shadow_wrap_write32(WRAP_REG_INJ_CTRL, GATEWAY_SHADOW_INJ_ARM_CTRL);",
            "DATA_SYNC;",
            "usleep(1000U);",
            "gateway_shadow_wrap_write32(WRAP_REG_INJ_CTRL, (frame_word_count << 16));",
        ):
            self.assertIn(token, block)

    def test_shadow_runtime_emits_boundary_diagnostics(self):
        for token in (
            "udp_crypto_gateway: shadow queued",
            "udp_crypto_gateway: shadow submit rc=",
            "udp_crypto_gateway: shadow inject rc=",
            "udp_crypto_gateway: shadow active",
        ):
            self.assertIn(token, self.text)

    def test_shadow_submit_capacity_is_dma_aligned(self):
        block = _extract_function_block(self.text, "static int gateway_shadow_start_next_job(")

        for token in (
            "gateway_shadow_buffer_capacity(",
            "dma_ring_submit_stream(&g_shadow_ring_ctx,",
            "job->expected_actual_len",
            "DMA_RAW_COPY_LEN_MULTIPLE",
        ):
            self.assertIn(token, self.text)

        self.assertIn("gateway_shadow_buffer_capacity(job->expected_actual_len)", block)

    def test_shadow_payload_word_uses_network_order(self):
        block = _extract_function_block(self.text, "static uint32_t gateway_shadow_payload_word(")

        for token in (
            "payload[base + 0U] << 24",
            "payload[base + 1U] << 16",
            "payload[base + 2U] << 8",
            "(uint32_t)payload[base + 3U]",
        ):
            self.assertIn(token, block)

        self.assertNotIn("payload[base + 1U] << 8", block)
        self.assertNotIn("payload[base + 3U] << 24", block)

    def test_shadow_compare_uses_word_normalization_not_raw_memcmp(self):
        block = _extract_function_block(self.text, "static int gateway_shadow_compare_result(")

        self.assertIn("gateway_shadow_payload_word(", block)
        self.assertIn("g_shadow_dma_region.words[word_idx]", block)
        self.assertNotIn("memcmp(g_shadow_dma_region.words", block)
        self.assertIn("invalidate_len = gateway_shadow_buffer_capacity(expected_actual_len);", block)
        self.assertIn("dma_ring_invalidate_result(g_shadow_dma_region.words, invalidate_len);", block)

    def test_shadow_compare_accepts_dma_actual_len_up_to_aligned_capacity(self):
        block = _extract_function_block(self.text, "static int gateway_shadow_compare_result(")

        self.assertIn("invalidate_len = gateway_shadow_buffer_capacity(expected_actual_len);", block)
        self.assertIn("if ((actual_len < payload_len) || (actual_len > invalidate_len)) {", block)
        self.assertNotIn("if (actual_len != expected_actual_len) {", block)

    def test_shadow_compare_logs_first_word_mismatch(self):
        block = _extract_function_block(self.text, "static int gateway_shadow_compare_result(")

        for token in (
            "shadow compare word mismatch",
            "got=0x%08x",
            "exp=0x%08x",
            "GATEWAY_UART_U32(actual_word)",
            "GATEWAY_UART_U32(expected_word)",
        ):
            self.assertIn(token, block)

    def test_shadow_fallback_dma_path_reports_actual_len_from_descriptor_transfer_length(self):
        text = self.crypto_dma_subsystem

        self.assertIn("assign dma_actual_len = sink_done ? final_len : 32'd0;", text)
        self.assertNotIn("assign dma_actual_len = sink_done ? sink_bytes_written : 32'd0;", text)

    def test_shadow_acl_drop_fallback_short_circuits_before_dma_compare(self):
        text = self.text
        service_block = _extract_function_block(text, "static void gateway_shadow_service(")

        self.assertIn("#define GATEWAY_FASTPATH_STATUS_TXCAP_STORAGE_SHIFT 6U", text)
        self.assertIn("#define GATEWAY_FASTPATH_STATUS_TXCAP_STORAGE_MASK 0x00000001U", text)
        self.assertIn("#define GATEWAY_FASTPATH_STATUS_REASON_SHIFT 2U", text)
        self.assertIn("#define GATEWAY_FASTPATH_STATUS_REASON_MASK 0x0000000FU", text)
        self.assertIn("#define GATEWAY_FASTPATH_REASON_ACL_DROP 3U", text)
        self.assertIn("uint32_t fastpath_reason = 0U;", service_block)
        self.assertIn(
            "fastpath_reason = (job->status >> GATEWAY_FASTPATH_STATUS_REASON_SHIFT) &",
            service_block,
        )
        self.assertIn(
            "if (fastpath_reason == GATEWAY_FASTPATH_REASON_ACL_DROP) {",
            service_block,
        )
        self.assertIn('xil_printf("SHADOW_ACL_DROP PASS status=0x%08x local_port=%u len=%u\\r\\n"', service_block)
        self.assertIn("gateway_shadow_prepare_ring();", service_block)
        self.assertLess(
            service_block.index("if (fastpath_reason == GATEWAY_FASTPATH_REASON_ACL_DROP) {"),
            service_block.index("if (gateway_shadow_poll_active_job(&csw) != 0) {"),
        )

    def test_shadow_acl_counter_short_circuits_before_dma_compare(self):
        text = self.text
        service_block = _extract_function_block(text, "static void gateway_shadow_service(")

        self.assertIn("uint32_t acl_count_base;", text)
        self.assertIn("uint32_t acl_count = gateway_shadow_wrap_read32(WRAP_REG_ACL_CNT);", service_block)
        self.assertIn("job->acl_count_base = gateway_shadow_wrap_read32(WRAP_REG_ACL_CNT);", text)
        self.assertIn("if (acl_count != job->acl_count_base) {", service_block)
        self.assertIn('xil_printf("SHADOW_ACL_DROP PASS acl_count=%u local_port=%u len=%u\\r\\n"', service_block)
        self.assertLess(
            service_block.index("if (acl_count != job->acl_count_base) {"),
            service_block.index("if (gateway_shadow_poll_active_job(&csw) != 0) {"),
        )

    def test_shadow_wrapper_fastpath_status_encodes_txcap_storage_mode_without_moving_reason_bits(self):
        text = self.shadow_wrapper

        self.assertIn("localparam integer FASTPATH_STATUS_TXCAP_STORAGE_SHIFT = 6;", text)
        self.assertIn(
            "assign fastpath_status          = (32'd1 << FASTPATH_STATUS_TXCAP_STORAGE_SHIFT) |",
            text,
        )
        self.assertIn(
            "{26'd0, fastpath_last_reason_q, fastpath_last_hit_q, ctrl_fastpath_en};",
            text,
        )

    def test_bench_contract_uses_same_board_sw_and_hw_paths(self):
        block = _extract_function_block(self.text, "static int gateway_run_bench(")

        for token in (
            "gateway_sw_encrypt_buffer(",
            "gateway_store_be16(&record[0], current_len);",
            "gateway_store_be_word(&record[4], sw_us);",
            "gateway_store_be_word(&record[8], hw_us);",
            "BENCH response record contract",
        ):
            self.assertIn(token, block)

        self.assertIn("gateway_run_bench_dma_batch(", self.text)
        self.assertIn("gateway_hw_encrypt_buffer_sync(", self.text)
        self.assertIn("gateway_run_bench_dma_batch(", block)

    def test_bench_dma_batch_reuses_descriptor_ring_contract(self):
        block = _extract_function_block(self.text, "static int gateway_run_bench_dma_batch(")

        for token in (
            "GATEWAY_BENCH_DMA_RING_ENTRY_COUNT 2048U",
            "GATEWAY_BENCH_DMA_USABLE_RING_ENTRIES",
            "dma_ring_submit_nodoorbell(",
            "dma_ring_publish_tail(",
            "dma_ring_ring_doorbell(",
            "dma_ring_read_actual_len(",
            "dma_ring_invalidate_result(",
            "gateway_bench_dma_prepare_ring(",
            "gateway_bench_dma_configure_crypto_context(",
            "g_bench_dma_desc_region",
            "g_bench_dma_src_region",
            "g_bench_dma_dst_region",
        ):
            self.assertIn(token, self.text if token.startswith("GATEWAY_BENCH_DMA_") or token.startswith("g_bench_dma_") else block)

    def test_bench_maps_dma_batch_failures_to_internal_status_instead_of_raw_negative(self):
        block = _extract_function_block(self.text, "static int gateway_run_bench(")

        self.assertIn("bench_rc = gateway_run_bench_dma_batch(", block)
        self.assertIn("xil_printf(\"udp_crypto_gateway: bench dma rc=%d", block)
        self.assertIn("return GATEWAY_CTRL_STATUS_INTERNAL;", block)
        self.assertNotIn("return -1;", block[block.index("bench_rc = gateway_run_bench_dma_batch("):block.index("#else") if "#else" in block else len(block)])

    def test_bench_emits_uart_diagnostics_for_non_rc_internal_failures(self):
        run_block = _extract_function_block(self.text, "static int gateway_run_bench(")
        dma_block = _extract_function_block(self.text, "static int gateway_run_bench_dma_batch(")

        for token in (
            "udp_crypto_gateway: bench backend unavailable",
            "udp_crypto_gateway: bench effective key missing",
            "udp_crypto_gateway: bench final compare fail",
            "udp_crypto_gateway: bench dma submit rc=",
            "udp_crypto_gateway: bench dma publish tail failed",
            "udp_crypto_gateway: bench dma poll timeout",
            "udp_crypto_gateway: bench dma csw fail",
            "udp_crypto_gateway: bench dma actual len mismatch",
            "udp_crypto_gateway: bench dma compare fail",
        ):
            self.assertIn(token, run_block + dma_block)

    def test_bench_last_desc_poll_preserves_descriptor_error_and_logs_debug_regs(self):
        poll_block = _extract_function_block(self.text, "static int gateway_bench_dma_poll_last_desc(")
        dma_block = _extract_function_block(self.text, "static int gateway_run_bench_dma_batch(")

        self.assertIn("if (rc == 0) {", poll_block)
        self.assertIn("if (rc < 0) {", poll_block)
        self.assertIn("return -1;", poll_block)

        for token in (
            "udp_crypto_gateway: bench dma last desc err rc=%d",
            "DMA_CSR_IRQ_STATUS",
            "DMA_CSR_DEBUG_STATUS",
            "DMA_CSR_DEBUG_SOURCE_PROGRESS",
            "DMA_CSR_DEBUG_SINK_PROGRESS",
        ):
            self.assertIn(token, dma_block)

    def test_sync_hw_path_uses_cross_call_key_ctrl_cache(self):
        text = self.text
        block = _extract_function_block(text, "static int GATEWAY_MAYBE_UNUSED gateway_hw_encrypt_buffer_sync(")

        for token in (
            "gateway_hw_sync_cache_t",
            "static gateway_hw_sync_cache_t g_hw_sync_cache;",
            "static void gateway_hw_sync_cache_invalidate(void)",
            "static int sync_ensure_key_and_ctrl(",
        ):
            self.assertIn(token, text)

        self.assertIn("sync_ensure_key_and_ctrl(", block)
        self.assertNotIn("gateway_load_key_hw_sync(algo, effective_key);", block)
        self.assertNotIn("gateway_backend_write_ctrl(gateway_ctrl_word(algo));", block)

    def test_sync_hw_path_marks_sync_encrypt_helper_unused_when_shadow_build_is_enabled(self):
        text = self.text

        self.assertIn("#if UDP_GATEWAY_ENABLE_SHADOW_MIRROR", text)
        self.assertIn("#define GATEWAY_MAYBE_UNUSED __attribute__((unused))", text)
        self.assertIn("#define GATEWAY_MAYBE_UNUSED", text)
        self.assertIn("static int GATEWAY_MAYBE_UNUSED gateway_hw_encrypt_buffer_sync(", text)

    def test_sync_hw_cache_invalidates_on_session_mutations(self):
        lock_block = _extract_function_block(self.text, "static void gateway_lock_session(")
        unlock_block = _extract_function_block(self.text, "static void gateway_unlock_session(")
        set_key_block = _extract_function_block(self.text, "static void udp_control_callback(")

        self.assertIn("gateway_hw_sync_cache_invalidate();", lock_block)
        self.assertIn("gateway_hw_sync_cache_invalidate();", unlock_block)
        self.assertIn("case GATEWAY_CTRL_MSG_SET_KEY:", set_key_block)
        self.assertIn("gateway_hw_sync_cache_invalidate();", set_key_block)

    def test_sync_pull_block_reads_four_words_without_per_word_polling(self):
        pull_block = _extract_function_block(self.text, "static void sync_pull_block_4words(")
        sync_block = _extract_function_block(self.text, "static int GATEWAY_MAYBE_UNUSED gateway_hw_encrypt_buffer_sync(")

        self.assertIn("sync_pull_block_4words(&output[offset]);", sync_block)
        self.assertNotIn("gateway_backend_read_status(", pull_block)
        self.assertNotIn("poll_count", pull_block)
        self.assertNotIn("GATEWAY_WAIT_TX_WORD_POLLS", pull_block)

    def test_shadow_ctrl_csr_exposes_read_only_device_dna_registers(self):
        text = self.shadow_ctrl_csr

        for token in (
            "input  logic [31:0]            i_device_dna_lo,",
            "input  logic [31:0]            i_device_dna_hi,",
            "input  logic [31:0]            i_device_dna_status,",
            "8'hD4: s_axil_rdata <= i_device_dna_lo;",
            "8'hD8: s_axil_rdata <= i_device_dna_hi;",
            "8'hDC: s_axil_rdata <= i_device_dna_status;",
        ):
            self.assertIn(token, text)

        self.assertNotIn("8'hD4:", _extract_function_block(text, "always_ff @(posedge clk or negedge rst_n) begin"))

    def test_shadow_ctrl_csr_exposes_acl_control_window_and_counter(self):
        text = self.shadow_ctrl_csr

        for token in (
            "output logic                   o_acl_en,",
            "output logic                   o_acl_write_en,",
            "output logic                   o_acl_clear,",
            "output logic [11:0]            o_acl_write_addr,",
            "output logic [103:0]           o_acl_write_data,",
            "input  logic                   i_acl_inc,",
            "logic [31:0] reg_ctrl;",
            "logic [31:0] reg_acl_cnt;",
            "logic [31:0] reg_acl_addr;",
            "logic [31:0] reg_acl_data0;",
            "logic [31:0] reg_acl_data1;",
            "logic [31:0] reg_acl_data2;",
            "logic [31:0] reg_acl_data3;",
            "8'h00: reg_ctrl <= apply_wstrb(reg_ctrl, s_axil_wdata, s_axil_wstrb);",
            "8'h44: reg_acl_cnt <= apply_wstrb(reg_acl_cnt, s_axil_wdata, s_axil_wstrb);",
            "8'h60: reg_acl_addr <= apply_wstrb(reg_acl_addr, s_axil_wdata, s_axil_wstrb);",
            "8'h64: reg_acl_data0 <= apply_wstrb(reg_acl_data0, s_axil_wdata, s_axil_wstrb);",
            "8'h68: reg_acl_data1 <= apply_wstrb(reg_acl_data1, s_axil_wdata, s_axil_wstrb);",
            "8'h6C: reg_acl_data2 <= apply_wstrb(reg_acl_data2, s_axil_wdata, s_axil_wstrb);",
            "reg_acl_data3 <= apply_wstrb(reg_acl_data3, s_axil_wdata, s_axil_wstrb);",
            "if (s_axil_wstrb[1] && s_axil_wdata[8]) begin",
            "o_acl_write_en <= 1'b1;",
            "if (s_axil_wstrb[1] && s_axil_wdata[9]) begin",
            "o_acl_clear <= 1'b1;",
            "if (i_acl_inc && reg_acl_cnt < 32'hFFFFFFFF) begin",
            "8'h44: s_axil_rdata <= reg_acl_cnt;",
            "8'h60: s_axil_rdata <= reg_acl_addr;",
            "8'h64: s_axil_rdata <= reg_acl_data0;",
            "8'h68: s_axil_rdata <= reg_acl_data1;",
            "8'h6C: s_axil_rdata <= reg_acl_data2;",
            "8'h70: s_axil_rdata <= reg_acl_data3;",
            "assign o_acl_en = reg_ctrl[7];",
            "assign o_acl_write_addr = reg_acl_addr[11:0];",
            "assign o_acl_write_data = {acl_data3_effective[7:0], reg_acl_data2, reg_acl_data1, reg_acl_data0};",
        ):
            self.assertIn(token, text)

    def test_shadow_ctrl_csr_exposes_fastpath_enable_and_read_only_status_window(self):
        text = self.shadow_ctrl_csr
        write_block = _extract_function_block(text, "always_ff @(posedge clk or negedge rst_n) begin")

        for token in (
            "output logic                   o_fastpath_en,",
            "input  logic [31:0]            i_fastpath_status,",
            "input  logic [31:0]            i_fastpath_hit_count,",
            "input  logic [31:0]            i_fastpath_fallback_count,",
            "8'hE0: s_axil_rdata <= i_fastpath_status;",
            "8'hE4: s_axil_rdata <= i_fastpath_hit_count;",
            "8'hE8: s_axil_rdata <= i_fastpath_fallback_count;",
            "assign o_fastpath_en = reg_ctrl[11];",
        ):
            self.assertIn(token, text)

        self.assertNotIn("i_fastpath_pass_count", text)

        for token in (
            "8'hE0:",
            "8'hE4:",
            "8'hE8:",
        ):
            self.assertNotIn(token, write_block)

    def test_shadow_ctrl_csr_acl_write_uses_current_data3_low_byte_during_pulse(self):
        text = self.shadow_ctrl_csr

        for token in (
            "logic [31:0] acl_data3_effective;",
            "always_comb begin",
            "acl_data3_effective = reg_acl_data3;",
            "if (write_en && (awaddr_latch[7:0] == 8'h70)) begin",
            "acl_data3_effective = apply_wstrb(reg_acl_data3, s_axil_wdata, s_axil_wstrb);",
            "assign o_acl_write_data = {acl_data3_effective[7:0], reg_acl_data2, reg_acl_data1, reg_acl_data0};",
        ):
            self.assertIn(token, text)

        self.assertNotIn(
            "assign o_acl_write_data = {reg_acl_data3[7:0], reg_acl_data2, reg_acl_data1, reg_acl_data0};",
            text,
        )

    def test_shadow_wrapper_instantiates_device_dna_reader_and_wires_shadow_csr(self):
        text = self.shadow_wrapper

        for token in (
            "device_dna_reader u_device_dna_reader",
            ".o_dna_value(device_dna_value)",
            ".o_dna_valid(device_dna_valid)",
            ".o_dna_busy(device_dna_busy)",
            ".i_device_dna_lo(device_dna_value[31:0])",
            ".i_device_dna_hi(device_dna_value[63:32])",
            ".i_device_dna_status({30'd0, device_dna_busy, device_dna_valid})",
        ):
            self.assertIn(token, text)

    def test_shadow_wrapper_routes_acl_output_into_txcap_fastpath_before_dma_fallback(self):
        text = self.shadow_wrapper

        for token in (
            "wire                  ctrl_fastpath_en;",
            "wire [31:0]           fastpath_status;",
            "wire [31:0]           fastpath_hit_count;",
            "wire [31:0]           fastpath_fallback_count;",
            ".o_fastpath_en(ctrl_fastpath_en)",
            ".i_fastpath_status(fastpath_status)",
            ".i_fastpath_hit_count(fastpath_hit_count)",
            ".i_fastpath_fallback_count(fastpath_fallback_count)",
            "localparam integer FASTPATH_HDR_WORDS = 11;",
            "localparam integer FASTPATH_TXCAP_DEPTH =",
            "localparam [2:0] FASTPATH_ROUTE_REPLAY = 3'd2;",
            "localparam [2:0] FASTPATH_ROUTE_DMA = 3'd3;",
            "localparam [2:0] FASTPATH_ROUTE_TXCAP = 3'd4;",
            "frame_dst_port_q",
            "payload_words_q",
            "fastpath_hit_count_q",
            "fastpath_fallback_count_q",
            "txcap_read_data_q",
            "txcap_payload_rd_pending_q",
            "u_txcap_payload_mem",
            "if (!ctrl_fastpath_en) begin",
            "txcap_count_q < FASTPATH_TXCAP_DEPTH",
            "((aclf_tdata[15:0] - 16'd8) >> 2) + FASTPATH_HDR_WORDS <= FASTPATH_TXCAP_DEPTH",
            "xpm_memory_sdpram #(",
            '.MEMORY_PRIMITIVE("block")',
            ".ena(txcap_payload_wr_en)",
            ".dina(aclf_tdata)",
            ".enb(txcap_payload_rd_fire)",
            ".doutb(txcap_payload_rd_data)",
            "txcap_read_data_q <=",
            "classifier_dma_tdata",
            "classifier_dma_tvalid",
            "classifier_dma_tlast",
        ):
            self.assertIn(token, text)

        depth_match = re.search(
            r"localparam integer FASTPATH_TXCAP_DEPTH = (\d+);",
            text,
        )
        self.assertIsNotNone(depth_match, "FASTPATH_TXCAP_DEPTH definition missing")
        self.assertGreaterEqual(
            int(depth_match.group(1)),
            379,
            "FASTPATH_TXCAP_DEPTH must allow full-frame capture",
        )
        self.assertNotIn("localparam integer FASTPATH_TXCAP_DEPTH = 64;", text)
        self.assertNotIn("fastpath_pass_count", text)
        self.assertNotIn("reg  [31:0]           txcap_data_mem", text)
        self.assertNotIn(
            "for (fastpath_copy_idx = 0; fastpath_copy_idx < (FASTPATH_HDR_WORDS - 1); fastpath_copy_idx = fastpath_copy_idx + 1) begin",
            text,
        )
        self.assertNotIn(
            "assign txcap_data               = (SHADOW_INJECT_ONLY != 0) ? ((txcap_count_q != 0) ? txcap_data_mem[txcap_rd_ptr_q] : 32'd0) : stage1_txcap_data;",
            text,
        )

    def test_shadow_wrapper_routes_acl_between_shadow_inject_and_classifier(self):
        text = self.shadow_wrapper

        for token in (
            "wire                  ctrl_acl_en;",
            "wire                  ctrl_acl_write_en;",
            "wire                  ctrl_acl_clear;",
            "wire [11:0]           ctrl_acl_write_addr;",
            "wire [103:0]          ctrl_acl_write_data;",
            "wire [31:0]           aclf_tdata;",
            "wire                  aclf_tvalid;",
            "wire                  aclf_tlast;",
            "wire                  aclf_tready;",
            "wire                  acl_drop_pulse;",
            ".o_acl_en(ctrl_acl_en)",
            ".o_acl_write_en(ctrl_acl_write_en)",
            ".o_acl_clear(ctrl_acl_clear)",
            ".o_acl_write_addr(ctrl_acl_write_addr)",
            ".o_acl_write_data(ctrl_acl_write_data)",
            ".i_acl_inc(acl_drop_pulse)",
            "acl_packet_filter u_shadow_acl_filter",
            ".acl_en(ctrl_acl_en)",
            ".s_tdata(stage1_inject_tdata)",
            ".s_tvalid(stage1_inject_tvalid)",
            ".s_tlast(stage1_inject_tlast)",
            ".s_tready(stage1_inject_tready)",
            ".m_tdata(aclf_tdata)",
            ".m_tvalid(aclf_tvalid)",
            ".m_tlast(aclf_tlast)",
            ".m_tready(aclf_tready)",
            ".acl_write_en(ctrl_acl_write_en)",
            ".acl_write_addr(ctrl_acl_write_addr)",
            ".acl_write_data(ctrl_acl_write_data)",
            ".acl_clear(ctrl_acl_clear)",
            ".acl_drop_pulse(acl_drop_pulse)",
            "wire [31:0]           classifier_s_tdata;",
            "wire                  classifier_s_tvalid;",
            "wire                  classifier_s_tlast;",
            "wire                  classifier_s_tready;",
            ".s_axis_tdata(classifier_s_tdata)",
            ".s_axis_tvalid(classifier_s_tvalid)",
            ".s_axis_tlast(classifier_s_tlast)",
            ".s_axis_tready(classifier_s_tready)",
        ):
            self.assertIn(token, text)

    def test_shadow_export_includes_acl_rtl_sources(self):
        text = self.shadow_export_tcl

        for token in (
            '{"rtl/security/acl_match_engine.sv" "SystemVerilog"}',
            '{"rtl/security/acl_packet_filter.sv" "SystemVerilog"}',
        ):
            self.assertIn(token, text)

    def test_gateway_control_plane_exposes_acl_messages_and_shadow_mmio_helpers(self):
        text = self.text

        for token in (
            "#define WRAP_REG_ACL_CNT              0x44U",
            "#define WRAP_REG_ACL_ADDR             0x60U",
            "#define WRAP_REG_ACL_DATA0            0x64U",
            "#define WRAP_REG_ACL_DATA1            0x68U",
            "#define WRAP_REG_ACL_DATA2            0x6CU",
            "#define WRAP_REG_ACL_DATA3            0x70U",
            "#define GATEWAY_SHADOW_ACL_WRITE_PULSE 0x00000100U",
            "#define GATEWAY_SHADOW_ACL_CLEAR_PULSE 0x00000200U",
            "#define GATEWAY_CTRL_MSG_ACL_WRITE 7U",
            "#define GATEWAY_CTRL_MSG_ACL_CLEAR 8U",
            "#define GATEWAY_CTRL_MSG_ACL_STATUS 9U",
            "#define GATEWAY_ACL_TUPLE_PAYLOAD_BYTES 13U",
            "static uint16_t gateway_shadow_acl_hash_tuple(",
            "static void gateway_shadow_acl_pack_rule_regs(",
            "static int gateway_shadow_acl_write_rule(",
            "static void gateway_shadow_acl_clear_all(void)",
            "gateway_shadow_wrap_write32(WRAP_REG_ACL_ADDR, (uint32_t)rule_addr);",
            "gateway_shadow_wrap_write32(WRAP_REG_ACL_DATA0, data0);",
            "gateway_shadow_wrap_write32(WRAP_REG_ACL_DATA1, data1);",
            "gateway_shadow_wrap_write32(WRAP_REG_ACL_DATA2, data2);",
            "gateway_shadow_wrap_write32(WRAP_REG_ACL_DATA3, data3 | GATEWAY_SHADOW_ACL_WRITE_PULSE);",
            "gateway_shadow_wrap_write32(WRAP_REG_ACL_DATA3, GATEWAY_SHADOW_ACL_CLEAR_PULSE);",
        ):
            self.assertIn(token, text)

        udp_block = _extract_function_block(text, "static void udp_control_callback(")
        for token in (
            "case GATEWAY_CTRL_MSG_ACL_WRITE:",
            "case GATEWAY_CTRL_MSG_ACL_CLEAR:",
            "case GATEWAY_CTRL_MSG_ACL_STATUS:",
            "payload_len != GATEWAY_ACL_TUPLE_PAYLOAD_BYTES",
            "gateway_shadow_acl_write_rule(",
            "gateway_shadow_acl_clear_all();",
            "gateway_store_be_word(response_payload, gateway_shadow_wrap_read32(WRAP_REG_ACL_CNT));",
        ):
            self.assertIn(token, udp_block)

    def test_gateway_shadow_acl_hash_matches_rtl_single_stage_final_mix(self):
        block = _extract_function_block(
            self.text,
            "static uint16_t gateway_shadow_acl_hash_tuple(",
        )

        for token in (
            "h = (uint16_t)(dst_port ^",
            "h ^= (uint16_t)(((h & 0x00FFU) << 8) | ((h >> 8) & 0x00FFU));",
            "h ^= 0x9E37U;",
            "return (uint16_t)((h ^",
            '((h & 0x07FFU) << 5) | ((h >> 11) & 0x001FU)',
            "(uint16_t)(h >> 3)) & 0x0FFFU);",
        ):
            self.assertIn(token, block)

        self.assertNotIn("h ^= (uint16_t)(h >> 3);", block)

    def test_acl_packet_filter_extracts_tuple_from_full_shadow_injected_frame(self):
        text = self.acl_packet_filter

        for token in (
            "localparam int ACL_HEADER_WORDS = 10;",
            "buf_data[6][23:16]",
            "buf_data[7]",
            "buf_data[9][15:0]",
            "buf_data[8]",
            "buf_data[9][31:16]",
        ):
            self.assertIn(token, text)

        for stale_token in (
            "buf_data[4],",
            "buf_data[5],",
            "buf_data[6][31:16]",
            "buf_data[6][15:0]",
        ):
            self.assertNotIn(stale_token, text)

    def test_udp_crypto_control_cli_exposes_acl_write_and_clear_commands(self):
        text = self.udp_control_py

        for token in (
            "MSG_ACL_WRITE = 7",
            "MSG_ACL_CLEAR = 8",
            "MSG_ACL_STATUS = 9",
            "def acl_write(",
            "def acl_clear(",
            "def acl_status(",
            'subparsers.add_parser("acl-write"',
            'subparsers.add_parser("acl-clear"',
            'subparsers.add_parser("acl-status"',
            'if args.command == "acl-write":',
            'if args.command == "acl-clear":',
            'if args.command == "acl-status":',
        ):
            self.assertIn(token, text)

    def test_udp_crypto_control_cli_supports_explicit_seq_id_for_replay_safe_board_checks(self):
        text = self.udp_control_py

        for token in (
            "def add_seq_argument(",
            "add_seq_argument(set_key_parser)",
            "add_seq_argument(status_parser)",
            "add_seq_argument(lock_parser)",
            "add_seq_argument(unlock_parser)",
            "add_seq_argument(bench_parser)",
            "add_seq_argument(acl_write_parser)",
            "add_seq_argument(acl_clear_parser)",
            "add_seq_argument(acl_status_parser)",
            'if hasattr(args, "seq_id") and args.seq_id is not None:',
            'client.seq_id = max(args.seq_id - 1, 0)',
        ):
            self.assertIn(token, text)

    def test_udp_crypto_control_cli_can_expect_non_ok_status_without_traceback(self):
        text = self.udp_control_py

        for token in (
            "class ControlStatusError(RuntimeError):",
            "parser.add_argument(",
            '"--expect-status"',
            "except ControlStatusError as exc:",
            "if exc.status_code == args.expect_status:",
            'print(f"status_code={exc.status_code}")',
            'print(f"msg_type={exc.msg_type}")',
            'print(f"session_id=0x{exc.message.session_id:08x}")',
            "return 0",
        ):
            self.assertIn(token, text)

        self.assertNotIn(
            'raise RuntimeError(f"control status={message.status_code} msg_type={message.msg_type}")',
            text,
        )

    def test_udp_crypto_control_decodes_packed_reason_bits_from_authorized_mask_word(self):
        text = self.udp_control_py

        for token in (
            '"authorized_mask_raw":',
            '"last_drop_reason":',
            '"last_lock_reason":',
            'fields[2] & 0xFF',
            '(fields[2] >> 8) & 0x0F',
            '(fields[2] >> 12) & 0x0F',
        ):
            self.assertIn(token, text)

    def test_send_udp_helper_drains_stale_packets_and_uses_session_reply_validation_without_stale_udp(self):
        text = self.send_udp_test

        for token in (
            "def drain_stale_udp_packets(",
            "sock.setblocking(False)",
            "drain_stale_udp_packets(sock)",
            'expected_mode = "auto_session_reply"',
            'reply_from_expected_endpoint=',
            'reply_len_match=',
        ):
            self.assertIn(token, text)

        self.assertNotIn('elif args.algo == "aes":', text)

    def test_udp_crypto_control_decodes_packed_reason_bits_without_changing_authorized_mask(self):
        for module_path, module_name in (
            (UDP_CONTROL_PY, "shadow_udp_crypto_control_runtime"),
            (HANDOFF_UDP_CONTROL_PY, "handoff_udp_crypto_control_runtime"),
        ):
            module = _load_python_module(module_path, module_name)
            authorized_mask = 0x03
            last_drop_reason = 0x04
            last_lock_reason = 0x03
            packed_authorized_word = (
                authorized_mask |
                (last_drop_reason << 8) |
                (last_lock_reason << 12)
            )
            payload = module.STATUS_STRUCT.pack(
                0xC4BA0C4B,
                0x00000001,
                packed_authorized_word,
                0x00000001,
                2,
                3,
                4,
                5,
                6,
                7,
                8,
                9,
                10,
                11,
            )

            decoded = module.decode_status_payload(payload)

            self.assertEqual(decoded["authorized_mask"], authorized_mask)
            self.assertEqual(decoded["authorized_mask_raw"], packed_authorized_word)
            self.assertEqual(decoded["last_drop_reason"], last_drop_reason)
            self.assertEqual(decoded["last_lock_reason"], last_lock_reason)
            self.assertEqual(decoded["locked"], 1)

    def test_gateway_status_payload_packs_drop_and_lock_reason_into_authorized_mask_word(self):
        text = self.text

        for token in (
            "DROP_REASON_NONE",
            "DROP_REASON_INVALID",
            "DROP_REASON_UNAUTHORIZED",
            "DROP_REASON_REPLAY",
            "DROP_REASON_ACL",
            "LOCK_REASON_NONE",
            "LOCK_REASON_MANUAL",
            "LOCK_REASON_AUTH_THRESHOLD",
            "LOCK_REASON_REPLAY_THRESHOLD",
            "g_last_drop_reason",
            "g_last_lock_reason",
            "gateway_store_be_word(&out[8],",
            "((uint32_t)g_last_drop_reason << 8)",
            "((uint32_t)g_last_lock_reason << 12)",
            "& 0xFFU",
        ):
            self.assertIn(token, text)

    def test_gateway_unlock_does_not_clear_last_lock_reason(self):
        unlock_block = _extract_function_block(self.text, "static void gateway_unlock_session(gateway_session_t *session)")

        self.assertNotIn("g_last_lock_reason = LOCK_REASON_NONE;", unlock_block)
        self.assertIn("session->locked = 0U;", unlock_block)

    def test_device_dna_reader_uses_real_dna_port_with_divided_clock_and_57bit_shift(self):
        text = self.device_dna_reader

        for token in (
            "module device_dna_reader",
            "DNA_PORT u_dna",
            ".CLK(dna_clk)",
            "DNA_WIDTH = 57",
            "DNA_CLK_DIV",
            "always_ff @(posedge dna_clk or negedge rst_n)",
            "dna_shift_value <= {dna_shift_value[DNA_WIDTH-2:0], dna_dout};",
            "if (dna_bit_count == (DNA_WIDTH-1)) begin",
        ):
            self.assertIn(token, text)

        self.assertNotIn(".CLK(clk)", text)

    def test_shadow_phasec_constraints_restore_device_dna_generated_clock_and_multi_pblock_floorplan(self):
        xdc = self.shadow_phasec_xdc
        export_tcl = self.shadow_export_tcl

        for token in (
            "shadow_mirror_phasec_constraints.xdc",
            "u_device_dna_reader/dna_clk_reg/Q",
            "create_generated_clock",
            "-divide_by 32",
            "dna_done_sync_ff",
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
            "SLICE_X0Y0:SLICE_X113Y49",
            "SLICE_X26Y50:SLICE_X95Y98",
            "SLICE_X0Y100:SLICE_X95Y149",
            "SLICE_X96Y50:SLICE_X113Y98",
            "RAMB36_X3Y0:RAMB36_X5Y11",
            "RAMB18_X3Y24:RAMB18_X3Y31",
        ):
            self.assertIn(token, xdc + export_tcl)

        self.assertIn("ensure_constraint_source", export_tcl)
        self.assertIn("add_files -fileset constrs_1 -norecurse", export_tcl)
        self.assertNotIn("create_pblock live_crypto_region", xdc)
        self.assertNotIn("set_property IS_SOFT TRUE [get_pblocks live_crypto_region]", xdc)
        self.assertNotIn("shadow_core_region", xdc)
        self.assertNotIn("concat", xdc)
        self.assertNotIn("foreach", xdc)
        self.assertNotIn("lsort", xdc)
        self.assertNotIn("if {[", xdc)

    def test_gateway_status_payload_packs_last_drop_and_lock_reasons_into_authorized_mask_word(self):
        text = self.text

        for token in (
            "DROP_REASON_NONE",
            "DROP_REASON_INVALID",
            "DROP_REASON_UNAUTHORIZED",
            "DROP_REASON_REPLAY",
            "DROP_REASON_ACL",
            "LOCK_REASON_NONE",
            "LOCK_REASON_MANUAL",
            "LOCK_REASON_AUTH_THRESHOLD",
            "LOCK_REASON_REPLAY_THRESHOLD",
            "g_last_drop_reason",
            "g_last_lock_reason",
            "gateway_store_be_word(&out[8],",
            "g_last_drop_reason << 8",
            "g_last_lock_reason << 12",
        ):
            self.assertIn(token, text)

    def test_dma_fifos_use_sync_clear_instead_of_lut_driven_async_reset_muxing(self):
        self.assertIn("input  logic                   i_clear,", self.dma_axis_fifo_wrapper)
        self.assertIn(".i_clear(i_clear),", self.dma_axis_fifo_wrapper)
        self.assertIn("input  logic                   i_clear,", self.axis_packet_fifo_bram)
        self.assertIn("else if (i_clear) begin", self.axis_packet_fifo_bram)
        self.assertIn("assign axis_rst_n = rst_n;", self.dma_crypto_source_reader)
        self.assertIn(".i_clear(i_soft_reset || fifo_flush_q),", self.dma_crypto_source_reader)
        self.assertIn("assign axis_rst_n = rst_n;", self.dma_raw_copy_engine)
        self.assertIn(".i_clear(i_soft_reset || fifo_flush_q),", self.dma_raw_copy_engine)
        self.assertNotIn("assign axis_rst_n = rst_n && !i_soft_reset && !fifo_flush_q;", self.dma_crypto_source_reader)
        self.assertNotIn("assign axis_rst_n = rst_n && !i_soft_reset && !fifo_flush_q;", self.dma_raw_copy_engine)

    def test_gateway_reads_raw_device_dna_from_shadow_wrapper_and_folds_binding_id(self):
        text = self.text

        for token in (
            "#define WRAP_REG_DEVICE_DNA_LO         0xD4U",
            "#define WRAP_REG_DEVICE_DNA_HI         0xD8U",
            "#define WRAP_REG_DEVICE_DNA_STATUS     0xDCU",
            "static uint64_t gateway_get_device_dna_raw(void)",
            "static uint32_t gateway_fold_device_binding_id(uint64_t device_dna)",
            "gateway_wrap_read32(WRAP_REG_DEVICE_DNA_STATUS)",
            "gateway_wrap_read32(WRAP_REG_DEVICE_DNA_LO)",
            "gateway_wrap_read32(WRAP_REG_DEVICE_DNA_HI)",
        ):
            self.assertIn(token, text)

        binding_block = _extract_function_block(text, "static uint32_t gateway_get_device_binding_id(void)")
        self.assertIn("gateway_fold_device_binding_id(gateway_get_device_dna_raw())", binding_block)
        self.assertNotIn("return GATEWAY_BINDING_ID_DEFAULT;", binding_block)

    def test_gateway_shadow_runtime_exposes_fastpath_mmio_and_uart_diagnostics(self):
        text = self.text

        for pattern in (
            r"#define WRAP_REG_FASTPATH_STATUS\s+0xE0U",
            r"#define WRAP_REG_FASTPATH_HIT_COUNT\s+0xE4U",
            r"#define WRAP_REG_FASTPATH_FALLBACK_COUNT\s+0xE8U",
        ):
            self.assertRegex(text, pattern)

        for token in (
            "#define GATEWAY_SHADOW_FASTPATH_EN 0x00000800U",
            "SHADOW_FASTPATH PASS",
            "SHADOW_FASTPATH FALLBACK",
            "static int gateway_shadow_compare_fastpath_result(",
            "gateway_shadow_wrap_read32(WRAP_REG_FASTPATH_STATUS)",
            "gateway_shadow_wrap_read32(WRAP_REG_FASTPATH_HIT_COUNT)",
            "gateway_shadow_wrap_read32(WRAP_REG_FASTPATH_FALLBACK_COUNT)",
            "job->fastpath_hit_count_base = gateway_shadow_wrap_read32(WRAP_REG_FASTPATH_HIT_COUNT);",
            "job->fastpath_fallback_count_base = gateway_shadow_wrap_read32(WRAP_REG_FASTPATH_FALLBACK_COUNT);",
            "gateway_shadow_wrap_write32(WRAP_REG_CTRL, ctrl | GATEWAY_SHADOW_FASTPATH_EN);",
        ):
            self.assertIn(token, text)

        self.assertNotIn("WRAP_REG_FASTPATH_PASS_COUNT", text)
        self.assertNotIn("SHADOW_FASTPATH HIT", text)
        self.assertNotIn("fastpath_pass_count_base", text)

        compare_block = _extract_function_block(text, "static int gateway_shadow_compare_fastpath_result(")
        for token in (
            "gateway_shadow_wrap_read32(WRAP_REG_TXCAP_STATUS)",
            "gateway_shadow_wrap_read32(WRAP_REG_TXCAP_DATA)",
            "gateway_shadow_wrap_write32(WRAP_REG_TXCAP_CTRL, 2U);",
            "gateway_shadow_wrap_write32(WRAP_REG_TXCAP_CTRL, 1U);",
            "g_shadow_frame_words[word_idx]",
        ):
            self.assertIn(token, compare_block)

    def test_gateway_effective_key_derivation_mixes_full_device_dna_not_only_binding_id(self):
        block = _extract_function_block(
            self.text,
            "static void gateway_derive_effective_key(const uint8_t *user_key, uint64_t device_dna, gateway_algo_t algo, uint8_t *out_key)",
        )

        for token in (
            "uint8_t material[26];",
            "uint32_t dna_hi = (uint32_t)(device_dna >> 32);",
            "uint32_t dna_lo = (uint32_t)(device_dna & 0xFFFFFFFFU);",
            "gateway_store_be_word(&material[16], dna_hi);",
            "gateway_store_be_word(&material[20], dna_lo);",
            "material[24] = (uint8_t)algo;",
            "material[25] = (uint8_t)counter;",
        ):
            self.assertIn(token, block)

        self.assertNotIn("gateway_store_be_word(&material[16], binding_id);", block)

    def test_sessions_store_raw_device_dna_and_use_it_for_effective_keys(self):
        text = self.text

        for token in (
            "uint64_t device_dna;",
            "session->device_dna = gateway_get_device_dna_raw();",
            "session->binding_id = gateway_fold_device_binding_id(session->device_dna);",
            "gateway_derive_effective_key(user_key, session->device_dna, GATEWAY_ALGO_AES, session->effective_key_aes);",
            "gateway_derive_effective_key(user_key, session->device_dna, GATEWAY_ALGO_SM4, session->effective_key_sm4);",
        ):
            self.assertIn(token, text)

    def test_sync_hw_scheduler_uses_single_status_snapshot_per_iteration(self):
        block = _extract_function_block(self.text, "static int GATEWAY_MAYBE_UNUSED gateway_hw_encrypt_buffer_sync(")

        self.assertIn("while (blocks_completed < blocks_total)", block)
        self.assertEqual(1, block.count("status = gateway_backend_read_status();"))
        self.assertIn("status_reads_total++;", block)
        self.assertNotIn("gateway_wait_ready_sync(", block)
        self.assertNotIn("sync_wait_block_done(", block)

    def test_sync_hw_scheduler_uses_window_two_and_drain_fallback(self):
        text = self.text
        block = _extract_function_block(text, "static int GATEWAY_MAYBE_UNUSED gateway_hw_encrypt_buffer_sync(")

        self.assertIn("#define GATEWAY_SYNC_WINDOW_BLOCKS 2U", text)
        self.assertIn("blocks_inflight < GATEWAY_SYNC_WINDOW_BLOCKS", block)
        self.assertRegex(
            block,
            r"else if\s*\(\(blocks_inflight > 0U\)\s*&&\s*\(\(status & STATUS_TX_EMPTY\) == 0U\)\)",
        )

    def test_sync_hw_scheduler_tracks_watchdog_and_diag_counters(self):
        text = self.text
        block = _extract_function_block(text, "static int GATEWAY_MAYBE_UNUSED gateway_hw_encrypt_buffer_sync(")

        for token in (
            "typedef struct {",
            "} gateway_hw_sync_diag_t;",
            "static gateway_hw_sync_diag_t g_hw_sync_diag_last;",
            "scheduler_idle_spins",
            "scheduler_idle_limit",
            "inflight_high_watermark",
            "wready_stall_start",
            "wready_stall_end",
            "wready_stall_cnt_delta",
        ):
            self.assertIn(token, text if token.startswith("typedef") or token.startswith("} gateway") or token.startswith("static gateway_hw_sync_diag_t") else block)

        self.assertIn("if (scheduler_idle_spins > scheduler_idle_limit)", block)
        self.assertIn("gateway_drain_stale_output_sync()", block)

    def test_gateway_status_payload_packs_reason_bits_into_authorized_mask_word(self):
        block = _extract_function_block(self.text, "static void gateway_pack_status_payload(uint8_t *out, const gateway_session_t *session)")

        for token in (
            "uint32_t authorized_mask_word = 0U;",
            "authorized_mask_word |= ((uint32_t)g_last_drop_reason & 0xFU) << 8;",
            "authorized_mask_word |= ((uint32_t)g_last_lock_reason & 0xFU) << 12;",
            "authorized_mask_word |= ((session != NULL) ? (uint32_t)session->authorized_algos : 0U) & 0xFFU;",
            "gateway_store_be_word(&out[8], authorized_mask_word);",
        ):
            self.assertIn(token, block)

    def test_gateway_runtime_defines_latched_last_drop_and_lock_reason_enums(self):
        text = self.text

        for token in (
            "typedef enum {",
            "GATEWAY_DROP_REASON_NONE = 0,",
            "GATEWAY_DROP_REASON_INVALID = 1,",
            "GATEWAY_DROP_REASON_UNAUTHORIZED = 2,",
            "GATEWAY_DROP_REASON_REPLAY = 3,",
            "GATEWAY_DROP_REASON_ACL = 4,",
            "GATEWAY_LOCK_REASON_NONE = 0,",
            "GATEWAY_LOCK_REASON_MANUAL = 1,",
            "GATEWAY_LOCK_REASON_AUTH_THRESHOLD = 2,",
            "GATEWAY_LOCK_REASON_REPLAY_THRESHOLD = 3,",
            "static gateway_drop_reason_t g_last_drop_reason;",
            "static gateway_lock_reason_t g_last_lock_reason;",
        ):
            self.assertIn(token, text)

    def test_gateway_runtime_updates_reason_latches_on_real_drop_and_lock_paths(self):
        text = self.text

        for token in (
            "g_last_lock_reason = GATEWAY_LOCK_REASON_MANUAL;",
            "g_last_lock_reason = GATEWAY_LOCK_REASON_AUTH_THRESHOLD;",
            "g_last_lock_reason = GATEWAY_LOCK_REASON_REPLAY_THRESHOLD;",
            "g_last_drop_reason = GATEWAY_DROP_REASON_INVALID;",
            "g_last_drop_reason = GATEWAY_DROP_REASON_UNAUTHORIZED;",
            "g_last_drop_reason = GATEWAY_DROP_REASON_REPLAY;",
            "g_last_drop_reason = GATEWAY_DROP_REASON_ACL;",
            "g_last_drop_reason = GATEWAY_DROP_REASON_NONE;",
            "g_last_lock_reason = GATEWAY_LOCK_REASON_NONE;",
        ):
            self.assertIn(token, text)

    def test_gateway_session_struct_tracks_last_active_ms_without_per_session_diag_latches(self):
        match = re.search(
            r"typedef\s+struct\s*\{\s*uint8_t active;.*?\}\s*gateway_session_t;",
            self.text,
            re.S,
        )
        self.assertIsNotNone(match, "gateway_session_t definition missing")
        block = match.group(0)

        self.assertIn("uint32_t last_active_ms;", block)
        for token in (
            "g_last_drop_reason",
            "g_last_lock_reason",
            "acl_hit_seen",
            "replay_seen",
            "timeout_seen",
            "reauth_seen",
            "reauth_pending",
        ):
            self.assertNotIn(token, block)

    def test_gateway_runtime_declares_file_static_sticky_diag_state(self):
        for token in (
            "static gateway_drop_reason_t g_last_drop_reason;",
            "static gateway_lock_reason_t g_last_lock_reason;",
            "static uint8_t g_diag_acl_hit_seen;",
            "static uint8_t g_diag_replay_seen;",
            "static uint8_t g_diag_timeout_seen;",
            "static uint8_t g_diag_reauth_seen;",
            "static uint8_t g_diag_reauth_pending;",
        ):
            self.assertIn(token, self.text)

    def test_gateway_now_ms32_uses_xtime_with_safe_uint64_math(self):
        block = _extract_function_block(self.text, "static uint32_t gateway_now_ms32(void)\n")

        for token in (
            "XTime now_ticks;",
            "uint64_t now_ms;",
            "XTime_GetTime(&now_ticks);",
            "((uint64_t)now_ticks * 1000ULL) / (uint64_t)COUNTS_PER_SECOND",
            "return (uint32_t)now_ms;",
        ):
            self.assertIn(token, block)

    def test_gateway_timeout_invalidation_clears_session_without_locking_and_marks_pending_reauth(self):
        block = _extract_function_block(
            self.text,
            "static void gateway_timeout_invalidate_session(gateway_session_t *session)\n",
        )

        for token in (
            "uint8_t had_authorized = 0U;",
            "had_authorized = (session->authorized_algos != 0U) ? 1U : 0U;",
            "memset(session, 0, sizeof(*session));",
            "g_diag_timeout_seen = 1U;",
            "if (had_authorized != 0U) {",
            "g_diag_reauth_pending = 1U;",
            "gateway_hw_sync_cache_invalidate();",
        ):
            self.assertIn(token, block)

        self.assertNotIn("gateway_lock_session(", block)
        self.assertNotIn("session->locked = 1U;", block)

    def test_gateway_session_lookup_expires_idle_sessions_before_reuse(self):
        block = _extract_function_block(self.text, "static gateway_session_t *gateway_find_session_by_ip(const ip_addr_t *remote_ip)")

        for token in (
            "gateway_session_expire_if_idle(&g_sessions[i]);",
            "if (g_sessions[i].active != 0U) {",
        ):
            self.assertIn(token, block)

    def test_gateway_status_payload_packs_seen_bits_above_existing_reason_fields(self):
        block = _extract_function_block(self.text, "static void gateway_pack_status_payload(uint8_t *out, const gateway_session_t *session)")

        for token in (
            "authorized_mask_word |= ((uint32_t)g_diag_acl_hit_seen & 0x1U) << 16;",
            "authorized_mask_word |= ((uint32_t)g_diag_replay_seen & 0x1U) << 17;",
            "authorized_mask_word |= ((uint32_t)g_diag_timeout_seen & 0x1U) << 18;",
            "authorized_mask_word |= ((uint32_t)g_diag_reauth_seen & 0x1U) << 19;",
            "authorized_mask_word |= ((uint32_t)g_last_drop_reason & 0xFU) << 8;",
            "authorized_mask_word |= ((uint32_t)g_last_lock_reason & 0xFU) << 12;",
        ):
            self.assertIn(token, block)

    def test_gateway_set_key_success_clears_sticky_diag_bits_and_promotes_timeout_reauth(self):
        block = _extract_function_block(
            self.text,
            "static void udp_control_callback(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)",
        )

        for token in (
            "uint8_t reauth_pending = g_diag_reauth_pending;",
            "g_last_drop_reason = GATEWAY_DROP_REASON_NONE;",
            "g_last_lock_reason = GATEWAY_LOCK_REASON_NONE;",
            "g_diag_acl_hit_seen = 0U;",
            "g_diag_replay_seen = 0U;",
            "g_diag_timeout_seen = 0U;",
            "g_diag_reauth_seen = 0U;",
            "g_diag_reauth_pending = 0U;",
            "if (reauth_pending != 0U) {",
            "g_diag_reauth_seen = 1U;",
        ):
            self.assertIn(token, block)

    def test_gateway_acl_and_replay_drop_paths_latch_seen_bits(self):
        text = self.text

        for token in (
            "g_diag_acl_hit_seen = 1U;",
            "g_diag_replay_seen = 1U;",
            "g_diag_timeout_seen = 1U;",
        ):
            self.assertIn(token, text)

    def test_gateway_refreshes_last_active_only_on_successful_control_and_data_reply_paths(self):
        control_block = _extract_function_block(
            self.text,
            "static void udp_control_callback(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)",
        )
        send_block = _extract_function_block(self.text, "static int send_active_response(void)")
        rx_block = _extract_function_block(
            self.text,
            "static void udp_rx_callback(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)",
        )

        self.assertIn("gateway_refresh_session_activity(session);", control_block)
        self.assertIn("gateway_refresh_session_activity(active_session);", send_block)
        self.assertNotIn("gateway_refresh_session_activity(", rx_block)

    def test_udp_crypto_control_decodes_reason_bits_without_changing_authorized_mask_semantics(self):
        text = self.udp_control_py

        for token in (
            'status["authorized_mask_raw"] = fields[2]',
            'status["authorized_mask"] = fields[2] & 0xFF',
            'status["last_drop_reason"] = (fields[2] >> 8) & 0xF',
            'status["last_lock_reason"] = (fields[2] >> 12) & 0xF',
        ):
            self.assertIn(token, text)

    def test_dma_driver_exposes_crypto_nodoorbell_submission(self):
        self.assertIn("int dma_ring_submit_nodoorbell(", self.dma_driver_h)
        self.assertIn("int dma_ring_submit_batch(", self.dma_driver_h)
        self.assertIn("int dma_ring_submit_nodoorbell(", self.dma_driver_c)
        self.assertIn("int dma_ring_submit_batch(", self.dma_driver_c)

    def test_crypto_dma_subsystem_consumes_real_ring_doorbell(self):
        self.assertIn(".i_ring_doorbell(ring_doorbell)", self.crypto_dma_subsystem)
        self.assertNotIn(".i_ring_doorbell(1'b1)", self.crypto_dma_subsystem)

    def test_dma_fetcher_uses_doorbell_as_batch_wake_event(self):
        self.assertIn("always_ff @(posedge clk or negedge rst_n) begin", self.dma_fetcher)
        self.assertIn("if (i_ring_doorbell) begin", self.dma_fetcher)
        self.assertIn("fetch_active <= 1'b1;", self.dma_fetcher)
        self.assertIn("if ((i_ring_doorbell || fetch_active) &&", self.dma_fetcher)
        self.assertIn("if (next_head_ptr == i_sw_tail_ptr)", self.dma_fetcher)

    def test_crypto_dma_subsystem_consumes_fetcher_src_addr_instead_of_unused_stub(self):
        text = self.crypto_dma_subsystem

        self.assertNotIn("fetcher_src_addr_unused", text)
        self.assertIn("fetcher_src_addr", text)
        self.assertIn(".o_dma_src_addr(fetcher_src_addr)", text)

    def test_crypto_dma_subsystem_instantiates_descriptor_driven_source_reader(self):
        text = self.crypto_dma_subsystem

        self.assertIn("dma_crypto_source_reader", text)
        self.assertIn("u_dma_crypto_source_reader", text)
        self.assertIn("source_reader_start", text)
        self.assertIn(".i_start(source_reader_start)", text)
        self.assertIn(".i_src_addr(fetcher_src_addr)", text)
        self.assertIn(".i_total_len(final_len)", text)

    def test_crypto_dma_subsystem_muxes_crypto_input_between_pbm_and_ddr_source(self):
        text = self.crypto_dma_subsystem

        for token in (
            "crypto_src_data",
            "crypto_src_empty",
            "crypto_src_valid",
            "crypto_src_rd_en",
            "assign crypto_src_data = use_desc_source ? source_rd_data : pbm_data;",
            "assign crypto_src_empty = use_desc_source ? source_rd_empty : pbm_empty;",
            "assign crypto_src_valid = use_desc_source ? source_rd_valid : bridge_rd_valid;",
            "assign source_rd_en = use_desc_source ? crypto_src_rd_en : 1'b0;",
            "assign bridge_rd_pbm = use_desc_source ? 1'b0 : crypto_src_rd_en;",
            ".i_pbm_data(crypto_src_data)",
            ".i_pbm_empty(crypto_src_empty)",
            ".i_pbm_valid(crypto_src_valid)",
            ".o_pbm_rd_en(crypto_src_rd_en)",
        ):
            self.assertIn(token, text)

    def test_crypto_dma_subsystem_latches_batch_debug_status_until_next_doorbell(self):
        text = self.crypto_dma_subsystem

        for token in (
            "source_error_sticky_q",
            "sink_error_sticky_q",
            "source_done_sticky_q",
            "sink_done_sticky_q",
            "debug_source_rresp_q",
            "debug_sink_bresp_q",
            "source_progress_sticky_q",
            "sink_progress_sticky_q",
            "if (!rst_n) begin",
            "else if (csr_soft_reset || ring_doorbell) begin",
            "if (source_error) begin",
            "if (sink_error) begin",
            "if (source_done) begin",
            "if (sink_done) begin",
            "if (source_rvalid && source_rready) begin",
            "if (source_bytes_fetched > source_progress_sticky_q)",
            "if (sink_bytes_written > sink_progress_sticky_q)",
            "assign csr_debug_source_progress = source_progress_sticky_q;",
            "assign csr_debug_sink_progress = sink_progress_sticky_q;",
        ):
            self.assertIn(token, text)

    def test_crypto_dma_subsystem_forwards_s2mm_awvalid(self):
        text = self.crypto_dma_subsystem

        self.assertIn("assign m_axis_s2mm_awvalid = s2mm_awvalid;", text)
        self.assertIn(".m_axis_awvalid(s2mm_awvalid)", text)

    def test_crypto_dma_subsystem_propagates_ingress_error_into_pbm_rollback(self):
        text = self.crypto_dma_subsystem

        for token in (
            "input  logic                   rx_wr_error,",
            ".i_wr_valid(rx_wr_valid), .i_wr_data(rx_wr_data), .i_wr_last(rx_wr_last), .i_wr_error(rx_wr_error),",
            ".o_rollback_active()",
        ):
            self.assertIn(token, text)

    def test_dma_crypto_source_reader_exposes_fifo_like_bridge_contract(self):
        text = self.dma_crypto_source_reader

        self.assertIn("module dma_crypto_source_reader #(", text)
        for token in (
            "input  logic                    i_start,",
            "input  logic [ADDR_WIDTH-1:0]   i_src_addr,",
            "input  logic [31:0]             i_total_len,",
            "output logic [DATA_WIDTH-1:0]   o_rd_data,",
            "output logic                    o_rd_valid,",
            "output logic                    o_rd_empty,",
            "input  logic                    i_rd_en,",
            "output logic                    o_done,",
            "output logic                    o_error,",
            "dma_axis_fifo_wrapper",
        ):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
