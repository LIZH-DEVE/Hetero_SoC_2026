`timescale 1ns / 1ps

/**
 * 模块名称: dma_subsystem
 * 版本: Day08_Final_Fix (Support Error Injection)
 * 描述: 
 * 集成 CSR -> Crypto -> FIFO -> Gearbox -> PBM -> DMA。
 * [Fix] 增加了 pbm_error_inject 信号，方便仿真注入错误。
 */

module dma_subsystem #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // AXI-Lite CSR Interface
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
    output logic                   s_axil_rvalid,
    input  logic                   s_axil_rready,

    // AXI4 Master Interface
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
    
    // Read Channel Tie-off
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
    output logic                   m_axi_rready
);

    // ==========================================================
    // 内部信号定义
    // ==========================================================
    logic        dma_start;     
    logic [31:0] dma_base_addr; 
    logic [31:0] dma_len;       
    logic        dma_done;             
    
    logic        w_algo_sel;    
    logic        w_enc_dec;     
    logic [127:0] w_crypto_key; 
    
    logic        csr_hw_init;
    logic        csr_cache_flush;

    // Data Path Signals
    logic [127:0] crypto_result_data; 
    logic         crypto_data_valid;  
    logic [127:0] fifo_rdata;         
    logic         fifo_empty;         
    logic         fifo_ren;           
    logic         fifo_full; 
    
    logic [31:0]  gearbox_dout;
    logic         gearbox_valid;
    logic         gearbox_ready;
    logic         gearbox_last;    

    // PBM Signals
    logic [31:0]  pbm_rdata;
    logic         pbm_empty;
    logic         pbm_ren;
    logic         pbm_valid_dummy;

    // [Day 8 Fix] 专门用于注入错误的信号
    // 正常模式下为 0，TB 可以 force 它为 1 来模拟错误
    logic         pbm_error_inject;
    assign        pbm_error_inject = 1'b0;

    // ==========================================================
    // AXI Static Logic
    // ==========================================================
    assign m_axi_awsize  = 3'b010; 
    assign m_axi_awburst = 2'b01;  
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000; 
    assign m_axi_wstrb   = {(DATA_WIDTH/8){1'b1}}; 

    assign m_axi_araddr  = '0; assign m_axi_arlen   = '0; assign m_axi_arsize  = 3'b0;
    assign m_axi_arburst = 2'b0; assign m_axi_arvalid = 1'b0; assign m_axi_rready  = 1'b0; 

    // ==========================================================
    // 模块实例化
    // ==========================================================
    
    axil_csr #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) u_axil_csr (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        
        .o_start(dma_start), .o_base_addr(dma_base_addr), .o_len(dma_len),
        .o_algo_sel(w_algo_sel), .o_enc_dec(w_enc_dec), .o_key(w_crypto_key), 
        .i_done(dma_done), .i_error(1'b0), 
        .o_hw_init(csr_hw_init), .o_cache_flush(csr_cache_flush), .i_acl_cnt(32'd0)
    );

    crypto_engine u_crypto_engine (
        .clk(clk), .rst_n(rst_n),
        .algo_sel(w_algo_sel), .key(w_crypto_key), .start(dma_start),
        .done(crypto_data_valid), .busy(),
        .din(128'd0), .dout(crypto_result_data) 
    );

    async_fifo #(.DATA_WIDTH(128), .ADDR_WIDTH(4)) u_cdc_fifo (
        .wclk(clk), .wrst_n(rst_n), .wen(crypto_data_valid), .wdata(crypto_result_data), .wfull(fifo_full),
        .rclk(clk), .rrst_n(rst_n), .ren(fifo_ren), .rdata(fifo_rdata), .rempty(fifo_empty)
    );

    gearbox_128_to_32 u_gearbox (
        .clk(clk), .rst_n(rst_n),
        .din(fifo_rdata), .din_valid(!fifo_empty), .din_ready(fifo_ren), 
        .dout(gearbox_dout), .dout_valid(gearbox_valid), .dout_last(gearbox_last), .dout_ready(gearbox_ready)
    );

    // [Day 8 Integrated PBM]
    pbm_controller #(.PBM_ADDR_WIDTH(14), .DATA_WIDTH(32)) u_pbm (
        .clk(clk), .rst_n(rst_n),
        .i_wr_valid (gearbox_valid),
        .i_wr_data  (gearbox_dout),
        .i_wr_last  (gearbox_last),
        .i_wr_error (pbm_error_inject), // [Fix] 连接到内部信号，便于 Force
        .o_wr_ready (gearbox_ready), 
        .i_rd_en    (pbm_ren),
        .o_rd_data  (pbm_rdata),
        .o_rd_valid (pbm_valid_dummy),
        .o_rd_empty (pbm_empty),
        .o_buffer_usage()
    );

    dma_master_engine i_dma (
        .clk(clk), .rst_n(rst_n),
        .i_start(dma_start), .i_base_addr(dma_base_addr), .i_total_len(dma_len), .o_done(dma_done),
        .i_fifo_rdata(pbm_rdata), .i_fifo_empty(pbm_empty), .o_fifo_ren(pbm_ren),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), 
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wlast(m_axi_wlast), 
        .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        .m_axi_bresp(m_axi_bresp)
    );

endmodule