`timescale 1ns / 1ps

// 简化测试台：直接使用 CSR 控制模式，不使用 Fetcher

module tb_crypto_dma_subsystem_simple();

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

    // --- RX Input (数据注入) ---
    logic        rx_wr_valid, rx_wr_last, rx_wr_ready;
    logic [31:0] rx_wr_data;

    // --- AXI4 Master (DMA -> DDR) ---
    // 写地址
    logic [31:0] m_axi_awaddr;
    logic [7:0]  m_axi_awlen;
    logic [2:0]  m_axi_awsize;
    logic [1:0]  m_axi_awburst;
    logic [3:0]  m_axi_awcache;
    logic [2:0]  m_axi_awprot;
    logic        m_axi_awvalid, m_axi_awready;
    // 写数据
    logic [31:0] m_axi_wdata;
    logic [3:0]  m_axi_wstrb;
    logic        m_axi_wlast, m_axi_wvalid, m_axi_wready;
    // 写响应
    logic [1:0]  m_axi_bresp;
    logic        m_axi_bvalid, m_axi_bready;
    // 读地址
    logic [31:0] m_axi_araddr;
    logic [7:0]  m_axi_arlen;
    logic [2:0]  m_axi_arsize;
    logic [1:0]  m_axi_arburst;
    logic        m_axi_arvalid, m_axi_arready;
    // 读数据
    logic [31:0] m_axi_rdata;
    logic [1:0]  m_axi_rresp;
    logic        m_axi_rlast, m_axi_rvalid, m_axi_rready;

    // =========================================================
    // 2. 模拟 DDR 存储器 (Stub Model)
    // =========================================================

    // --- AXI Read Channel Simulation (Fetcher 读取描述符) ---
    always @(posedge clk) begin
        if(!rst_n) begin
            m_axi_arready <= 0;
            m_axi_rvalid <= 0;
            m_axi_rlast <= 0;
            m_axi_rdata <= 0;
        end else begin
            m_axi_arready <= 1'b1;

            if (m_axi_arvalid && m_axi_arready) begin
                repeat(2) @(posedge clk);

                for(int i=0; i<4; i++) begin
                    m_axi_rvalid <= 1'b1;
                    m_axi_rdata  <= 32'h0000_0000;  // 描述符数据
                    m_axi_rlast  <= (i == 3);

                    do begin
                        @(posedge clk);
                    end while(!m_axi_rready);

                    m_axi_rvalid <= 1'b0;
                    m_axi_rlast <= 0;
                end
            end
        end
    end

    // --- AXI Write Channel Simulation (DMA 写回密文) ---
    always @(posedge clk) begin
        if(!rst_n) begin
            m_axi_awready <= 0;
            m_axi_wready <= 0;
            m_axi_bvalid <= 0;
        end else begin
            m_axi_awready <= 1'b1;
            m_axi_wready <= 1'b1;

            if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                m_axi_bvalid <= 1'b1;
                $display("[TB] >>> DMA Wrote data to DDR: %h <<<", m_axi_wdata);
            end
            else if (m_axi_bready && m_axi_bvalid) begin
                m_axi_bvalid <= 1'b0;
            end
        end
    end

    // =========================================================
    // 3. DUT 实例化
    // =========================================================
    crypto_dma_subsystem u_dut (
        .clk(clk),
        .rst_n(rst_n),

        // AXI-Lite Slave
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),

        // RX Data
        .rx_wr_valid(rx_wr_valid), .rx_wr_data(rx_wr_data), .rx_wr_last(rx_wr_last), .rx_wr_ready(rx_wr_ready),

        // AXI Master AR (Read)
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
        .m_axi_rresp(m_axi_rresp),

        // AXI Master AW/W (Write)
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awcache(m_axi_awcache), .m_axi_awprot(m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready)
    );

    // =========================================================
    // 4. 测试激励流程 (简化版：使用 CSR 控制模式)
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
            s_axil_bready <= 0;

            $display("[TB] Write CSR Addr: %h, Data: %h", addr, data);
        end
    endtask

    initial begin
        // --- 初始化 ---
        rst_n = 0;
        s_axil_awvalid = 0; s_axil_wvalid = 0; s_axil_bready = 0;
        s_axil_arvalid = 0; s_axil_rready = 0;
        rx_wr_valid = 0; rx_wr_data = 0; rx_wr_last = 0;

        #100 rst_n = 1; #100;

        // =================================================
        // 关键：不设置 ring_size (保持为 0)，使用 CSR 控制模式
        // =================================================
        $display("[TB] Test 1: Simple DMA with CSR Control Mode");

        // 配置 DMA 参数
        axil_write(32'h08, 32'h2000_0000);  // base_addr = 0x20000000
        axil_write(32'h0C, 32'd32);         // len = 32 bytes

        // 注入数据到 PBM (32 bytes = 8 words)
        $display("[TB] Injecting 32 bytes to PBM...");
        for (int i=1; i<=8; i++) begin
            rx_wr_valid = 1;
            rx_wr_data = i * 32'h1111_1111;
            rx_wr_last = (i == 8);

            @(posedge clk);
            wait(rx_wr_ready);  // 等待 PBM 接收数据
            $display("[TB] Wrote data %d: %h (rx_wr_ready=%d)", i, rx_wr_data, rx_wr_ready);
        end
        rx_wr_valid = 0; rx_wr_last = 0;

        #100;

        // =================================================
        // Step 2: 触发 DMA 启动 (Bit 0)
        // =================================================
        $display("[TB] Triggering DMA Start...");
        axil_write(32'h00, 32'h0000_0001);  // Bit 0 = Start

        // =================================================
        // Step 3: 等待完成
        // =================================================
        $display("[TB] Waiting for DMA Done...");

        fork
            begin
                wait(u_dut.dma_done);
                $display("[TB] >>> DMA DONE SIGNAL DETECTED! TEST PASSED! <<<");
            end
            begin
                #50000;
                $display("[TB] >>> TIMEOUT! DMA Done not received. <<<");
                $stop;
            end
        join_any

        #500 $stop;
    end

endmodule
