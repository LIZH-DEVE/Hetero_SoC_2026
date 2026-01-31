`timescale 1ns / 1ps

/**
 * Testbench: tb_full_system_verification
 * Description: 完整系统验证测试平台
 * - 验证CSR寄存器（CACHE_CTRL, ACL_COLLISION_CNT）
 * - 验证DMA Master拆包逻辑和对齐检查
 * - 验证Packet Dispatcher的tuser分发逻辑
 * - 验证AXI BFM功能
 * - 验证整体系统集成
 */
module tb_full_system_verification;

    // ========================================================
    // 时钟和复位
    // ========================================================
    logic clk;
    logic rst_n;

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end

    initial begin
        rst_n = 0;
        #100;
        rst_n = 1;
    end

    // ========================================================
    // CSR接口
    // ========================================================
    logic [31:0]  csr_awaddr;
    logic        csr_awvalid;
    logic        csr_awready;
    logic [31:0]  csr_wdata;
    logic [3:0]   csr_wstrb;
    logic        csr_wvalid;
    logic        csr_wready;
    logic [1:0]   csr_bresp;
    logic        csr_bvalid;
    logic        csr_bready;
    logic [31:0]  csr_araddr;
    logic        csr_arvalid;
    logic        csr_arready;
    logic [31:0]  csr_rdata;
    logic [1:0]   csr_rresp;
    logic        csr_rvalid;
    logic        csr_rready;

    // CSR控制输出
    logic        csr_start;
    logic        csr_hw_init;
    logic        csr_algo_sel;
    logic        csr_enc_dec;
    logic        csr_cache_flush;
    logic [31:0] csr_acl_cnt;

    // ========================================================
    // AXI Master接口
    // ========================================================
    logic [31:0]  m_axi_awaddr;
    logic [7:0]   m_axi_awlen;
    logic [2:0]   m_axi_awsize;
    logic [1:0]   m_axi_awburst;
    logic [3:0]   m_axi_awcache;
    logic [2:0]   m_axi_awprot;
    logic        m_axi_awvalid;
    logic        m_axi_awready;
    logic [31:0]  m_axi_wdata;
    logic [3:0]   m_axi_wstrb;
    logic        m_axi_wlast;
    logic        m_axi_wvalid;
    logic        m_axi_wready;
    logic [1:0]   m_axi_wresp;
    logic        m_axi_blast;
    logic        m_axi_bvalid;
    logic        m_axi_bready;

    // ========================================================
    // Packet Dispatcher接口
    // ========================================================
    logic [31:0]  pd_s_axis_tdata;
    logic        pd_s_axis_tvalid;
    logic        pd_s_axis_tlast;
    logic        pd_s_axis_tuser;
    logic        pd_s_axis_tready;

    logic [31:0]  pd_m_axis0_tdata;
    logic        pd_m_axis0_tvalid;
    logic        pd_m_axis0_tlast;
    logic        pd_m_axis0_tready;

    logic [31:0]  pd_m_axis1_tdata;
    logic        pd_m_axis1_tvalid;
    logic        pd_m_axis1_tlast;
    logic        pd_m_axis1_tready;

    logic [1:0]   pd_disp_mode;

    // ========================================================
    // 实例化DUT
    // ========================================================
    axil_csr u_csr (
        .clk              (clk),
        .rst_n            (rst_n),
        .s_axil_awaddr    (csr_awaddr),
        .s_axil_awvalid   (csr_awvalid),
        .s_axil_awready   (csr_awready),
        .s_axil_wdata     (csr_wdata),
        .s_axil_wstrb     (csr_wstrb),
        .s_axil_wvalid    (csr_wvalid),
        .s_axil_wready    (csr_wready),
        .s_axil_bresp     (csr_bresp),
        .s_axil_bvalid    (csr_bvalid),
        .s_axil_bready    (csr_bready),
        .s_axil_araddr    (csr_araddr),
        .s_axil_arvalid   (csr_arvalid),
        .s_axil_arready   (csr_arready),
        .s_axil_rdata     (csr_rdata),
        .s_axil_rresp     (csr_rresp),
        .s_axil_rvalid    (csr_rvalid),
        .s_axil_rready    (csr_rready),
        .o_start          (csr_start),
        .o_hw_init        (csr_hw_init),
        .o_algo_sel       (csr_algo_sel),
        .o_enc_dec        (csr_enc_dec),
        .o_s2mm_en        (),
        .o_mm2s_en        (),
        .o_loopback_mode  (),
        .o_base_addr      (),
        .o_len            (),
        .o_key            (),
        .o_cache_flush    (csr_cache_flush),
        .i_acl_inc        (1'b0),
        .o_acl_cnt        (csr_acl_cnt),
        .o_ring_base      (),
        .o_ring_size      (),
        .o_sw_tail_ptr    (),
        .i_hw_head_ptr    (16'd0),
        .i_done           (1'b0),
        .i_error          (1'b0)
    );

    packet_dispatcher u_dispatcher (
        .clk              (clk),
        .rst_n            (rst_n),
        .s_axis_tdata     (pd_s_axis_tdata),
        .s_axis_tvalid    (pd_s_axis_tvalid),
        .s_axis_tlast     (pd_s_axis_tlast),
        .s_axis_tkeep     (4'hF),
        .s_axis_tuser     (pd_s_axis_tuser),
        .s_axis_tready    (pd_s_axis_tready),
        .m_axis0_tdata    (pd_m_axis0_tdata),
        .m_axis0_tvalid   (pd_m_axis0_tvalid),
        .m_axis0_tlast    (pd_m_axis0_tlast),
        .m_axis0_tkeep    (),
        .m_axis0_tready   (pd_m_axis0_tready),
        .m_axis1_tdata    (pd_m_axis1_tdata),
        .m_axis1_tvalid   (pd_m_axis1_tvalid),
        .m_axis1_tlast    (pd_m_axis1_tlast),
        .m_axis1_tkeep    (),
        .m_axis1_tready   (pd_m_axis1_tready),
        .disp_mode        (pd_disp_mode)
    );

    // ========================================================
    // 测试任务
    // ========================================================

    // Task: CSR读写测试
    task test_csr_rw();
        begin
            $display("[%0t] >>> Test: CSR Read/Write", $time);
            
            // 测试CACHE_CTRL寄存器 (0x40)
            csr_awaddr = 32'h40;
            csr_wdata = 32'h01;
            csr_wstrb = 4'hF;
            @(posedge clk);
            csr_awvalid = 1;
            csr_wvalid = 1;
            wait(csr_awready && csr_wready);
            csr_awvalid = 0;
            csr_wvalid = 0;
            wait(csr_bvalid);
            csr_bready = 1;
            @(posedge clk);
            csr_bready = 0;
            
            if (csr_cache_flush == 1'b1) begin
                $display("[%0t] PASS: CACHE_CTRL bit 0 set correctly", $time);
            end else begin
                $display("[%0t] FAIL: CACHE_CTRL bit 0 not set!", $time);
            end

            // 读取ACL_COLLISION_CNT寄存器 (0x44)
            csr_araddr = 32'h44;
            @(posedge clk);
            csr_arvalid = 1;
            wait(csr_arready);
            csr_arvalid = 0;
            wait(csr_rvalid);
            csr_rready = 1;
            @(posedge clk);
            csr_rready = 0;
            
            $display("[%0t] ACL_COLLISION_CNT = 0x%h", $time, csr_rdata);
            
            $display("[%0t] <<< Test Complete: CSR Read/Write", $time);
            $display();
        end
    endtask

    // Task: Packet Dispatcher tuser分发测试
    task test_dispatcher_tuser();
        begin
            $display("[%0t] >>> Test: Dispatcher tuser-based", $time);
            
            // 设置tuser模式
            pd_disp_mode = 2'b00;
            
            // 测试tuser=0，应该发往path0
            pd_s_axis_tdata = 32'hAABBCCDD;
            pd_s_axis_tlast = 0;
            pd_s_axis_tuser = 0;
            pd_m_axis0_tready = 1;
            pd_m_axis1_tready = 0;
            @(posedge clk);
            pd_s_axis_tvalid = 1;
            wait(pd_s_axis_tready);
            pd_s_axis_tvalid = 0;
            
            if (pd_m_axis0_tvalid == 1'b1 && pd_m_axis0_tdata == 32'hAABBCCDD) begin
                $display("[%0t] PASS: tuser=0 -> path0", $time);
            end else begin
                $display("[%0t] FAIL: tuser=0 not routed to path0!", $time);
            end
            
            // 测试tuser=1，应该发往path1
            pd_s_axis_tdata = 32'h11223344;
            pd_s_axis_tuser = 1;
            pd_m_axis0_tready = 0;
            pd_m_axis1_tready = 1;
            @(posedge clk);
            pd_s_axis_tvalid = 1;
            wait(pd_s_axis_tready);
            pd_s_axis_tvalid = 0;
            
            if (pd_m_axis1_tvalid == 1'b1 && pd_m_axis1_tdata == 32'h11223344) begin
                $display("[%0t] PASS: tuser=1 -> path1", $time);
            end else begin
       
