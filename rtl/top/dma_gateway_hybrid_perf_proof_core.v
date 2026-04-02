`timescale 1ns / 1ps

module dma_gateway_hybrid_perf_proof_core #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    output wire                    dma_irq,

    input  wire [ADDR_WIDTH-1:0]   s_axil_ctrl_awaddr,
    input  wire                    s_axil_ctrl_awvalid,
    output wire                    s_axil_ctrl_awready,
    input  wire [DATA_WIDTH-1:0]   s_axil_ctrl_wdata,
    input  wire [3:0]              s_axil_ctrl_wstrb,
    input  wire                    s_axil_ctrl_wvalid,
    output wire                    s_axil_ctrl_wready,
    output wire [1:0]              s_axil_ctrl_bresp,
    output wire                    s_axil_ctrl_bvalid,
    input  wire                    s_axil_ctrl_bready,
    input  wire [ADDR_WIDTH-1:0]   s_axil_ctrl_araddr,
    input  wire                    s_axil_ctrl_arvalid,
    output wire                    s_axil_ctrl_arready,
    output wire [DATA_WIDTH-1:0]   s_axil_ctrl_rdata,
    output wire [1:0]              s_axil_ctrl_rresp,
    output wire                    s_axil_ctrl_rvalid,
    input  wire                    s_axil_ctrl_rready,

    input  wire [ADDR_WIDTH-1:0]   s_axil_dma_awaddr,
    input  wire                    s_axil_dma_awvalid,
    output wire                    s_axil_dma_awready,
    input  wire [DATA_WIDTH-1:0]   s_axil_dma_wdata,
    input  wire [3:0]              s_axil_dma_wstrb,
    input  wire                    s_axil_dma_wvalid,
    output wire                    s_axil_dma_wready,
    output wire [1:0]              s_axil_dma_bresp,
    output wire                    s_axil_dma_bvalid,
    input  wire                    s_axil_dma_bready,
    input  wire [ADDR_WIDTH-1:0]   s_axil_dma_araddr,
    input  wire                    s_axil_dma_arvalid,
    output wire                    s_axil_dma_arready,
    output wire [DATA_WIDTH-1:0]   s_axil_dma_rdata,
    output wire [1:0]              s_axil_dma_rresp,
    output wire                    s_axil_dma_rvalid,
    input  wire                    s_axil_dma_rready,

    output wire [ADDR_WIDTH-1:0]   m_axi_dma_wr_awaddr,
    output wire [7:0]              m_axi_dma_wr_awlen,
    output wire [2:0]              m_axi_dma_wr_awsize,
    output wire [1:0]              m_axi_dma_wr_awburst,
    output wire [3:0]              m_axi_dma_wr_awcache,
    output wire [2:0]              m_axi_dma_wr_awprot,
    output wire                    m_axi_dma_wr_awvalid,
    input  wire                    m_axi_dma_wr_awready,
    output wire [DATA_WIDTH-1:0]   m_axi_dma_wr_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axi_dma_wr_wstrb,
    output wire                    m_axi_dma_wr_wlast,
    output wire                    m_axi_dma_wr_wvalid,
    input  wire                    m_axi_dma_wr_wready,
    input  wire [1:0]              m_axi_dma_wr_bresp,
    input  wire                    m_axi_dma_wr_bvalid,
    output wire                    m_axi_dma_wr_bready,

    output wire [ADDR_WIDTH-1:0]   m_axi_s2mm_awaddr,
    output wire [7:0]              m_axi_s2mm_awlen,
    output wire [2:0]              m_axi_s2mm_awsize,
    output wire [1:0]              m_axi_s2mm_awburst,
    output wire [3:0]              m_axi_s2mm_awcache,
    output wire [2:0]              m_axi_s2mm_awprot,
    output wire                    m_axi_s2mm_awvalid,
    input  wire                    m_axi_s2mm_awready,
    output wire [DATA_WIDTH-1:0]   m_axi_s2mm_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axi_s2mm_wstrb,
    output wire                    m_axi_s2mm_wlast,
    output wire                    m_axi_s2mm_wvalid,
    input  wire                    m_axi_s2mm_wready,
    input  wire [1:0]              m_axi_s2mm_bresp,
    input  wire                    m_axi_s2mm_bvalid,
    output wire                    m_axi_s2mm_bready,
    output wire [ADDR_WIDTH-1:0]   m_axi_s2mm_araddr,
    output wire [7:0]              m_axi_s2mm_arlen,
    output wire [2:0]              m_axi_s2mm_arsize,
    output wire [1:0]              m_axi_s2mm_arburst,
    output wire                    m_axi_s2mm_arvalid,
    input  wire                    m_axi_s2mm_arready,
    input  wire [DATA_WIDTH-1:0]   m_axi_s2mm_rdata,
    input  wire [1:0]              m_axi_s2mm_rresp,
    input  wire                    m_axi_s2mm_rlast,
    input  wire                    m_axi_s2mm_rvalid,
    output wire                    m_axi_s2mm_rready,

    output wire [ADDR_WIDTH-1:0]   m_axi_fetcher_araddr,
    output wire [7:0]              m_axi_fetcher_arlen,
    output wire [2:0]              m_axi_fetcher_arsize,
    output wire [1:0]              m_axi_fetcher_arburst,
    output wire                    m_axi_fetcher_arvalid,
    input  wire                    m_axi_fetcher_arready,
    input  wire [DATA_WIDTH-1:0]   m_axi_fetcher_rdata,
    input  wire [1:0]              m_axi_fetcher_rresp,
    input  wire                    m_axi_fetcher_rlast,
    input  wire                    m_axi_fetcher_rvalid,
    output wire                    m_axi_fetcher_rready
);

    wire                  ctrl_start_unused;
    wire                  ctrl_hw_init_unused;
    wire                  ctrl_algo_sel_unused;
    wire                  ctrl_enc_dec_unused;
    wire                  ctrl_s2mm_en_unused;
    wire                  ctrl_mm2s_en_unused;
    wire                  ctrl_auth_en_unused;
    wire                  ctrl_acl_en_unused;
    wire                  ctrl_dna_lock_unused;
    wire                  ctrl_soft_reset_unused;
    wire [31:0]           ctrl_s2mm_addr_unused;
    wire [31:0]           ctrl_s2mm_data_unused;
    wire [1:0]            ctrl_loopback_unused;
    wire                  ctrl_acl_write_en_unused;
    wire                  ctrl_acl_clear_unused;
    wire [11:0]           ctrl_acl_write_addr_unused;
    wire [103:0]          ctrl_acl_write_data_unused;
    wire                  ctrl_network_enable_unused;
    wire                  ctrl_network_ingress_sel_unused;
    wire                  ctrl_arp_enable_unused;
    wire [31:0]           ctrl_net_local_ip_unused;
    wire [47:0]           ctrl_net_local_mac_unused;
    wire                  ctrl_net_cfg0_we_unused;
    wire                  ctrl_net_local_ip_we_unused;
    wire                  ctrl_net_local_mac_lo_we_unused;
    wire                  ctrl_net_local_mac_hi_we_unused;
    wire                  ctrl_inj_clear_unused;
    wire                  ctrl_inj_push_unused;
    wire [31:0]           ctrl_inj_data_unused;
    wire [15:0]           ctrl_inj_expected_words_unused;
    wire                  ctrl_txcap_clear_unused;
    wire                  ctrl_txcap_pop_unused;
    wire [31:0]           ctrl_base_addr_unused;
    wire [31:0]           ctrl_len_unused;
    wire [127:0]          ctrl_key_unused;
    wire [127:0]          ctrl_key_hi_unused;
    wire                  ctrl_aes256_unused;
    wire                  ctrl_cache_flush_unused;
    wire [31:0]           ctrl_acl_cnt_unused;
    wire                  ctrl_ring_doorbell_unused;
    wire [31:0]           ctrl_ring_base_unused;
    wire [31:0]           ctrl_ring_size_unused;
    wire [15:0]           ctrl_sw_tail_unused;
    wire                  ctrl_irq_enable_unused;
    wire                  ctrl_irq_ack_unused;
    wire [31:0]           ctrl_irq_count_unused;
    wire [31:0]           ctrl_irq_timeout_unused;

    wire [31:0]           tx_axis_tdata_unused;
    wire                  tx_axis_tvalid_unused;
    wire                  tx_axis_tlast_unused;
    wire [3:0]            tx_axis_tkeep_unused;

    assign dma_irq = 1'b0;

    axil_csr #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_ctrl_csr (
        .clk(clk),
        .rst_n(rst_n),
        .s_axil_awaddr(s_axil_ctrl_awaddr),
        .s_axil_awvalid(s_axil_ctrl_awvalid),
        .s_axil_awready(s_axil_ctrl_awready),
        .s_axil_wdata(s_axil_ctrl_wdata),
        .s_axil_wstrb(s_axil_ctrl_wstrb),
        .s_axil_wvalid(s_axil_ctrl_wvalid),
        .s_axil_wready(s_axil_ctrl_wready),
        .s_axil_bresp(s_axil_ctrl_bresp),
        .s_axil_bvalid(s_axil_ctrl_bvalid),
        .s_axil_bready(s_axil_ctrl_bready),
        .s_axil_araddr(s_axil_ctrl_araddr),
        .s_axil_arvalid(s_axil_ctrl_arvalid),
        .s_axil_arready(s_axil_ctrl_arready),
        .s_axil_rdata(s_axil_ctrl_rdata),
        .s_axil_rresp(s_axil_ctrl_rresp),
        .s_axil_rvalid(s_axil_ctrl_rvalid),
        .s_axil_rready(s_axil_ctrl_rready),
        .o_start(ctrl_start_unused),
        .o_hw_init(ctrl_hw_init_unused),
        .o_algo_sel(ctrl_algo_sel_unused),
        .o_enc_dec(ctrl_enc_dec_unused),
        .o_s2mm_en(ctrl_s2mm_en_unused),
        .o_mm2s_en(ctrl_mm2s_en_unused),
        .o_auth_en(ctrl_auth_en_unused),
        .o_acl_en(ctrl_acl_en_unused),
        .o_dna_lock_en(ctrl_dna_lock_unused),
        .o_soft_reset(ctrl_soft_reset_unused),
        .o_s2mm_addr(ctrl_s2mm_addr_unused),
        .o_s2mm_data(ctrl_s2mm_data_unused),
        .o_loopback_mode(ctrl_loopback_unused),
        .o_acl_write_en(ctrl_acl_write_en_unused),
        .o_acl_clear(ctrl_acl_clear_unused),
        .o_acl_write_addr(ctrl_acl_write_addr_unused),
        .o_acl_write_data(ctrl_acl_write_data_unused),
        .o_network_enable(ctrl_network_enable_unused),
        .o_network_ingress_sel(ctrl_network_ingress_sel_unused),
        .o_arp_enable(ctrl_arp_enable_unused),
        .o_net_local_ip(ctrl_net_local_ip_unused),
        .o_net_local_mac(ctrl_net_local_mac_unused),
        .o_net_cfg0_we(ctrl_net_cfg0_we_unused),
        .o_net_local_ip_we(ctrl_net_local_ip_we_unused),
        .o_net_local_mac_lo_we(ctrl_net_local_mac_lo_we_unused),
        .o_net_local_mac_hi_we(ctrl_net_local_mac_hi_we_unused),
        .o_inj_clear(ctrl_inj_clear_unused),
        .o_inj_push(ctrl_inj_push_unused),
        .o_inj_data(ctrl_inj_data_unused),
        .o_inj_expected_words(ctrl_inj_expected_words_unused),
        .i_inj_status(32'd0),
        .o_txcap_clear(ctrl_txcap_clear_unused),
        .o_txcap_pop(ctrl_txcap_pop_unused),
        .i_txcap_status(32'd0),
        .i_txcap_data(32'd0),
        .i_netdbg_status(32'd0),
        .i_net_applied_cfg0(32'd0),
        .i_net_applied_local_ip(32'd0),
        .i_net_applied_local_mac_lo(32'd0),
        .i_net_applied_local_mac_hi(32'd0),
        .i_drop_wrong_port_count(32'd0),
        .i_drop_unaligned_count(32'd0),
        .o_base_addr(ctrl_base_addr_unused),
        .o_len(ctrl_len_unused),
        .o_key(ctrl_key_unused),
        .o_key_hi(ctrl_key_hi_unused),
        .o_aes256_en(ctrl_aes256_unused),
        .o_cache_flush(ctrl_cache_flush_unused),
        .i_acl_inc(1'b0),
        .o_acl_cnt(ctrl_acl_cnt_unused),
        .o_ring_doorbell(ctrl_ring_doorbell_unused),
        .o_ring_base(ctrl_ring_base_unused),
        .o_ring_size(ctrl_ring_size_unused),
        .o_sw_tail_ptr(ctrl_sw_tail_unused),
        .i_hw_head_ptr(16'd0),
        .o_irq_enable(ctrl_irq_enable_unused),
        .o_irq_ack(ctrl_irq_ack_unused),
        .o_irq_coalesce_count(ctrl_irq_count_unused),
        .o_irq_coalesce_timeout(ctrl_irq_timeout_unused),
        .i_irq_status(32'd0),
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
         .i_done(1'b0),
        .i_error(1'b0),
        .i_busy(1'b0)
    );

    crypto_dma_subsystem #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .CRYPTO_NUM_INSTANCES(2)
    ) i_hybrid_dma (
        .clk(clk),
        .rst_n(rst_n),
        .s_axil_awaddr(s_axil_dma_awaddr),
        .s_axil_awvalid(s_axil_dma_awvalid),
        .s_axil_awready(s_axil_dma_awready),
        .s_axil_wdata(s_axil_dma_wdata),
        .s_axil_wstrb(s_axil_dma_wstrb),
        .s_axil_wvalid(s_axil_dma_wvalid),
        .s_axil_wready(s_axil_dma_wready),
        .s_axil_bresp(s_axil_dma_bresp),
        .s_axil_bvalid(s_axil_dma_bvalid),
        .s_axil_bready(s_axil_dma_bready),
        .s_axil_araddr(s_axil_dma_araddr),
        .s_axil_arvalid(s_axil_dma_arvalid),
        .s_axil_arready(s_axil_dma_arready),
        .s_axil_rdata(s_axil_dma_rdata),
        .s_axil_rresp(s_axil_dma_rresp),
        .s_axil_rvalid(s_axil_dma_rvalid),
        .s_axil_rready(s_axil_dma_rready),
        .rx_wr_valid(1'b0),
        .rx_wr_data(32'd0),
        .rx_wr_last(1'b0),
        .rx_wr_ready(),
        .tx_axis_tdata(tx_axis_tdata_unused),
        .tx_axis_tvalid(tx_axis_tvalid_unused),
        .tx_axis_tlast(tx_axis_tlast_unused),
        .tx_axis_tkeep(tx_axis_tkeep_unused),
        .tx_axis_tready(1'b0),
        .m_axis_awaddr(m_axi_dma_wr_awaddr),
        .m_axis_awlen(m_axi_dma_wr_awlen),
        .m_axis_awsize(m_axi_dma_wr_awsize),
        .m_axis_awburst(m_axi_dma_wr_awburst),
        .m_axis_awcache(m_axi_dma_wr_awcache),
        .m_axis_awprot(m_axi_dma_wr_awprot),
        .m_axis_awvalid(m_axi_dma_wr_awvalid),
        .m_axis_awready(m_axi_dma_wr_awready),
        .m_axis_wdata(m_axi_dma_wr_wdata),
        .m_axis_wstrb(m_axi_dma_wr_wstrb),
        .m_axis_wlast(m_axi_dma_wr_wlast),
        .m_axis_wvalid(m_axi_dma_wr_wvalid),
        .m_axis_wready(m_axi_dma_wr_wready),
        .m_axis_bresp(m_axi_dma_wr_bresp),
        .m_axis_bvalid(m_axi_dma_wr_bvalid),
        .m_axis_bready(m_axi_dma_wr_bready),
        .m_axis_s2mm_awaddr(m_axi_s2mm_awaddr),
        .m_axis_s2mm_awlen(m_axi_s2mm_awlen),
        .m_axis_s2mm_awsize(m_axi_s2mm_awsize),
        .m_axis_s2mm_awburst(m_axi_s2mm_awburst),
        .m_axis_s2mm_awcache(m_axi_s2mm_awcache),
        .m_axis_s2mm_awprot(m_axi_s2mm_awprot),
        .m_axis_s2mm_awvalid(m_axi_s2mm_awvalid),
        .m_axis_s2mm_awready(m_axi_s2mm_awready),
        .m_axis_s2mm_wdata(m_axi_s2mm_wdata),
        .m_axis_s2mm_wstrb(m_axi_s2mm_wstrb),
        .m_axis_s2mm_wlast(m_axi_s2mm_wlast),
        .m_axis_s2mm_wvalid(m_axi_s2mm_wvalid),
        .m_axis_s2mm_wready(m_axi_s2mm_wready),
        .m_axis_s2mm_bresp(m_axi_s2mm_bresp),
        .m_axis_s2mm_bvalid(m_axi_s2mm_bvalid),
        .m_axis_s2mm_bready(m_axi_s2mm_bready),
        .m_axis_s2mm_araddr(m_axi_s2mm_araddr),
        .m_axis_s2mm_arlen(m_axi_s2mm_arlen),
        .m_axis_s2mm_arsize(m_axi_s2mm_arsize),
        .m_axis_s2mm_arburst(m_axi_s2mm_arburst),
        .m_axis_s2mm_arvalid(m_axi_s2mm_arvalid),
        .m_axis_s2mm_arready(m_axi_s2mm_arready),
        .m_axis_s2mm_rdata(m_axi_s2mm_rdata),
        .m_axis_s2mm_rresp(m_axi_s2mm_rresp),
        .m_axis_s2mm_rlast(m_axi_s2mm_rlast),
        .m_axis_s2mm_rvalid(m_axi_s2mm_rvalid),
        .m_axis_s2mm_rready(m_axi_s2mm_rready),
        .m_axis_fetcher_araddr(m_axi_fetcher_araddr),
        .m_axis_fetcher_arlen(m_axi_fetcher_arlen),
        .m_axis_fetcher_arsize(m_axi_fetcher_arsize),
        .m_axis_fetcher_arburst(m_axi_fetcher_arburst),
        .m_axis_fetcher_arvalid(m_axi_fetcher_arvalid),
        .m_axis_fetcher_arready(m_axi_fetcher_arready),
        .m_axis_fetcher_rdata(m_axi_fetcher_rdata),
        .m_axis_fetcher_rresp(m_axi_fetcher_rresp),
        .m_axis_fetcher_rlast(m_axi_fetcher_rlast),
        .m_axis_fetcher_rvalid(m_axi_fetcher_rvalid),
        .m_axis_fetcher_rready(m_axi_fetcher_rready)
    );

endmodule
