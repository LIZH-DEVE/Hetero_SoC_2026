`timescale 1ns / 1ps

/**
 * 模块名称: dma_subsystem
 * 所属阶段: Phase 1 - 系统集成与协议合规 (System Integration)
 * 描述: 
 * 连接控制平面 (CSR AXI-Lite) 与数据平面 (DMA Engine AXI4-Full) 的顶层封装。
 * [核心价值] 在此层强制实施 AXI4 协议约束，确保 DDR 控制器 (MIG/PS) 能正确识别传输模式。
 */

// [Source: Project Structure] 引用全局参数包，统一常量定义
//import pkg_axi_stream::*;

module dma_subsystem #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // =========================================================================
    // 1. AXI-Lite 从机接口 (Control Plane -> Zynq PS)
    // [Source: AMBA AXI-Lite Spec] CPU 通过此接口配置寄存器，不涉及突发传输。
    // =========================================================================
    input  logic [ADDR_WIDTH-1:0]  s_axil_awaddr,
    input  logic                   s_axil_awvalid,
    output logic                   s_axil_awready,
    input  logic [DATA_WIDTH-1:0]  s_axil_wdata,
    
    // [Source: AXI-Lite Spec] 关键修正：写选通信号 (Write Strobe)
    // 必须透传 CPU 的字节掩码。如果强行接 4'hF，CPU 的字节写指令 (如 char赋值) 将破坏相邻数据。
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

    // =========================================================================
    // 2. AXI4 主机接口 (Data Plane -> DDR Memory)
    // [Source: AMBA AXI4 Spec] 高带宽 DMA 写通道。此处增加了多个静态信号以满足 DDR 控制器要求。
    // =========================================================================
    // --- 写地址通道 (Write Address) ---
    output logic [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output logic [7:0]             m_axi_awlen,
    
    // [Source: AXI4 Spec] 传输大小 (Burst Size)。010=4字节，必须显式驱动，否则默认为0(1字节)导致效率暴跌。
    output logic [2:0]             m_axi_awsize,  
    
    // [Source: AXI4 Spec] 突发类型 (Burst Type)。01=INCR(递增)。严禁为00(FIXED)，否则会覆盖同一地址！
    output logic [1:0]             m_axi_awburst, 
    
    // [Source: Zynq TRM] 缓存属性 (Cache Type)。0011=Normal Non-cacheable Bufferable，适合 DMA。
    output logic [3:0]             m_axi_awcache, 
    
    // [Source: AXI4 Spec] 保护级别 (Protection)。000=无特权安全数据访问。
    output logic [2:0]             m_axi_awprot,  
    
    output logic                   m_axi_awvalid,
    input  logic                   m_axi_awready,
    
    // --- 写数据通道 (Write Data) ---
    output logic [DATA_WIDTH-1:0]  m_axi_wdata,
    
    // [Source: AXI4 Spec] 写数据选通。防止部分字节无效。DMA搬运通常全开。
    output logic [DATA_WIDTH/8-1:0] m_axi_wstrb,  
    
    output logic                   m_axi_wlast,
    output logic                   m_axi_wvalid,
    input  logic                   m_axi_wready,
    
    // --- 写响应通道 (Write Response) ---
    input  logic [1:0]             m_axi_bresp,
    input  logic                   m_axi_bvalid,
    output logic                   m_axi_bready,
    
    // --- 读通道 (Phase 1 暂未使用，需做安全封堵) ---
    output logic [ADDR_WIDTH-1:0]  m_axi_araddr,
    output logic [7:0]             m_axi_arlen,   
    output logic [2:0]             m_axi_arsize,
    output logic [1:0]             m_axi_arburst,
    output logic                   m_axi_arvalid,
    input  logic                   m_axi_arready, // 需要接收 DDR 的 Ready 信号
    input  logic [DATA_WIDTH-1:0]  m_axi_rdata,   // DDR 返回的数据
    input  logic [1:0]             m_axi_rresp,   
    input  logic                   m_axi_rlast,
    input  logic                   m_axi_rvalid,
    output logic                   m_axi_rready
);

    // ========================================================
    // 内部互联信号 (子系统内部连线)
    // ========================================================
    logic        dma_start;     // CSR -> Engine: 启动脉冲
    logic [31:0] dma_base_addr; // CSR -> Engine: 源地址
    logic [31:0] dma_len;       // CSR -> Engine: 长度
    logic        dma_done;      // Engine -> CSR: 完成标志
    logic        dma_error;     // Engine -> CSR: 错误标志

    // ========================================================
    // AXI4 静态信号驱动 (协议合规性强制逻辑)
    // ========================================================
    assign m_axi_awsize  = 3'b010; // 32-bit (4 Bytes)
    assign m_axi_awburst = 2'b01;  // INCR mode
    assign m_axi_awcache = 4'b0011;// Normal Non-cacheable
    assign m_axi_awprot  = 3'b000; // Secure Data
    
    // [Source: Design Decision] 假设 DMA 搬运总是 32-bit 对齐的完整字，所有字节有效
    assign m_axi_wstrb   = {(DATA_WIDTH/8){1'b1}}; 

    // ========================================================
    // 读通道安全封堵 (Tie-off)
    // [Source: FPGA Design Rule] 显式将未使用的输出置为 0，防止输出 X 态或高阻态导致总线挂死。
    // ========================================================
    assign m_axi_araddr  = '0;
    assign m_axi_arlen   = '0;
    assign m_axi_arsize  = 3'b0;
    assign m_axi_arburst = 2'b0;
    assign m_axi_arvalid = 1'b0;
    
    // [Source: Safety] 显式拒绝接收任何读数据
    assign m_axi_rready  = 1'b0; 

    // ========================================================
    // 3. 实例化控制平面 (CSR)
    // ========================================================
    axil_csr #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) i_csr (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI-Lite 信号透传
        .s_axil_awaddr  (s_axil_awaddr),
        .s_axil_awvalid (s_axil_awvalid),
        .s_axil_awready (s_axil_awready),
        .s_axil_wdata   (s_axil_wdata),
        .s_axil_wstrb   (s_axil_wstrb), // [关键连接] 透传 WSTRB
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

        // 内部控制接口
        .o_start        (dma_start),
        .o_base_addr    (dma_base_addr),
        .o_len          (dma_len),
        .i_done         (dma_done),
        .i_error        (dma_error)
    );

    // ========================================================
    // 4. 实例化数据平面 (DMA Engine)
    // ========================================================
    dma_master_engine #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) i_dma (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // 软硬握手接口
        .i_start        (dma_start),
        .i_base_addr    (dma_base_addr),
        .i_total_len    (dma_len),
        .o_done         (dma_done),
        .o_error        (dma_error),
        
        // AXI4 写通道 (只连接动态信号，静态信号由顶层驱动)
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
        
        // [Source: Optimization] 引擎内部未使用的信号留空，由顶层统一管理
        .m_axi_awsize   (), 
        .m_axi_awburst  (), 
        .m_axi_wstrb    (), 
        .m_axi_bresp    (m_axi_bresp) 
    );

// ========================================================
    // 5. Crypto Core 实例化 (无参版 - 强制连接)
    // ========================================================
    
    // 信号定义
    logic         crypto_s1_valid;
    logic [127:0] crypto_s1_data;
    logic [127:0] crypto_key;
    logic [127:0] crypto_iv;
    logic [1:0]   crypto_op;
    logic         crypto_mode;
    logic         crypto_s1_ready;
    logic         crypto_s2_valid;
    logic [127:0] crypto_s2_data;
    logic         crypto_s2_ready;

    // 默认赋值
    assign crypto_s1_valid = 1'b0;
    assign crypto_s1_data  = '0;
    assign crypto_key      = '0;
    assign crypto_iv       = '0;
    assign crypto_op       = '0;
    assign crypto_mode     = 1'b0;
    assign crypto_s2_ready = 1'b1;

    // 实例化 (注意：我删掉了 #(.DATA_WIDTH(128)) )
    crypto_core u_crypto_core (
        .clk            (clk),
        .rst_n          (rst_n),
        .s1_valid       (crypto_s1_valid),
        .s1_data        (crypto_s1_data),
        .s1_key         (crypto_key),
        .s1_iv          (crypto_iv),
        .s1_op          (crypto_op),
        .s1_mode        (crypto_mode),
        .s1_ready       (crypto_s1_ready),
        .s2_valid       (crypto_s2_valid),
        .s2_data        (crypto_s2_data),
        .s2_ready       (crypto_s2_ready),
        .error_code     ()
    );

endmodule