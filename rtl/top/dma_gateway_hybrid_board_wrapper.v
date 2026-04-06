`timescale 1ns / 1ps

module dma_gateway_hybrid_board_wrapper #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer SHADOW_INJECT_ONLY = 0,
    parameter integer CRYPTO_NUM_INSTANCES = 1
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

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMA_WR AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI_DMA_WR, ADDR_WIDTH 32, DATA_WIDTH 32, PROTOCOL AXI3, READ_WRITE_MODE WRITE_ONLY, HAS_BURST 1, HAS_CACHE 1, HAS_PROT 1, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 0, HAS_LOCK 0, HAS_QOS 0, HAS_REGION 0, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, MAX_BURST_LENGTH 16, ID_WIDTH 0, AWUSER_WIDTH 0, ARUSER_WIDTH 0, WUSER_WIDTH 0, RUSER_WIDTH 0, BUSER_WIDTH 0, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN udp_gateway_shadow_mirror_processing_system7_0_0_FCLK_CLK0, NUM_READ_THREADS 1, NUM_WRITE_THREADS 1, INSERT_VIP 0" *)
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

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_S2MM AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI_S2MM, ADDR_WIDTH 32, DATA_WIDTH 32, PROTOCOL AXI3, READ_WRITE_MODE READ_WRITE, HAS_BURST 1, HAS_CACHE 1, HAS_PROT 1, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1, HAS_LOCK 0, HAS_QOS 0, HAS_REGION 0, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, MAX_BURST_LENGTH 16, ID_WIDTH 0, AWUSER_WIDTH 0, ARUSER_WIDTH 0, WUSER_WIDTH 0, RUSER_WIDTH 0, BUSER_WIDTH 0, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN udp_gateway_shadow_mirror_processing_system7_0_0_FCLK_CLK0, NUM_READ_THREADS 1, NUM_WRITE_THREADS 1, INSERT_VIP 0" *)
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

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_FETCHER ARADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI_FETCHER, ADDR_WIDTH 32, DATA_WIDTH 32, PROTOCOL AXI3, READ_WRITE_MODE READ_ONLY, HAS_BURST 1, HAS_CACHE 0, HAS_PROT 0, HAS_WSTRB 0, HAS_BRESP 0, HAS_RRESP 1, HAS_LOCK 0, HAS_QOS 0, HAS_REGION 0, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, MAX_BURST_LENGTH 16, ID_WIDTH 0, AWUSER_WIDTH 0, ARUSER_WIDTH 0, WUSER_WIDTH 0, RUSER_WIDTH 0, BUSER_WIDTH 0, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN udp_gateway_shadow_mirror_processing_system7_0_0_FCLK_CLK0, NUM_READ_THREADS 1, NUM_WRITE_THREADS 1, INSERT_VIP 0" *)
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
    output wire                    m_axi_fetcher_rready,

    output wire [31:0]             o_tx_axis_tdata,
    output wire                    o_tx_axis_tvalid,
    output wire                    o_tx_axis_tlast,
    output wire [3:0]              o_tx_axis_tkeep,
    input  wire                    i_tx_axis_tready
);

    localparam [7:0] WRAP_REG_DROP_WRONG_PORT_COUNT = 8'hCC;
    localparam [7:0] WRAP_REG_DROP_UNALIGNED_COUNT = 8'hD0;
    localparam integer FASTPATH_HDR_WORDS = 11;
    localparam integer FASTPATH_TXCAP_DEPTH = 384;
    localparam integer FASTPATH_PAYLOAD_DEPTH = FASTPATH_TXCAP_DEPTH - FASTPATH_HDR_WORDS;
    localparam integer TXCAP_PAYLOAD_ADDR_WIDTH = 9;
    localparam integer TXCAP_PAYLOAD_MEM_DEPTH = (1 << TXCAP_PAYLOAD_ADDR_WIDTH);
    localparam [8:0] FASTPATH_HDR_WORDS_ADDR = FASTPATH_HDR_WORDS;
    localparam integer FASTPATH_STATUS_TXCAP_STORAGE_SHIFT = 6;
    localparam [2:0] FASTPATH_ROUTE_IDLE = 3'd0;
    localparam [2:0] FASTPATH_ROUTE_HEADER = 3'd1;
    localparam [2:0] FASTPATH_ROUTE_REPLAY = 3'd2;
    localparam [2:0] FASTPATH_ROUTE_DMA = 3'd3;
    localparam [2:0] FASTPATH_ROUTE_EGRESS_REPLAY = 3'd4;
    localparam [2:0] FASTPATH_ROUTE_EGRESS_DMA = 3'd5;
    localparam [3:0] FASTPATH_REASON_IDLE = 4'd0;
    localparam [3:0] FASTPATH_REASON_HIT = 4'd1;
    localparam [3:0] FASTPATH_REASON_DISABLED = 4'd2;
    localparam [3:0] FASTPATH_REASON_ACL_DROP = 4'd3;
    localparam [3:0] FASTPATH_REASON_TX_BUSY = 4'd4;
    localparam [3:0] FASTPATH_REASON_FRAME_INVALID = 4'd5;

    wire                  ctrl_start_unused;
    wire                  ctrl_hw_init_unused;
    wire                  ctrl_algo_sel_unused;
    wire                  ctrl_enc_dec_unused;
    wire                  ctrl_s2mm_en_unused;
    wire                  ctrl_mm2s_en_unused;
    wire                  ctrl_auth_en_unused;
    wire                  ctrl_acl_en;
    wire                  ctrl_dna_lock_unused;
    wire                  ctrl_soft_reset_unused;
    wire                  ctrl_fastpath_en;
    wire [31:0]           ctrl_s2mm_addr_unused;
    wire [31:0]           ctrl_s2mm_data_unused;
    wire [1:0]            ctrl_loopback_unused;
    wire                  ctrl_acl_write_en;
    wire                  ctrl_acl_clear;
    wire [11:0]           ctrl_acl_write_addr;
    wire [103:0]          ctrl_acl_write_data;
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
    wire [31:0]           subsys_tx_axis_tdata;
    wire                  subsys_tx_axis_tvalid;
    wire                  subsys_tx_axis_tlast;
    wire [3:0]            subsys_tx_axis_tkeep;
    wire                  subsys_tx_axis_tready;
    wire [31:0]           egress_tx_axis_tdata;
    wire                  egress_tx_axis_tvalid;
    wire                  egress_tx_axis_tlast;
    wire [3:0]            egress_tx_axis_tkeep;
    wire                  fastpath_egress_selected;

    wire                  stage1_network_enable;
    wire                  stage1_ingress_inject_sel;
    wire                  stage1_arp_enable;
    wire [31:0]           stage1_local_ip;
    wire [47:0]           stage1_local_mac;
    wire                  stage1_net_cfg0_we_unused;
    wire                  stage1_local_ip_we_unused;
    wire                  stage1_local_mac_lo_we_unused;
    wire                  stage1_local_mac_hi_we_unused;
    wire                  inj_clear;
    wire                  inj_push;
    wire [31:0]           inj_data;
    wire [15:0]           inj_expected_words;
    wire [31:0]           inj_status;
    wire                  txcap_clear;
    wire                  txcap_pop;
    wire [31:0]           txcap_status;
    wire [31:0]           txcap_data;
    wire [31:0]           netdbg_status;
    wire [31:0]           fastpath_status;
    wire [31:0]           fastpath_hit_count;
    wire [31:0]           fastpath_fallback_count;
    wire [31:0]           stage1_txcap_status;
    wire [31:0]           stage1_txcap_data;
    wire [31:0]           stage1_netdbg_status;
    wire [31:0]           net_applied_cfg0;
    wire [31:0]           net_applied_local_ip;
    wire [31:0]           net_applied_local_mac_lo;
    wire [31:0]           net_applied_local_mac_hi;
    wire [63:0]           device_dna_value;
    wire                  device_dna_valid;
    wire                  device_dna_busy;

    wire [31:0]           stage1_inject_tdata;
    wire                  stage1_inject_tvalid;
    wire                  stage1_inject_tlast;
    wire                  stage1_inject_tready;
    wire [31:0]           aclf_tdata;
    wire                  aclf_tvalid;
    wire                  aclf_tlast;
    wire                  aclf_tready;
    wire [31:0]           classifier_s_tdata;
    wire                  classifier_s_tvalid;
    wire                  classifier_s_tlast;
    wire                  classifier_s_tready;
    wire                  acl_hit_unused;
    wire                  acl_drop_unused;
    wire                  acl_drop_pulse;
    wire [31:0]           acl_hit_count_unused;
    wire [31:0]           acl_miss_count_unused;

    wire [31:0]           classifier_dma_tdata;
    wire                  classifier_dma_tvalid;
    wire                  classifier_dma_tlast;
    wire                  classifier_dma_terror;
    wire                  classifier_dma_pkt_start;
    wire                  classifier_dma_pkt_end;
    wire                  classifier_dma_cbc_mode;
    wire [127:0]          classifier_dma_iv_header;
    wire                  classifier_dma_tready;
    wire [31:0]           drop_wrong_port_count;
    wire [31:0]           drop_unaligned_count;
    wire [31:0]           drop_cbc_length_invalid_count;
    wire                  classifier_dma_idle;

    reg  [2:0]            fastpath_route_state_q;
    reg  [3:0]            fastpath_header_count_q;
    reg  [3:0]            fastpath_replay_idx_q;
    reg  [31:0]           fastpath_header_mem [0:FASTPATH_HDR_WORDS-1];
    reg  [15:0]           frame_dst_port_q;
    reg  [15:0]           payload_words_q;
    reg  [15:0]           fastpath_last_payload_words_q;
    reg                   fastpath_frame_ended_in_header_q;
    reg                   fastpath_last_hit_q;
    reg  [3:0]            fastpath_last_reason_q;
    reg  [31:0]           fastpath_hit_count_q;
    reg  [31:0]           fastpath_fallback_count_q;
    reg  [31:0]           txcap_header_mem [0:FASTPATH_HDR_WORDS-1];
    reg  [8:0]            txcap_payload_wr_ptr_q;
    reg  [8:0]            txcap_rd_ptr_q;
    reg  [9:0]            txcap_count_q;
    reg  [31:0]           txcap_read_data_q;
    reg                   txcap_done_q;
    reg                   txcap_overflow_q;
    reg                   txcap_payload_rd_pending_q;

    wire                  txcap_payload_wr_en;
    wire [0:0]            txcap_payload_wr_wea;
    wire [TXCAP_PAYLOAD_ADDR_WIDTH-1:0] txcap_payload_wr_addr;
    wire [8:0]            txcap_next_rd_ptr;
    wire                  txcap_payload_rd_fire;
    wire [TXCAP_PAYLOAD_ADDR_WIDTH-1:0] txcap_payload_rd_addr;
    wire [31:0]           txcap_payload_rd_data;

    assign net_applied_cfg0         = {29'd0, stage1_arp_enable, stage1_ingress_inject_sel, stage1_network_enable};
    assign net_applied_local_ip     = stage1_local_ip;
    assign net_applied_local_mac_lo = stage1_local_mac[31:0];
    assign net_applied_local_mac_hi = {16'd0, stage1_local_mac[47:32]};
    assign txcap_status             = (SHADOW_INJECT_ONLY != 0) ? {13'd0, txcap_overflow_q, txcap_done_q, (txcap_count_q != 0), 6'd0, txcap_count_q} : stage1_txcap_status;
    assign txcap_data               = (SHADOW_INJECT_ONLY != 0) ? txcap_read_data_q : stage1_txcap_data;
    assign netdbg_status            = (SHADOW_INJECT_ONLY != 0) ? 32'd0 : stage1_netdbg_status;
    assign fastpath_status          = (32'd1 << FASTPATH_STATUS_TXCAP_STORAGE_SHIFT) |
                                      {26'd0, fastpath_last_reason_q, fastpath_last_hit_q, ctrl_fastpath_en};
    assign fastpath_hit_count       = fastpath_hit_count_q;
    assign fastpath_fallback_count  = fastpath_fallback_count_q;
    assign txcap_payload_wr_en      = 1'b0;
    assign txcap_payload_wr_wea     = {txcap_payload_wr_en};
    assign txcap_payload_wr_addr    = txcap_payload_wr_ptr_q;
    assign txcap_next_rd_ptr        = txcap_rd_ptr_q + 9'd1;
    assign txcap_payload_rd_fire    = txcap_pop && (txcap_count_q > 10'd1) &&
                                      (txcap_next_rd_ptr >= FASTPATH_HDR_WORDS_ADDR);
    assign txcap_payload_rd_addr    = txcap_next_rd_ptr - FASTPATH_HDR_WORDS_ADDR;
    assign egress_tx_axis_tdata = (fastpath_route_state_q == FASTPATH_ROUTE_EGRESS_REPLAY) ?
                                  fastpath_header_mem[fastpath_replay_idx_q] : aclf_tdata;
    assign egress_tx_axis_tvalid = (fastpath_route_state_q == FASTPATH_ROUTE_EGRESS_REPLAY) ? 1'b1 :
                                   ((fastpath_route_state_q == FASTPATH_ROUTE_EGRESS_DMA) ? aclf_tvalid : 1'b0);
    assign egress_tx_axis_tlast = (fastpath_route_state_q == FASTPATH_ROUTE_EGRESS_REPLAY) ?
                                  (fastpath_frame_ended_in_header_q && ((fastpath_replay_idx_q + 4'd1) == fastpath_header_count_q)) :
                                  ((fastpath_route_state_q == FASTPATH_ROUTE_EGRESS_DMA) ? aclf_tlast : 1'b0);
    assign egress_tx_axis_tkeep = 4'hF;
    assign fastpath_egress_selected = (fastpath_route_state_q == FASTPATH_ROUTE_EGRESS_REPLAY) ||
                                      (fastpath_route_state_q == FASTPATH_ROUTE_EGRESS_DMA);
    assign subsys_tx_axis_tready = fastpath_egress_selected ? 1'b0 : i_tx_axis_tready;

    // Force TXCAP payload storage into block RAM. Attribute-only inference kept
    // this payload store in distributed RAM, so use an explicit simple dual-port
    // memory and absorb the payload pop latency with txcap_payload_rd_pending_q.
    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(TXCAP_PAYLOAD_ADDR_WIDTH),
        .ADDR_WIDTH_B(TXCAP_PAYLOAD_ADDR_WIDTH),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(DATA_WIDTH),
        .CASCADE_HEIGHT(0),
        .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(TXCAP_PAYLOAD_MEM_DEPTH * DATA_WIDTH),
        .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_B(DATA_WIDTH),
        .READ_LATENCY_B(1),
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC"),
        .SIM_ASSERT_CHK(0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(0),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(DATA_WIDTH),
        .WRITE_MODE_B("read_first")
    ) u_txcap_payload_mem (
        .sleep(1'b0),
        .clka(clk),
        .ena(txcap_payload_wr_en),
        .wea(txcap_payload_wr_wea),
        .addra(txcap_payload_wr_addr),
        .dina(aclf_tdata),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .clkb(clk),
        .rstb(!rst_n),
        .enb(txcap_payload_rd_fire),
        .regceb(1'b1),
        .addrb(txcap_payload_rd_addr),
        .doutb(txcap_payload_rd_data),
        .sbiterrb(),
        .dbiterrb()
    );

    device_dna_reader u_device_dna_reader (
        .clk(clk),
        .rst_n(rst_n),
        .o_dna_value(device_dna_value),
        .o_dna_valid(device_dna_valid),
        .o_dna_busy(device_dna_busy)
    );

    generate
        if (SHADOW_INJECT_ONLY != 0) begin : gen_shadow_ctrl_csr
            assign ctrl_start_unused = 1'b0;
            assign ctrl_hw_init_unused = 1'b0;
            assign ctrl_algo_sel_unused = 1'b0;
            assign ctrl_enc_dec_unused = 1'b0;
            assign ctrl_s2mm_en_unused = 1'b0;
            assign ctrl_mm2s_en_unused = 1'b0;
            assign ctrl_auth_en_unused = 1'b0;
            assign ctrl_dna_lock_unused = 1'b0;
            assign ctrl_soft_reset_unused = 1'b0;
            assign ctrl_s2mm_addr_unused = 32'd0;
            assign ctrl_s2mm_data_unused = 32'd0;
            assign ctrl_loopback_unused = 2'd0;
            assign ctrl_base_addr_unused = 32'd0;
            assign ctrl_len_unused = 32'd0;
            assign ctrl_key_unused = 128'd0;
            assign ctrl_key_hi_unused = 128'd0;
            assign ctrl_aes256_unused = 1'b0;
            assign ctrl_cache_flush_unused = 1'b0;
            assign ctrl_acl_cnt_unused = 32'd0;
            assign ctrl_ring_doorbell_unused = 1'b0;
            assign ctrl_ring_base_unused = 32'd0;
            assign ctrl_ring_size_unused = 32'd0;
            assign ctrl_sw_tail_unused = 16'd0;
            assign ctrl_irq_enable_unused = 1'b0;
            assign ctrl_irq_ack_unused = 1'b0;
            assign ctrl_irq_count_unused = 32'd0;
            assign ctrl_irq_timeout_unused = 32'd0;
            assign stage1_net_cfg0_we_unused = 1'b0;
            assign stage1_local_ip_we_unused = 1'b0;
            assign stage1_local_mac_lo_we_unused = 1'b0;
            assign stage1_local_mac_hi_we_unused = 1'b0;

            udp_gateway_shadow_ctrl_csr #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH)
            ) u_shadow_ctrl_csr (
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
                .o_network_enable(stage1_network_enable),
                .o_network_ingress_sel(stage1_ingress_inject_sel),
                .o_arp_enable(stage1_arp_enable),
                .o_net_local_ip(stage1_local_ip),
                .o_net_local_mac(stage1_local_mac),
                .o_inj_clear(inj_clear),
                .o_inj_push(inj_push),
                .o_inj_data(inj_data),
                .o_inj_expected_words(inj_expected_words),
                .o_txcap_clear(txcap_clear),
                .o_txcap_pop(txcap_pop),
                .o_acl_en(ctrl_acl_en),
                .o_acl_write_en(ctrl_acl_write_en),
                .o_acl_clear(ctrl_acl_clear),
                .o_fastpath_en(ctrl_fastpath_en),
                .o_acl_write_addr(ctrl_acl_write_addr),
                .o_acl_write_data(ctrl_acl_write_data),
                .i_inj_status(inj_status),
                .i_txcap_status(txcap_status),
                .i_txcap_data(txcap_data),
                .i_netdbg_status(netdbg_status),
                .i_net_applied_cfg0(net_applied_cfg0),
                .i_net_applied_local_ip(net_applied_local_ip),
                .i_net_applied_local_mac_lo(net_applied_local_mac_lo),
                .i_net_applied_local_mac_hi(net_applied_local_mac_hi),
                .i_drop_wrong_port_count(drop_wrong_port_count),
                .i_drop_unaligned_count(drop_unaligned_count),
                .i_device_dna_lo(device_dna_value[31:0]),
                .i_device_dna_hi(device_dna_value[63:32]),
                .i_device_dna_status({30'd0, device_dna_busy, device_dna_valid}),
                .i_fastpath_status(fastpath_status),
                .i_fastpath_hit_count(fastpath_hit_count),
                .i_fastpath_fallback_count(fastpath_fallback_count),
                .i_acl_inc(acl_drop_pulse),
                .i_busy(!classifier_dma_idle)
            );
        end else begin : gen_full_ctrl_csr
            assign ctrl_fastpath_en = 1'b0;
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
                .o_acl_en(ctrl_acl_en),
                .o_dna_lock_en(ctrl_dna_lock_unused),
                .o_soft_reset(ctrl_soft_reset_unused),
                .o_s2mm_addr(ctrl_s2mm_addr_unused),
                .o_s2mm_data(ctrl_s2mm_data_unused),
                .o_loopback_mode(ctrl_loopback_unused),
                .o_acl_write_en(ctrl_acl_write_en),
                .o_acl_clear(ctrl_acl_clear),
                .o_acl_write_addr(ctrl_acl_write_addr),
                .o_acl_write_data(ctrl_acl_write_data),
                .o_network_enable(stage1_network_enable),
                .o_network_ingress_sel(stage1_ingress_inject_sel),
                .o_arp_enable(stage1_arp_enable),
                .o_net_local_ip(stage1_local_ip),
                .o_net_local_mac(stage1_local_mac),
                .o_net_cfg0_we(stage1_net_cfg0_we_unused),
                .o_net_local_ip_we(stage1_local_ip_we_unused),
                .o_net_local_mac_lo_we(stage1_local_mac_lo_we_unused),
                .o_net_local_mac_hi_we(stage1_local_mac_hi_we_unused),
                .o_inj_clear(inj_clear),
                .o_inj_push(inj_push),
                .o_inj_data(inj_data),
                .o_inj_expected_words(inj_expected_words),
                .i_inj_status(inj_status),
                .o_txcap_clear(txcap_clear),
                .o_txcap_pop(txcap_pop),
                .i_txcap_status(txcap_status),
                .i_txcap_data(txcap_data),
                .i_netdbg_status(netdbg_status),
                .i_net_applied_cfg0(net_applied_cfg0),
                .i_net_applied_local_ip(net_applied_local_ip),
                .i_net_applied_local_mac_lo(net_applied_local_mac_lo),
                .i_net_applied_local_mac_hi(net_applied_local_mac_hi),
                .i_drop_wrong_port_count(drop_wrong_port_count),
                .i_drop_unaligned_count(drop_unaligned_count),
                .o_base_addr(ctrl_base_addr_unused),
                .o_len(ctrl_len_unused),
                .o_key(ctrl_key_unused),
                .o_key_hi(ctrl_key_hi_unused),
                .o_aes256_en(ctrl_aes256_unused),
                .o_cache_flush(ctrl_cache_flush_unused),
                .i_acl_inc(acl_drop_pulse),
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
                .i_busy(!classifier_dma_idle)
            );
        end
    endgenerate

    generate
        if (SHADOW_INJECT_ONLY != 0) begin : gen_shadow_inject_only
            udp_gateway_shadow_inject_path u_shadow_inject (
                .clk(clk),
                .rst_n(rst_n),
                .i_network_enable(stage1_network_enable),
                .i_ingress_inject_sel(stage1_ingress_inject_sel),
                .i_inj_clear(inj_clear),
                .i_inj_push(inj_push),
                .i_inj_data(inj_data),
                .i_inj_expected_words(inj_expected_words),
                .o_inj_status(inj_status),
                .o_inject_tdata(stage1_inject_tdata),
                .o_inject_tvalid(stage1_inject_tvalid),
                .o_inject_tlast(stage1_inject_tlast),
                .i_inject_tready(stage1_inject_tready)
            );
            assign stage1_txcap_status = 32'd0;
            assign stage1_txcap_data = 32'd0;
            assign stage1_netdbg_status = 32'd0;
        end else begin : gen_full_stage1
            wire [31:0] tx_axis_tdata_unused;
            wire        tx_axis_tvalid_unused;
            wire        tx_axis_tlast_unused;
            wire [3:0]  tx_axis_tkeep_unused;

            network_stage1_path u_network_stage1 (
                .clk(clk),
                .rst_n(rst_n),
                .i_network_enable(stage1_network_enable),
                .i_ingress_inject_sel(stage1_ingress_inject_sel),
                .i_arp_enable(stage1_arp_enable),
                .i_local_ip(stage1_local_ip),
                .i_local_mac(stage1_local_mac),
                .i_inj_clear(inj_clear),
                .i_inj_push(inj_push),
                .i_inj_data(inj_data),
                .i_inj_expected_words(inj_expected_words),
                .o_inj_status(inj_status),
                .i_txcap_clear(txcap_clear),
                .i_txcap_pop(txcap_pop),
                .o_txcap_status(stage1_txcap_status),
                .o_txcap_data(stage1_txcap_data),
                .o_debug_status(stage1_netdbg_status),
                .i_ext_rx_valid(1'b0),
                .i_ext_rx_data(32'd0),
                .i_ext_rx_last(1'b0),
                .o_ext_rx_ready(),
                .o_inject_tdata(stage1_inject_tdata),
                .o_inject_tvalid(stage1_inject_tvalid),
                .o_inject_tlast(stage1_inject_tlast),
                .i_inject_tready(stage1_inject_tready),
                .o_tx_axis_tdata(tx_axis_tdata_unused),
                .o_tx_axis_tvalid(tx_axis_tvalid_unused),
                .o_tx_axis_tlast(tx_axis_tlast_unused),
                .o_tx_axis_tkeep(tx_axis_tkeep_unused)
            );
        end
    endgenerate

    acl_packet_filter u_shadow_acl_filter (
        .clk(clk),
        .rst_n(rst_n),
        .acl_en(ctrl_acl_en),
        .s_tdata(stage1_inject_tdata),
        .s_tvalid(stage1_inject_tvalid),
        .s_tlast(stage1_inject_tlast),
        .s_tready(stage1_inject_tready),
        .m_tdata(aclf_tdata),
        .m_tvalid(aclf_tvalid),
        .m_tlast(aclf_tlast),
        .m_tready(aclf_tready),
        .acl_write_en(ctrl_acl_write_en),
        .acl_write_addr(ctrl_acl_write_addr),
        .acl_write_data(ctrl_acl_write_data),
        .acl_clear(ctrl_acl_clear),
        .acl_hit(acl_hit_unused),
        .acl_drop(acl_drop_unused),
        .acl_drop_pulse(acl_drop_pulse),
        .acl_hit_count(acl_hit_count_unused),
        .acl_miss_count(acl_miss_count_unused)
    );

    assign classifier_s_tdata = (SHADOW_INJECT_ONLY == 0) ? aclf_tdata :
                                ((fastpath_route_state_q == FASTPATH_ROUTE_REPLAY) ? fastpath_header_mem[fastpath_replay_idx_q] : aclf_tdata);
    assign classifier_s_tvalid = (SHADOW_INJECT_ONLY == 0) ? aclf_tvalid :
                                 ((fastpath_route_state_q == FASTPATH_ROUTE_REPLAY) ? 1'b1 :
                                  ((fastpath_route_state_q == FASTPATH_ROUTE_DMA) ? aclf_tvalid : 1'b0));
    assign classifier_s_tlast = (SHADOW_INJECT_ONLY == 0) ? aclf_tlast :
                                ((fastpath_route_state_q == FASTPATH_ROUTE_REPLAY) ?
                                 (fastpath_frame_ended_in_header_q && ((fastpath_replay_idx_q + 4'd1) == fastpath_header_count_q)) :
                                 ((fastpath_route_state_q == FASTPATH_ROUTE_DMA) ? aclf_tlast : 1'b0));
    assign aclf_tready = (SHADOW_INJECT_ONLY == 0) ? classifier_s_tready :
                         (((fastpath_route_state_q == FASTPATH_ROUTE_IDLE) || (fastpath_route_state_q == FASTPATH_ROUTE_HEADER)) ? 1'b1 :
                          ((fastpath_route_state_q == FASTPATH_ROUTE_DMA) ? classifier_s_tready :
                           ((fastpath_route_state_q == FASTPATH_ROUTE_EGRESS_DMA) ? i_tx_axis_tready : 1'b0)));

    // Keep TXCAP bookkeeping synchronous so BRAM enable/counting logic is not
    // driven from async-reset flops.
    always @(posedge clk) begin
        if (!rst_n || (SHADOW_INJECT_ONLY == 0)) begin
            fastpath_route_state_q <= FASTPATH_ROUTE_IDLE;
            fastpath_header_count_q <= 4'd0;
            fastpath_replay_idx_q <= 4'd0;
            frame_dst_port_q <= 16'd0;
            payload_words_q <= 16'd0;
            fastpath_last_payload_words_q <= 16'd0;
            fastpath_frame_ended_in_header_q <= 1'b0;
            fastpath_last_hit_q <= 1'b0;
            fastpath_last_reason_q <= FASTPATH_REASON_IDLE;
            fastpath_hit_count_q <= 32'd0;
            fastpath_fallback_count_q <= 32'd0;
            txcap_payload_wr_ptr_q <= 9'd0;
            txcap_rd_ptr_q <= 9'd0;
            txcap_count_q <= 10'd0;
            txcap_read_data_q <= 32'd0;
            txcap_done_q <= 1'b0;
            txcap_overflow_q <= 1'b0;
            txcap_payload_rd_pending_q <= 1'b0;
        end else begin
            if (txcap_payload_rd_pending_q) begin
                txcap_read_data_q <= txcap_payload_rd_data;
            end
            txcap_payload_rd_pending_q <= txcap_payload_rd_fire;

            if (txcap_clear) begin
                txcap_payload_wr_ptr_q <= 9'd0;
                txcap_rd_ptr_q <= 9'd0;
                txcap_count_q <= 10'd0;
                txcap_read_data_q <= 32'd0;
                txcap_done_q <= 1'b0;
                txcap_overflow_q <= 1'b0;
                txcap_payload_rd_pending_q <= 1'b0;
            end else if (txcap_pop && (txcap_count_q != 0)) begin
                if (txcap_count_q == 10'd1) begin
                    txcap_rd_ptr_q <= 9'd0;
                    txcap_count_q <= 10'd0;
                    txcap_read_data_q <= 32'd0;
                    txcap_payload_rd_pending_q <= 1'b0;
                end else begin
                    txcap_rd_ptr_q <= txcap_rd_ptr_q + 9'd1;
                    txcap_count_q <= txcap_count_q - 10'd1;
                    if (txcap_next_rd_ptr < FASTPATH_HDR_WORDS_ADDR) begin
                        txcap_read_data_q <= txcap_header_mem[txcap_next_rd_ptr];
                        txcap_payload_rd_pending_q <= 1'b0;
                    end
                end
            end

            if (acl_drop_pulse) begin
                fastpath_last_hit_q <= 1'b0;
                fastpath_last_reason_q <= FASTPATH_REASON_ACL_DROP;
            end

            case (fastpath_route_state_q)
                FASTPATH_ROUTE_IDLE: begin
                    fastpath_header_count_q <= 4'd0;
                    fastpath_replay_idx_q <= 4'd0;
                    fastpath_frame_ended_in_header_q <= 1'b0;
                    payload_words_q <= 16'd0;
                    if (aclf_tvalid && aclf_tready) begin
                        fastpath_header_mem[0] <= aclf_tdata;
                        fastpath_header_count_q <= 4'd1;
                        frame_dst_port_q <= 16'd0;
                        if (aclf_tlast) begin
                            fastpath_route_state_q <= FASTPATH_ROUTE_REPLAY;
                            fastpath_frame_ended_in_header_q <= 1'b1;
                            fastpath_last_hit_q <= 1'b0;
                            fastpath_last_reason_q <= ctrl_fastpath_en ? FASTPATH_REASON_FRAME_INVALID : FASTPATH_REASON_DISABLED;
                            fastpath_fallback_count_q <= fastpath_fallback_count_q + 32'd1;
                        end else begin
                            fastpath_route_state_q <= FASTPATH_ROUTE_HEADER;
                        end
                    end
                end

                FASTPATH_ROUTE_HEADER: begin
                    if (aclf_tvalid && aclf_tready) begin
                        fastpath_header_mem[fastpath_header_count_q] <= aclf_tdata;
                        if (fastpath_header_count_q == 4'd9) begin
                            frame_dst_port_q <= aclf_tdata[31:16];
                        end
                        if (aclf_tlast) begin
                            fastpath_header_count_q <= fastpath_header_count_q + 4'd1;
                            fastpath_replay_idx_q <= 4'd0;
                            fastpath_frame_ended_in_header_q <= 1'b1;
                            fastpath_route_state_q <= FASTPATH_ROUTE_REPLAY;
                            payload_words_q <= 16'd0;
                            fastpath_last_payload_words_q <= 16'd0;
                            fastpath_last_hit_q <= 1'b0;
                            fastpath_last_reason_q <= ctrl_fastpath_en ? FASTPATH_REASON_FRAME_INVALID : FASTPATH_REASON_DISABLED;
                            fastpath_fallback_count_q <= fastpath_fallback_count_q + 32'd1;
                        end else if (fastpath_header_count_q == 4'd10) begin
                            fastpath_header_count_q <= 4'd11;
                            if (!ctrl_fastpath_en) begin
                                payload_words_q <= 16'd0;
                                fastpath_last_payload_words_q <= 16'd0;
                                fastpath_last_hit_q <= 1'b0;
                                fastpath_last_reason_q <= FASTPATH_REASON_DISABLED;
                                fastpath_fallback_count_q <= fastpath_fallback_count_q + 32'd1;
                                fastpath_route_state_q <= FASTPATH_ROUTE_REPLAY;
                                fastpath_replay_idx_q <= 4'd0;
                            end else if (((frame_dst_port_q == 16'd4660) || (frame_dst_port_q == 16'd4661)) &&
                                         (aclf_tdata[15:0] >= 16'd8) &&
                                         (((aclf_tdata[15:0] - 16'd8) & 16'h0003) == 16'd0) &&
                                         (((aclf_tdata[15:0] - 16'd8) & 16'h000F) == 16'd0) &&
                                         (((aclf_tdata[15:0] - 16'd8) >> 2) + FASTPATH_HDR_WORDS <= FASTPATH_TXCAP_DEPTH)) begin
                                payload_words_q <= (aclf_tdata[15:0] - 16'd8) >> 2;
                                fastpath_last_payload_words_q <= (aclf_tdata[15:0] - 16'd8) >> 2;
                                fastpath_last_hit_q <= 1'b1;
                                fastpath_last_reason_q <= FASTPATH_REASON_HIT;
                                fastpath_replay_idx_q <= 4'd0;
                                fastpath_route_state_q <= FASTPATH_ROUTE_EGRESS_REPLAY;
                            end else begin
                                payload_words_q <= 16'd0;
                                fastpath_last_payload_words_q <= 16'd0;
                                fastpath_last_hit_q <= 1'b0;
                                fastpath_last_reason_q <= FASTPATH_REASON_FRAME_INVALID;
                                fastpath_fallback_count_q <= fastpath_fallback_count_q + 32'd1;
                                fastpath_route_state_q <= FASTPATH_ROUTE_REPLAY;
                                fastpath_replay_idx_q <= 4'd0;
                            end
                        end else begin
                            fastpath_header_count_q <= fastpath_header_count_q + 4'd1;
                        end
                    end
                end

                FASTPATH_ROUTE_REPLAY: begin
                    if (classifier_s_tready && classifier_s_tvalid) begin
                        if ((fastpath_replay_idx_q + 4'd1) == fastpath_header_count_q) begin
                            fastpath_replay_idx_q <= 4'd0;
                            if (fastpath_frame_ended_in_header_q) begin
                                fastpath_route_state_q <= FASTPATH_ROUTE_IDLE;
                                fastpath_header_count_q <= 4'd0;
                                fastpath_frame_ended_in_header_q <= 1'b0;
                            end else begin
                                fastpath_route_state_q <= FASTPATH_ROUTE_DMA;
                            end
                        end else begin
                            fastpath_replay_idx_q <= fastpath_replay_idx_q + 4'd1;
                        end
                    end
                end

                FASTPATH_ROUTE_DMA: begin
                    if (aclf_tvalid && classifier_s_tready && aclf_tlast) begin
                        fastpath_route_state_q <= FASTPATH_ROUTE_IDLE;
                        fastpath_header_count_q <= 4'd0;
                        fastpath_frame_ended_in_header_q <= 1'b0;
                    end
                end

                FASTPATH_ROUTE_EGRESS_REPLAY: begin
                    if (i_tx_axis_tready && egress_tx_axis_tvalid) begin
                        if ((fastpath_replay_idx_q + 4'd1) == fastpath_header_count_q) begin
                            fastpath_replay_idx_q <= 4'd0;
                            if (fastpath_frame_ended_in_header_q) begin
                                fastpath_hit_count_q <= fastpath_hit_count_q + 32'd1;
                                fastpath_route_state_q <= FASTPATH_ROUTE_IDLE;
                                fastpath_header_count_q <= 4'd0;
                                fastpath_frame_ended_in_header_q <= 1'b0;
                            end else begin
                                fastpath_route_state_q <= FASTPATH_ROUTE_EGRESS_DMA;
                            end
                        end else begin
                            fastpath_replay_idx_q <= fastpath_replay_idx_q + 4'd1;
                        end
                    end
                end

                FASTPATH_ROUTE_EGRESS_DMA: begin
                    if (aclf_tvalid && i_tx_axis_tready && aclf_tlast) begin
                        fastpath_hit_count_q <= fastpath_hit_count_q + 32'd1;
                        fastpath_route_state_q <= FASTPATH_ROUTE_IDLE;
                        fastpath_header_count_q <= 4'd0;
                        fastpath_frame_ended_in_header_q <= 1'b0;
                    end
                end

                default: begin
                    fastpath_route_state_q <= FASTPATH_ROUTE_IDLE;
                end
            endcase
        end
    end

    udp_dma_ingress_classifier u_classifier (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(classifier_s_tdata),
        .s_axis_tvalid(classifier_s_tvalid),
        .s_axis_tlast(classifier_s_tlast),
        .s_axis_tready(classifier_s_tready),
        .m_axis_dma_tdata(classifier_dma_tdata),
        .m_axis_dma_tvalid(classifier_dma_tvalid),
        .m_axis_dma_tlast(classifier_dma_tlast),
        .m_axis_dma_terror(classifier_dma_terror),
        .m_axis_dma_pkt_start(classifier_dma_pkt_start),
        .m_axis_dma_pkt_end(classifier_dma_pkt_end),
        .m_axis_dma_cbc_mode(classifier_dma_cbc_mode),
        .m_axis_dma_iv_header(classifier_dma_iv_header),
        .m_axis_dma_tready(classifier_dma_tready),
        .o_drop_wrong_port_count(drop_wrong_port_count),
        .o_drop_unaligned_count(drop_unaligned_count),
        .o_drop_cbc_length_invalid_count(drop_cbc_length_invalid_count),
        .o_dma_idle(classifier_dma_idle)
    );

    assign dma_irq = 1'b0;
    assign o_tx_axis_tdata = fastpath_egress_selected ? egress_tx_axis_tdata : subsys_tx_axis_tdata;
    assign o_tx_axis_tvalid = fastpath_egress_selected ? egress_tx_axis_tvalid : subsys_tx_axis_tvalid;
    assign o_tx_axis_tlast = fastpath_egress_selected ? egress_tx_axis_tlast : subsys_tx_axis_tlast;
    assign o_tx_axis_tkeep = fastpath_egress_selected ? egress_tx_axis_tkeep : subsys_tx_axis_tkeep;

    crypto_dma_subsystem #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .CRYPTO_NUM_INSTANCES(CRYPTO_NUM_INSTANCES)
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
        .rx_wr_valid(classifier_dma_tvalid),
        .rx_wr_data(classifier_dma_tdata),
        .rx_wr_last(classifier_dma_tlast),
        .rx_wr_error(classifier_dma_terror),
        .rx_wr_pkt_start(classifier_dma_pkt_start),
        .rx_wr_pkt_end(classifier_dma_pkt_end),
        .rx_wr_cbc_mode(classifier_dma_cbc_mode),
        .rx_wr_iv_header(classifier_dma_iv_header),
        .rx_wr_ready(classifier_dma_tready),
        .tx_axis_tdata(subsys_tx_axis_tdata),
        .tx_axis_tvalid(subsys_tx_axis_tvalid),
        .tx_axis_tlast(subsys_tx_axis_tlast),
        .tx_axis_tkeep(subsys_tx_axis_tkeep),
        .tx_axis_tready(subsys_tx_axis_tready),
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
