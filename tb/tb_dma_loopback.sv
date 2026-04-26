`timescale 1ns / 1ps

// 测试 Loopback Mux 功能：DDR 回环 / PBM 直通

module tb_dma_loopback();

    // =========================================================
    // 1. 信号与接口定义
    // =========================================================
    logic clk;
    logic rst_n;

    // --- AXI-Lite (CSR 配置接口) ---
    logic [31:0] s_axil_awaddr;
    logic        s_axil_awvalid, s_axil_awready;
    logic [31:0] s_axil_wdata;
    logic [3:0]  s_axil_wstrb;
    logic        s_axil_wvalid, s_axil_wready;
    logic [1:0]  s_axil_bresp;
    logic        s_axil_bvalid, s_axil_bready;
    logic [31:0] s_axil_araddr;
    logic        s_axil_arvalid, s_axil_arready;
    logic [31:0] s_axil_rdata;
    logic [1:0]  s_axil_rresp;
    logic        s_axil_rvalid, s_axil_rready;

    // --- 数据输入路径 (PBM) ---
    logic        rx_wr_valid, rx_wr_last, rx_wr_ready;
    logic [31:0] rx_wr_data;

    // --- TX Output Interface (PBM Passthrough) ---
    logic [31:0] tx_axis_tdata;
    logic        tx_axis_tvalid, tx_axis_tlast;
    logic [3:0]  tx_axis_tkeep;
    logic        tx_axis_tready;

    // --- AXI4 Master (DMA -> DDR) ---
    logic [31:0] m_axis_awaddr;
    logic [7:0]  m_axis_awlen;
    logic [2:0]  m_axis_awsize;
    logic [1:0]  m_axis_awburst;
    logic [3:0]  m_axis_awcache;
    logic [2:0]  m_axis_awprot;
    logic        m_axis_awvalid, m_axis_awready;
    logic [31:0] m_axis_wdata;
    logic [3:0]  m_axis_wstrb;
    logic        m_axis_wlast, m_axis_wvalid;
    logic        m_axis_wready;
    logic [1:0]  m_axis_bresp;
    logic        m_axis_bvalid, m_axis_bready;

    // --- S2MM/MM2S AXI Master ---
    logic [31:0] m_axis_s2mm_awaddr;
    logic [7:0]  m_axis_s2mm_awlen;
    logic [2:0]  m_axis_s2mm_awsize;
    logic [1:0]  m_axis_s2mm_awburst;
    logic        m_axis_s2mm_awvalid, m_axis_s2mm_awready;
    logic [31:0] m_axis_s2mm_wdata;
    logic [3:0]  m_axis_s2mm_wstrb;
    logic        m_axis_s2mm_wlast, m_axis_s2mm_wvalid;
    logic        m_axis_s2mm_wready;
    logic [1:0]  m_axis_s2mm_bresp;
    logic        m_axis_s2mm_bvalid, m_axis_s2mm_bready;
    logic [31:0] m_axis_s2mm_araddr;
    logic [7:0]  m_axis_s2mm_arlen;
    logic        m_axis_s2mm_arvalid, m_axis_s2mm_arready;
    logic [31:0] m_axis_s2mm_rdata;
    logic        m_axis_s2mm_rvalid, m_axis_s2mm_rready;

    // --- Fetcher AXI Master ---
    logic [31:0] m_axis_fetcher_araddr;
    logic [7:0]  m_axis_fetcher_arlen;
    logic        m_axis_fetcher_arvalid, m_axis_fetcher_arready;
    logic [31:0] m_axis_fetcher_rdata;
    logic        m_axis_fetcher_rvalid, m_axis_fetcher_rready;

    // =========================================================
    // 2. 模拟 DDR 存储器 (Stub Model)
    // =========================================================
    logic [31:0] mock_ddr [0:4095];
    logic [31:0] ddr_write_data;
    logic [31:0] expected_ddr_data;
    
    // 初始化 DDR
    initial begin
        for(int i=0; i<4096; i++) mock_ddr[i] = 32'h0000_0000;
        expected_ddr_data = 32'hABCD_1234;
    end

    // --- AXI Write Channel Simulation (DMA 写回密文) ---
    always @(posedge clk) begin
        if(!rst_n) begin
            m_axis_awready <= 0;
            m_axis_wready <= 0;
            m_axis_bvalid <= 0;
        end else begin
            m_axis_awready <= 1'b1;
            m_axis_wready <= 1'b1;
            
            if (m_axis_wvalid && m_axis_wready) begin
                ddr_write_data <= m_axis_wdata;
                mock_ddr[m_axis_awaddr[13:2]] <= m_axis_wdata;
                $display("[TB] DMA Write to DDR: Addr=%h, Data=%h", m_axis_awaddr, m_axis_wdata);
            end
            
            if (m_axis_wvalid && m_axis_wready && m_axis_wlast) begin
                m_axis_bvalid <= 1'b1;
            end
            
            if (m_axis_bvalid && m_axis_bready) begin
                m_axis_bvalid <= 1'b0;
            end
        end
    end

    // --- S2MM/MM2S Bypass ---
    always @(posedge clk) begin
        m_axis_s2mm_awready <= 1'b1;
        m_axis_s2mm_wready <= 1'b1;
        m_axis_s2mm_bvalid <= 1'b0;
        m_axis_s2mm_arready <= 1'b1;
        m_axis_s2mm_rvalid <= 1'b0;
    end

    // --- Fetcher Bypass ---
    always @(posedge clk) begin
        m_axis_fetcher_arready <= 1'b1;
        if (m_axis_fetcher_arvalid && m_axis_fetcher_arready) begin
            m_axis_fetcher_rvalid <= 1'b1;
            m_axis_fetcher_rdata <= 32'h2000_0000; // Base addr
        end else begin
            m_axis_fetcher_rvalid <= 1'b0;
        end
    end

    // =========================================================
    // 3. DUT 实例化
    // =========================================================
    crypto_dma_subsystem #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) u_dut (
        .clk(clk), .rst_n(rst_n),
        
        // AXI-Lite Slave
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        
        // RX Input
        .rx_wr_valid(rx_wr_valid), .rx_wr_data(rx_wr_data), .rx_wr_last(rx_wr_last), .rx_wr_ready(rx_wr_ready),
        
        // TX Output
        .tx_axis_tdata(tx_axis_tdata), .tx_axis_tvalid(tx_axis_tvalid), .tx_axis_tlast(tx_axis_tlast),
        .tx_axis_tkeep(tx_axis_tkeep), .tx_axis_tready(tx_axis_tready),
        
        // DMA AXI Master
        .m_axis_awaddr(m_axis_awaddr), .m_axis_awlen(m_axis_awlen), .m_axis_awsize(m_axis_awsize),
        .m_axis_awburst(m_axis_awburst), .m_axis_awcache(m_axis_awcache), .m_axis_awprot(m_axis_awprot),
        .m_axis_awvalid(m_axis_awvalid), .m_axis_awready(m_axis_awready),
        .m_axis_wdata(m_axis_wdata), .m_axis_wstrb(m_axis_wstrb), .m_axis_wlast(m_axis_wlast),
        .m_axis_wvalid(m_axis_wvalid), .m_axis_wready(m_axis_wready),
        .m_axis_bresp(m_axis_bresp), .m_axis_bvalid(m_axis_bvalid), .m_axis_bready(m_axis_bready),
        
        // S2MM/MM2S AXI Master
        .m_axis_s2mm_awaddr(m_axis_s2mm_awaddr), .m_axis_s2mm_awlen(m_axis_s2mm_awlen),
        .m_axis_s2mm_awsize(m_axis_s2mm_awsize), .m_axis_s2mm_awburst(m_axis_s2mm_awburst),
        .m_axis_s2mm_awcache(), .m_axis_s2mm_awprot(), .m_axis_s2mm_awvalid(m_axis_s2mm_awvalid),
        .m_axis_s2mm_awready(m_axis_s2mm_awready), .m_axis_s2mm_wdata(m_axis_s2mm_wdata),
        .m_axis_s2mm_wstrb(4'hF), .m_axis_s2mm_wlast(1'b1), .m_axis_s2mm_wvalid(m_axis_s2mm_wvalid),
        .m_axis_s2mm_wready(m_axis_s2mm_wready), .m_axis_s2mm_bresp(), .m_axis_s2mm_bvalid(m_axis_s2mm_bvalid),
        .m_axis_s2mm_bready(m_axis_s2mm_bready), .m_axis_s2mm_araddr(m_axis_s2mm_araddr),
        .m_axis_s2mm_arlen(m_axis_s2mm_arlen), .m_axis_s2mm_arsize(), .m_axis_s2mm_arburst(),
        .m_axis_s2mm_arvalid(m_axis_s2mm_arvalid), .m_axis_s2mm_arready(m_axis_s2mm_arready),
        .m_axis_s2mm_rdata(m_axis_s2mm_rdata), .m_axis_s2mm_rresp(), .m_axis_s2mm_rlast(),
        .m_axis_s2mm_rvalid(m_axis_s2mm_rvalid), .m_axis_s2mm_rready(m_axis_s2mm_rready),
        
        // Fetcher AXI Master
        .m_axis_fetcher_araddr(m_axis_fetcher_araddr), .m_axis_fetcher_arlen(m_axis_fetcher_arlen),
        .m_axis_fetcher_arsize(), .m_axis_fetcher_arburst(), .m_axis_fetcher_arvalid(m_axis_fetcher_arvalid),
        .m_axis_fetcher_arready(m_axis_fetcher_arready), .m_axis_fetcher_rdata(m_axis_fetcher_rdata),
        .m_axis_fetcher_rlast(), .m_axis_fetcher_rvalid(m_axis_fetcher_rvalid), .m_axis_fetcher_rready(m_axis_fetcher_rready)
    );

    // =========================================================
    // 4. 测试激励流程
    // =========================================================
    
    // 时钟生成 (10ns = 100MHz)
    initial begin clk = 0; forever #5 clk = ~clk; end

    // 辅助任务：AXI-Lite 写寄存器
    task axil_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axil_awaddr <= addr; s_axil_awvalid <= 1;
            s_axil_wdata <= data; s_axil_wvalid <= 1; s_axil_wstrb <= 4'hF;
            s_axil_bready <= 1;
            
            wait(s_axil_awready && s_axil_wready);
            @(posedge clk);
            s_axil_awvalid <= 0; s_axil_wvalid <= 0;
            
            wait(s_axil_bvalid);
            @(posedge clk);
            s_axil_bvalid <= 0;
            
            $display("[TB] Write CSR Addr: %h, Data: %h", addr, data);
        end
    endtask

    // 辅助任务：写入 PBM 数据
    task pbm_write(input [31:0] data, input last_bit);
        begin
            @(posedge clk);
            rx_wr_valid <= 1;
            rx_wr_data <= data;
            rx_wr_last <= last_bit;
            
            wait(rx_wr_ready);
            @(posedge clk);
            rx_wr_valid <= 0;
            rx_wr_last <= 0;
            
            $display("[TB] PBM Write: Data=%h, Last=%d", data, last_bit);
        end
    endtask

    initial begin
        // --- 初始化 ---
        rst_n = 0;
        s_axil_awvalid = 0; s_axil_wvalid = 0; s_axil_bready = 0;
        s_axil_arvalid = 0; s_axil_rready = 0;
        rx_wr_valid = 0; rx_wr_data = 0; rx_wr_last = 0;
        tx_axis_tready <= 1;
        
        #100 rst_n = 1; #100;

        // =================================================
        // Test 1: 配置 DMA (Normal 模式）
        // =================================================
        $display("[TB] ========================================================");
        $display("[TB] Test 1: 配置 DMA (Normal 模式 - 写入 DDR)");
        $display("[TB] ========================================================");
        
        // 设置基地址和长度
        axil_write(32'h08, 32'h2000_0000);  // 0x08: Base Addr = 0x20000000
        axil_write(32'h0C, 32'd32);         // 0x0C: Length = 32 bytes
        
        // 禁用 Ring 模式（使用 CSR 模式）
        axil_write(32'h5C, 32'd0);         // 0x5C: Ring Size = 0
        
        #1000;

        // =================================================
        // Test 2: 注入数据到 PBM
        // =================================================
        $display("[TB] ========================================================");
        $display("[TB] Test 2: 注入数据到 PBM (32 字节)");
        $display("[TB] ========================================================");
        
        // 注入 32 字节的数据（8 个 32-bit 字）
        for(int i=1; i<=8; i++) begin
            pbm_write(32'hDEAD_CAFE + i*32'h1111_1111, (i == 8));
        end
        
        #1000;

        // =================================================
        // Test 3: 启动 DMA
        // =================================================
        $display("[TB] ========================================================");
        $display("[TB] Test 3: 启动 DMA");
        $display("[TB] ========================================================");
        
        axil_write(32'h00, 32'h01);  // Bit 0: Start
        
        #5000;
        
        // =================================================
        // Test 4: 验证 DDR 数据
        // =================================================
        $display("[TB] ========================================================");
        $display("[TB] Test 4: 验证 DDR 数据");
        $display("[TB] DDR[0] = %h", mock_ddr[0]);
        $display("[TB] DDR[1] = %h", mock_ddr[1]);
        
        #500;
        
        // =================================================
        // Test 5: 配置 Loopback 模式 (PBM Passthrough)
        // =================================================
        $display("[TB] ========================================================");
        $display("[TB] Test 5: 配置 Loopback 模式 (PBM Passthrough)");
        $display("[TB] ========================================================");
        
        axil_write(32'h48, 32'h02);  // 0x48: Loopback Mode = 2 (PBM Passthrough)
        
        #1000;
        
        // =================================================
        // Test 6: 重新注入数据并验证 TX 输出
        // =================================================
        $display("[TB] ========================================================");
        $display("[TB] Test 6: 重新注入数据 (Passthrough 模式)");
        $display("[TB] ========================================================");
        
        // 清空 DDR（模拟）
        for(int i=0; i<10; i++) mock_ddr[i] = 32'h0000_0000;
        
        // 重新注入数据
        for(int i=1; i<=8; i++) begin
            pbm_write(32'hCAFE_BABE + i*32'h2222_2222, (i == 8));
        end
        
        #2000;
        
        // 验证 DDR 没有被写入（Passthrough 模式）
        $display("[TB] DDR[0] after Passthrough = %h (should be 0)", mock_ddr[0]);
        
        #500 $stop;
    end

endmodule
