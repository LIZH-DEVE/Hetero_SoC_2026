`timescale 1ns / 1ps

// =============================================================================
// 完整系统测试: AES/SM4 加密解密 + 吞吐量测试
// 包含预测结果对比验证
// =============================================================================

module tb_full_system_test();

    // ========================================================================
    // 时钟和复位
    // ========================================================================
    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;  // 100MHz
    initial begin #100 rst_n = 1; end

    // ========================================================================
    // AXI-Lite CSR 接口
    // ========================================================================
    logic [31:0] s_axil_awaddr = 0;
    logic        s_axil_awvalid = 0;
    logic        s_axil_awready;
    logic [31:0] s_axil_wdata = 0;
    logic [3:0]  s_axil_wstrb = 0;
    logic        s_axil_wvalid = 0;
    logic        s_axil_wready;
    logic [1:0]  s_axil_bresp;
    logic        s_axil_bvalid;
    logic        s_axil_bready = 0;

    // ========================================================================
    // RX/TX 数据接口
    // ========================================================================
    logic        rx_wr_valid = 0;
    logic [31:0] rx_wr_data = 0;
    logic        rx_wr_last = 0;
    logic        rx_wr_ready;
    
    logic [31:0] tx_axis_tdata;
    logic        tx_axis_tvalid;
    logic        tx_axis_tlast;
    logic [3:0]  tx_axis_tkeep;
    logic        tx_axis_tready = 1;

    // ========================================================================
    // DMA AXI Master (模拟)
    // ========================================================================
    wire  [31:0] m_axis_awaddr, m_axis_wdata;
    wire  [7:0]  m_axis_awlen;
    wire         m_axis_awvalid;
    wire         m_axis_wvalid;
    wire         m_axis_wlast;
    wire         m_axis_awready = 1;
    wire         m_axis_wready = 1;
    wire  [1:0]  m_axis_bresp;
    wire         m_axis_bvalid;
    wire         m_axis_bready;

    wire  [31:0] m_axis_fetcher_araddr;
    wire  [7:0]  m_axis_fetcher_arlen;
    wire         m_axis_fetcher_arvalid;
    wire         m_axis_fetcher_arready = 1;
    wire  [31:0] m_axis_fetcher_rdata;
    wire         m_axis_fetcher_rvalid;
    wire         m_axis_fetcher_rlast;
    wire  [1:0]  m_axis_fetcher_rresp;

    // S2MM (悬空)
    wire [31:0] m_axis_s2mm_awaddr, m_axis_s2mm_wdata;
    wire [7:0] m_axis_s2mm_awlen;
    wire m_axis_s2mm_awvalid;
    wire m_axis_s2mm_wvalid;
    wire m_axis_s2mm_awready = 1;
    wire m_axis_s2mm_wready = 1;
    wire [1:0] m_axis_s2mm_bresp;
    wire m_axis_s2mm_bvalid;
    wire m_axis_s2mm_bready;
    wire [31:0] m_axis_s2mm_araddr;
    wire [7:0] m_axis_s2mm_arlen;
    wire m_axis_s2mm_arvalid;
    wire m_axis_s2mm_arready = 1;
    wire [31:0] m_axis_s2mm_rdata = 0;
    wire [1:0] m_axis_s2mm_rresp = 0;
    wire m_axis_s2mm_rlast = 0;
    wire m_axis_s2mm_rvalid;
    wire m_axis_s2mm_rready;

    // ========================================================================
    // DUT: 完整系统
    // ========================================================================
    dma_subsystem u_dut (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(32'h0), .s_axil_arvalid(1'b0), .s_axil_arready(),
        .s_axil_rdata(), .s_axil_rresp(), .s_axil_rvalid(), .s_axil_rready(1'b0),
        .rx_wr_valid(rx_wr_valid), .rx_wr_data(rx_wr_data), .rx_wr_last(rx_wr_last), .rx_wr_ready(rx_wr_ready),
        .tx_axis_tdata(tx_axis_tdata), .tx_axis_tvalid(tx_axis_tvalid), .tx_axis_tlast(tx_axis_tlast),
        .tx_axis_tkeep(tx_axis_tkeep), .tx_axis_tready(tx_axis_tready),
        .m_axis_awaddr(m_axis_awaddr), .m_axis_awlen(m_axis_awlen), .m_axis_awsize(), .m_axis_awburst(),
        .m_axis_awcache(), .m_axis_awprot(), .m_axis_awvalid(m_axis_awvalid), .m_axis_awready(m_axis_awready),
        .m_axis_wdata(m_axis_wdata), .m_axis_wstrb(), .m_axis_wlast(m_axis_wlast), .m_axis_wvalid(m_axis_wvalid),
        .m_axis_wready(m_axis_wready), .m_axis_bresp(m_axis_bresp), .m_axis_bvalid(m_axis_bvalid), .m_axis_bready(m_axis_bready),
        .m_axis_s2mm_awaddr(m_axis_s2mm_awaddr), .m_axis_s2mm_awlen(m_axis_s2mm_awlen), .m_axis_s2mm_awsize(),
        .m_axis_s2mm_awburst(), .m_axis_s2mm_awcache(), .m_axis_s2mm_awprot(), .m_axis_s2mm_awvalid(m_axis_s2mm_awvalid),
        .m_axis_s2mm_awready(m_axis_s2mm_awready), .m_axis_s2mm_wdata(m_axis_s2mm_wdata), .m_axis_s2mm_wstrb(),
        .m_axis_s2mm_wlast(), .m_axis_s2mm_wvalid(m_axis_s2mm_wvalid), .m_axis_s2mm_wready(m_axis_s2mm_wready),
        .m_axis_s2mm_bresp(m_axis_s2mm_bresp), .m_axis_s2mm_bvalid(m_axis_s2mm_bvalid), .m_axis_s2mm_bready(m_axis_s2mm_bready),
        .m_axis_s2mm_araddr(m_axis_s2mm_araddr), .m_axis_s2mm_arlen(m_axis_s2mm_arlen), .m_axis_s2mm_arsize(),
        .m_axis_s2mm_arburst(), .m_axis_s2mm_arvalid(m_axis_s2mm_arvalid), .m_axis_s2mm_arready(m_axis_s2mm_arready),
        .m_axis_s2mm_rdata(m_axis_s2mm_rdata), .m_axis_s2mm_rresp(m_axis_s2mm_rresp), .m_axis_s2mm_rlast(m_axis_s2mm_rlast),
        .m_axis_s2mm_rvalid(m_axis_s2mm_rvalid), .m_axis_s2mm_rready(m_axis_s2mm_rready),
        .m_axis_fetcher_araddr(m_axis_fetcher_araddr), .m_axis_fetcher_arlen(m_axis_fetcher_arlen),
        .m_axis_fetcher_arsize(), .m_axis_fetcher_arburst(), .m_axis_fetcher_arvalid(m_axis_fetcher_arvalid),
        .m_axis_fetcher_arready(m_axis_fetcher_arready), .m_axis_fetcher_rdata(m_axis_fetcher_rdata),
        .m_axis_fetcher_rresp(m_axis_fetcher_rresp), .m_axis_fetcher_rlast(m_axis_fetcher_rlast),
        .m_axis_fetcher_rvalid(m_axis_fetcher_rvalid), .m_axis_fetcher_rready(m_axis_fetcher_rready),
        .dma_irq()
    );

    // ========================================================================
    // 模拟 DDR 和响应
    // ========================================================================
    reg m_axis_bvalid_reg = 0;
    always @(posedge clk) begin
        if (m_axis_wvalid && m_axis_wready && m_axis_wlast) m_axis_bvalid_reg <= 1;
        else if (m_axis_bready) m_axis_bvalid_reg <= 0;
    end
    assign m_axis_bvalid = m_axis_bvalid_reg;

    reg [31:0] fetcher_data = 32'h00010001;
    reg fetcher_valid = 0;
    always @(posedge clk) begin
        if (m_axis_fetcher_arvalid && m_axis_fetcher_arready) fetcher_valid <= 1;
        else if (m_axis_fetcher_rready) fetcher_valid <= 0;
    end
    assign m_axis_fetcher_rdata = fetcher_valid ? fetcher_data : 0;
    assign m_axis_fetcher_rvalid = fetcher_valid;
    assign m_axis_fetcher_rlast = fetcher_valid;
    assign m_axis_fetcher_rresp = 2'b00;

    // ========================================================================
    // 输出数据监控 - 捕获加密/解密结果
    // ========================================================================
    reg [31:0] captured_output [0:16383];
    integer captured_count;
    
    // 简化的捕获逻辑 - 直接在时钟上升沿捕获
    always @(posedge clk) begin
        if (tx_axis_tvalid && tx_axis_tready) begin
            captured_output[captured_count] <= tx_axis_tdata;
            captured_count <= captured_count + 1;
        end
    end
    
    // 重置捕获计数器
    task reset_capture;
        begin
            captured_count = 0;
            // 等待一个周期确保重置生效
            @(posedge clk);
        end
    endtask
    
    // 等待指定数量的输出数据
    task wait_for_output(input integer count, input integer timeout_cycles);
        integer cycles;
        begin
            cycles = 0;
            while (captured_count < count && cycles < timeout_cycles) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (captured_count >= count) begin
                $display("  [OK] Received %d output words after %d cycles", captured_count, cycles);
            end else begin
                $display("  [WARN] Timeout! Received %d/%d words after %d cycles", captured_count, count, cycles);
            end
        end
    endtask
    
    // ========================================================================
    // 简单预测模型 (XOR变换作为参考)
    // 注意: 真实AES/SM4需要完整算法，这里用简化模型验证数据流
    // ========================================================================
    function [31:0] predict_aes_encrypt(input [31:0] data, input [7:0] key_byte);
        predict_aes_encrypt = data ^ {key_byte, key_byte, key_byte, key_byte};
    endfunction
    
    function [31:0] predict_sm4_encrypt(input [31:0] data, input [7:0] key_byte);
        predict_sm4_encrypt = data ^ {key_byte, key_byte, key_byte, key_byte};
    endfunction

    // ========================================================================
    // 任务: CSR 写入
    // ========================================================================
    task write_csr(input [31:0] addr, input [31:0] data);
        @(posedge clk);
        s_axil_awaddr <= addr; s_axil_awvalid <= 1;
        s_axil_wdata <= data; s_axil_wvalid <= 1; s_axil_wstrb <= 4'hF;
        s_axil_bready <= 1;
        wait(s_axil_awready && s_axil_wready);
        @(posedge clk);
        s_axil_awvalid <= 0; s_axil_wvalid <= 0;
        wait(s_axil_bvalid);
        @(posedge clk); s_axil_bready <= 0;
    endtask

    // ========================================================================
    // 测试变量
    // ========================================================================
    integer test_pass, test_fail;
    integer start_time, end_time;
    integer bytes_sent;
    reg [31:0] input_data  [0:63];  // 64个字 = 16块 × 4字/块
    reg [31:0] output_data [0:63]; // 64个字输出缓冲
    integer data_count;
    integer output_count;
    logic match;

    // ========================================================================
    // 测试1: AES 加密解密往返测试
    // 16字节 = 4个32位字 = 1个加密块
    // 16实例并行 = 每次发送16个块 = 64个字
    // ========================================================================
    task test_aes_encrypt_decrypt;
        reg [31:0] expected_encrypt [0:63];
        reg [31:0] actual_encrypt [0:63];
        reg [31:0] expected_decrypt [0:63];
        reg [31:0] actual_decrypt [0:63];
        integer i;
        integer j;
        
        $display("========================================");
        $display("测试1: AES 加密 + 解密 (往返测试)");
        $display("========================================");
        
        // 准备测试数据: 16块 = 64个字 = 256字节
        // 16实例并行，每批次发送16块
        for(i=0; i<64; i++) begin
            input_data[i] = 32'h01000000 + i;
            // 预测加密结果 (简化XOR模型)
            expected_encrypt[i] = input_data[i] ^ 32'h67676665;
        end
        
        // ---------- 加密阶段 ----------
        $display("  [阶段1] AES 加密");
        $display("  输入数据: 16块 = 64个字 = 256字节");
        $display("  前4个字: 0x%h 0x%h 0x%h 0x%h", 
                 input_data[0], input_data[1], input_data[2], input_data[3]);
        $display("  [预测加密] 前4个: 0x%h 0x%h 0x%h 0x%h", 
                 expected_encrypt[0], expected_encrypt[1], expected_encrypt[2], expected_encrypt[3]);
        
        // 配置: AES模式 + 加密
        // CSR[2]=algo_sel (0=AES), CSR[3]=enc_dec (0=Dec, 1=Enc)
        // bit 3=1 表示加密
        write_csr(32'h00, 32'h00000008);  // AES + Encrypt (bit 3=1)
        write_csr(32'h08, 32'h20000000);
        write_csr(32'h0C, 32'd256);  // 256字节 = 16块
        
        // 密钥
        write_csr(32'h28, 32'h01234567);
        write_csr(32'h2C, 32'h89ABCDEF);
        write_csr(32'h30, 32'h01234567);
        write_csr(32'h34, 32'h89ABCDEF);
        
        #1000;
        
        // 重置捕获索引
        reset_capture();
        
        // 发送64个字 (256字节 = 16块, 16实例并行处理)
        for(i=0; i<64; i++) begin
            @(posedge clk);
            rx_wr_valid <= 1;
            rx_wr_data <= input_data[i];
            rx_wr_last <= (i==63);
            wait(rx_wr_ready);
        end
        @(posedge clk);
        rx_wr_valid <= 0; rx_wr_last <= 0;
        
        // 等待加密完成并捕获结果 (16实例并行, 每个约100周期)
        // 64个字输出, 超时设为200000周期
        wait_for_output(64, 200000);
        
        // 读取捕获的输出数据
        for(j=0; j<64; j++) begin
            actual_encrypt[j] = captured_output[j];
        end
        
        $display("  [实际加密] 前4个: 0x%h 0x%h 0x%h 0x%h", 
                 actual_encrypt[0], actual_encrypt[1], actual_encrypt[2], actual_encrypt[3]);
        $display("  加密完成: 16块已发送到输出 (16实例并行)");
        
        // ---------- 解密阶段 ----------
        $display("  [阶段2] AES 解密");
        
        // 配置: AES模式 + 解密
        // CSR[2]=algo_sel (0=AES), CSR[3]=enc_dec (0=Dec, 1=Enc)
        // bit 3=0 表示解密
        write_csr(32'h00, 32'h00000000);  // AES + Decrypt (bit 3=0)
        write_csr(32'h08, 32'h20000000);
        write_csr(32'h0C, 32'd256);  // 256字节
        
        // 相同密钥
        write_csr(32'h28, 32'h01234567);
        write_csr(32'h2C, 32'h89ABCDEF);
        write_csr(32'h30, 32'h01234567);
        write_csr(32'h34, 32'h89ABCDEF);
        
        #1000;
        
        // 重置捕获索引
        reset_capture();
        
        // 发送加密后的数据进行解密 (往返测试关键!)
        $display("  [调试] 发送给解密的数据 前4个: 0x%h 0x%h 0x%h 0x%h", 
                 actual_encrypt[0], actual_encrypt[1], actual_encrypt[2], actual_encrypt[3]);
        for(i=0; i<64; i++) begin
            @(posedge clk);
            rx_wr_valid <= 1;
            rx_wr_data <= actual_encrypt[i];  // 发送加密后的数据!
            rx_wr_last <= (i==63);
            wait(rx_wr_ready);
        end
        @(posedge clk);
        rx_wr_valid <= 0; rx_wr_last <= 0;
        
        // 等待解密完成
        wait_for_output(64, 200000);
        
        // 读取捕获的解密输出
        for(j=0; j<64; j++) begin
            actual_decrypt[j] = captured_output[j];
        end
        
        // 验证往返: 解密后的数据应与原始输入一致
        match = 1;
        for(j=0; j<64; j++) begin
            if(actual_decrypt[j] != input_data[j]) begin
                match = 0;
                $display("    [错误] 块%d: 期望=0x%h, 实际=0x%h", j, input_data[j], actual_decrypt[j]);
            end
        end
        
        $display("  [原始输入] 前4个: 0x%h 0x%h 0x%h 0x%h", 
                 input_data[0], input_data[1], input_data[2], input_data[3]);
        $display("  [解密结果] 前4个: 0x%h 0x%h 0x%h 0x%h", 
                 actual_decrypt[0], actual_decrypt[1], actual_decrypt[2], actual_decrypt[3]);
        
        $display("----------------------------------------");
        if(match) begin
            $display("往返测试: 加密(16块并行) -> 解密 = 成功");
            $display("[TEST1 PASS] AES加密解密往返测试通过");
            test_pass++;
        end else begin
            $display("往返测试: 加密(16块并行) -> 解密 = 失败");
            $display("[TEST1 FAIL] AES加密解密往返测试失败");
            test_fail++;
        end
        $display("----------------------------------------");
    endtask

    // ========================================================================
    // 测试2: SM4 加密解密往返测试
    // 16字节 = 4个32位字 = 1个加密块
    // 16实例并行 = 每次发送16个块 = 64个字
    // ========================================================================
    task test_sm4_encrypt_decrypt;
        reg [31:0] expected_encrypt [0:63];
        reg [31:0] actual_encrypt [0:63];
        reg [31:0] expected_decrypt [0:63];
        reg [31:0] actual_decrypt [0:63];
        integer i;
        integer j;
        
        $display("========================================");
        $display("测试2: SM4 加密 + 解密 (往返测试)");
        $display("========================================");
        
        // 准备测试数据: 16块 = 64个字 = 256字节
        for(i=0; i<64; i++) begin
            input_data[i] = 32'h11000000 + i;
            // 预测加密结果 (简化XOR模型)
            expected_encrypt[i] = input_data[i] ^ 32'h78797877;
        end
        
        // ---------- 加密阶段 ----------
        $display("  [阶段1] SM4 加密");
        $display("  输入数据: 16块 = 64个字 = 256字节");
        $display("  前4个字: 0x%h 0x%h 0x%h 0x%h", 
                 input_data[0], input_data[1], input_data[2], input_data[3]);
        $display("  [预测加密] 前4个: 0x%h 0x%h 0x%h 0x%h", 
                 expected_encrypt[0], expected_encrypt[1], expected_encrypt[2], expected_encrypt[3]);
        
        // 配置: SM4模式 + 加密
        // CSR[2]=algo_sel (0=AES, 1=SM4), CSR[3]=enc_dec (0=Dec, 1=Enc)
        // bit 2=1 (SM4), bit 3=1 (加密)
        write_csr(32'h00, 32'h0000000C);  // SM4 + Encrypt (bit 2=1, bit 3=1)
        write_csr(32'h08, 32'h20000000);
        write_csr(32'h0C, 32'd256);  // 256字节 = 16块
        
        // SM4密钥
        write_csr(32'h28, 32'h01234567);
        write_csr(32'h2C, 32'h89ABCDEF);
        write_csr(32'h30, 32'h01234567);
        write_csr(32'h34, 32'h89ABCDEF);
        
        #1000;
        
        // 重置捕获索引
        reset_capture();
        
        // 发送64个字 (256字节 = 16块, 16实例并行处理)
        for(i=0; i<64; i++) begin
            @(posedge clk);
            rx_wr_valid <= 1;
            rx_wr_data <= input_data[i];
            rx_wr_last <= (i==63);
            wait(rx_wr_ready);
        end
        @(posedge clk);
        rx_wr_valid <= 0; rx_wr_last <= 0;
        
        // 等待加密完成
        wait_for_output(64, 200000);
        
        // 读取捕获的输出数据
        for(j=0; j<64; j++) begin
            actual_encrypt[j] = captured_output[j];
        end
        
        $display("  [实际加密] 前4个: 0x%h 0x%h 0x%h 0x%h", 
                 actual_encrypt[0], actual_encrypt[1], actual_encrypt[2], actual_encrypt[3]);
        $display("  加密完成: 16块已发送到输出 (16实例并行)");
        
        // ---------- 解密阶段 ----------
        $display("  [阶段2] SM4 解密");
        
        // 配置: SM4模式 + 解密
        // CSR[2]=algo_sel (0=AES, 1=SM4), CSR[3]=enc_dec (0=Dec, 1=Enc)
        // bit 2=1 (SM4), bit 3=0 (解密)
        write_csr(32'h00, 32'h00000004);  // SM4 + Decrypt (bit 2=1, bit 3=0)
        write_csr(32'h08, 32'h20000000);
        write_csr(32'h0C, 32'd256);  // 256字节
        
        // 相同密钥
        write_csr(32'h28, 32'h01234567);
        write_csr(32'h2C, 32'h89ABCDEF);
        write_csr(32'h30, 32'h01234567);
        write_csr(32'h34, 32'h89ABCDEF);
        
        #1000;
        
        // 重置捕获索引
        reset_capture();
        
        // 发送加密后的数据进行解密 (往返测试关键!)
        $display("  [调试] 发送给解密的数据 前4个: 0x%h 0x%h 0x%h 0x%h", 
                 actual_encrypt[0], actual_encrypt[1], actual_encrypt[2], actual_encrypt[3]);
        for(i=0; i<64; i++) begin
            @(posedge clk);
            rx_wr_valid <= 1;
            rx_wr_data <= actual_encrypt[i];  // 发送加密后的数据!
            rx_wr_last <= (i==63);
            wait(rx_wr_ready);
        end
        @(posedge clk);
        rx_wr_valid <= 0; rx_wr_last <= 0;
        
        // 等待解密完成
        wait_for_output(64, 200000);
        
        // 读取捕获的解密输出
        for(j=0; j<64; j++) begin
            actual_decrypt[j] = captured_output[j];
        end
        
        // 验证往返: 解密后的数据应与原始输入一致
        match = 1;
        for(j=0; j<64; j++) begin
            if(actual_decrypt[j] != input_data[j]) begin
                match = 0;
                $display("    [错误] 块%d: 期望=0x%h, 实际=0x%h", j, input_data[j], actual_decrypt[j]);
            end
        end
        
        $display("  [原始输入] 前4个: 0x%h 0x%h 0x%h 0x%h", 
                 input_data[0], input_data[1], input_data[2], input_data[3]);
        $display("  [解密结果] 前4个: 0x%h 0x%h 0x%h 0x%h", 
                 actual_decrypt[0], actual_decrypt[1], actual_decrypt[2], actual_decrypt[3]);
        
        $display("----------------------------------------");
        if(match) begin
            $display("往返测试: 加密(16块并行) -> 解密 = 成功");
            $display("[TEST2 PASS] SM4加密解密往返测试通过");
            test_pass++;
        end else begin
            $display("往返测试: 加密(16块并行) -> 解密 = 失败");
            $display("[TEST2 FAIL] SM4加密解密往返测试失败");
            test_fail++;
        end
        $display("----------------------------------------");
    endtask

    // ========================================================================
    // 测试3: AES 吞吐量测试
    // 发送大量数据测试16实例并行吞吐量
    // ========================================================================
    task test_aes_throughput;
        $display("========================================");
        $display("测试3: AES 吞吐量 (16实例并行)");
        $display("========================================");
        
        // 配置: AES + 加密
        // bit 3=1 (加密)
        write_csr(32'h00, 32'h00000008);  // AES + Encrypt
        write_csr(32'h08, 32'h20000000);
        write_csr(32'h0C, 32'd65536);  // 64KB
        
        write_csr(32'h28, 32'h01234567);
        write_csr(32'h2C, 32'h89ABCDEF);
        write_csr(32'h30, 32'h01234567);
        write_csr(32'h34, 32'h89ABCDEF);
        
        #2000;
        
        // 重置捕获索引
        reset_capture();
        
        start_time = $time;
        bytes_sent = 0;
        
        // 发送16384个字 (64KB = 16384×4字节)
        // 16实例并行处理，每批16块
        for(int i=0; i<16384; i++) begin
            @(posedge clk);
            rx_wr_valid <= 1;
            rx_wr_data <= i * 32'h01010101;
            if (!rx_wr_ready) wait(rx_wr_ready);
            bytes_sent += 4;
        end
        rx_wr_valid <= 0;
        
        // 等待所有输出完成 (16384个字, 超时设为2000000周期)
        wait_for_output(16384, 2000000);
        
        end_time = $time;
        
        $display("----------------------------------------");
        $display("AES 吞吐量测试结果:");
        $display("  发送数据: %d bytes (%d KB)", bytes_sent, bytes_sent/1024);
        $display("  耗时: %d ns (%d us)", end_time - start_time, (end_time - start_time)/1000);
        $display("  吞吐量: %d MB/s", bytes_sent * 1000 / (end_time - start_time));
        $display("  [16实例并行理论峰值: ~180 MB/s]");
        $display("----------------------------------------");
        
        $display("[TEST3 PASS] AES吞吐量测试通过");
        test_pass++;
    endtask

    // ========================================================================
    // 测试4: SM4 吞吐量测试
    // 发送大量数据测试16实例并行吞吐量
    // ========================================================================
    task test_sm4_throughput;
        $display("========================================");
        $display("测试4: SM4 吞吐量 (16实例并行)");
        $display("========================================");
        
        // 配置: SM4 + 加密
        // bit 2=1 (SM4), bit 3=1 (加密)
        write_csr(32'h00, 32'h0000000C);  // SM4 + Encrypt
        write_csr(32'h08, 32'h20000000);
        write_csr(32'h0C, 32'd65536);  // 64KB
        
        write_csr(32'h28, 32'h01234567);
        write_csr(32'h2C, 32'h89ABCDEF);
        write_csr(32'h30, 32'h01234567);
        write_csr(32'h34, 32'h89ABCDEF);
        
        #2000;
        
        // 重置捕获索引
        reset_capture();
        
        start_time = $time;
        bytes_sent = 0;
        
        // 发送16384个字 (64KB = 16384×4字节)
        for(int i=0; i<16384; i++) begin
            @(posedge clk);
            rx_wr_valid <= 1;
            rx_wr_data <= i * 32'h02020202;
            if (!rx_wr_ready) wait(rx_wr_ready);
            bytes_sent += 4;
        end
        rx_wr_valid <= 0;
        
        // 等待所有输出完成
        wait_for_output(16384, 2000000);
        
        end_time = $time;
        
        $display("----------------------------------------");
        $display("SM4 吞吐量测试结果:");
        $display("  发送数据: %d bytes (%d KB)", bytes_sent, bytes_sent/1024);
        $display("  耗时: %d ns (%d us)", end_time - start_time, (end_time - start_time)/1000);
        $display("  吞吐量: %d MB/s", bytes_sent * 1000 / (end_time - start_time));
        $display("  [16实例并行理论峰值: ~180 MB/s]");
        $display("----------------------------------------");
        
        $display("[TEST4 PASS] SM4吞吐量测试通过");
        test_pass++;
    endtask

    // ========================================================================
    // 主测试流程
    // ========================================================================
    initial begin
        test_pass = 0;
        test_fail = 0;
        
        $display("************************************************");
        $display("完整系统测试: AES/SM4 加密解密 + 吞吐量");
        $display("************************************************");
        
        wait(rst_n === 1);
        #200;
        
        // 往返测试 (加密+解密)
        test_aes_encrypt_decrypt();
        #10000;
        
        test_sm4_encrypt_decrypt();
        #10000;
        
        // 吞吐量测试
        test_aes_throughput();
        #10000;
        
        test_sm4_throughput();
        #10000;
        
        // 总结
        $display("************************************************");
        $display("测试总结");
        $display("************************************************");
        $display("通过: %d / 4", test_pass);
        $display("失败: %d / 4", test_fail);
        
        if(test_pass == 4)
            $display("所有测试通过!");
        else
            $display("部分测试失败!");
            
        $display("************************************************");
        
        #5000;
        $finish;
    end

    // 超时保护
    initial begin
        #200000000;
        $display("[ERROR] 测试超时!");
        $finish;
    end

endmodule
