`timescale 1ns / 1ps

module dma_raw_copy_subsystem #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter FIFO_DEPTH = dma_csr_pkg::DMA_RAW_COPY_FIFO_DEPTH
)(
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic [ADDR_WIDTH-1:0]  s_axil_awaddr,
    input  logic                   s_axil_awvalid,
    output logic                   s_axil_awready,
    input  logic [DATA_WIDTH-1:0]  s_axil_wdata,
    input  logic [3:0]             s_axil_wstrb,
    input  logic                   s_axil_wvalid,
    output logic                   s_axil_wready,
    output logic [1:0]             s_axil_bresp,
    output logic                   s_axil_bvalid,
    input  logic                   s_axil_bready,
    input  logic [ADDR_WIDTH-1:0]  s_axil_araddr,
    input  logic                   s_axil_arvalid,
    output logic                   s_axil_arready,
    output logic [DATA_WIDTH-1:0]  s_axil_rdata,
    output logic [1:0]             s_axil_rresp,
    output logic                   s_axil_rvalid,
    input  logic                   s_axil_rready,

    input  logic [DATA_WIDTH-1:0]  s_axis_tdata,
    input  logic                   s_axis_tvalid,
    output logic                   s_axis_tready,
    input  logic                   s_axis_tlast,

    output logic [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output logic [7:0]             m_axi_awlen,
    output logic [2:0]             m_axi_awsize,
    output logic [1:0]             m_axi_awburst,
    output logic [3:0]             m_axi_awcache,
    output logic [2:0]             m_axi_awprot,
    output logic                   m_axi_awvalid,
    input  logic                   m_axi_awready,
    output logic [DATA_WIDTH-1:0]  m_axi_wdata,
    output logic [DATA_WIDTH/8-1:0] m_axi_wstrb,
    output logic                   m_axi_wlast,
    output logic                   m_axi_wvalid,
    input  logic                   m_axi_wready,
    input  logic [1:0]             m_axi_bresp,
    input  logic                   m_axi_bvalid,
    output logic                   m_axi_bready,

    output logic [ADDR_WIDTH-1:0]  m_axi_araddr,
    output logic [7:0]             m_axi_arlen,
    output logic [2:0]             m_axi_arsize,
    output logic [1:0]             m_axi_arburst,
    output logic                   m_axi_arvalid,
    input  logic                   m_axi_arready,
    input  logic [DATA_WIDTH-1:0]  m_axi_rdata,
    input  logic [1:0]             m_axi_rresp,
    input  logic                   m_axi_rlast,
    input  logic                   m_axi_rvalid,
    output logic                   m_axi_rready,

    output logic [ADDR_WIDTH-1:0]  m_axi_fetcher_araddr,
    output logic [7:0]             m_axi_fetcher_arlen,
    output logic [2:0]             m_axi_fetcher_arsize,
    output logic [1:0]             m_axi_fetcher_arburst,
    output logic                   m_axi_fetcher_arvalid,
    input  logic                   m_axi_fetcher_arready,
    input  logic [DATA_WIDTH-1:0]  m_axi_fetcher_rdata,
    input  logic [1:0]             m_axi_fetcher_rresp,
    input  logic                   m_axi_fetcher_rlast,
    input  logic                   m_axi_fetcher_rvalid,
    output logic                   m_axi_fetcher_rready,

    output logic [ADDR_WIDTH-1:0]  m_axi_wb_awaddr,
    output logic [7:0]             m_axi_wb_awlen,
    output logic [2:0]             m_axi_wb_awsize,
    output logic [1:0]             m_axi_wb_awburst,
    output logic [3:0]             m_axi_wb_awcache,
    output logic [2:0]             m_axi_wb_awprot,
    output logic                   m_axi_wb_awvalid,
    input  logic                   m_axi_wb_awready,
    output logic [DATA_WIDTH-1:0]  m_axi_wb_wdata,
    output logic [3:0]             m_axi_wb_wstrb,
    output logic                   m_axi_wb_wlast,
    output logic                   m_axi_wb_wvalid,
    input  logic                   m_axi_wb_wready,
    input  logic [1:0]             m_axi_wb_bresp,
    input  logic                   m_axi_wb_bvalid,
    output logic                   m_axi_wb_bready,

    output logic                   dma_irq
);

    import dma_csr_pkg::*;

    logic                   ring_doorbell;
    logic [31:0]            ring_base;
    logic [31:0]            ring_size;
    logic [15:0]            sw_tail;
    logic [15:0]            hw_head;
    logic                   csr_hw_init_unused;
    logic                   csr_algo_sel_unused;
    logic                   csr_enc_dec_unused;
    logic                   csr_s2mm_en_unused;
    logic                   csr_mm2s_en_unused;
    logic                   csr_auth_en_unused;
    logic                   csr_acl_en_unused;
    logic                   csr_dna_lock_en_unused;
    logic                   csr_soft_reset;
    logic                   csr_start_unused;
    logic [31:0]            csr_s2mm_addr_unused;
    logic [31:0]            csr_s2mm_data_unused;
    logic [1:0]             csr_loopback_mode_unused;
    logic                   csr_acl_write_en_unused;
    logic                   csr_acl_clear_unused;
    logic [11:0]            csr_acl_write_addr_unused;
    logic [103:0]           csr_acl_write_data_unused;
    logic                   csr_network_enable_unused;
    logic                   csr_network_ingress_sel_unused;
    logic                   csr_arp_enable_unused;
    logic [31:0]            csr_net_local_ip_unused;
    logic [47:0]            csr_net_local_mac_unused;
    logic                   csr_net_cfg0_we_unused;
    logic                   csr_net_local_ip_we_unused;
    logic                   csr_net_local_mac_lo_we_unused;
    logic                   csr_net_local_mac_hi_we_unused;
    logic                   csr_inj_clear_unused;
    logic                   csr_inj_push_unused;
    logic [31:0]            csr_inj_data_unused;
    logic [15:0]            csr_inj_expected_words_unused;
    logic                   csr_txcap_clear_unused;
    logic                   csr_txcap_pop_unused;
    logic [31:0]            csr_base_addr_unused;
    logic [31:0]            csr_len_unused;
    logic [127:0]           csr_key_unused;
    logic [127:0]           csr_key_hi_unused;
    logic                   csr_aes256_en_unused;
    logic                   csr_cache_flush_unused;
    logic [31:0]            csr_acl_cnt_unused;
    logic                   dma_done;
    logic                   dma_error;
    logic                   dma_busy;
    logic [1:0]             dma_bresp;
    logic [31:0]            dma_actual_len;
    logic                   fetch_dma_start;
    logic [31:0]            fetch_dma_dst_addr;
    logic [31:0]            fetch_dma_src_addr;
    logic [31:0]            fetch_dma_len;
    logic                   fetch_dma_algo;
    logic                   fetch_dma_stream_tlast;
    logic                   fetch_wb_active;
    logic                   fetch_completion_event;
    logic                   csr_irq_enable;
    logic                   csr_irq_ack;
    logic [31:0]            csr_irq_status;
    logic [31:0]            csr_irq_coalesce_count;
    logic [31:0]            csr_irq_coalesce_timeout;
    logic [31:0]            irq_pending_count_q;
    logic [31:0]            irq_elapsed_cycles_q;
    logic                   irq_pending_q;
    logic [31:0]            irq_pending_count_n;
    logic [31:0]            irq_elapsed_cycles_n;
    logic                   irq_pending_n;

    axil_csr #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .RAW_COPY_IRQ_WINDOW(1'b1)
    ) u_csr (
        .clk(clk),
        .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr),
        .s_axil_awvalid(s_axil_awvalid),
        .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata),
        .s_axil_wstrb(s_axil_wstrb),
        .s_axil_wvalid(s_axil_wvalid),
        .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp),
        .s_axil_bvalid(s_axil_bvalid),
        .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr),
        .s_axil_arvalid(s_axil_arvalid),
        .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata),
        .s_axil_rresp(s_axil_rresp),
        .s_axil_rvalid(s_axil_rvalid),
        .s_axil_rready(s_axil_rready),
        .o_start(csr_start_unused),
        .o_hw_init(csr_hw_init_unused),
        .o_algo_sel(csr_algo_sel_unused),
        .o_enc_dec(csr_enc_dec_unused),
        .o_s2mm_en(csr_s2mm_en_unused),
        .o_mm2s_en(csr_mm2s_en_unused),
        .o_auth_en(csr_auth_en_unused),
        .o_acl_en(csr_acl_en_unused),
        .o_dna_lock_en(csr_dna_lock_en_unused),
        .o_soft_reset(csr_soft_reset),
        .o_s2mm_addr(csr_s2mm_addr_unused),
        .o_s2mm_data(csr_s2mm_data_unused),
        .o_loopback_mode(csr_loopback_mode_unused),
        .o_acl_write_en(csr_acl_write_en_unused),
        .o_acl_clear(csr_acl_clear_unused),
        .o_acl_write_addr(csr_acl_write_addr_unused),
        .o_acl_write_data(csr_acl_write_data_unused),
        .o_network_enable(csr_network_enable_unused),
        .o_network_ingress_sel(csr_network_ingress_sel_unused),
        .o_arp_enable(csr_arp_enable_unused),
        .o_net_local_ip(csr_net_local_ip_unused),
        .o_net_local_mac(csr_net_local_mac_unused),
        .o_net_cfg0_we(csr_net_cfg0_we_unused),
        .o_net_local_ip_we(csr_net_local_ip_we_unused),
        .o_net_local_mac_lo_we(csr_net_local_mac_lo_we_unused),
        .o_net_local_mac_hi_we(csr_net_local_mac_hi_we_unused),
        .o_inj_clear(csr_inj_clear_unused),
        .o_inj_push(csr_inj_push_unused),
        .o_inj_data(csr_inj_data_unused),
        .o_inj_expected_words(csr_inj_expected_words_unused),
        .o_txcap_clear(csr_txcap_clear_unused),
        .o_txcap_pop(csr_txcap_pop_unused),
        .o_base_addr(csr_base_addr_unused),
        .o_len(csr_len_unused),
        .o_key(csr_key_unused),
        .o_key_hi(csr_key_hi_unused),
        .o_aes256_en(csr_aes256_en_unused),
        .o_cache_flush(csr_cache_flush_unused),
        .o_acl_cnt(csr_acl_cnt_unused),
        .o_ring_doorbell(ring_doorbell),
        .o_ring_base(ring_base),
        .o_ring_size(ring_size),
        .o_sw_tail_ptr(sw_tail),
        .i_hw_head_ptr(hw_head),
        .o_irq_enable(csr_irq_enable),
        .o_irq_ack(csr_irq_ack),
        .o_irq_coalesce_count(csr_irq_coalesce_count),
        .o_irq_coalesce_timeout(csr_irq_coalesce_timeout),
        .i_irq_status(csr_irq_status),
        .i_debug_status(32'd0),
        .i_debug_source_progress(32'd0),
        .i_debug_sink_progress(32'd0),
        .i_debug_plaintext_word0(32'd0),
        .i_debug_plaintext_word1(32'd0),
        .i_debug_plaintext_word2(32'd0),
        .i_debug_plaintext_word3(32'd0),
        .i_debug_key_word0(32'd0),
        .i_debug_key_word1(32'd0),
        .i_debug_key_word2(32'd0),
        .i_debug_key_word3(32'd0),
        .i_done(dma_done),
        .i_error(dma_error),
        .i_busy(dma_busy),
        .i_inj_status(32'd0),
        .i_txcap_status(32'd0),
        .i_txcap_data(32'd0),
        .i_netdbg_status(32'd0),
        .i_net_applied_cfg0(32'd0),
        .i_net_applied_local_ip(32'd0),
        .i_net_applied_local_mac_lo(32'd0),
        .i_net_applied_local_mac_hi(32'd0),
        .i_drop_wrong_port_count(32'd0),
        .i_drop_unaligned_count(32'd0),
        .i_acl_inc(1'b0)
    );

    dma_desc_fetcher #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_fetcher (
        .clk(clk),
        .rst_n(rst_n),
        .i_soft_reset(csr_soft_reset),
        .i_ring_base(ring_base),
        .i_ring_size(ring_size),
        .i_ring_doorbell(ring_doorbell),
        .i_sw_tail_ptr(sw_tail),
        .o_hw_head_ptr(hw_head),
        .o_dma_start(fetch_dma_start),
        .o_dma_addr(fetch_dma_dst_addr),
        .o_dma_src_addr(fetch_dma_src_addr),
        .o_dma_len(fetch_dma_len),
        .o_dma_algo(fetch_dma_algo),
        .o_dma_stream_tlast(fetch_dma_stream_tlast),
        .i_dma_done(dma_done),
        .i_dma_error(dma_error),
        .i_dma_bresp(dma_bresp),
        .i_dma_actual_len(dma_actual_len),
        .o_completion_event(fetch_completion_event),
        .m_axi_araddr(m_axi_fetcher_araddr),
        .m_axi_arlen(m_axi_fetcher_arlen),
        .m_axi_arsize(m_axi_fetcher_arsize),
        .m_axi_arburst(m_axi_fetcher_arburst),
        .m_axi_arvalid(m_axi_fetcher_arvalid),
        .m_axi_arready(m_axi_fetcher_arready),
        .m_axi_rdata(m_axi_fetcher_rdata),
        .m_axi_rlast(m_axi_fetcher_rlast),
        .m_axi_rvalid(m_axi_fetcher_rvalid),
        .m_axi_rready(m_axi_fetcher_rready),
        .m_axi_awaddr(m_axi_wb_awaddr),
        .m_axi_awlen(m_axi_wb_awlen),
        .m_axi_awsize(m_axi_wb_awsize),
        .m_axi_awburst(m_axi_wb_awburst),
        .m_axi_awcache(m_axi_wb_awcache),
        .m_axi_awprot(m_axi_wb_awprot),
        .m_axi_awvalid(m_axi_wb_awvalid),
        .m_axi_awready(m_axi_wb_awready),
        .m_axi_wdata(m_axi_wb_wdata),
        .m_axi_wstrb(m_axi_wb_wstrb),
        .m_axi_wlast(m_axi_wb_wlast),
        .m_axi_wvalid(m_axi_wb_wvalid),
        .m_axi_wready(m_axi_wb_wready),
        .m_axi_bresp(m_axi_wb_bresp),
        .m_axi_bvalid(m_axi_wb_bvalid),
        .m_axi_bready(m_axi_wb_bready),
        .o_wb_active(fetch_wb_active)
    );

    // Stream/TLAST mode is carried all the way into the engine now, even though
    // the current raw-copy datapath still uses memory-backed capacity-bounded
    // transfers. This keeps the Phase 3 contract live without mixing gateway
    // integration into the smoke subsystem.
    dma_raw_copy_engine #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_raw_copy (
        .clk(clk),
        .rst_n(rst_n),
        .i_soft_reset(csr_soft_reset),
        .i_start(fetch_dma_start),
        .i_stream_tlast(fetch_dma_stream_tlast),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .i_src_addr(fetch_dma_src_addr),
        .i_dst_addr(fetch_dma_dst_addr),
        .i_total_len(fetch_dma_len),
        .o_actual_len(dma_actual_len),
        .o_done(dma_done),
        .o_error(dma_error),
        .o_busy(dma_busy),
        .o_bresp(dma_bresp),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );

    always_comb begin
        irq_pending_count_n = irq_pending_count_q;
        irq_elapsed_cycles_n = irq_elapsed_cycles_q;
        irq_pending_n = irq_pending_q;

        if (csr_irq_ack) begin
            irq_pending_count_n = 32'd0;
            irq_elapsed_cycles_n = 32'd0;
            irq_pending_n = 1'b0;
        end else begin
            if (fetch_completion_event) begin
                irq_pending_count_n = irq_pending_count_q + 32'd1;
                irq_elapsed_cycles_n = 32'd0;
            end else if ((irq_pending_count_q != 32'd0) && !irq_pending_q) begin
                irq_elapsed_cycles_n = irq_elapsed_cycles_q + 32'd1;
            end

            if (!irq_pending_q && (irq_pending_count_n != 32'd0)) begin
                if (((csr_irq_coalesce_count != 32'd0) &&
                     (irq_pending_count_n >= csr_irq_coalesce_count)) ||
                    ((csr_irq_coalesce_timeout != 32'd0) &&
                     (irq_elapsed_cycles_n >= csr_irq_coalesce_timeout))) begin
                    irq_pending_n = 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_pending_count_q <= 32'd0;
            irq_elapsed_cycles_q <= 32'd0;
            irq_pending_q <= 1'b0;
        end else if (csr_soft_reset) begin
            irq_pending_count_q <= 32'd0;
            irq_elapsed_cycles_q <= 32'd0;
            irq_pending_q <= 1'b0;
        end else begin
            irq_pending_count_q <= irq_pending_count_n;
            irq_elapsed_cycles_q <= irq_elapsed_cycles_n;
            irq_pending_q <= irq_pending_n;
        end
    end

    assign csr_irq_status = irq_pending_q ? DMA_IRQ_STATUS_DONE_PENDING : 32'd0;
    assign dma_irq = csr_irq_enable && irq_pending_q;

endmodule
