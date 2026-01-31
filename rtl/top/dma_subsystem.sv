`timescale 1ns / 1ps

/**
 * 模块名称: dma_subsystem
 * 版本: Day 10 Ultimate (Swap & TX Integrated)
 * 描述: 
 * 1. 集成 RX Parser (带信息提取)
 * 2. 集成 TX Stack (带动态目标地址)
 * 3. 实现 Info Swap (自动回显逻辑)
 * 4. 实现 PBM 读仲裁 (TX 优先级高于 DMA)
 */

module dma_subsystem #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // --- CSR Interface (AXI-Lite) ---
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

    // --- DMA Interface (AXI4 Master) ---
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

    // --- RX Interface (MAC -> FPGA) ---
    input  logic [31:0]            rx_axis_tdata,
    input  logic                   rx_axis_tvalid,
    input  logic                   rx_axis_tlast,
    input  logic                   rx_axis_tuser,
    output logic                   rx_axis_tready,

    // --- TX Interface (FPGA -> MAC) ---
    output logic [31:0]            tx_axis_tdata,
    output logic                   tx_axis_tvalid,
    output logic                   tx_axis_tlast,
    output logic [3:0]             tx_axis_tkeep,
    input  logic                   tx_axis_tready,

    // --- Debug / Display Interface ---
    output logic [3:0]             o_seven_seg_an,
    output logic [7:0]             o_seven_seg_seg
);

    // =========================================================
    // 1. 内部信号定义
    // =========================================================
    
    // CSR Control Signals
    logic        dma_start_csr;
    logic [31:0] op_base_addr; 
    logic [31:0] op_len;       
    logic        op_done_dma;
    logic        op_done_tx;
    logic        w_algo_sel, w_enc_dec;
    logic [127:0] w_crypto_key;

    // RX Path
    logic [31:0] rx_pbm_wdata;
    logic        rx_pbm_wvalid;
    logic        rx_pbm_wlast;
    logic        rx_pbm_werror;
    logic        rx_pbm_ready;
    logic [15:0] rx_meta_len;
    logic        rx_meta_valid;

    // [Day 10 Feature] Info Swap Signals (自动回显)
    logic [47:0] rec_src_mac;
    logic [31:0] rec_src_ip;
    logic [15:0] rec_src_port;
    logic        rec_valid;

    logic [47:0] target_mac_reg;
    logic [31:0] target_ip_reg;
    logic [15:0] target_port_reg;

    // PBM Signals (Arbitrated)
    logic [31:0] pbm_rdata;
    logic        pbm_empty;
    logic        pbm_ren_final;    // 仲裁后的读使能
    
    // DMA Specific
    logic        dma_ren;       // DMA 请求读
    
    // TX Stack Specific
    logic        tx_ren;        // TX 请求读
    logic        tx_busy;       // TX 忙信号

    // AXI Static Logic (Read Channel Tie-off)
    assign m_axi_araddr = '0; assign m_axi_arlen = '0; assign m_axi_arsize = 3'b0;
    assign m_axi_arburst = 2'b0; assign m_axi_arvalid = 1'b0; assign m_axi_rready = 1'b0; 

    // =========================================================
    // 2. 交换逻辑 (Info Swap Logic)
    // =========================================================
    // 当 RX 收到合法包时，锁存源地址，作为下一次发送的目标地址
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            target_mac_reg  <= 48'hFF_FF_FF_FF_FF_FF; // 默认广播
            target_ip_reg   <= 32'hC0_A8_01_64;      // 默认 192.168.1.100
            target_port_reg <= 16'd5678;             // 默认端口
        end else if (rec_valid) begin
            target_mac_reg  <= rec_src_mac;
            target_ip_reg   <= rec_src_ip;
            target_port_reg <= rec_src_port;
        end
    end

    // =========================================================
    // 3. 核心模块实例化
    // =========================================================

    // --- 3.1 CSR ---
    axil_csr #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_axil_csr (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        
        .o_start(dma_start_csr),
        .o_base_addr(op_base_addr), 
        .o_len(op_len),
        .i_done(op_done_dma || op_done_tx), 
        .i_error(1'b0), 
        .o_algo_sel(w_algo_sel), .o_enc_dec(w_enc_dec), .o_key(w_crypto_key),
        .o_hw_init(), .o_cache_flush(), .i_acl_cnt(32'd0)
    );

    // --- 3.2 RX Parser (带信息提取) ---
    rx_parser u_rx_parser (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(rx_axis_tdata), .s_axis_tvalid(rx_axis_tvalid), 
        .s_axis_tlast(rx_axis_tlast), .s_axis_tuser(rx_axis_tuser), .s_axis_tready(rx_axis_tready),
        .o_pbm_wdata(rx_pbm_wdata), .o_pbm_wvalid(rx_pbm_wvalid), .o_pbm_wlast(rx_pbm_wlast), 
        .o_pbm_werror(rx_pbm_werror), .i_pbm_ready(rx_pbm_ready),
        .o_meta_data(rx_meta_len), .o_meta_valid(rx_meta_valid), .i_meta_ready(1'b1),
        
        // Info Swap Connections
        .o_rec_src_mac(rec_src_mac), .o_rec_src_ip(rec_src_ip), 
        .o_rec_src_port(rec_src_port), .o_rec_valid(rec_valid),
        
        .o_arp_data(), .o_arp_valid()
    );

    // --- 3.3 PBM Controller ---
    // 仲裁逻辑: TX 优先级高于 DMA
    assign pbm_ren_final = (tx_busy) ? tx_ren : dma_ren;

    pbm_controller #(.PBM_ADDR_WIDTH(14), .DATA_WIDTH(32)) u_pbm (
        .clk(clk), .rst_n(rst_n),
        .i_wr_valid (rx_pbm_wvalid), .i_wr_data (rx_pbm_wdata), 
        .i_wr_last (rx_pbm_wlast), .i_wr_error (rx_pbm_werror), 
        .o_wr_ready (rx_pbm_ready), 
        // Read Port (From Arbiter)
        .i_rd_en (pbm_ren_final), 
        .o_rd_data (pbm_rdata),
        .o_rd_valid (pbm_rvalid), .o_rd_empty (pbm_empty),
        .o_buffer_usage(pbm_usage), .o_rollback_active(pbm_rollback)
    );

    // --- 3.4 DMA Engine ---
    dma_master_engine i_dma (
        .clk(clk), .rst_n(rst_n),
        // 只有当 CSR 启动且不需要 TX 时，才启动 DMA
        .i_start(dma_start_csr && !tx_busy), // 简单互斥
        .i_base_addr(op_base_addr), .i_total_len(op_len), .o_done(op_done_dma),
        
        // PBM Interface
        .i_fifo_rdata(pbm_rdata), 
        .i_fifo_empty(pbm_empty), 
        .o_fifo_ren(dma_ren),

        // AXI Master
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awcache(m_axi_awcache), .m_axi_awprot(m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast), 
        .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready), .m_axi_bresp(m_axi_bresp),
        // Read unused
        .m_axi_araddr(), .m_axi_arlen(), .m_axi_arburst(), .m_axi_arvalid(), .m_axi_arready(1'b1),
        .m_axi_rdata(32'd0), .m_axi_rvalid(1'b0), .m_axi_rlast(1'b0), .m_axi_rresp(2'b00), .m_axi_rready()
    );

    // --- 3.5 TX Stack ---
    tx_stack u_tx_stack (
        .clk           (clk),
        .rst_n         (rst_n),
        
        // Control: 复用 CSR Start (Debug Mode)
        .i_tx_start    (dma_start_csr), 
        .i_payload_len (op_len[15:0]),
        
        // Info Swap Inputs
        .i_dst_mac     (target_mac_reg),
        .i_dst_ip      (target_ip_reg),
        .i_dst_port    (target_port_reg),
        
        .o_tx_done     (op_done_tx),
        .o_tx_busy     (tx_busy),
        
        // PBM Interface
        .o_pbm_addr    (), 
        .o_pbm_ren     (tx_ren),
        .i_pbm_rdata   (pbm_rdata),
        
        // AXIS Output
        .m_axis_tdata  (tx_axis_tdata),
        .m_axis_tvalid (tx_axis_tvalid),
        .m_axis_tlast  (tx_axis_tlast),
        .m_axis_tkeep  (tx_axis_tkeep),
        .m_axis_tready (tx_axis_tready)
    );

    // --- 3.6 Display Driver ---
    logic [15:0] display_len_latch;
    always_ff @(posedge clk) if(rx_meta_valid) display_len_latch <= rx_meta_len;
    
    seven_seg_driver u_disp (
        .clk(clk), .rst_n(rst_n), 
        .i_data(display_len_latch), 
        .i_dots(4'b0), 
        .o_an(o_seven_seg_an), 
        .o_seg(o_seven_seg_seg)
    );

    // Dummy ARP
    arp_responder u_arp (.clk(clk), .rst_n(rst_n), .i_arp_data(0), .i_arp_valid(0), .o_tx_data(), .o_tx_valid());

endmodule