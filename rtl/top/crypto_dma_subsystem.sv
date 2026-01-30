`timescale 1ns / 1ps

module crypto_dma_subsystem (
    input  logic        clk,
    input  logic        rst_n,

    // --- CPU AXI-Lite 接口 ---
    input  logic [31:0] s_axil_awaddr,
    input  logic        s_axil_awvalid,
    output logic        s_axil_awready,
    input  logic [31:0] s_axil_wdata,
    input  logic [3:0]  s_axil_wstrb,
    input  logic        s_axil_wvalid,
    output logic        s_axil_wready,
    output logic [1:0]  s_axil_bresp,   
    output logic        s_axil_bvalid,
    input  logic        s_axil_bready,
    input  logic [31:0] s_axil_araddr,
    input  logic        s_axil_arvalid,
    output logic        s_axil_arready,
    output logic [31:0] s_axil_rdata,
    output logic [1:0]  s_axil_rresp,   
    output logic        s_axil_rvalid,
    input  logic        s_axil_rready,

    // --- 数据输入路径 ---
    input  logic        rx_wr_valid,
    input  logic [31:0] rx_wr_data,
    input  logic        rx_wr_last,
    output logic        rx_wr_ready,

    // --- AXI4 Master 接口 (读描述符通道) ---
    output logic [31:0] m_axi_araddr,
    output logic [7:0]  m_axi_arlen,
    output logic [2:0]  m_axi_arsize,   
    output logic [1:0]  m_axi_arburst,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    input  logic [31:0] m_axi_rdata,
    input  logic        m_axi_rlast,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready,
    input  logic [1:0]  m_axi_rresp,

    // --- AXI4 Master 接口 (写回密文通道) ---
    output logic [31:0] m_axi_awaddr,
    output logic [7:0]  m_axi_awlen,
    output logic [2:0]  m_axi_awsize,   
    output logic [1:0]  m_axi_awburst,
    output logic [3:0]  m_axi_awcache, 
    output logic [2:0]  m_axi_awprot,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb, 
    output logic        m_axi_wlast,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready
);

    // =========================================================
    // 1. 内部信号定义 (修复点：确保所有Wire都定义了位宽)
    // =========================================================
    logic csr_start, fetcher_start, final_start;
    logic [31:0] csr_addr, fetcher_addr, final_addr;
    logic [31:0] csr_len, fetcher_len, final_len;
    logic csr_algo, fetcher_algo, final_algo;
    logic [31:0] ring_base, ring_size;
    logic [15:0] sw_tail, hw_head;
    logic dma_done, hw_init;
    logic [127:0] csr_key; 

    // PBM <-> Crypto 信号
    logic [31:0] pbm_data;
    logic        pbm_empty;
    logic        bridge_rd_pbm;
    
    // Crypto <-> DMA 信号 (关键修复：之前漏了定义，导致变成1-bit)
    logic [31:0] crypto_to_dma_data; 
    logic        crypto_to_dma_empty;
    logic        dma_req_rd;

    // =========================================================
    // 2. 模式选择 MUX
    // =========================================================
    assign final_start = (ring_size > 0) ? fetcher_start : csr_start;
    assign final_addr  = (ring_size > 0) ? fetcher_addr  : csr_addr;
    assign final_len   = (ring_size > 0) ? fetcher_len   : csr_len;
    assign final_algo  = (ring_size > 0) ? fetcher_algo  : csr_algo;

    // =========================================================
    // 3. 模块实例化
    // =========================================================

    // CSR
    axil_csr u_csr (
        .clk(clk), .rst_n(rst_n), .*, 
        .o_start(csr_start), .o_base_addr(csr_addr), .o_len(csr_len),
        .o_ring_base(ring_base), .o_ring_size(ring_size), 
        .o_sw_tail_ptr(sw_tail), .i_hw_head_ptr(hw_head),
        .i_done(dma_done), .i_error(1'b0), .o_algo_sel(csr_algo),
        .o_hw_init(hw_init), .o_key(csr_key),
        .o_cache_flush(), .i_acl_cnt(32'd0), .o_enc_dec()
    );

    // Fetcher
    dma_desc_fetcher u_fetcher (
        .clk(clk), .rst_n(rst_n),
        .i_ring_base(ring_base), .i_ring_size(ring_size),
        .i_sw_tail_ptr(sw_tail), .o_hw_head_ptr(hw_head),
        .o_dma_start(fetcher_start), .o_dma_addr(fetcher_addr), 
        .o_dma_len(fetcher_len), .o_dma_algo(fetcher_algo),
        .i_dma_done(dma_done),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), 
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rlast(m_axi_rlast), 
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready)
    );

    // PBM
    pbm_controller u_pbm (
        .clk(clk), .rst_n(rst_n),
        .i_wr_valid(rx_wr_valid), .i_wr_data(rx_wr_data),
        .i_wr_last(rx_wr_last), .i_wr_error(1'b0),
        .o_wr_ready(rx_wr_ready),
        .i_rd_en(bridge_rd_pbm), .o_rd_data(pbm_data),
        .o_rd_valid(), .o_rd_empty(pbm_empty), .o_buffer_usage()
    );

    // Crypto Bridge
    crypto_bridge_top u_crypto_bridge (
        .clk(clk), .rst_n(rst_n),
        .i_algo_sel(final_algo), 
        .i_key(csr_key),
        .o_system_ready(), 
        .i_pbm_data(pbm_data), .i_pbm_empty(pbm_empty),
        .o_pbm_rd_en(bridge_rd_pbm),
        .o_tx_data(crypto_to_dma_data),   // 连到 32-bit 信号
        .o_tx_empty(crypto_to_dma_empty), // 连到 1-bit 信号
        .i_tx_rd_en(dma_req_rd)
    );

    // DMA Engine
    dma_master_engine u_dma_engine (
        .clk(clk), .rst_n(rst_n),
        .i_start(final_start), 
        .i_base_addr(final_addr),
        .i_total_len(final_len),
        .o_done(dma_done),
        .i_fifo_rdata(crypto_to_dma_data),   // 连到 32-bit 信号
        .i_fifo_empty(crypto_to_dma_empty), // 连到 1-bit 信号
        .o_fifo_ren(dma_req_rd),
        
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awcache(m_axi_awcache), .m_axi_awprot(m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready), .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        
        .m_axi_arready(1'b0), .m_axi_rvalid(1'b0), .m_axi_rdata(32'b0),
        .m_axi_rlast(1'b0), .m_axi_rresp(2'b0)
    );

endmodule