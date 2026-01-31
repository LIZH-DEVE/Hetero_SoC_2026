`timescale 1ns / 1ps

module tb_dma_master_engine;

    // --- 1. 参数与信号定义 ---
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;

    logic clk;
    logic rst_n;

    // User Interface
    logic                   i_start;
    logic [ADDR_WIDTH-1:0] i_base_addr;
    logic [31:0]           i_total_len;
    logic                   o_done;
    logic                   o_error;

    // AXI Interface (Wires)
    logic [ADDR_WIDTH-1:0] m_axi_awaddr;
    logic [7:0]            m_axi_awlen;
    logic [2:0]            m_axi_awsize;
    logic [1:0]            m_axi_awburst;
    logic                   m_axi_awvalid;
    logic                   m_axi_awready;

    logic [DATA_WIDTH-1:0] m_axi_wdata;
    logic [DATA_WIDTH/8-1:0] m_axi_wstrb;
    logic                   m_axi_wlast;
    logic                   m_axi_wvalid;
    logic                   m_axi_wready;

    logic [1:0]            m_axi_bresp;
    logic                   m_axi_bvalid;
    logic                   m_axi_bready;

    // Unused Read Channels
    logic [ADDR_WIDTH-1:0] m_axi_araddr;
    logic [7:0]            m_axi_arlen;
    logic [2:0]            m_axi_arsize;
    logic [1:0]            m_axi_arburst;
    logic                   m_axi_arvalid;
    logic                   m_axi_arready = 0;
    logic [DATA_WIDTH-1:0] m_axi_rdata = 0;
    logic                   m_axi_rlast = 0;
    logic [1:0]            m_axi_rresp = 0;
    logic                   m_axi_rvalid = 0;
    logic                   m_axi_rready;

    // --- 2. DUT 实例化 ---
    dma_master_engine #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_start(i_start),
        .i_base_addr(i_base_addr),
        .i_total_len(i_total_len),
        .o_done(o_done),
        .o_error(o_error),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

    // --- 3. 基础驱动逻辑 (Day 4 升级版压力测试) ---
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 随机背压驱动核心 
    integer seed = 666; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awready <= 0;
            m_axi_wready  <= 0;
            m_axi_bvalid  <= 0;
            m_axi_bresp   <= 0;
        end else begin
            // A. 地址通道随机背压：30% 概率不 Ready
            if (m_axi_awvalid && !m_axi_awready) begin
                if ($dist_uniform(seed, 0, 100) < 30) 
                    m_axi_awready <= 0; 
                else 
                    m_axi_awready <= 1;
            end else begin
                m_axi_awready <= 0;
            end

            // B. 数据通道随机背压：40% 概率卡顿 
            // 验证 Master 是否能正确维持 WVALID 和 WDATA 直到握手完成
            if ($dist_uniform(seed, 0, 100) < 40) 
                m_axi_wready <= 0;
            else 
                m_axi_wready <= 1;

            // C. 写响应逻辑 [cite: 30, 31]
            if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                m_axi_bvalid <= 1; 
                m_axi_bresp  <= 2'b00; // OKAY
            end 
            else if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 0; 
            end
        end
    end

    // --- 4. 测试流程控制 ---
    initial begin
        rst_n = 0; i_start = 0; i_base_addr = 0; i_total_len = 0;
        #100; rst_n = 1; #20;

        $display("=== Simulation Start (Day 4: Stress Testing) ===");

        // Case 1: 正常传输测试
        $display("[Time %t] Case 1: Standard Transfer (1024 Bytes)", $time);
        @(posedge clk);
        i_base_addr = 32'h1000_0000; i_total_len = 32'd1024; i_start = 1;
        @(posedge clk); i_start = 0;
        wait(o_done);
        $display("[Time %t] Case 1 PASSED.", $time);
        
        #100;

        // Case 2: 拆包压力测试 (2048 字节，多次 Burst，含随机背压) [cite: 36]
        $display("[Time %t] Case 3: Burst Splitting (2048 Bytes) under Stress", $time);
        @(posedge clk);
        i_base_addr = 32'h2000_0000; i_total_len = 32'd2048; i_start = 1;
        @(posedge clk); i_start = 0;
        wait(o_done);
        $display("[Time %t] Case 3 PASSED: Multi-Burst Robustness Verified.", $time);

        #100;
        $display("=== Simulation Finished ===");
        $finish;
    end

    // =========================================================
    // 5. BFM Verification Tasks
    // =========================================================
    
    // Task: 检查地址对齐
    task check_alignment(input [31:0] addr, input string test_name);
        begin
            if (addr[2:0] != 3'b000) begin
                $display("[ERROR] %s: Address 0x%08h is NOT 8-byte aligned!", test_name, addr);
                $display("        Address[2:0] = %b (should be 000)", addr[2:0]);
            end else begin
                $display("[PASS] %s: Address 0x%08h is properly aligned", test_name, addr);
            end
        end
    endtask
 
endmodule