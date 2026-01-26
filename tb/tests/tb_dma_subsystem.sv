`timescale 1ns / 1ps

/**
 * 模块名称: tb_dma_subsystem
 * 描述: 
 * DMA 子系统的系统级验证平台。
 * [功能 1] 模拟 CPU (BFM) 配置寄存器。
 * [功能 2] 模拟 DDR (Dummy Slave) 响应 DMA 的写请求，防止总线死锁。
 * [功能 3] 自动检查 AXI4 协议合规性 (Assertion)。
 */

import pkg_axi_stream::*;

module tb_dma_subsystem;

    // 参数定义
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;

    // 时钟与复位
    logic clk;
    logic rst_n;

    // ==========================================
    // 1. AXI-Lite 信号 (模拟 CPU 连接)
    // ==========================================
    logic [ADDR_WIDTH-1:0]  s_axil_awaddr;
    logic                   s_axil_awvalid;
    logic                   s_axil_awready;
    logic [DATA_WIDTH-1:0]  s_axil_wdata;
    logic [3:0]             s_axil_wstrb; // [新增]
    logic                   s_axil_wvalid;
    logic                   s_axil_wready;
    logic [1:0]             s_axil_bresp;
    logic                   s_axil_bvalid;
    logic                   s_axil_bready;
    logic [ADDR_WIDTH-1:0]  s_axil_araddr;
    logic                   s_axil_arvalid;
    logic                   s_axil_arready;
    logic [DATA_WIDTH-1:0]  s_axil_rdata;
    logic                   s_axil_rvalid;
    logic                   s_axil_rready;

    // ==========================================
    // 2. AXI4 Master 信号 (模拟 DDR 连接)
    // ==========================================
    // 必须声明所有新增加的端口，否则实例化会报错
    logic [ADDR_WIDTH-1:0]  m_axi_awaddr;
    logic [7:0]             m_axi_awlen;
    logic [2:0]             m_axi_awsize;  // [监控对象]
    logic [1:0]             m_axi_awburst; // [监控对象]
    logic [3:0]             m_axi_awcache;
    logic [2:0]             m_axi_awprot;
    logic                   m_axi_awvalid;
    logic                   m_axi_awready; // 需 TB 驱动
    
    logic [DATA_WIDTH-1:0]  m_axi_wdata;
    logic [DATA_WIDTH/8-1:0] m_axi_wstrb;
    logic                   m_axi_wlast;
    logic                   m_axi_wvalid;
    logic                   m_axi_wready;  // 需 TB 驱动
    
    logic [1:0]             m_axi_bresp;   // 需 TB 驱动
    logic                   m_axi_bvalid;  // 需 TB 驱动
    logic                   m_axi_bready;

    // 读通道 (Dummy)
    logic [ADDR_WIDTH-1:0]  m_axi_araddr;
    logic [7:0]             m_axi_arlen;
    logic [2:0]             m_axi_arsize;
    logic [1:0]             m_axi_arburst;
    logic                   m_axi_arvalid;
    logic                   m_axi_arready;
    logic [DATA_WIDTH-1:0]  m_axi_rdata;
    logic [1:0]             m_axi_rresp;
    logic                   m_axi_rlast;
    logic                   m_axi_rvalid;
    logic                   m_axi_rready;

    // ==========================================
    // 3. DUT 实例化 (Device Under Test)
    // ==========================================
    dma_subsystem #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI-Lite Slave
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
        
        // AXI4 Master (连接所有新端口)
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awcache  (m_axi_awcache),
        .m_axi_awprot   (m_axi_awprot),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),
        
        // 读通道
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready)
    );

    // ==========================================
    // 4. 时钟生成 (100MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ==========================================
    // 5. 模拟 DDR 从机响应 (Dummy Slave BFM)
    // [重要] 如果没有这段，DUT 会一直等待 Ready 信号
    // ==========================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awready <= 0;
            m_axi_wready  <= 0;
            m_axi_bvalid  <= 0;
            m_axi_bresp   <= 0;
        end else begin
            // 1. 地址握手：如果 DUT 发来 valid，我们立刻回 ready (100% 接受率)
            if (m_axi_awvalid && !m_axi_awready)
                m_axi_awready <= 1;
            else
                m_axi_awready <= 0;

            // 2. 数据握手：同上
            if (m_axi_wvalid && !m_axi_wready)
                m_axi_wready <= 1;
            else
                m_axi_wready <= 0;

            // 3. 写响应：简单模拟，当收到 Last 且握手完成时，返回 BVALID
            if (m_axi_wlast && m_axi_wvalid && m_axi_wready) begin
                m_axi_bvalid <= 1;
                m_axi_bresp  <= 2'b00; // OKAY
            end else if (m_axi_bready && m_axi_bvalid) begin
                m_axi_bvalid <= 0;
            end
        end
    end
    
    // 读通道响应 (Dummy)
    assign m_axi_arready = 1'b0; // 不处理读
    assign m_axi_rvalid  = 1'b0;

    // ==========================================
    // 6. BFM Tasks (Bus Functional Model)
    // ==========================================
    task cpu_write_reg(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axil_awaddr  <= addr;
            s_axil_awvalid <= 1;
            s_axil_wdata   <= data;
            s_axil_wstrb   <= 4'hF; // [Fix] 默认全字节有效
            s_axil_wvalid  <= 1;
            s_axil_bready  <= 1;
            
            // 等待地址握手
            wait(s_axil_awready);
            @(posedge clk);
            s_axil_awvalid <= 0;
            
            // 等待数据握手
            wait(s_axil_wready);
            @(posedge clk);
            s_axil_wvalid <= 0;
            s_axil_wstrb  <= 0;

            // 等待写响应
            wait(s_axil_bvalid);
            @(posedge clk);
            s_axil_bready <= 0;
            $display("[BFM] Write Addr: %h, Data: %h", addr, data);
        end
    endtask

    // ==========================================
    // 7. 测试主流程 (Main Test)
    // ==========================================
    initial begin
        // 初始化信号
        rst_n = 0;
        s_axil_awaddr = 0; s_axil_awvalid = 0;
        s_axil_wdata = 0;  s_axil_wvalid = 0; s_axil_wstrb = 0;
        s_axil_bready = 0;
        
        // 复位释放
        #100;
        rst_n = 1;
        #100;

        $display("-------------------------------------------");
        $display("[TEST START] System Integration Test");
        $display("-------------------------------------------");

        // 步骤 1: 配置 DMA 基地址 (0x08)
        cpu_write_reg(32'h08, 32'h1000_0000); // 正常对齐地址

        // 步骤 2: 配置 DMA 长度 (0x0C)
        cpu_write_reg(32'h0C, 32'd64); // 64字节

        // 步骤 3: 启动 DMA (0x00 -> 0x01)
        cpu_write_reg(32'h00, 32'h0000_0001);

        // 步骤 4: 监控波形
        // 此时应该看到 m_axi_awvalid 拉高，且 awburst=01
        
        // 步骤 5: Task 1.3 非对齐测试 (Poison Injection)
        #200;
        $display("[TEST] Injecting Unaligned Address (Task 1.3)...");
        cpu_write_reg(32'h08, 32'h1000_0007); // 毒药地址
        cpu_write_reg(32'h00, 32'h0000_0001); // 尝试启动

        #500;
        $stop;
    end

    // ==========================================
    // 8. 协议合规性自动检查 (Assertions)
    // ==========================================
    always @(posedge clk) begin
        if (m_axi_awvalid) begin
            // 检查 1: Burst 必须是 INCR (01)
            if (m_axi_awburst !== 2'b01) 
                $error("[Protocol Fail] AWBURST must be INCR(01), got %b", m_axi_awburst);
            
            // 检查 2: Size 必须是 32-bit (010)
            if (m_axi_awsize !== 3'b010) 
                $error("[Protocol Fail] AWSIZE must be 32-bit(010), got %b", m_axi_awsize);
        end
    end

endmodule