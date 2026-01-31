`timescale 1ns / 1ps

module crypto_dma_subsystem #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
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
    logic                   csr_start, fetcher_start, final_start;
    logic [31:0]            csr_addr, fetcher_addr, final_addr;
    logic [31:0]            csr_len, fetcher_len, final_len;
    logic                   csr_algo, fetcher_algo, final_algo;
    logic [31:0]            ring_base, ring_size;
    logic [15:0]            sw_tail, hw_head;
    logic                   dma_done, hw_init;
    logic [127:0]           csr_key;
    
    // S2MM/MM2S signals
    logic                   s2mm_en, mm2s_en;
    logic [31:0]            s2mm_addr, s2mm_data, mm2s_data;
    logic [1:0]             loopback_mode;
    
    // PBM signals
    logic [31:0]            pbm_data;
    logic                   pbm_empty;
    logic                   bridge_rd_pbm;
    
    // Crypto Bridge signals
    logic [31:0]            crypto_to_dma_data;
    logic                   crypto_to_dma_empty;
    logic                   dma_req_rd;
    
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
                tx_last_from_crypto = 1'b0;
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
                tx_last_from_crypto = 1'b0;
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

    // =========================================================================
    // 3. AXI Master Interface Connections
    // =========================================================================
    // DMA Engine Write Channel (Normal mode only)
    assign m_axis_awaddr = (loopback_mode == 2'b00) ? dma_awaddr : 32'b0;
    assign m_axis_awlen = (loopback_mode == 2'b00) ? dma_awlen : 8'b0;
    assign m_axis_awsize = (loopback_mode == 2'b00) ? dma_awsize : 3'b010;
    assign m_axis_awburst = (loopback_mode == 2'b00) ? dma_awburst : 2'b01;
    assign m_axis_awcache = (loopback_mode == 2'b00) ? dma_awcache : 4'b0011;
    assign m_axis_awprot = (loopback_mode == 2'b00) ? dma_awprot : 3'b000;
    assign m_axis_wdata = (loopback_mode == 2'b00) ? dma_wdata : 32'b0;
    assign m_axis_wstrb = (loopback_mode == 2'b00) ? dma_wstrb : 4'hF;
    assign m_axis_wlast = (loopback_mode == 2'b00) ? dma_wlast : 1'b1;
    assign m_axis_wvalid = (loopback_mode == 2'b00) ? dma_wvalid : 1'b0;
    assign m_axis_awvalid = (loopback_mode == 2'b00) ? dma_awvalid : 1'b0;

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
    assign tx_axis_tdata = tx_data_from_crypto;
    assign tx_axis_tvalid = tx_valid_from_crypto;
    assign tx_axis_tlast = tx_last_from_crypto;
    assign tx_axis_tkeep = 4'hF;

    // =========================================================================
    // 5. Module Instantiations
    // =========================================================================

    // CSR (Control and Status Registers)
    axil_csr #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_csr (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        .o_start(csr_start), .o_base_addr(csr_addr), .o_len(csr_len),
        .o_ring_base(ring_base), .o_ring_size(ring_size),
        .o_sw_tail_ptr(sw_tail), .i_hw_head_ptr(hw_head),
        .i_done(dma_done), .i_error(1'b0), .o_algo_sel(csr_algo),
        .o_hw_init(hw_init), .o_key(csr_key),
        .i_acl_cnt(32'd0),
        .o_s2mm_en(s2mm_en), .o_mm2s_en(mm2s_en),
        .o_s2mm_addr(s2mm_addr), .o_s2mm_data(s2mm_data),
        .o_loopback_mode(loopback_mode)
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
        .clk(clk), .rst_n(rst_n),
        .i_ring_base(ring_base), .i_ring_size(ring_size),
        .i_sw_tail_ptr(sw_tail), .o_hw_head_ptr(hw_head),
        .o_dma_start(fetcher_start), .o_dma_addr(fetcher_addr),
        .o_dma_len(fetcher_len), .o_dma_algo(fetcher_algo),
        .i_dma_done(dma_done),
        .m_axi_araddr(m_axis_fetcher_araddr), .m_axi_arlen(m_axis_fetcher_arlen),
        .m_axi_arsize(m_axis_fetcher_arsize), .m_axi_arburst(m_axis_fetcher_arburst),
        .m_axi_arvalid(m_axis_fetcher_arvalid), .m_axi_arready(m_axis_fetcher_arready),
        .m_axi_rdata(m_axis_fetcher_rdata), .m_axi_rlast(m_axis_fetcher_rlast),
        .m_axi_rvalid(m_axis_fetcher_rvalid), .m_axi_rready(m_axis_fetcher_rready)
    );

    // PBM Controller
    pbm_controller #(.PBM_ADDR_WIDTH(14), .DATA_WIDTH(DATA_WIDTH)) u_pbm (
        .clk(clk), .rst_n(rst_n),
        .i_wr_valid(rx_wr_valid), .i_wr_data(rx_wr_data), .i_wr_last(rx_wr_last), .i_wr_error(1'b0),
        .o_wr_ready(rx_wr_ready), .o_rd_data(pbm_data), .o_rd_empty(pbm_empty), .o_rd_valid(), .i_rd_en(bridge_rd_pbm), .o_buffer_usage(), .o_rollback_active()
    );

    // Crypto Bridge
    crypto_bridge_top u_crypto_bridge (
        .clk(clk), .rst_n(rst_n),
        .i_algo_sel(final_algo),
        .i_key(csr_key),
        .o_system_ready(),
        .i_pbm_data(pbm_data), .i_pbm_empty(pbm_empty),
        .o_pbm_rd_en(bridge_rd_pbm),
        .o_tx_data(crypto_to_dma_data),
        .o_tx_empty(crypto_to_dma_empty),
        .i_tx_rd_en(dma_req_rd)
    );

    dma_master_engine #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_dma_engine (
        .clk(clk), .rst_n(rst_n),
        .i_start(final_start),
        .i_base_addr(final_addr),
        .i_total_len(final_len),
        .o_done(dma_done),
        .i_fifo_rdata(muxed_crypto_data),
        .i_fifo_empty(muxed_crypto_empty),
        .o_fifo_ren(dma_req_rd),
        .m_axi_awaddr(dma_awaddr), .m_axi_awlen(dma_awlen),
        .m_axi_awsize(dma_awsize), .m_axi_awburst(dma_awburst),
        .m_axi_awcache(dma_awcache), .m_axi_awprot(dma_awprot),
        .m_axi_awvalid(dma_awvalid), .m_axi_awready(m_axis_awready),
        .m_axi_wdata(dma_wdata), .m_axi_wstrb(dma_wstrb),
        .m_axi_wlast(dma_wlast), .m_axi_wvalid(dma_wvalid),
        .m_axi_wready(m_axis_wready), .m_axi_wresp(2'b00), .m_axi_blast(1'b0),
        .m_axi_bvalid(m_axis_bvalid), .m_axi_bready(m_axis_bready),
        .m_axi_araddr(), .m_axi_arlen(), .m_axi_arsize(),
        .m_axi_arburst(), .m_axi_arvalid(), .m_axi_arready(1'b0),
        .m_axi_rdata(32'b0), .m_axi_rresp(2'b00), .m_axi_rlast(1'b0),
        .m_axi_rvalid(1'b0), .m_axi_rready()
    );

endmodule
