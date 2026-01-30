`timescale 1ns / 1ps

module tb_crypto_dma_subsystem();

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

    // --- AXI4 Master (DMA/Fetcher -> DDR) ---
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
    logic        m_axi_bvalid, m_axi_bready; // bready 由 DUT 驱动
    // 读地址
    logic [31:0] m_axi_araddr;
    logic [7:0]  m_axi_arlen;
    logic [2:0]  m_axi_arsize; // 关键信号
    logic [1:0]  m_axi_arburst;
    logic        m_axi_arvalid, m_axi_arready;
    // 读数据
    logic [31:0] m_axi_rdata;
    logic [1:0]  m_axi_rresp;
    logic        m_axi_rlast, m_axi_rvalid, m_axi_rready;

    // =========================================================
    // 2. 模拟 DDR 存储器 (Stub Model)
    // =========================================================
    logic [31:0] mock_ddr [0:3]; 
    initial begin
        // 描述符内容: Dest=0x10000000, Len=32B, Algo=SM4
        mock_ddr[0] = 32'h1000_0000; 
        mock_ddr[1] = 32'h8000_0020; 
        mock_ddr[2] = 32'h0000_0000; 
        mock_ddr[3] = 32'h0000_0000; 
    end

    // --- AXI Read Channel Simulation (Fetcher 读取描述符) ---
    always @(posedge clk) begin
        if(!rst_n) begin
            m_axi_arready <= 0; 
            m_axi_rvalid <= 0; 
            m_axi_rlast <= 0;
            m_axi_rdata <= 0;
        end else begin
            // 永远准备好接收读地址
            m_axi_arready <= 1'b1;
            
            // 简单的握手逻辑：收到地址后，发回数据
            if (m_axi_arvalid && m_axi_arready) begin
                // 模拟 DRAM 延迟
                repeat(2) @(posedge clk);
                
                // 发送 4 个 Beat (Burst Length = 3, Total 4)
                for(int i=0; i<4; i++) begin
                    m_axi_rvalid <= 1'b1;
                    m_axi_rdata  <= mock_ddr[i];
                    m_axi_rlast  <= (i == 3); // 最后一个数据拉高 RLAST
                    
                    // 等待 Master (Fetcher) 接收数据
                    do begin
                        @(posedge clk);
                    end while(!m_axi_rready);
                    
                    // 数据已传输，清除 Valid，准备下一个
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
            // 永远准备好接收写地址和写数据
            m_axi_awready <= 1'b1; 
            m_axi_wready <= 1'b1;
            
            // 简单的写响应逻辑
            // 当收到 WLAST (最后一个数据) 时，发送 BVALID (写响应)
            if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                m_axi_bvalid <= 1'b1;
            end 
            // 当 Master (DMA) 收到响应并拉高 BREADY 后，撤销 BVALID
            else if (m_axi_bready && m_axi_bvalid) begin
                m_axi_bvalid <= 1'b0;
            end
        end
    end

    // =========================================================
    // 3. DUT 实例化 (显式连接，防止 Implicit Error)
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
        .m_axi_arsize(m_axi_arsize), // Explicitly connected!
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rlast(m_axi_rlast), 
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
        .m_axi_rresp(m_axi_rresp),
        
        // AXI Master AW/W (Write)
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize), 
        .m_axi_awburst(m_axi_awburst), .m_axi_awcache(m_axi_awcache), .m_axi_awprot(m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready)
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
            
            // 等待写地址和写数据握手
            wait(s_axil_awready && s_axil_wready);
            @(posedge clk);
            s_axil_awvalid <= 0; s_axil_wvalid <= 0;
            
            // 等待写响应
            wait(s_axil_bvalid);
            @(posedge clk);
            s_axil_bready <= 0;
            
            $display("[TB] Write CSR Addr: %h, Data: %h", addr, data);
        end
    endtask

    initial begin
        // --- 初始化 ---
        // 关键点：不要在这里给 m_axi_bready 赋值！它是 DUT 的输出！
        rst_n = 0; 
        s_axil_awvalid = 0; s_axil_wvalid = 0; s_axil_bready = 0;
        s_axil_arvalid = 0; s_axil_rready = 0; 
        rx_wr_valid = 0; rx_wr_data = 0; rx_wr_last = 0;
        
        #100 rst_n = 1; #100;

        // =================================================
        // Step 1: 配置 Ring Buffer
        // =================================================
        $display("[TB] Step 1: Configuring Ring Buffer...");
        // 0x50: Ring Base Addr = 0x2000_0000
        axil_write(32'h50, 32'h0000_0000); // 假设 TB 里的 mock_ddr 映射到基址 0
        // 0x5C: Ring Size = 256 (启用 Ring 模式)
        axil_write(32'h5C, 32'd256);

        // =================================================
        // Step 2: 硬件初始化 (Key Expansion)
        // =================================================
        $display("[TB] Step 2: Triggering HW Init (Key Expansion)...");
        // 0x00: Bit 1 = HW_INIT (触发 AES/SM4 密钥扩展)
        axil_write(32'h00, 32'h0000_0002);
        
        // 重要：等待初始化完成 (SM4 需要一些周期)
        #1000; 

        // =================================================
        // Step 3: 注入数据 (PBM Input)
        // =================================================
        $display("[TB] Step 3: Injecting Data to PBM...");
        @(posedge clk);
        for (int i=1; i<=8; i++) begin
            rx_wr_valid = 1;
            rx_wr_data = i * 32'h1111_1111;
            rx_wr_last = (i == 8);
            
            @(posedge clk);
            wait(rx_wr_ready);  // 等待 PBM 准备好接收数据
            $display("[TB] Wrote data %d: %h", i, rx_wr_data);
        end
        rx_wr_valid = 0; rx_wr_last = 0;

        // =================================================
        // Step 4: 更新 Tail 指针 (触发 Fetcher)
        // =================================================
        $display("[TB] Step 4: Updating Tail Ptr to Trigger Fetch...");
        // 0x58: SW_TAIL = 1 (告诉硬件有一个新任务)
        axil_write(32'h58, 32'd1);
        
        // 等待 Fetcher 开始工作
        #100;

        // =================================================
        // Step 5: 等待完成
        // =================================================
        $display("[TB] Waiting for DMA Done...");
        
        // 设置超时防止死锁
        fork
            begin
                wait(u_dut.dma_done);
                $display("[TB] >>> DMA DONE SIGNAL DETECTED! TEST PASSED! <<<");
            end
            begin
                #50000;
                $display("[TB] >>> TIMEOUT! DMA Done not received. <<<");
                $display("[TB] Check the following signals in waveform:");
                $display("[TB]   - u_dut.u_pbm.ptr_head_commit (PBM head pointer)");
                $display("[TB]   - u_dut.u_pbm.ptr_tail (PBM tail pointer)");
                $display("[TB]   - u_dut.u_dma_engine.state (DMA state machine)");
                $display("[TB]   - u_dut.u_fetcher.state (Fetcher state machine)");
                $stop;
            end
        join_any
        
        #500 $stop;
    end

endmodule
