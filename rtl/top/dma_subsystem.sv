`timescale 1ns / 1ps


module dma_subsystem #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter int CRYPTO_NUM_INSTANCES = 4,
    parameter int PBM_ADDR_WIDTH = 14
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // =========================================================================
    // AXI-Lite Slave Interface (CPU Access)
    // =========================================================================
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

    // =========================================================================
    // RX Input Path (From MAC)
    // =========================================================================
    input  logic                   rx_wr_valid,
    input  logic [31:0]            rx_wr_data,
    input  logic                   rx_wr_last,
    output logic                   rx_wr_ready,

    // =========================================================================
    // TX Output Path (PBM Passthrough)
    // =========================================================================
    output logic [31:0]            tx_axis_tdata,
    output logic                   tx_axis_tvalid,
    output logic                   tx_axis_tlast,
    output logic [3:0]             tx_axis_tkeep,
    input  logic                   tx_axis_tready,

    // =========================================================================
    // AXI4 Master Interface (DMA to DDR - Write Channel)
    // =========================================================================
    output logic [ADDR_WIDTH-1:0]  m_axis_awaddr,
    output logic [7:0]             m_axis_awlen,
    output logic [2:0]             m_axis_awsize,
    output logic [1:0]             m_axis_awburst,
    output logic [3:0]             m_axis_awcache,
    output logic [2:0]             m_axis_awprot,
    output logic                   m_axis_awvalid,
    input  logic                   m_axis_awready,
    output logic [DATA_WIDTH-1:0]  m_axis_wdata,
    output logic [DATA_WIDTH/8-1:0] m_axis_wstrb,
    output logic                   m_axis_wlast,
    output logic                   m_axis_wvalid,
    input  logic                   m_axis_wready,
    input  logic [1:0]             m_axis_bresp,
    input  logic                   m_axis_bvalid,
    output logic                   m_axis_bready,

    // =========================================================================
    // AXI4 Master Interface (S2MM/MM2S - Read/Write for CPU Direct Access)
    // =========================================================================
    output logic [ADDR_WIDTH-1:0]  m_axis_s2mm_awaddr,
    output logic [7:0]             m_axis_s2mm_awlen,
    output logic [2:0]             m_axis_s2mm_awsize,
    output logic [1:0]             m_axis_s2mm_awburst,
    output logic [3:0]             m_axis_s2mm_awcache,
    output logic [2:0]             m_axis_s2mm_awprot,
    output logic                   m_axis_s2mm_awvalid,
    input  logic                   m_axis_s2mm_awready,
    output logic [DATA_WIDTH-1:0]  m_axis_s2mm_wdata,
    output logic [DATA_WIDTH/8-1:0] m_axis_s2mm_wstrb,
    output logic                   m_axis_s2mm_wlast,
    output logic                   m_axis_s2mm_wvalid,
    input  logic                   m_axis_s2mm_wready,
    input  logic [1:0]             m_axis_s2mm_bresp,
    input  logic                   m_axis_s2mm_bvalid,
    output logic                   m_axis_s2mm_bready,
    output logic [ADDR_WIDTH-1:0]  m_axis_s2mm_araddr,
    output logic [7:0]             m_axis_s2mm_arlen,
    output logic [2:0]             m_axis_s2mm_arsize,
    output logic [1:0]             m_axis_s2mm_arburst,
    output logic                   m_axis_s2mm_arvalid,
    input  logic                   m_axis_s2mm_arready,
    input  logic [DATA_WIDTH-1:0]  m_axis_s2mm_rdata,
    input  logic [1:0]             m_axis_s2mm_rresp,
    input  logic                   m_axis_s2mm_rlast,
    input  logic                   m_axis_s2mm_rvalid,
    output logic                   m_axis_s2mm_rready,

    // =========================================================================
    // AXI4 Master Interface (Fetcher - Read Descriptor)
    // =========================================================================
    output logic [ADDR_WIDTH-1:0]  m_axis_fetcher_araddr,
    output logic [7:0]             m_axis_fetcher_arlen,
    output logic [2:0]             m_axis_fetcher_arsize,
    output logic [1:0]             m_axis_fetcher_arburst,
    output logic                   m_axis_fetcher_arvalid,
    input  logic                   m_axis_fetcher_arready,
    input  logic [DATA_WIDTH-1:0]  m_axis_fetcher_rdata,
    input  logic [1:0]             m_axis_fetcher_rresp,
    input  logic                   m_axis_fetcher_rlast,
    input  logic                   m_axis_fetcher_rvalid,
    output logic                   m_axis_fetcher_rready,

    // =========================================================================
    // Interrupt Output
    // =========================================================================
    output logic                   dma_irq
);

    // =========================================================================
    // Internal Signals
    // =========================================================================
    logic                   csr_start, fetcher_start, final_start_raw, final_start;
    logic                   csr_soft_reset;
    logic                   fetcher_completion_event_unused;
    logic                   fetcher_stream_tlast_unused;
    logic [31:0]            csr_addr, fetcher_addr, fetcher_src_addr_unused, final_addr;
    logic [31:0]            csr_len, fetcher_len, final_len;
    logic                   csr_algo, fetcher_algo, final_algo;
    logic                   csr_encdec;  // Encrypt/Decrypt control
    logic [31:0]            ring_base, ring_size;
    logic [15:0]            sw_tail, hw_head;
    logic                   ring_doorbell;
    logic                   dma_done, dma_error, dma_busy, hw_init;
    logic [1:0]             dma_status_bresp;
    logic [127:0]           csr_key;
    logic [127:0]           csr_key_hi;
    logic                   csr_aes256_en;
    
    // S2MM/MM2S signals
    logic                   s2mm_en, mm2s_en;
    logic [31:0]            s2mm_addr, s2mm_data, mm2s_data;
        logic [1:0]             loopback_mode;

    // Security control and status
    logic                   auth_en, acl_en, dna_lock_en;
    logic                   csr_network_enable, csr_network_ingress_sel, csr_arp_enable;
    logic                   stage1_network_enable, stage1_ingress_inject_sel, stage1_arp_enable;
    logic                   acl_cfg_we, acl_cfg_clear;
    logic [11:0]            acl_cfg_addr;
    logic [103:0]           acl_cfg_data;
    logic                   acl_hit, acl_drop, acl_drop_pulse;
    logic [31:0]            acl_hit_count, acl_miss_count;
    logic [31:0]            csr_net_local_ip, stage1_local_ip;
    logic [47:0]            csr_net_local_mac;
    logic [31:0]            stage1_local_mac_lo, stage1_local_mac_hi;
    logic [47:0]            stage1_local_mac;
    logic                   net_cfg0_we, net_local_ip_we, net_local_mac_lo_we, net_local_mac_hi_we;
    logic                   inj_clear, inj_push, txcap_clear, txcap_pop;
    logic [31:0]            inj_data, inj_status, txcap_status, txcap_data, netdbg_status;
    logic [15:0]            inj_expected_words;
    logic [31:0]            net_applied_cfg0, net_applied_local_ip, net_applied_local_mac_lo, net_applied_local_mac_hi;
    logic [31:0]            network_tx_tdata;
    logic                   network_tx_tvalid, network_tx_tlast;
    logic [3:0]             network_tx_tkeep;
    logic                   network_ext_rx_ready;
    logic [31:0]            stage1_inject_tdata;
    logic                   stage1_inject_tvalid;
    logic                   stage1_inject_tlast;
    logic                   stage1_inject_tready;
    logic                   use_stage1_inject;

    logic [127:0]           secure_key;
    logic [127:0]           secure_key_hi;
    logic                   secure_aes256_en;
    logic [127:0]           effective_key;
    logic [127:0]           effective_key_hi;
    logic                   effective_key_valid;
    logic                   effective_key_hi_valid;
    logic [1:0]             key_lock_status;
    logic                   key_system_locked;
    logic                   key_hi_system_locked;
    logic                   key_tamper;
    logic                   key_hi_tamper;
    logic [56:0]            dna_out_sig;

    // Auth/ACL ingress stream
    logic [31:0]            auth_tdata;
    logic [3:0]             auth_tkeep;
    logic                   auth_tlast, auth_tvalid, auth_tready;
    logic [31:0]            auth_acl_tdata;
    logic [3:0]             auth_acl_tkeep;
    logic                   auth_acl_tlast, auth_acl_tvalid, auth_acl_tready;
    logic [31:0]            ingress_tdata;
    logic                   ingress_tlast, ingress_tvalid, ingress_tready;
    logic [31:0]            aclf_tdata;
    logic                   aclf_tlast, aclf_tvalid, pbm_wr_ready;
    logic [PBM_ADDR_WIDTH:0] pbm_buffer_usage;
    logic                   pbm_rollback_active;
    logic                   pbm_high_water;
    logic                   pbm_drop_pulse;
    logic                   ingress_drop_until_tlast;
    logic                   ingress_drop_now;
    logic                   pbm_ingress_error;

    typedef enum logic [1:0] {
        AUTH_STRIP_HDR0,
        AUTH_STRIP_HDR1,
        AUTH_STRIP_STREAM
    } auth_acl_state_t;
    auth_acl_state_t auth_acl_state;
    
    // PBM signals
    logic [31:0]            pbm_data;
    logic                   pbm_empty;
    logic                   bridge_rd_pbm;
    logic                   bridge_rd_valid;

    // Crypto Bridge signals
    logic [31:0]            crypto_to_dma_data;
    logic                   crypto_to_dma_empty;
    logic                   crypto_to_dma_last;
    logic                   dma_req_rd;
    logic                   bridge_tx_rd_en;

    // Loopback Mux signals
    logic [31:0]            muxed_crypto_data;
    logic                   muxed_crypto_empty;
    logic [31:0]            tx_data_from_crypto;
    logic                   tx_valid_from_crypto;
    logic                   tx_last_from_crypto;
    
    // DMA Engine internal signals
    logic [31:0]            dma_awaddr, dma_wdata;
    logic [7:0]             dma_awlen;
    logic [2:0]             dma_awsize;
    logic [1:0]             dma_awburst;
    logic [3:0]             dma_awcache;
    logic [2:0]             dma_awprot;
    logic [3:0]             dma_wstrb;
    logic                   dma_awvalid, dma_wvalid, dma_bready;
    logic                   dma_wlast;
    logic [1:0]             dma_bresp;
    logic [31:0]            fetch_wb_awaddr, fetch_wb_wdata;
    logic [7:0]             fetch_wb_awlen;
    logic [2:0]             fetch_wb_awsize;
    logic [1:0]             fetch_wb_awburst;
    logic [3:0]             fetch_wb_awcache;
    logic [2:0]             fetch_wb_awprot;
    logic [3:0]             fetch_wb_wstrb;
    logic                   fetch_wb_awvalid, fetch_wb_awready;
    logic                   fetch_wb_wlast, fetch_wb_wvalid, fetch_wb_wready;
    logic [1:0]             fetch_wb_bresp;
    logic                   fetch_wb_bvalid, fetch_wb_bready, fetch_wb_active;

    // S2MM/MM2S internal signals
    logic [31:0]            s2mm_awaddr, s2mm_wdata;
    logic [7:0]             s2mm_awlen;
    logic [2:0]             s2mm_awsize;
    logic [1:0]             s2mm_awburst;
    logic [3:0]             s2mm_awcache;
    logic [2:0]             s2mm_awprot;
    logic [3:0]             s2mm_wstrb;
    logic                   s2mm_awvalid, s2mm_wvalid, s2mm_bready;
    logic                   s2mm_wlast;
    logic [1:0]             s2mm_bresp;
    logic [31:0]            s2mm_araddr;
    logic [7:0]             s2mm_arlen;
    logic [2:0]             s2mm_arsize;
    logic [1:0]             s2mm_arburst;
    logic                   s2mm_arvalid, s2mm_rready;
    logic [1:0]             s2mm_rresp;

    // =========================================================================
    // 1. Loopback MUX (Mode Selection)
    // =========================================================================
    // Mode definitions:
    // 2'b00: Normal - PBM -> Crypto -> DMA -> DDR
    // 2'b01: DDR Loopback - DDR -> Crypto -> DMA -> DDR (for debugging)
    // 2'b10: PBM Passthrough - PBM -> Crypto -> TX Output (bypass DMA)
    
    always_comb begin
        case (loopback_mode)
            2'b00: begin  // Normal mode
                muxed_crypto_data = crypto_to_dma_data;
                muxed_crypto_empty = crypto_to_dma_empty;
                tx_data_from_crypto = crypto_to_dma_data;
                tx_valid_from_crypto = !crypto_to_dma_empty;
                tx_last_from_crypto = crypto_to_dma_last;
            end
            2'b01: begin  // DDR Loopback mode
                muxed_crypto_data = crypto_to_dma_data;
                muxed_crypto_empty = crypto_to_dma_empty;
                tx_data_from_crypto = 32'b0;
                tx_valid_from_crypto = 1'b0;
                tx_last_from_crypto = 1'b0;
            end
            2'b10: begin  // PBM Passthrough mode
                muxed_crypto_data = crypto_to_dma_data;
                muxed_crypto_empty = crypto_to_dma_empty;
                tx_data_from_crypto = crypto_to_dma_data;
                tx_valid_from_crypto = !crypto_to_dma_empty;
                tx_last_from_crypto = crypto_to_dma_last;
            end
            default: begin  // Default to Normal mode
                muxed_crypto_data = crypto_to_dma_data;
                muxed_crypto_empty = crypto_to_dma_empty;
                tx_data_from_crypto = 32'b0;
                tx_valid_from_crypto = 1'b0;
                tx_last_from_crypto = 1'b0;
            end
        endcase
    end

    assign bridge_tx_rd_en = (loopback_mode == 2'b10) ? (tx_axis_tready && !crypto_to_dma_empty) :
                                                   dma_req_rd;

    // =========================================================================
    // 2. Mode Selection MUX (DMA Parameters)
    // =========================================================================
    assign final_start_raw = (loopback_mode == 2'b00) ? 
                         ((ring_size > 0) ? fetcher_start : csr_start) : 1'b0;
    assign final_addr  = (loopback_mode == 2'b00) ? 
                         ((ring_size > 0) ? fetcher_addr : csr_addr) : 32'b0;
    assign final_len   = (loopback_mode == 2'b00) ? 
                         ((ring_size > 0) ? fetcher_len : csr_len) : 32'b0;
    assign final_algo  = (loopback_mode == 2'b00) ? 
                         ((ring_size > 0) ? fetcher_algo : csr_algo) : 1'b0;
    assign final_start = final_start_raw &&
                         (!dna_lock_en ||
                          (effective_key_valid && !key_system_locked &&
                           (!csr_aes256_en || (effective_key_hi_valid && !key_hi_system_locked))));

    // =========================================================================
    // 3. AXI Master Interface Connections
    // =========================================================================
    // DMA Engine Write Channel (Normal mode only)
    assign m_axis_awaddr = (loopback_mode == 2'b00) ?
                           (fetch_wb_active ? fetch_wb_awaddr : dma_awaddr) : 32'b0;
    assign m_axis_awlen = (loopback_mode == 2'b00) ?
                          (fetch_wb_active ? fetch_wb_awlen : dma_awlen) : 8'b0;
    assign m_axis_awsize = (loopback_mode == 2'b00) ?
                           (fetch_wb_active ? fetch_wb_awsize : dma_awsize) : 3'b010;
    assign m_axis_awburst = (loopback_mode == 2'b00) ?
                            (fetch_wb_active ? fetch_wb_awburst : dma_awburst) : 2'b01;
    assign m_axis_awcache = (loopback_mode == 2'b00) ?
                            (fetch_wb_active ? fetch_wb_awcache : dma_awcache) : 4'b0011;
    assign m_axis_awprot = (loopback_mode == 2'b00) ?
                           (fetch_wb_active ? fetch_wb_awprot : dma_awprot) : 3'b000;
    assign m_axis_wdata = (loopback_mode == 2'b00) ?
                          (fetch_wb_active ? fetch_wb_wdata : dma_wdata) : 32'b0;
    assign m_axis_wstrb = (loopback_mode == 2'b00) ?
                          (fetch_wb_active ? fetch_wb_wstrb : dma_wstrb) : 4'hF;
    assign m_axis_wlast = (loopback_mode == 2'b00) ?
                          (fetch_wb_active ? fetch_wb_wlast : dma_wlast) : 1'b1;
    assign m_axis_wvalid = (loopback_mode == 2'b00) ?
                           (fetch_wb_active ? fetch_wb_wvalid : dma_wvalid) : 1'b0;
    assign m_axis_awvalid = (loopback_mode == 2'b00) ?
                            (fetch_wb_active ? fetch_wb_awvalid : dma_awvalid) : 1'b0;
    assign m_axis_bready = (loopback_mode == 2'b00) ?
                           (fetch_wb_active ? fetch_wb_bready : dma_bready) : 1'b0;

    assign fetch_wb_awready = ((loopback_mode == 2'b00) && fetch_wb_active) ? m_axis_awready : 1'b0;
    assign fetch_wb_wready  = ((loopback_mode == 2'b00) && fetch_wb_active) ? m_axis_wready : 1'b0;
    assign fetch_wb_bresp   = ((loopback_mode == 2'b00) && fetch_wb_active) ? m_axis_bresp : 2'b00;
    assign fetch_wb_bvalid  = ((loopback_mode == 2'b00) && fetch_wb_active) ? m_axis_bvalid : 1'b0;
    assign dma_bresp        = ((loopback_mode == 2'b00) && !fetch_wb_active) ? m_axis_bresp : 2'b00;

    // S2MM/MM2S Write Channel
    assign m_axis_s2mm_awaddr = s2mm_awaddr;
    assign m_axis_s2mm_awlen = s2mm_awlen;
    assign m_axis_s2mm_awsize = s2mm_awsize;
    assign m_axis_s2mm_awburst = s2mm_awburst;
    assign m_axis_s2mm_awcache = s2mm_awcache;
    assign m_axis_s2mm_awprot = s2mm_awprot;
    assign m_axis_s2mm_wdata = s2mm_wdata;
    assign m_axis_s2mm_wstrb = s2mm_wstrb;
    assign m_axis_s2mm_wlast = s2mm_wlast;
    assign m_axis_s2mm_wvalid = s2mm_wvalid;
    assign m_axis_s2mm_bready = s2mm_bready;

    // S2MM/MM2S Read Channel
    assign m_axis_s2mm_araddr = s2mm_araddr;
    assign m_axis_s2mm_arlen = s2mm_arlen;
    assign m_axis_s2mm_arsize = s2mm_arsize;
    assign m_axis_s2mm_arburst = s2mm_arburst;
    assign m_axis_s2mm_arvalid = s2mm_arvalid;
    assign m_axis_s2mm_rready = s2mm_rready;

    // =========================================================================
    // 4. TX Output Interface
    // =========================================================================
    assign tx_axis_tdata = stage1_network_enable ? network_tx_tdata : tx_data_from_crypto;
    assign tx_axis_tvalid = stage1_network_enable ? network_tx_tvalid : tx_valid_from_crypto;
    assign tx_axis_tlast = stage1_network_enable ? network_tx_tlast : tx_last_from_crypto;
    assign tx_axis_tkeep = stage1_network_enable ? network_tx_tkeep : 4'hF;

    // =========================================================================
    // 5. Module Instantiations
    // =========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_busy <= 1'b0;
        end else if (dma_done || dma_error) begin
            dma_busy <= 1'b0;
        end else if (final_start) begin
            dma_busy <= 1'b1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_network_enable <= 1'b0;
            stage1_ingress_inject_sel <= 1'b0;
            stage1_arp_enable <= 1'b1;
            stage1_local_ip <= 32'hC0A8_0114;
            stage1_local_mac_lo <= 32'h3500_0120;
            stage1_local_mac_hi <= 32'h0000_020A;
        end else begin
            if (net_cfg0_we) begin
                stage1_network_enable <= csr_network_enable;
                stage1_ingress_inject_sel <= csr_network_ingress_sel;
                stage1_arp_enable <= csr_arp_enable;
            end
            if (net_local_ip_we) begin
                stage1_local_ip <= csr_net_local_ip;
            end
            if (net_local_mac_lo_we) begin
                stage1_local_mac_lo <= csr_net_local_mac[31:0];
            end
            if (net_local_mac_hi_we) begin
                stage1_local_mac_hi <= {16'd0, csr_net_local_mac[47:32]};
            end
        end
    end

    assign stage1_local_mac = {stage1_local_mac_hi[15:0], stage1_local_mac_lo};
    assign net_applied_cfg0 = {29'd0, stage1_arp_enable, stage1_ingress_inject_sel, stage1_network_enable};
    assign net_applied_local_ip = stage1_local_ip;
    assign net_applied_local_mac_lo = stage1_local_mac_lo;
    assign net_applied_local_mac_hi = stage1_local_mac_hi;
    assign use_stage1_inject = stage1_network_enable && stage1_ingress_inject_sel;

    // CSR (Control and Status Registers)
    axil_csr #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_csr (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        .o_start(csr_start), .o_base_addr(csr_addr), .o_len(csr_len),
        .o_soft_reset(csr_soft_reset),
        .o_ring_doorbell(ring_doorbell), .o_ring_base(ring_base), .o_ring_size(ring_size),
        .o_sw_tail_ptr(sw_tail), .i_hw_head_ptr(hw_head),
        .o_irq_enable(), .o_irq_ack(), .o_irq_coalesce_count(), .o_irq_coalesce_timeout(), .i_irq_status(32'd0),
        .i_debug_status(32'd0), .i_debug_source_progress(32'd0), .i_debug_sink_progress(32'd0),
        .i_debug_plaintext_word0(32'd0), .i_debug_plaintext_word1(32'd0),
        .i_debug_plaintext_word2(32'd0), .i_debug_plaintext_word3(32'd0),
        .i_debug_key_word0(32'd0), .i_debug_key_word1(32'd0),
        .i_debug_key_word2(32'd0), .i_debug_key_word3(32'd0),
        .i_done(dma_done), .i_error(dma_error), .i_busy(dma_busy), .o_algo_sel(csr_algo),
        .o_enc_dec(csr_encdec),  // Encrypt/Decrypt control
        .o_hw_init(hw_init), .o_key(csr_key), .o_key_hi(csr_key_hi), .o_aes256_en(csr_aes256_en),
        .i_acl_inc(acl_drop_pulse), .o_acl_cnt(),
        .o_auth_en(auth_en), .o_acl_en(acl_en), .o_dna_lock_en(dna_lock_en),
        .o_acl_write_en(acl_cfg_we), .o_acl_clear(acl_cfg_clear),
        .o_acl_write_addr(acl_cfg_addr), .o_acl_write_data(acl_cfg_data),
        .o_s2mm_en(s2mm_en), .o_mm2s_en(mm2s_en),
        .o_s2mm_addr(s2mm_addr), .o_s2mm_data(s2mm_data),
        .o_loopback_mode(loopback_mode),
        .o_network_enable(csr_network_enable),
        .o_network_ingress_sel(csr_network_ingress_sel),
        .o_arp_enable(csr_arp_enable),
        .o_net_local_ip(csr_net_local_ip),
        .o_net_local_mac(csr_net_local_mac),
        .o_net_cfg0_we(net_cfg0_we),
        .o_net_local_ip_we(net_local_ip_we),
        .o_net_local_mac_lo_we(net_local_mac_lo_we),
        .o_net_local_mac_hi_we(net_local_mac_hi_we),
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
         .i_drop_wrong_port_count(32'd0),
         .i_drop_unaligned_count(32'd0)
     );

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
         .o_txcap_status(txcap_status),
         .o_txcap_data(txcap_data),
         .o_debug_status(netdbg_status),
         .i_ext_rx_valid(rx_wr_valid),
        .i_ext_rx_data(rx_wr_data),
        .i_ext_rx_last(rx_wr_last),
        .o_ext_rx_ready(network_ext_rx_ready),
        .o_inject_tdata(stage1_inject_tdata),
        .o_inject_tvalid(stage1_inject_tvalid),
        .o_inject_tlast(stage1_inject_tlast),
        .i_inject_tready(stage1_inject_tready),
        .o_tx_axis_tdata(network_tx_tdata),
        .o_tx_axis_tvalid(network_tx_tvalid),
        .o_tx_axis_tlast(network_tx_tlast),
        .o_tx_axis_tkeep(network_tx_tkeep)
    );

    // S2MM/MM2S Engine (Task 11.1/11.2)
    dma_s2mm_mm2s_engine #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_s2mm_mm2s (
        .clk(clk), .rst_n(rst_n),
        .i_s2mm_en(s2mm_en), .i_mm2s_en(mm2s_en),
        .i_s2mm_addr(s2mm_addr), .i_s2mm_data(s2mm_data),
        .o_mm2s_data(mm2s_data),
        // Write Channel
        .m_axis_awaddr(s2mm_awaddr), .m_axis_awlen(s2mm_awlen),
        .m_axis_awsize(s2mm_awsize), .m_axis_awburst(s2mm_awburst),
        .m_axis_awcache(s2mm_awcache), .m_axis_awprot(s2mm_awprot),
        .m_axis_awvalid(s2mm_awvalid), .m_axis_awready(m_axis_s2mm_awready),
        .m_axis_wdata(s2mm_wdata), .m_axis_wstrb(s2mm_wstrb),
        .m_axis_wlast(s2mm_wlast), .m_axis_wvalid(s2mm_wvalid),
        .m_axis_wready(m_axis_s2mm_wready), .m_axis_bresp(s2mm_bresp),
        .m_axis_bvalid(m_axis_s2mm_bvalid), .m_axis_bready(s2mm_bready),
        // Read Channel
        .m_axis_araddr(s2mm_araddr), .m_axis_arlen(s2mm_arlen),
        .m_axis_arsize(s2mm_arsize), .m_axis_arburst(s2mm_arburst),
        .m_axis_arvalid(s2mm_arvalid), .m_axis_arready(m_axis_s2mm_arready),
        .m_axis_rdata(m_axis_s2mm_rdata), .m_axis_rresp(s2mm_rresp),
        .m_axis_rlast(m_axis_s2mm_rlast), .m_axis_rvalid(m_axis_s2mm_rvalid), .m_axis_rready(s2mm_rready)
    );

    dma_desc_fetcher #(.ADDR_WIDTH(ADDR_WIDTH)) u_fetcher (
        .clk(clk), .rst_n(rst_n), .i_soft_reset(csr_soft_reset),
        .i_ring_base(ring_base), .i_ring_size(ring_size), .i_ring_doorbell(ring_doorbell),
        .i_sw_tail_ptr(sw_tail), .o_hw_head_ptr(hw_head),
        .o_dma_start(fetcher_start), .o_dma_addr(fetcher_addr),
        .o_dma_src_addr(fetcher_src_addr_unused),
        .o_dma_len(fetcher_len), .o_dma_algo(fetcher_algo),
        .o_dma_stream_tlast(fetcher_stream_tlast_unused),
        .i_dma_done(dma_done), .i_dma_error(dma_error), .i_dma_bresp(dma_status_bresp),
        .i_dma_actual_len(32'd0),
        .o_completion_event(fetcher_completion_event_unused),
        .m_axi_araddr(m_axis_fetcher_araddr), .m_axi_arlen(m_axis_fetcher_arlen),
        .m_axi_arsize(m_axis_fetcher_arsize), .m_axi_arburst(m_axis_fetcher_arburst),
        .m_axi_arvalid(m_axis_fetcher_arvalid), .m_axi_arready(m_axis_fetcher_arready),
        .m_axi_rdata(m_axis_fetcher_rdata), .m_axi_rlast(m_axis_fetcher_rlast),
        .m_axi_rvalid(m_axis_fetcher_rvalid), .m_axi_rready(m_axis_fetcher_rready),
        .m_axi_awaddr(fetch_wb_awaddr), .m_axi_awlen(fetch_wb_awlen),
        .m_axi_awsize(fetch_wb_awsize), .m_axi_awburst(fetch_wb_awburst),
        .m_axi_awcache(fetch_wb_awcache), .m_axi_awprot(fetch_wb_awprot),
        .m_axi_awvalid(fetch_wb_awvalid), .m_axi_awready(fetch_wb_awready),
        .m_axi_wdata(fetch_wb_wdata), .m_axi_wstrb(fetch_wb_wstrb),
        .m_axi_wlast(fetch_wb_wlast), .m_axi_wvalid(fetch_wb_wvalid),
        .m_axi_wready(fetch_wb_wready), .m_axi_bresp(fetch_wb_bresp),
        .m_axi_bvalid(fetch_wb_bvalid), .m_axi_bready(fetch_wb_bready),
        .o_wb_active(fetch_wb_active)
    );

    // Key vault: when DNA lock enabled, use DNA-bound key.
    key_vault u_key_vault (
        .clk(clk), .rst_n(rst_n),
        .dna_out(dna_out_sig),
        .user_key_in(csr_key),
        .user_key_valid(1'b1),
        .effective_key_out(effective_key),
        .effective_key_valid(effective_key_valid),
        .dna_lock_enable(dna_lock_en),
        .lock_status(key_lock_status),
        .system_locked(key_system_locked),
        .tamper_detected(key_tamper),
        .stored_dna(),
        .stored_hash(),
        .tamper_counter()
    );

        // Reuse DNA-bound low-half derivation to derive high-half key and avoid a second DNA_PORT.
    assign effective_key_hi       = {effective_key[63:0], effective_key[127:64]} ^ csr_key_hi;
    assign effective_key_hi_valid = effective_key_valid;
    assign key_hi_system_locked   = key_system_locked;
    assign key_hi_tamper          = key_tamper;
assign secure_key       = dna_lock_en ? effective_key : csr_key;
    assign secure_key_hi    = dna_lock_en ? effective_key_hi : csr_key_hi;
    assign secure_aes256_en = csr_aes256_en;

    // Optional auth stage. When disabled, traffic bypasses this block.
    config_packet_auth u_cfg_auth (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(rx_wr_data),
        .s_axis_tkeep(4'hF),
        .s_axis_tlast(rx_wr_last),
        .s_axis_tvalid(rx_wr_valid && auth_en && !stage1_network_enable),
        .s_axis_tready(auth_tready),
        .m_axis_tdata(auth_tdata),
        .m_axis_tkeep(auth_tkeep),
        .m_axis_tlast(auth_tlast),
        .m_axis_tvalid(auth_tvalid),
        .m_axis_tready(auth_acl_tready),
        .auth_success_cnt(),
        .auth_fail_cnt(),
        .replay_fail_cnt(),
        .last_seq_id(),
        .error_flag()
    );

    // When auth is enabled, strip the first two auth header words before ACL inspection
    // so ACL keeps matching on the semantic 7-word network header tuple.
    always_comb begin
        auth_acl_tdata  = auth_tdata;
        auth_acl_tkeep  = auth_tkeep;
        auth_acl_tlast  = auth_tlast;
        auth_acl_tvalid = 1'b0;
        auth_acl_tready = 1'b0;

        case (auth_acl_state)
            AUTH_STRIP_HDR0,
            AUTH_STRIP_HDR1: begin
                auth_acl_tready = 1'b1;
            end

            AUTH_STRIP_STREAM: begin
                auth_acl_tdata  = auth_tdata;
                auth_acl_tkeep  = auth_tkeep;
                auth_acl_tlast  = auth_tlast;
                auth_acl_tvalid = auth_tvalid;
                auth_acl_tready = ingress_tready;
            end

            default: begin
                auth_acl_tready = 1'b1;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            auth_acl_state <= AUTH_STRIP_HDR0;
        end else if (!auth_en) begin
            auth_acl_state <= AUTH_STRIP_HDR0;
        end else if (auth_tvalid && auth_acl_tready) begin
            case (auth_acl_state)
                AUTH_STRIP_HDR0: begin
                    if (auth_tlast) begin
                        auth_acl_state <= AUTH_STRIP_HDR0;
                    end else begin
                        auth_acl_state <= AUTH_STRIP_HDR1;
                    end
                end

                AUTH_STRIP_HDR1: begin
                    if (auth_tlast) begin
                        auth_acl_state <= AUTH_STRIP_HDR0;
                    end else begin
                        auth_acl_state <= AUTH_STRIP_STREAM;
                    end
                end

                AUTH_STRIP_STREAM: begin
                    if (auth_tlast) begin
                        auth_acl_state <= AUTH_STRIP_HDR0;
                    end
                end

                default: begin
                    auth_acl_state <= AUTH_STRIP_HDR0;
                end
            endcase
        end
    end

    assign ingress_tdata  = use_stage1_inject ? stage1_inject_tdata :
                            (auth_en ? auth_acl_tdata : rx_wr_data);
    assign ingress_tlast  = use_stage1_inject ? stage1_inject_tlast :
                            (auth_en ? auth_acl_tlast : rx_wr_last);
    assign ingress_tvalid = use_stage1_inject ? stage1_inject_tvalid :
                            (auth_en ? auth_acl_tvalid : (rx_wr_valid && !stage1_network_enable));
    assign stage1_inject_tready = use_stage1_inject ? ingress_tready : 1'b0;
    assign rx_wr_ready    = stage1_network_enable ? network_ext_rx_ready : (auth_en ? auth_tready : ingress_tready);

    // Once PBM hits high-water in the middle of a frame, mark the rest of the
    // frame as errored and let PBM roll the entire frame back on TLAST. This
    // preserves packet boundaries and prevents a dangling partial packet from
    // ever becoming visible to crypto/DMA.
    assign ingress_drop_now = aclf_tvalid && !ingress_drop_until_tlast && pbm_high_water;
    assign pbm_ingress_error = ingress_drop_until_tlast || ingress_drop_now;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ingress_drop_until_tlast <= 1'b0;
        end else if (aclf_tvalid && pbm_wr_ready) begin
            if (ingress_drop_until_tlast) begin
                if (aclf_tlast) begin
                    ingress_drop_until_tlast <= 1'b0;
                end
            end else if (ingress_drop_now && !aclf_tlast) begin
                ingress_drop_until_tlast <= 1'b1;
            end
        end
    end

    // ACL stage. With acl_en=0, this stage forwards traffic without dropping.
    acl_packet_filter u_acl_filter (
        .clk(clk), .rst_n(rst_n),
        .acl_en(acl_en),
        .s_tdata(ingress_tdata),
        .s_tvalid(ingress_tvalid),
        .s_tlast(ingress_tlast),
        .s_tready(ingress_tready),
        .m_tdata(aclf_tdata),
        .m_tvalid(aclf_tvalid),
        .m_tlast(aclf_tlast),
        .m_tready(pbm_wr_ready),
        .acl_write_en(acl_cfg_we),
        .acl_write_addr(acl_cfg_addr),
        .acl_write_data(acl_cfg_data),
        .acl_clear(acl_cfg_clear),
        .acl_hit(acl_hit),
        .acl_drop(acl_drop),
        .acl_drop_pulse(acl_drop_pulse),
        .acl_hit_count(acl_hit_count),
        .acl_miss_count(acl_miss_count)
    );
    // PBM Controller
    pbm_controller #(.PBM_ADDR_WIDTH(PBM_ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_pbm (
        .clk(clk), .rst_n(rst_n),
        .i_wr_valid(aclf_tvalid), .i_wr_data(aclf_tdata), .i_wr_last(aclf_tlast), .i_wr_error(pbm_ingress_error),
        .o_wr_ready(pbm_wr_ready), .o_rd_data(pbm_data), .o_rd_empty(pbm_empty), .o_rd_valid(bridge_rd_valid), .i_rd_en(bridge_rd_pbm),
        .o_buffer_usage(pbm_buffer_usage), .o_rollback_active(pbm_rollback_active),
        .o_high_water(pbm_high_water), .o_drop_pulse(pbm_drop_pulse)
    );

    // Crypto Bridge
    crypto_bridge_top #(
        .NUM_INSTANCES(CRYPTO_NUM_INSTANCES)
    ) u_crypto_bridge (
        .clk(clk), .rst_n(rst_n),
        .i_algo_sel(final_algo),
        .i_encdec(csr_encdec),     // Encrypt/Decrypt control
        .i_aes256_en(secure_aes256_en),
        .i_key(secure_key),
        .i_key_hi(secure_key_hi),
        .o_system_ready(),
        .o_debug_last_plaintext(),
        .o_debug_key_lo_active(),
        .i_pbm_data(pbm_data), .i_pbm_empty(pbm_empty), .i_pbm_valid(bridge_rd_valid),
        .o_pbm_rd_en(bridge_rd_pbm),
        .o_tx_data(crypto_to_dma_data),
        .o_tx_last(crypto_to_dma_last),
        .o_tx_empty(crypto_to_dma_empty),
        .i_tx_rd_en(bridge_tx_rd_en)
    );

    dma_master_engine #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_dma_engine (
        .clk(clk), .rst_n(rst_n),
        .i_start(final_start),
        .i_base_addr(final_addr),
        .i_total_len(final_len),
        .o_done(dma_done),
        .o_error(dma_error),
        .o_bresp(dma_status_bresp),
        .i_fifo_rdata(muxed_crypto_data),
        .i_fifo_empty(muxed_crypto_empty),
        .o_fifo_ren(dma_req_rd),
        .m_axi_awaddr(dma_awaddr), .m_axi_awlen(dma_awlen),
        .m_axi_awsize(dma_awsize), .m_axi_awburst(dma_awburst),
        .m_axi_awcache(dma_awcache), .m_axi_awprot(dma_awprot),
        .m_axi_awvalid(dma_awvalid), .m_axi_awready(fetch_wb_active ? 1'b0 : m_axis_awready),
        .m_axi_wdata(dma_wdata), .m_axi_wstrb(dma_wstrb),
        .m_axi_wlast(dma_wlast), .m_axi_wvalid(dma_wvalid),
        .m_axi_wready(fetch_wb_active ? 1'b0 : m_axis_wready), .m_axi_wresp(dma_bresp), .m_axi_blast(1'b0),
        .m_axi_bvalid(fetch_wb_active ? 1'b0 : m_axis_bvalid), .m_axi_bready(dma_bready),
        .m_axi_araddr(), .m_axi_arlen(), .m_axi_arsize(),
        .m_axi_arburst(), .m_axi_arvalid(), .m_axi_arready(1'b0),
        .m_axi_rdata(32'b0), .m_axi_rresp(2'b00), .m_axi_rlast(1'b0),
        .m_axi_rvalid(1'b0), .m_axi_rready()
    );

    // =========================================================================
    // 6. Interrupt Logic
    // =========================================================================
    assign dma_irq = dma_done;

endmodule












