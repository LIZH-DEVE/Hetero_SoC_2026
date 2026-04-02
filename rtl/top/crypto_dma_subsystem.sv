`timescale 1ns / 1ps

module crypto_dma_subsystem #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter CRYPTO_NUM_INSTANCES = 1
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
    output logic                   m_axis_fetcher_rready
);

    // =========================================================================
    // Internal Signals
    // =========================================================================
    logic                   csr_start, fetcher_start, final_start, source_reader_start;
    logic                   csr_soft_reset;
    logic                   fetcher_completion_event_unused;
    logic                   fetcher_stream_tlast_unused;
    (* mark_debug = "true" *) logic [31:0]            csr_addr, fetcher_addr, fetcher_src_addr, final_addr;
    (* mark_debug = "true" *) logic [31:0]            csr_len, fetcher_len, final_len;
    (* mark_debug = "true" *) logic                   csr_algo, fetcher_algo, final_algo;
    logic                   csr_encdec;  // Encrypt/Decrypt control from CSR
    logic                   ring_doorbell;
    logic [31:0]            ring_base, ring_size;
    logic [15:0]            sw_tail, hw_head;
    logic                   dma_done, dma_error, dma_busy, hw_init;
    logic [1:0]             dma_status_bresp;
    (* mark_debug = "true" *) logic [127:0]           csr_key;
    logic [127:0]            csr_key_hi;
    logic                    csr_aes256_en;
    
    // S2MM/MM2S signals
    logic                   s2mm_en, mm2s_en;
    logic [31:0]            s2mm_addr, s2mm_data, mm2s_data;
    logic [1:0]             loopback_mode;
    
    // PBM signals
    (* mark_debug = "true" *) logic [31:0]            pbm_data;
    (* mark_debug = "true" *) logic                   pbm_empty;
    (* mark_debug = "true" *) logic                   bridge_rd_pbm;
    (* mark_debug = "true" *) logic                   bridge_rd_valid;
    logic [31:0]                                     crypto_src_data;
    logic                                            crypto_src_empty;
    logic                                            crypto_src_valid;
    logic                                            crypto_src_rd_en;
    logic                                            use_desc_source;

    // Descriptor-driven source reader signals
    logic [31:0]                                     source_rd_data;
    logic                                            source_rd_empty;
    logic                                            source_rd_valid;
    logic                                            source_rd_en;
    logic                                            source_done;
    logic                                            source_error;
    logic [1:0]                                      source_last_rresp;
    logic [31:0]                                     source_bytes_fetched;
    logic [31:0]                                     source_bytes_delivered;
    logic [7:0]                                      source_debug_state;
    logic [ADDR_WIDTH-1:0]                           source_araddr;
    logic [7:0]                                      source_arlen;
    logic [2:0]                                      source_arsize;
    logic [1:0]                                      source_arburst;
    logic                                            source_arvalid;
    logic                                            source_arready;
    logic [DATA_WIDTH-1:0]                           source_rdata;
    logic [1:0]                                      source_rresp;
    logic                                            source_rlast;
    logic                                            source_rvalid;
    logic                                            source_rready;

    // Crypto Bridge signals
    (* mark_debug = "true" *) logic [31:0]            crypto_to_dma_data;
    (* mark_debug = "true" *) logic                   crypto_to_dma_empty;
    (* mark_debug = "true" *) logic                   crypto_to_dma_last;
    (* mark_debug = "true" *) logic                   dma_req_rd;
    logic                                              bridge_tx_rd_en;

    // Loopback Mux signals
    (* mark_debug = "true" *) logic [31:0]            muxed_crypto_data;
    (* mark_debug = "true" *) logic                   muxed_crypto_empty;
    (* mark_debug = "true" *) logic [31:0]            tx_data_from_crypto;
    (* mark_debug = "true" *) logic                   tx_valid_from_crypto;
    (* mark_debug = "true" *) logic                   tx_last_from_crypto;
    
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
    logic [31:0]            s2mm_rdata_in;
    logic [1:0]             s2mm_rresp;
    logic                   s2mm_rvalid_in;
    logic                   s2mm_rlast_in;

    // Combined DMA status for fetcher/CSR
    logic                   sink_done;
    logic                   sink_error;
    logic [1:0]             sink_bresp;
    logic [31:0]            dma_actual_len;
    logic [31:0]            sink_bytes_written;
    logic [7:0]             sink_debug_state;
    logic [31:0]            csr_debug_status;
    logic [31:0]            csr_debug_source_progress;
    logic [31:0]            csr_debug_sink_progress;
    logic [127:0]           bridge_debug_last_plaintext;
    logic [127:0]           bridge_debug_key_lo_active;
    logic                   source_error_sticky_q;
    logic                   sink_error_sticky_q;
    logic                   source_done_sticky_q;
    logic                   sink_done_sticky_q;
    logic [1:0]             debug_source_rresp_q;
    logic [1:0]             debug_sink_bresp_q;
    logic [7:0]             source_debug_state_sticky_q;
    logic [7:0]             sink_debug_state_sticky_q;
    logic [31:0]            source_progress_sticky_q;
    logic [31:0]            sink_progress_sticky_q;

    function automatic [31:0] dma_sink_word_order(input [31:0] value);
        begin
            dma_sink_word_order = {value[7:0], value[15:8], value[23:16], value[31:24]};
        end
    endfunction

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
                muxed_crypto_data = dma_sink_word_order(crypto_to_dma_data);
                muxed_crypto_empty = crypto_to_dma_empty;
                tx_data_from_crypto = crypto_to_dma_data;
                tx_valid_from_crypto = !crypto_to_dma_empty;
                tx_last_from_crypto = crypto_to_dma_last;
            end
            2'b01: begin  // DDR Loopback mode
                muxed_crypto_data = dma_sink_word_order(crypto_to_dma_data);
                muxed_crypto_empty = crypto_to_dma_empty;
                tx_data_from_crypto = 32'b0;
                tx_valid_from_crypto = 1'b0;
                tx_last_from_crypto = 1'b0;
            end
            2'b10: begin  // PBM Passthrough mode
                muxed_crypto_data = dma_sink_word_order(crypto_to_dma_data);
                muxed_crypto_empty = crypto_to_dma_empty;
                tx_data_from_crypto = crypto_to_dma_data;
                tx_valid_from_crypto = !crypto_to_dma_empty;
                tx_last_from_crypto = crypto_to_dma_last;
            end
            default: begin  // Default to Normal mode
                muxed_crypto_data = dma_sink_word_order(crypto_to_dma_data);
                muxed_crypto_empty = crypto_to_dma_empty;
                tx_data_from_crypto = 32'b0;
                tx_valid_from_crypto = 1'b0;
                tx_last_from_crypto = 1'b0;
            end
        endcase
    end

    // =========================================================================
    // 2. Mode Selection MUX (DMA Parameters)
    // =========================================================================
    assign final_start = (loopback_mode == 2'b00) ? 
                         ((ring_size > 0) ? fetcher_start : csr_start) : 1'b0;
    assign final_addr  = (loopback_mode == 2'b00) ? 
                         ((ring_size > 0) ? fetcher_addr : csr_addr) : 32'b0;
    assign final_len   = (loopback_mode == 2'b00) ? 
                         ((ring_size > 0) ? fetcher_len : csr_len) : 32'b0;
    assign final_algo  = (loopback_mode == 2'b00) ? 
                         ((ring_size > 0) ? fetcher_algo : csr_algo) : 1'b0;
    assign use_desc_source = (loopback_mode == 2'b00) && (ring_size > 0);
    assign source_reader_start = final_start && use_desc_source;

    assign crypto_src_data = use_desc_source ? source_rd_data : pbm_data;
    assign crypto_src_empty = use_desc_source ? source_rd_empty : pbm_empty;
    assign crypto_src_valid = use_desc_source ? source_rd_valid : bridge_rd_valid;
    assign source_rd_en = use_desc_source ? crypto_src_rd_en : 1'b0;
    assign bridge_rd_pbm = use_desc_source ? 1'b0 : crypto_src_rd_en;
    assign dma_done = sink_done;
    assign dma_error = sink_error || source_error;
    assign dma_status_bresp = sink_bresp;
    assign dma_actual_len = sink_done ? final_len : 32'd0;
    assign csr_debug_status = {
        16'd0,
        sink_debug_state_sticky_q,
        source_debug_state_sticky_q,
        debug_sink_bresp_q,
        debug_source_rresp_q,
        sink_done_sticky_q,
        source_done_sticky_q,
        sink_error_sticky_q,
        source_error_sticky_q
    };
    assign csr_debug_source_progress = source_progress_sticky_q;
    assign csr_debug_sink_progress = sink_progress_sticky_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_error_sticky_q <= 1'b0;
            sink_error_sticky_q <= 1'b0;
            source_done_sticky_q <= 1'b0;
            sink_done_sticky_q <= 1'b0;
            debug_source_rresp_q <= 2'b00;
            debug_sink_bresp_q <= 2'b00;
            source_debug_state_sticky_q <= 8'd0;
            sink_debug_state_sticky_q <= 8'd0;
            source_progress_sticky_q <= 32'd0;
            sink_progress_sticky_q <= 32'd0;
        end else if (csr_soft_reset || ring_doorbell) begin
            source_error_sticky_q <= 1'b0;
            sink_error_sticky_q <= 1'b0;
            source_done_sticky_q <= 1'b0;
            sink_done_sticky_q <= 1'b0;
            debug_source_rresp_q <= 2'b00;
            debug_sink_bresp_q <= 2'b00;
            source_debug_state_sticky_q <= 8'd0;
            sink_debug_state_sticky_q <= 8'd0;
            source_progress_sticky_q <= 32'd0;
            sink_progress_sticky_q <= 32'd0;
        end else begin
            if (source_rvalid && source_rready) begin
                debug_source_rresp_q <= source_rresp;
            end
            if (source_error) begin
                source_error_sticky_q <= 1'b1;
                debug_source_rresp_q <= source_rresp;
            end
            if (sink_error) begin
                sink_error_sticky_q <= 1'b1;
                debug_sink_bresp_q <= sink_bresp;
            end
            if (source_done) begin
                source_done_sticky_q <= 1'b1;
            end
            if (sink_done) begin
                sink_done_sticky_q <= 1'b1;
                debug_sink_bresp_q <= sink_bresp;
            end
            if (source_debug_state != 8'd0) begin
                source_debug_state_sticky_q <= source_debug_state;
            end
            if (sink_debug_state != 8'd0) begin
                sink_debug_state_sticky_q <= sink_debug_state;
            end
            if (source_bytes_fetched > source_progress_sticky_q) begin
                source_progress_sticky_q <= source_bytes_fetched;
            end
            if (sink_bytes_written > sink_progress_sticky_q) begin
                sink_progress_sticky_q <= sink_bytes_written;
            end
        end
    end

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
    assign m_axis_s2mm_araddr = use_desc_source ? source_araddr : s2mm_araddr;
    assign m_axis_s2mm_arlen = use_desc_source ? source_arlen : s2mm_arlen;
    assign m_axis_s2mm_arsize = use_desc_source ? source_arsize : s2mm_arsize;
    assign m_axis_s2mm_arburst = use_desc_source ? source_arburst : s2mm_arburst;
    assign m_axis_s2mm_arvalid = use_desc_source ? source_arvalid : s2mm_arvalid;
    assign m_axis_s2mm_rready = use_desc_source ? source_rready : s2mm_rready;
    assign source_arready = use_desc_source ? m_axis_s2mm_arready : 1'b0;
    assign source_rdata = use_desc_source ? m_axis_s2mm_rdata : 32'd0;
    assign source_rresp = use_desc_source ? m_axis_s2mm_rresp : 2'b00;
    assign source_rlast = use_desc_source ? m_axis_s2mm_rlast : 1'b0;
    assign source_rvalid = use_desc_source ? m_axis_s2mm_rvalid : 1'b0;
    assign s2mm_rdata_in = use_desc_source ? 32'd0 : m_axis_s2mm_rdata;
    assign s2mm_rresp = use_desc_source ? 2'b00 : m_axis_s2mm_rresp;
    assign s2mm_rlast_in = use_desc_source ? 1'b0 : m_axis_s2mm_rlast;
    assign s2mm_rvalid_in = use_desc_source ? 1'b0 : m_axis_s2mm_rvalid;

    // =========================================================================
    // 4. TX Output Interface
    // =========================================================================
    assign tx_axis_tdata = tx_data_from_crypto;
    assign tx_axis_tvalid = tx_valid_from_crypto;
    assign tx_axis_tlast = tx_last_from_crypto;
    assign tx_axis_tkeep = 4'hF;

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

    assign bridge_tx_rd_en = (loopback_mode == 2'b10) ? (tx_axis_tready && !crypto_to_dma_empty) :
                                                   dma_req_rd;

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
        .o_ring_doorbell(ring_doorbell),
        .o_ring_base(ring_base), .o_ring_size(ring_size),
        .o_sw_tail_ptr(sw_tail), .i_hw_head_ptr(hw_head),
        .o_irq_enable(), .o_irq_ack(), .o_irq_coalesce_count(), .o_irq_coalesce_timeout(), .i_irq_status(32'd0),
          .i_debug_status(csr_debug_status),
          .i_debug_source_progress(csr_debug_source_progress),
          .i_debug_sink_progress(csr_debug_sink_progress),
          .i_debug_plaintext_word0(bridge_debug_last_plaintext[127:96]),
          .i_debug_plaintext_word1(bridge_debug_last_plaintext[95:64]),
          .i_debug_plaintext_word2(bridge_debug_last_plaintext[63:32]),
          .i_debug_plaintext_word3(bridge_debug_last_plaintext[31:0]),
          .i_debug_key_word0(bridge_debug_key_lo_active[127:96]),
          .i_debug_key_word1(bridge_debug_key_lo_active[95:64]),
          .i_debug_key_word2(bridge_debug_key_lo_active[63:32]),
          .i_debug_key_word3(bridge_debug_key_lo_active[31:0]),
          .i_done(dma_done), .i_error(dma_error), .i_busy(dma_busy), .o_algo_sel(csr_algo),
          .o_enc_dec(csr_encdec),
        .o_hw_init(hw_init), .o_key(csr_key), .o_key_hi(csr_key_hi), .o_aes256_en(csr_aes256_en),
        .i_acl_inc(1'b0), .o_acl_cnt(),
        .o_s2mm_en(s2mm_en), .o_mm2s_en(mm2s_en),
        .o_s2mm_addr(s2mm_addr), .o_s2mm_data(s2mm_data),
        .o_loopback_mode(loopback_mode),
        .i_inj_status(32'd0),
        .i_txcap_status(32'd0),
        .i_txcap_data(32'd0),
        .i_netdbg_status(32'd0),
        .i_net_applied_cfg0(32'd0),
        .i_net_applied_local_ip(32'd0),
        .i_net_applied_local_mac_lo(32'd0),
        .i_net_applied_local_mac_hi(32'd0),
        .i_drop_wrong_port_count(32'd0),
        .i_drop_unaligned_count(32'd0)
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
        .m_axis_rdata(s2mm_rdata_in), .m_axis_rresp(s2mm_rresp),
        .m_axis_rlast(s2mm_rlast_in), .m_axis_rvalid(s2mm_rvalid_in), .m_axis_rready(s2mm_rready)
    );

    dma_desc_fetcher #(.ADDR_WIDTH(ADDR_WIDTH)) u_fetcher (
        .clk(clk), .rst_n(rst_n), .i_soft_reset(csr_soft_reset),
        .i_ring_base(ring_base), .i_ring_size(ring_size), .i_ring_doorbell(ring_doorbell),
        .i_sw_tail_ptr(sw_tail), .o_hw_head_ptr(hw_head),
        .o_dma_start(fetcher_start), .o_dma_addr(fetcher_addr),
        .o_dma_src_addr(fetcher_src_addr),
        .o_dma_len(fetcher_len), .o_dma_algo(fetcher_algo),
        .o_dma_stream_tlast(fetcher_stream_tlast_unused),
        .i_dma_done(dma_done), .i_dma_error(dma_error), .i_dma_bresp(dma_status_bresp),
        .i_dma_actual_len(dma_actual_len),
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

    dma_crypto_source_reader #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_dma_crypto_source_reader (
        .clk(clk), .rst_n(rst_n),
        .i_soft_reset(csr_soft_reset),
        .i_start(source_reader_start),
        .i_src_addr(fetcher_src_addr),
        .i_total_len(final_len),
        .o_rd_data(source_rd_data),
        .o_rd_valid(source_rd_valid),
        .o_rd_empty(source_rd_empty),
        .i_rd_en(source_rd_en),
        .o_done(source_done),
        .o_error(source_error),
        .o_busy(),
        .o_debug_last_rresp(source_last_rresp),
        .o_debug_bytes_fetched(source_bytes_fetched),
        .o_debug_bytes_delivered(source_bytes_delivered),
        .o_debug_state(source_debug_state),
        .m_axi_araddr(source_araddr),
        .m_axi_arlen(source_arlen),
        .m_axi_arsize(source_arsize),
        .m_axi_arburst(source_arburst),
        .m_axi_arvalid(source_arvalid),
        .m_axi_arready(source_arready),
        .m_axi_rdata(source_rdata),
        .m_axi_rresp(source_rresp),
        .m_axi_rlast(source_rlast),
        .m_axi_rvalid(source_rvalid),
        .m_axi_rready(source_rready)
    );

    // PBM Controller
    pbm_controller #(.PBM_ADDR_WIDTH(14), .DATA_WIDTH(DATA_WIDTH)) u_pbm (
        .clk(clk), .rst_n(rst_n),
        .i_wr_valid(rx_wr_valid), .i_wr_data(rx_wr_data), .i_wr_last(rx_wr_last), .i_wr_error(1'b0),
        .o_wr_ready(rx_wr_ready), .o_rd_data(pbm_data), .o_rd_empty(pbm_empty), .o_rd_valid(bridge_rd_valid), .i_rd_en(bridge_rd_pbm), .o_buffer_usage(), .o_rollback_active()
    );

    // Crypto Bridge
    crypto_bridge_top #(
        .NUM_INSTANCES(CRYPTO_NUM_INSTANCES)
    ) u_crypto_bridge (
        .clk(clk), .rst_n(rst_n),
          .i_algo_sel(final_algo),
          .i_encdec(csr_encdec),
          .i_aes256_en(csr_aes256_en),
          .i_key(csr_key),
          .i_key_hi(csr_key_hi),
          .o_system_ready(),
          .o_debug_last_plaintext(bridge_debug_last_plaintext),
          .o_debug_key_lo_active(bridge_debug_key_lo_active),
          .i_pbm_data(crypto_src_data), .i_pbm_empty(crypto_src_empty), .i_pbm_valid(crypto_src_valid),
          .o_pbm_rd_en(crypto_src_rd_en),
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
        .o_done(sink_done),
        .o_error(sink_error),
        .o_bresp(sink_bresp),
        .o_debug_bytes_written(sink_bytes_written),
        .o_debug_state(sink_debug_state),
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

endmodule



