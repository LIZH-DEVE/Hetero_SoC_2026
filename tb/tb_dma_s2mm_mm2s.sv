`timescale 1ns / 1ps

// 测试 S2MM/MM2S 功能：CPU 直接读写 DDR

module tb_dma_s2mm_mm2s();

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

    // --- AXI4 Master (S2MM/MM2S -> DDR) ---
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
    logic [31:0] m_axis_araddr;
    logic [7:0]  m_axis_arlen;
    logic [2:0]  m_axis_arsize;
    logic [1:0]  m_axis_arburst;
    logic        m_axis_arvalid, m_axis_arready;
    logic [31:0] m_axis_rdata;
    logic [1:0]  m_axis_rresp;
    logic        m_axis_rlast, m_axis_rvalid, m_axis_rready;

    // =========================================================
    // 2. 模拟 DDR 存储器 (Stub Model)
    // =========================================================
    logic [31:0] mock_ddr [0:1023];
    
    // 初始化 DDR
    initial begin
        for(int i=0; i<1024; i++) mock_ddr[i] = 32'hDEAD_BEEF;
    end

    // --- AXI Write Channel Simulation (S2MM 写入 DDR) ---
    always @(posedge clk) begin
        if(!rst_n) begin
            m_axis_awready <= 0;
            m_axis_wready <= 0;
            m_axis_bvalid <= 0;
        end else begin
            m_axis_awready <= 1'b1;
            m_axis_wready <= 1'b1;
            
            if (m_axis_wvalid && m_axis_wready) begin
                mock_ddr[m_axis_awaddr[11:2]] <= m_axis_wdata;
                $display("[TB] S2MM Write: Addr=%h, Data=%h", m_axis_awaddr, m_axis_wdata);
            end
            
            if (m_axis_wvalid && m_axis_wready && m_axis_wlast) begin
                m_axis_bvalid <= 1'b1;
            end
            
            if (m_axis_bvalid && m_axis_bready) begin
                m_axis_bvalid <= 1'b0;
            end
        end
    end

    // --- AXI Read Channel Simulation (MM2S 从 DDR 读取) ---
    always @(posedge clk) begin
        if(!rst_n) begin
            m_axis_arready <= 0;
            m_axis_rvalid <= 0;
            m_axis_rdata <= 0;
        end else begin
            m_axis_arready <= 1'b1;
            
            if (m_axis_arvalid && m_axis_arready) begin
                m_axis_rvalid <= 1'b1;
                m_axis_rdata <= mock_ddr[m_axis_araddr[11:2]];
                $display("[TB] MM2S Read: Addr=%h, Data=%h", m_axis_araddr, mock_ddr[m_axis_araddr[11:2]]);
            end
            
            if (m_axis_rvalid && m_axis_rready) begin
                m_axis_rvalid <= 1'b0;
            end
        end
    end

    // =========================================================
    // 3. DUT 实例化
    // =========================================================
    dma_s2mm_mm2s_engine #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) u_dut (
        .clk(clk), .rst_n(rst_n),
        
        // Control Interface
        .i_s2mm_en(),
        .i_mm2s_en(),
        .i_s2mm_addr(32'h2000_0000),  // 固定目标地址
        .i_s2mm_data(32'h0000_0000),  // 初始数据
        .o_mm2s_data(),
        
        // AXI4 Master Interface
        .m_axis_awaddr(m_axis_awaddr), .m_axis_awlen(m_axis_awlen),
        .m_axis_awsize(m_axis_awsize), .m_axis_awburst(m_axis_awburst),
        .m_axis_awcache(m_axis_awcache), .m_axis_awprot(m_axis_awprot),
        .m_axis_awvalid(m_axis_awvalid), .m_axis_awready(m_axis_awready),
        .m_axis_wdata(m_axis_wdata), .m_axis_wstrb(m_axis_wstrb),
        .m_axis_wlast(m_axis_wlast), .m_axis_wvalid(m_axis_wvalid),
        .m_axis_wready(m_axis_wready), .m_axis_bresp(m_axis_bresp),
        .m_axis_bvalid(m_axis_bvalid), .m_axis_bready(m_axis_bready),
        
        .m_axis_araddr(m_axis_araddr), .m_axis_arlen(m_axis_arlen), 
        .m_axis_arsize(m_axis_arsize), .m_axis_arburst(m_axis_arburst),
        .m_axis_arvalid(m_axis_arvalid), .m_axis_arready(m_axis_arready),
        .m_axis_rdata(m_axis_rdata), .m_axis_rresp(m_axis_rresp),
        .m_axis_rlast(m_axis_rlast), .m_axis_rvalid(m_axis_rvalid), 
        .m_axis_rready(m_axis_rready)
    );

    // =========================================================
    // 4. 测试激励流程
    // =========================================================
    
    // 时钟生成 (10ns = 100MHz)
    initial begin clk = 0; forever #5 clk = ~clk; end

    // 辅助任务：触发 S2MM 写操作
    task trigger_s2mm(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            // 直接驱动 DUT 的控制信号
            u_dut.i_s2mm_en <= 1;
            u_dut.i_s2mm_addr <= addr;
            u_dut.i_s2mm_data <= data;
            @(posedge clk);
            u_dut.i_s2mm_en <= 0;
            $display("[TB] Trigger S2MM: Addr=%h, Data=%h", addr, data);
        end
    endtask

    // 辅助任务：触发 MM2S 读操作
    task trigger_mm2s(input [31:0] addr);
        begin
            @(posedge clk);
            u_dut.i_mm2s_en <= 1;
            u_dut.i_s2mm_addr <= addr;
            @(posedge clk);
            u_dut.i_mm2s_en <= 0;
            $display("[TB] Trigger MM2S: Addr=%h", addr);
        end
    endtask

    logic [31:0] s2mm_read_data;
    logic [31:0] mm2s_result;

    initial begin
        // --- 初始化 ---
        rst_n = 0;
        u_dut.i_s2mm_en <= 0;
        u_dut.i_mm2s_en <= 0;
        u_dut.i_s2mm_addr <= 0;
        u_dut.i_s2mm_data <= 0;
        
        #100 rst_n = 1; #100;

        // =================================================
        // Test 1: 测试 S2MM (CPU 写入 DDR)
        // =================================================
        $display("[TB] ========================================================");
        $display("[TB] Test 1: 测试 S2MM (CPU 直接写入 DDR)");
        $display("[TB] ========================================================");
        
        trigger_s2mm(32'h1000_0000, 32'hABCD_EF01);
        
        #500;
        
        // =================================================
        // Test 2: 测试 MM2S (CPU 读取 DDR)
        // =================================================
        $display("[TB] ========================================================");
        $display("[TB] Test 2: 测试 MM2S (CPU 直接读取 DDR)");
        $display("[TB] ========================================================");
        
        trigger_mm2s(32'h1000_0000);
        
        #500;
        mm2s_result = u_dut.o_mm2s_data;
        $display("[TB] MM2S Result: %h", mm2s_result);
        
        // =================================================
        // Test 3: 验证数据一致性
        // =================================================
        $display("[TB] ========================================================");
        $display("[TB] Test 3: 验证数据一致性");
        $display("[TB] ========================================================");
        
        if (mm2s_result == 32'hABCD_EF01) begin
            $display("[TB] PASS: 数据一致!");
        end else begin
            $display("[TB] FAIL: 数据不一致! Expected: %h, Got: %h", 32'hABCD_EF01, mm2s_result);
        end
        
        #500 $stop;
    end

endmodule
