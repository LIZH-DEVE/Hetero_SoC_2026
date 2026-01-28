`timescale 1ns / 1ps

/**
 * 模块名称: tb_dma_boundary
 * 版本: Patch 6 Verified Edition
 * 描述: 
 * 1. 模拟 AXI Slave (总是 Ready) 以防止状态机卡死。
 * 2. 专门验证 0x0FF0 跨页地址的拆包逻辑。
 * 3. 自动打印判定结果。
 */

module tb_dma_boundary();

    // ==========================================
    // 1. 信号定义
    // ==========================================
    logic        clk;
    logic        rst_n;
    
    // 控制接口
    logic        i_start;
    logic [31:0] i_base_addr;
    logic [31:0] i_total_len;
    logic        o_done;

    // AXI Master 接口 (我们需要监测这些)
    logic [31:0] m_axi_awaddr;
    logic [7:0]  m_axi_awlen;
    logic        m_axi_awvalid;
    logic        m_axi_awready; // 输入给 DUT
    logic [31:0] m_axi_wdata;
    logic        m_axi_wlast;
    logic        m_axi_wvalid;
    logic        m_axi_wready;  // 输入给 DUT
    logic        m_axi_bvalid;  // 输入给 DUT
    logic        m_axi_bready;
    logic [1:0]  m_axi_bresp;   // 输入给 DUT

    // 数据源接口 (模拟 FIFO)
    logic        i_fifo_empty;
    logic [31:0] i_fifo_rdata;
    logic        o_fifo_ren;

    // ==========================================
    // 2. DUT 实例化
    // ==========================================
    dma_master_engine u_dut (
        .clk(clk), 
        .rst_n(rst_n),
        
        // Control
        .i_start(i_start), 
        .i_base_addr(i_base_addr), 
        .i_total_len(i_total_len),
        .o_done(o_done),
        
        // AXI Write Address Channel
        .m_axi_awaddr(m_axi_awaddr), 
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awvalid(m_axi_awvalid), 
        .m_axi_awready(m_axi_awready),
        
        // AXI Write Data Channel
        .m_axi_wdata(m_axi_wdata), 
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid), 
        .m_axi_wready(m_axi_wready),
        
        // AXI Write Response Channel
        .m_axi_bvalid(m_axi_bvalid), 
        .m_axi_bready(m_axi_bready),
        .m_axi_bresp(m_axi_bresp),

        // FIFO Interface
        .i_fifo_empty(i_fifo_empty),
        .i_fifo_rdata(i_fifo_rdata),
        .o_fifo_ren(o_fifo_ren)
    );

    // ==========================================
    // 3. 激励与模拟逻辑
    // ==========================================
    
    // 时钟生成 (100MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // 模拟 FIFO 数据源 (总是满的，数据是累加数)
    assign i_fifo_empty = 0;
    assign i_fifo_rdata = 32'hDEAD_BEEF; // 假数据

    // 模拟 AXI Slave (DDR) 行为：总是极速响应
    // 如果不写这个，DMA 发出请求没人理，就会卡死！
    initial begin
        m_axi_awready = 0;
        m_axi_wready  = 0;
        m_axi_bvalid  = 0;
        m_axi_bresp   = 0;
    end

    // AXI 握手模拟
    always @(posedge clk) begin
        // 地址握手
        m_axi_awready <= 1'b1; // Always ready to accept address

        // 数据握手
        m_axi_wready  <= 1'b1; // Always ready to accept data

        // 写响应握手 (简单模拟：只要 Master 准备好收响应，我就给有效)
        if (m_axi_bready) 
            m_axi_bvalid <= 1'b1;
        else 
            m_axi_bvalid <= 1'b0;
    end

    // ==========================================
    // 4. 主测试流程 (Patch 6 验证)
    // ==========================================
    initial begin
        $display("\n========================================================");
        $display("   [Patch 6] DMA 4K Boundary Crossing Test");
        $display("========================================================");
        
        // 初始化
        rst_n = 0;
        i_start = 0;
        i_base_addr = 0;
        i_total_len = 0;
        
        #100 rst_n = 1; // 释放复位
        #20;

        // --- 核心测试用例 ---
        // 场景：从 0x0FF0 开始写 64 字节
        // 0x0FF0 到 0x1000 只有 16 字节 (4拍)
        // 剩下的 48 字节 (12拍) 必须放到下一个 Burst
        i_base_addr = 32'h0000_0FF0;
        i_total_len = 64; 

        $display("[TIME %t] Starting DMA Transaction...", $time);
        @(posedge clk);
        i_start = 1;
        @(posedge clk);
        i_start = 0;

        // --- 自动监测 Burst ---
        
        // 1. 等待第一个 Burst 地址发出
        wait(m_axi_awvalid && m_axi_awready);
        $display("[TIME %t] Burst 1 Issued:", $time);
        $display("   Addr: %h (Expected: 00000ff0)", m_axi_awaddr);
        $display("   Len : %d (Expected: 3 [16 bytes])", m_axi_awlen);

        // 判定 Burst 1
        if (m_axi_awaddr == 32'h0000_0FF0 && m_axi_awlen == 8'd3) begin
            $display("   -> [PASS] Burst 1 is correct.");
        end else begin
            $display("   -> [FAIL] Burst 1 Error! Did not stop at 4K boundary.");
            $stop;
        end

        // 等待第一个 Burst 数据传完 (wlast)
        wait(m_axi_wlast);
        @(posedge clk); // 等一拍状态机切换

        // 2. 等待第二个 Burst 地址发出
        wait(m_axi_awvalid && m_axi_awready);
        $display("[TIME %t] Burst 2 Issued:", $time);
        $display("   Addr: %h (Expected: 00001000)", m_axi_awaddr);
        $display("   Len : %d (Expected: 11 [48 bytes])", m_axi_awlen);

        // 判定 Burst 2
        if (m_axi_awaddr == 32'h0000_1000 && m_axi_awlen == 8'd11) begin
            $display("   -> [PASS] Burst 2 is correct. Crossed boundary safely.");
        end else begin
            $display("   -> [FAIL] Burst 2 Address/Len Error!");
            $stop;
        end

        // 等待完成
        wait(o_done);
        $display("\n[SUCCESS] DMA 4K Boundary Test Passed!");
        $finish;
    end

endmodule