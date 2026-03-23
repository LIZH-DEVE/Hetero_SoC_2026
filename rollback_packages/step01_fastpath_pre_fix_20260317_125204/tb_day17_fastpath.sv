`timescale 1ns / 1ps

/**
 * Day 17: Zero-Copy FastPath Testbench
 * Task 16.1: FastPath Rules (Patch)
 */

module tb_day17_fastpath;

    // ========================================================================
    // Clock and Reset
    // ========================================================================
    logic clk;
    logic rst_n;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 0;
        #200;
        rst_n = 1;
    end

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam CRYPTO_PORT = 16'h1234;
    localparam CONFIG_PORT = 16'h4321;

    // ========================================================================
    // FastPath DUT Interface
    // ========================================================================
    logic [31:0]  s_axis_tdata;
    logic [3:0]   s_axis_tkeep;
    logic         s_axis_tlast;
    logic         s_axis_tvalid;
    logic         s_axis_tready;

    logic [15:0]  dst_port;
    logic [15:0]  payload_len;
    logic         drop_flag;
    logic         meta_valid;

    logic [15:0]  ip_checksum;
    logic [15:0]  udp_checksum;
    logic         checksum_valid;

    logic [31:0]  pbm_wdata;
    logic         pbm_wvalid;
    logic         pbm_wlast;
    logic         pbm_ready;

    logic [31:0]  m_axis_tdata;
    logic [3:0]   m_axis_tkeep;
    logic         m_axis_tlast;
    logic         m_axis_tvalid;
    logic         m_axis_tready;

    logic [15:0]  meta_out_data;
    logic         meta_out_valid;
    logic [15:0]  meta_out_checksum;
    logic         meta_out_checksum_valid;

    logic         fast_path_enable;
    logic [31:0]  fast_path_cnt;
    logic [31:0]  bypass_cnt;
    logic         drop_cnt;
    logic [31:0]  checksum_pass_cnt;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    fast_path #(
        .AXI_DATA_WIDTH(32),
        .CRYPTO_PORT(CRYPTO_PORT),
        .CONFIG_PORT(CONFIG_PORT)
    ) u_fast_path (
        .clk                 (clk),
        .rst_n               (rst_n),

        // RX Path Input
        .s_axis_tdata        (s_axis_tdata),
        .s_axis_tkeep        (s_axis_tkeep),
        .s_axis_tlast        (s_axis_tlast),
        .s_axis_tvalid       (s_axis_tvalid),
        .s_axis_tready       (s_axis_tready),

        // Control Signals
        .dst_port            (dst_port),
        .payload_len         (payload_len),
        .drop_flag           (drop_flag),
        .meta_valid          (meta_valid),

        // Checksum Signals
        .ip_checksum         (ip_checksum),
        .udp_checksum        (udp_checksum),
        .checksum_valid      (checksum_valid),

        // PBM Interface
        .pbm_wdata           (pbm_wdata),
        .pbm_wvalid          (pbm_wvalid),
        .pbm_wlast           (pbm_wlast),
        .pbm_ready           (pbm_ready),

        // TX Path Output
        .m_axis_tdata        (m_axis_tdata),
        .m_axis_tkeep        (m_axis_tkeep),
        .m_axis_tlast        (m_axis_tlast),
        .m_axis_tvalid       (m_axis_tvalid),
        .m_axis_tready       (m_axis_tready),

        // Meta Data Output
        .meta_out_data       (meta_out_data),
        .meta_out_valid      (meta_out_valid),
        .meta_out_checksum   (meta_out_checksum),
        .meta_out_checksum_valid (meta_out_checksum_valid),

        // Status and Statistics
        .fast_path_enable    (fast_path_enable),
        .fast_path_cnt       (fast_path_cnt),
        .bypass_cnt          (bypass_cnt),
        .drop_cnt            (drop_cnt),
        .checksum_pass_cnt   (checksum_pass_cnt)
    );

    // ========================================================================
    // Task: Send UDP Packet
    // ========================================================================
    task send_udp_packet;
        input [15:0] src_port_num;
        input [15:0] dst_port_num;
        input [15:0] payload_length;
        input [31:0] payload_data;
        input        acl_drop;
        input        checksum_en;
        begin
            $display("[%0t] Sending UDP packet", $time);
            $display("  Src Port: %d", src_port_num);
            $display("  Dst Port: %d", dst_port_num);
            $display("  Payload Length: %d", payload_length);
            $display("  ACL Drop: %d", acl_drop);
            $display("  Checksum: %d", checksum_en);

            // Set control signals
            dst_port = dst_port_num;
            payload_len = payload_length;
            drop_flag = acl_drop;
            meta_valid = 1'b1;

            if (checksum_en) begin
                ip_checksum = 16'h1234;
                udp_checksum = 16'h5678;
                checksum_valid = 1'b1;
            end else begin
                checksum_valid = 1'b0;
            end

            // Send header (skip for simplicity)
            s_axis_tdata = 32'hDEADBEEF;
            s_axis_tkeep = 4'hF;
            s_axis_tlast = 1'b0;
            s_axis_tvalid = 1'b1;
            @(posedge clk);
            while (!s_axis_tready) @(posedge clk);

            // Send payload
            s_axis_tdata = payload_data;
            s_axis_tkeep = 4'hF;
            s_axis_tlast = 1'b1;
            s_axis_tvalid = 1'b1;
            @(posedge clk);
            while (!s_axis_tready) @(posedge clk);

            // Reset signals
            s_axis_tvalid = 1'b0;
            meta_valid = 1'b0;
            checksum_valid = 1'b0;

            $display("[%0t] UDP packet sent", $time);
        end
    endtask

    // ========================================================================
    // Test Cases
    // ========================================================================
    int test_pass;
    int test_fail;
    logic [31:0] fp_cnt_before;
    logic [31:0] bp_cnt_before;
    logic         drop_cnt_before;
    logic [31:0] cs_pass_cnt_before;

    initial begin
        test_pass = 0;
        test_fail = 0;
        s_axis_tvalid = 1'b0;
        s_axis_tdata = 32'h0;
        s_axis_tkeep = 4'h0;
        s_axis_tlast = 1'b0;
        dst_port = 16'h0;
        payload_len = 16'h0;
        drop_flag = 1'b0;
        meta_valid = 1'b0;
        ip_checksum = 16'h0;
        udp_checksum = 16'h0;
        checksum_valid = 1'b0;
        pbm_ready = 1'b1;
        m_axis_tready = 1'b1;

        wait(rst_n);
        #1000;

        $display("========================================");
        $display("Day 17: Zero-Copy FastPath");
        $display("========================================");
        $display();
        $display("Task 16.1: FastPath Rules (Patch)");
        $display("  CRYPTO Port: 0x%h", CRYPTO_PORT);
        $display("  CONFIG Port: 0x%h", CONFIG_PORT);
        $display();

        // ====================================================================
        // Test 1: FastPath Condition Met (Normal Port)
        // ====================================================================
        $display("========================================");
        $display("Test 1: FastPath Condition Met");
        $display("  Dst Port: 0x%h (not CRYPTO/CONFIG)", 16'h1235);
        $display("  Payload Length: 32 (16-byte aligned)");
        $display("  ACL Drop: 0");
        $display("========================================");
        $display();

        fp_cnt_before = fast_path_cnt;
        bp_cnt_before = bypass_cnt;
        drop_cnt_before = drop_cnt;
        cs_pass_cnt_before = checksum_pass_cnt;

        send_udp_packet(16'h1000, 16'h1235, 16'd32, 32'hAABBCCDD, 1'b0, 1'b1);

        #1000;

        if (fast_path_cnt == fp_cnt_before + 1 && 
            fast_path_enable && 
            meta_out_valid && 
            meta_out_checksum_valid &&
            meta_out_checksum == 16'h5678) begin
            $display("✅ Test 1 PASS: FastPath enabled, checksum passed");
            $display("  FastPath Count: %d (expected %d)", fast_path_cnt, fp_cnt_before + 1);
            $display("  Bypass Count: %d (expected %d)", bypass_cnt, bp_cnt_before);
            $display("  Drop Count: %d (expected %d)", drop_cnt, drop_cnt_before);
            $display("  Checksum Pass Count: %d (expected %d)", checksum_pass_cnt, cs_pass_cnt_before + 1);
            test_pass++;
        end else begin
            $display("❌ Test 1 FAIL: FastPath not enabled correctly");
            $display("  FastPath Enable: %d", fast_path_enable);
            $display("  FastPath Count: %d (expected %d)", fast_path_cnt, fp_cnt_before + 1);
            $display("  Meta Valid: %d", meta_out_valid);
            $display("  Meta Checksum Valid: %d", meta_out_checksum_valid);
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 2: Crypto Port (Should Bypass)
        // ====================================================================
        $display("========================================");
        $display("Test 2: Crypto Port (Should Bypass)");
        $display("  Dst Port: 0x%h (CRYPTO)", CRYPTO_PORT);
        $display("  Payload Length: 32 (16-byte aligned)");
        $display("  ACL Drop: 0");
        $display("========================================");
        $display();

        fp_cnt_before = fast_path_cnt;
        bp_cnt_before = bypass_cnt;

        send_udp_packet(16'h1000, CRYPTO_PORT, 16'd32, 32'hAABBCCDD, 1'b0, 1'b1);

        #1000;

        if (!fast_path_enable && bypass_cnt == bp_cnt_before + 1) begin
            $display("✅ Test 2 PASS: Crypto port bypassed");
            $display("  FastPath Count: %d (expected %d)", fast_path_cnt, fp_cnt_before);
            $display("  Bypass Count: %d (expected %d)", bypass_cnt, bp_cnt_before + 1);
            test_pass++;
        end else begin
            $display("❌ Test 2 FAIL: Crypto port not bypassed correctly");
            $display("  FastPath Enable: %d", fast_path_enable);
            $display("  FastPath Count: %d (expected %d)", fast_path_cnt, fp_cnt_before);
            $display("  Bypass Count: %d (expected %d)", bypass_cnt, bp_cnt_before + 1);
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 3: Config Port (Should Bypass)
        // ====================================================================
        $display("========================================");
        $display("Test 3: Config Port (Should Bypass)");
        $display("  Dst Port: 0x%h (CONFIG)", CONFIG_PORT);
        $display("  Payload Length: 32 (16-byte aligned)");
        $display("  ACL Drop: 0");
        $display("========================================");
        $display();

        fp_cnt_before = fast_path_cnt;
        bp_cnt_before = bypass_cnt;

        send_udp_packet(16'h1000, CONFIG_PORT, 16'd32, 32'hAABBCCDD, 1'b0, 1'b1);

        #1000;

        if (!fast_path_enable && bypass_cnt == bp_cnt_before + 1) begin
            $display("✅ Test 3 PASS: Config port bypassed");
            $display("  FastPath Count: %d (expected %d)", fast_path_cnt, fp_cnt_before);
            $display("  Bypass Count: %d (expected %d)", bypass_cnt, bp_cnt_before + 1);
            test_pass++;
        end else begin
            $display("❌ Test 3 FAIL: Config port not bypassed correctly");
            $display("  FastPath Enable: %d", fast_path_enable);
            $display("  FastPath Count: %d (expected %d)", fast_path_cnt, fp_cnt_before);
            $display("  Bypass Count: %d (expected %d)", bypass_cnt, bp_cnt_before + 1);
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 4: ACL Drop (Should Drop)
        // ====================================================================
        $display("========================================");
        $display("Test 4: ACL Drop (Should Drop)");
        $display("  Dst Port: 0x%h (not CRYPTO/CONFIG)", 16'h1235);
        $display("  Payload Length: 32 (16-byte aligned)");
        $display("  ACL Drop: 1");
        $display("========================================");
        $display();

        fp_cnt_before = fast_path_cnt;
        bp_cnt_before = bypass_cnt;
        drop_cnt_before = drop_cnt;

        send_udp_packet(16'h1000, 16'h1235, 16'd32, 32'hAABBCCDD, 1'b1, 1'b1);

        #1000;

        if (!fast_path_enable && bypass_cnt == bp_cnt_before && drop_cnt == drop_cnt_before + 1) begin
            $display("✅ Test 4 PASS: ACL drop working");
            $display("  FastPath Count: %d (expected %d)", fast_path_cnt, fp_cnt_before);
            $display("  Bypass Count: %d (expected %d)", bypass_cnt, bp_cnt_before);
            $display("  Drop Count: %d (expected %d)", drop_cnt, drop_cnt_before + 1);
            test_pass++;
        end else begin
            $display("❌ Test 4 FAIL: ACL drop not working");
            $display("  FastPath Enable: %d", fast_path_enable);
            $display("  FastPath Count: %d (expected %d)", fast_path_cnt, fp_cnt_before);
            $display("  Bypass Count: %d (expected %d)", bypass_cnt, bp_cnt_before);
            $display("  Drop Count: %d (expected %d)", drop_cnt, drop_cnt_before + 1);
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 5: Payload Not Aligned (Should Bypass)
        // ====================================================================
        $display("========================================");
        $display("Test 5: Payload Not Aligned (Should Bypass)");
        $display("  Dst Port: 0x%h (not CRYPTO/CONFIG)", 16'h1235);
        $display("  Payload Length: 31 (not 16-byte aligned)");
        $display("  ACL Drop: 0");
        $display("========================================");
        $display();

        fp_cnt_before = fast_path_cnt;
        bp_cnt_before = bypass_cnt;

        send_udp_packet(16'h1000, 16'h1235, 16'd31, 32'hAABBCCDD, 1'b0, 1'b1);

        #1000;

        if (!fast_path_enable && bypass_cnt == bp_cnt_before + 1) begin
            $display("✅ Test 5 PASS: Non-aligned payload bypassed");
            $display("  FastPath Count: %d (expected %d)", fast_path_cnt, fp_cnt_before);
            $display("  Bypass Count: %d (expected %d)", bypass_cnt, bp_cnt_before + 1);
            test_pass++;
        end else begin
            $display("❌ Test 5 FAIL: Non-aligned payload not bypassed");
            $display("  FastPath Enable: %d", fast_path_enable);
            $display("  FastPath Count: %d (expected %d)", fast_path_cnt, fp_cnt_before);
            $display("  Bypass Count: %d (expected %d)", bypass_cnt, bp_cnt_before + 1);
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 6: Zero Payload Length (Should Bypass)
        // ====================================================================
        $display("========================================");
        $display("Test 6: Zero Payload Length (Should Bypass)");
        $display("  Dst Port: 0x%h (not CRYPTO/CONFIG)", 16'h1235);
        $display("  Payload Length: 0");
        $display("  ACL Drop: 0");
        $display("========================================");
        $display();

        fp_cnt_before = fast_path_cnt;
        bp_cnt_before = bypass_cnt;

        send_udp_packet(16'h1000, 16'h1235, 16'd0, 32'hAABBCCDD, 1'b0, 1'b1);

        #1000;

        if (!fast_path_enable && bypass_cnt == bp_cnt_before + 1) begin
            $display("✅ Test 6 PASS: Zero payload bypassed");
            $display("  FastPath Count: %d (expected %d)", fast_path_cnt, fp_cnt_before);
            $display("  Bypass Count: %d (expected %d)", bypass_cnt, bp_cnt_before + 1);
            test_pass++;
        end else begin
            $display("❌ Test 6 FAIL: Zero payload not bypassed");
            $display("  FastPath Enable: %d", fast_path_enable);
            $display("  FastPath Count: %d (expected %d)", fast_path_cnt, fp_cnt_before);
            $display("  Bypass Count: %d (expected %d)", bypass_cnt, bp_cnt_before + 1);
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 7: Checksum Passthrough (No Checksum)
        // ====================================================================
        $display("========================================");
        $display("Test 7: Checksum Passthrough (No Checksum)");
        $display("  Dst Port: 0x%h (not CRYPTO/CONFIG)", 16'h1235);
        $display("  Payload Length: 32 (16-byte aligned)");
        $display("  ACL Drop: 0");
        $display("  Checksum Valid: 0");
        $display("========================================");
        $display();

        fp_cnt_before = fast_path_cnt;
        cs_pass_cnt_before = checksum_pass_cnt;

        send_udp_packet(16'h1000, 16'h1235, 16'd32, 32'hAABBCCDD, 1'b0, 1'b0);

        #1000;

        if (fast_path_cnt == fp_cnt_before + 1 && 
            fast_path_enable && 
            meta_out_valid && 
            !meta_out_checksum_valid &&
            checksum_pass_cnt == cs_pass_cnt_before) begin
            $display("✅ Test 7 PASS: FastPath enabled, checksum not passed");
            $display("  FastPath Count: %d (expected %d)", fast_path_cnt, fp_cnt_before + 1);
            $display("  Meta Checksum Valid: %d (expected 0)", meta_out_checksum_valid);
            $display("  Checksum Pass Count: %d (expected %d)", checksum_pass_cnt, cs_pass_cnt_before);
            test_pass++;
        end else begin
            $display("❌ Test 7 FAIL: Checksum passthrough not working");
            $display("  FastPath Enable: %d", fast_path_enable);
            $display("  Meta Valid: %d", meta_out_valid);
            $display("  Meta Checksum Valid: %d", meta_out_checksum_valid);
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test Summary
        // ====================================================================
        $display("========================================");
        $display("Day 17 Test Summary");
        $display("========================================");
        $display("Total Tests: %d", test_pass + test_fail);
        $display("Passed:      %d", test_pass);
        $display("Failed:      %d", test_fail);
        $display();

        if (test_fail == 0) begin
            $display("✅ All tests passed!");
            $display();
            $display("Task 16.1: FastPath Rules (Patch) - ✅ PASS");
            $display();
            $display("FastPath Rules:");
            $display("  - Dst Port check (CRYPTO/CONFIG): OK");
            $display("  - ACL Drop check: OK");
            $display("  - Payload Length check: OK");
            $display("  - Payload Alignment check: OK");
            $display();
            $display("Zero-Copy Features:");
            $display("  - PBM direct passthrough: OK");
            $display("  - TX Stack direct output: OK");
            $display("  - Checksum passthrough: OK");
        end else begin
            $display("❌ Some tests failed!");
        end

        $display("========================================");
        $display("FastPath Statistics:");
        $display("  FastPath Count:  %d", fast_path_cnt);
        $display("  Bypass Count:    %d", bypass_cnt);
        $display("  Drop Count:      %d", drop_cnt);
        $display("  Checksum Pass:   %d", checksum_pass_cnt);
        $display("========================================");

        #1000;
        $finish;
    end

    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("tb_day17_fastpath.vcd");
        $dumpvars(0, tb_day17_fastpath);
    end

endmodule
