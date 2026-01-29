`timescale 1ns / 1ps

/**
 * 模块名称: dma_subsystem
 * 版本: Day 09 Final - Network Protocol Aware
 * 描述: 
 * 1. [Task 8.1] 接入 AXI-Stream MAC 接口。
 * 2. [Task 8.2] 引入 RX Parser，支持 IP/UDP 长度校验与 PBM 回滚触发。
 * 3. [Task 8.2] 引入 Meta FIFO，管理包元数据（描述符）。
 * 4. [Task 8.3] 预留 ARP Responder 接口。
 */

module dma_subsystem #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // --- AXI-Lite CSR Interface (Control) ---
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

    // --- AXI4 Master Interface (DMA Data to DDR) ---
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
    
    // AXI4 Read Channel (Tie-off)
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

    // --- [Task 8.1] RX Interface (From MAC IP) ---
    input  logic [31:0]            rx_axis_tdata,
    input  logic                   rx_axis_tvalid,
    input  logic                   rx_axis_tlast,
    input  logic                   rx_axis_tuser, // MAC Error flag (CRC etc.)
    output logic                   rx_axis_tready
);

    // ==========================================================
    // 内部信号定义
    // ==========================================================
    
    // CSR 控制信号
    logic        dma_start;     
    logic [31:0] dma_base_addr; 
    logic [31:0] dma_len;       
    logic        dma_done;             
    logic        w_algo_sel, w_enc_dec;
    logic [127:0] w_crypto_key;
    logic        csr_hw_init, csr_cache_flush;

    // Parser <-> PBM (Payload)
    logic [31:0] parser_to_pbm_data;
    logic        parser_to_pbm_valid;
    logic        parser_to_pbm_last;
    logic        parser_to_pbm_error; // 核心：触发 PBM 回滚
    logic        pbm_wr_ready;

    // Parser <-> Meta FIFO (Descriptors)
    logic [15:0] parser_meta_data;
    logic        parser_meta_valid;
    logic        meta_fifo_full;
    logic        meta_fifo_empty;
    logic [15:0] current_meta;

    // PBM <-> DMA
    logic [31:0] pbm_rdata;
    logic        pbm_empty;
    logic        pbm_ren;

    // ARP 预留信号
    logic [31:0] arp_data;
    logic        arp_valid;

    // ==========================================================
    // AXI 静态逻辑驱动
    // ==========================================================
    assign m_axi_awsize  = 3'b010; 
    assign m_axi_awburst = 2'b01;  
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000; 
    assign m_axi_wstrb   = 4'hF; 

    assign m_axi_araddr = '0; assign m_axi_arlen = '0; assign m_axi_arsize = 3'b0;
    assign m_axi_arburst = 2'b0; assign m_axi_arvalid = 1'b0; assign m_axi_rready = 1'b0; 

    // ==========================================================
    // 1. [Task 8.2] RX Parser (The "Brain")
    // ==========================================================
    rx_parser u_rx_parser (
        .clk             (clk),
        .rst_n           (rst_n),
        
        // From MAC (AXI-Stream)
        .s_axis_tdata    (rx_axis_tdata),
        .s_axis_tvalid   (rx_axis_tvalid),
        .s_axis_tlast    (rx_axis_tlast),
        .s_axis_tuser    (rx_axis_tuser),
        .s_axis_tready   (rx_axis_tready),
        
        // To PBM (Payload)
        .o_pbm_wdata     (parser_to_pbm_data),
        .o_pbm_wvalid    (parser_to_pbm_valid),
        .o_pbm_wlast     (parser_to_pbm_last),
        .o_pbm_werror    (parser_to_pbm_error), // 连到 PBM 回滚端口
        .i_pbm_ready     (pbm_wr_ready),

        // To Meta FIFO (Descriptors)
        .o_meta_data     (parser_meta_data),
        .o_meta_valid    (parser_meta_valid),
        .i_meta_ready    (!meta_fifo_full),

        // To ARP Responder
        .o_arp_data      (arp_data),
        .o_arp_valid     (arp_valid)
    );

    // ==========================================================
    // 2. [Task 8.2 Patch] Meta FIFO (描述符管理)
    // ==========================================================
    async_fifo #(
        .DATA_WIDTH(16), 
        .ADDR_WIDTH(4)
    ) u_meta_fifo (
        .wclk   (clk),
        .wrst_n (rst_n),
        .wen    (parser_meta_valid),
        .wdata  (parser_meta_data),
        .wfull  (meta_fifo_full),
        
        .rclk   (clk),
        .rrst_n (rst_n),
        .ren    (dma_done), // DMA 每搬完一个包，弹出一个元数据
        .rdata  (current_meta),
        .rempty (meta_empty)
    );

    // ==========================================================
    // 3. [Task 8.3] ARP Responder (预留)
    // ==========================================================
    arp_responder u_arp_resp (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_arp_data (arp_data),
        .i_arp_valid(arp_valid),
        .o_tx_data  (), // 暂不回连
        .o_tx_valid ()
    );

    // ==========================================================
    // 4. [Day 08] PBM Controller (存储核心)
    // ==========================================================
    pbm_controller #(
        .PBM_ADDR_WIDTH(14), 
        .DATA_WIDTH(32)
    ) u_pbm (
        .clk        (clk),
        .rst_n      (rst_n),
        
        // Write Side (From Parser)
        .i_wr_valid (parser_to_pbm_valid),
        .i_wr_data  (parser_to_pbm_data),
        .i_wr_last  (parser_to_pbm_last),
        .i_wr_error (parser_to_pbm_error), // [重要] Parser 发现长度不符时触发
        .o_wr_ready (pbm_wr_ready), 
        
        // Read Side (To DMA)
        .i_rd_en    (pbm_ren),
        .o_rd_data  (pbm_rdata),
        .o_rd_valid (),
        .o_rd_empty (pbm_empty),
        .o_buffer_usage()
    );

    // ==========================================================
    // 5. [Day 07] DMA Engine (数据搬运)
    // ==========================================================
    dma_master_engine i_dma (
        .clk            (clk),
        .rst_n          (rst_n),
        .i_start        (dma_start),
        .i_base_addr    (dma_base_addr),
        .i_total_len    (dma_len),
        .o_done         (dma_done),
        
        // Source: PBM
        .i_fifo_rdata   (pbm_rdata),
        .i_fifo_empty   (pbm_empty),
        .o_fifo_ren     (pbm_ren),

        // AXI Master Ports
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),
        .m_axi_bresp    (m_axi_bresp)
    );

    // ==========================================================
    // 6. [Day 05] CSR (控制平面)
    // ==========================================================
    axil_csr u_axil_csr (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axil_awaddr  (s_axil_awaddr),
        .s_axil_awvalid (s_axil_awvalid),
        .s_axil_awready (s_axil_awready),
        .s_axil_wdata   (s_axil_wdata),
        .s_axil_wstrb   (s_axil_wstrb),
        .s_axil_wvalid  (s_axil_wvalid),
        .s_axil_wready  (s_axil_wready),
        .s_axil_bresp   (s_axil_bresp),
        .s_axil_bvalid  (s_axil_bvalid),
        .s_axil_bready  (s_axil_bready),
        .s_axil_araddr  (s_axil_araddr),
        .s_axil_arvalid (s_axil_arvalid),
        .s_axil_arready (s_axil_arready),
        .s_axil_rdata   (s_axil_rdata),
        .s_axil_rvalid  (s_axil_rvalid),
        .s_axil_rready  (s_axil_rready),
        
        .o_start        (dma_start),
        .o_base_addr    (dma_base_addr),
        .o_len          (dma_len),
        .o_algo_sel     (w_algo_sel),
        .o_enc_dec      (w_enc_dec),
        .o_key          (w_crypto_key),
        .i_done         (dma_done),
        .i_error        (1'b0),
        .o_hw_init      (csr_hw_init),
        .o_cache_flush  (csr_cache_flush),
        .i_acl_cnt      (32'd0)
    );

endmodule