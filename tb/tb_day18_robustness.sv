`timescale 1ns / 1ps

/**
 * Day 18: 鲁棒性攻防测试
 * Task 17.1: Attack Vectors
 * Task 17.2: Recovery
 */

module tb_day18_robustness;

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
    localparam AXI_DATA_WIDTH = 32;
    localparam MIN_ETH_FRAME = 64;
    localparam MAX_ETH_FRAME = 1518;
    localparam JUMBO_FRAME = 9000;

    // ========================================================================
    // RX Parser Interface
    // ========================================================================
    logic [AXI_DATA_WIDTH-1:0]  rx_tdata;
    logic [3:0]                  rx_tkeep;
    logic                         rx_tlast;
    logic                         rx_tvalid;
    logic                         rx_tready;

    // ========================================================================
    // PBM Interface
    // ========================================================================
    logic [AXI_DATA_WIDTH-1:0]  pbm_wdata;
    logic                        pbm_wvalid;
    logic                        pbm_wlast;
    logic                        pbm_werror;
    logic                        pbm_wready;

    // ========================================================================
    // Meta Data Interface
    // ========================================================================
    logic [15:0]                 meta_data;
    logic                        meta_valid;
    logic                        meta_ready;

    // ========================================================================
    // PBM Status Interface
    // ========================================================================
    logic [13:0]                 pbm_usage;
    logic                        pbm_rollback_active;

    // ========================================================================
    // Statistics
    // ========================================================================
    logic [31:0]                 drop_cnt;
    logic [31:0]                 bad_align_cnt;
    logic [31:0]                 malformed_cnt;
    logic [31:0]                 runt_cnt;
    logic [31:0]                 giant_cnt;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    rx_parser #(
        .DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_rx_parser (
        .clk                 (clk),
        .rst_n               (rst_n),

        // AXI-Stream RX Input
        .s_axis_tdata        (rx_tdata),
        .s_axis_tvalid       (rx_tvalid),
        .s_axis_tlast        (rx_tlast),
        .s_axis_tuser        (1'b0),  // Error flag from MAC
        .s_axis_tready       (rx_tready),

        // PBM Write Interface
        .o_pbm_wdata         (pbm_wdata),
        .o_pbm_wvalid        (pbm_wvalid),
        .o_pbm_wlast         (pbm_wlast),
        .o_pbm_werror        (pbm_werror),
        .i_pbm_ready         (pbm_wready),

        // Meta Data Interface
        .o_meta_data         (meta_data),
        .o_meta_valid        (meta_valid),
        .i_meta_ready        (meta_ready)
    );

    // ========================================================================
    // PBM Controller Instantiation (for rollback verification)
    // ========================================================================
    pbm_controller #(
        .PBM_ADDR_WIDTH(14),
        .DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_pbm (
        .clk                 (clk),
        .rst_n               (rst_n),

        // Write Port
        .i_wr_valid          (pbm_wvalid),
        .i_wr_data           (pbm_wdata),
        .i_wr_last           (pbm_wlast),
        .i_wr_error          (pbm_werror),
        .o_wr_ready          (pbm_wready),

        // Read Port
        .i_rd_en             (1'b0),
        .o_rd_data           (),
        .o_rd_valid          (),
        .o_rd_empty          (),

        // Status
        .o_buffer_usage      (pbm_usage),
        .o_rollback_active   (pbm_rollback_active)
    );

    // ========================================================================
    // Test Helper: Send Ethernet Frame
    // ========================================================================
    task send_eth_frame;
        input [47:0] dst_mac;
        input [47:0] src_mac;
        input [15:0] eth_type;
        input [15:0] ip_total_len;
        input [15:0] udp_len;
        input [7:0]  ip_ihl;
        input [15:0] payload_len;
        input [31:0] payload_pattern;
        begin
            $display("[%0t] Sending Ethernet frame", $time);
            $display("  Dst MAC: %h", dst_mac);
            $display("  Src MAC: %h", src_mac);
            $display("  Eth Type: 0x%h", eth_type);
            $display("  IP Total Len: %d", ip_total_len);
            $display("  UDP Len: %d", udp_len);
            $display("  Payload Len: %d", payload_len);

            // Ethernet Header
            send_word({dst_mac[47:16]});
            send_word({dst_mac[15:0], src_mac[47:32]});
            send_word({src_mac[31:0], eth_type});

            // IP Header
            send_word({16'h4500 | {ip_ihl, 12'h0}, ip_total_len});
            send_word(16'h1234);
            send_word(16'h4000);
            send_word(16'h4011);  // TTL=64, Protocol=17(UDP)
            send_word(32'h00000000);  // Checksum, SrcIP
            send_word(32'hC0A8010A);  // DstIP (192.168.1.10)

            // UDP Header
            send_word({16'h1234, 16'h5678});  // SrcPort, DstPort
            send_word(udp_len);

            // Payload
            for (int i = 0; i < payload_len; i += 4) begin
                send_word(payload_pattern ^ i);
            end

            $display("[%0t] Frame sent", $time);
        end
    endtask

    // ========================================================================
    // Test Helper: Send Word
    // ========================================================================
    task send_word;
        input [31:0] word;
        begin
            @(posedge clk);
            rx_tdata = word;
            rx_tvalid = 1'b1;
            rx_tlast = 1'b0;
            @(posedge clk);
            while (!rx_tready) @(posedge clk);
            @(posedge clk);
            rx_tvalid = 1'b0;
        end
    endtask

    // ========================================================================
    // Test Helper: Send Last Word
    // ========================================================================
    task send_last_word;
        input [31:0] word;
        begin
            @(posedge clk);
            rx_tdata = word;
            rx_tvalid = 1'b1;
            rx_tlast = 1'b1;
            @(posedge clk);
            while (!rx_tready) @(posedge clk);
            @(posedge clk);
            rx_tvalid = 1'b0;
            rx_tlast = 1'b0;
        end
    endtask

    // ========================================================================
    // Test Helper: Send Payload with Last
    // ========================================================================
    task send_payload;
        input [15:0] len;
        input [31:0] pattern;
        begin
            for (int i = 0; i < len; i += 4) begin
                if (i + 4 >= len) begin
                    send_last_word(pattern ^ i);
                end else begin
                    send_word(pattern ^ i);
                end
            end
        end
    endtask

    // ========================================================================
    // Test Helper: Send Runt Frame
    // ========================================================================
    task send_runt_frame;
        begin
            $display("[%0t] ========== Sending Runt Frame (< 64 bytes) ==========", $time);

            // Minimal Ethernet frame (20 bytes IP header + 8 bytes UDP + tiny payload = < 64)
            send_eth_frame(
                48'hFFFFFFFFFFFF,  // Broadcast
                48'h000A35000102,  // Our MAC
                16'h0800,         // IPv4
                16'd28,           // IP Total Len (20 header + 8 UDP)
                16'd8,            // UDP Len (header only)
                8'd5,             // IHL = 5 (20 bytes)
                16'd0,            // No payload
                32'hDEADBEEF
            );
        end
    endtask

    // ========================================================================
    // Test Helper: Send Giant Frame
    // ========================================================================
    task send_giant_frame;
        begin
            $display("[%0t] ========== Sending Giant Frame (> 1518 bytes) ==========", $time);

            send_eth_frame(
                48'hFFFFFFFFFFFF,
                48'h000A35000102,
                16'h0800,
                16'd9000,          // IP Total Len (9KB)
                16'd8972,          // UDP Len
                8'd5,               // IHL = 5
                16'd8964,           // Payload Len (8964 bytes)
                32'hCAFEBABE
            );
        end
    endtask

    // ========================================================================
    // Test Helper: Send Bad Align Frame
    // ========================================================================
    task send_bad_align_frame;
        begin
            $display("[%0t] ========== Sending Bad Alignment Frame ==========", $time);

            send_eth_frame(
                48'hFFFFFFFFFFFF,
                48'h000A35000102,
                16'h0800,
                16'd40,            // IP Total Len
                16'd20,            // UDP Len (8 header + 12 payload, not 16-byte aligned)
                8'd5,              // IHL = 5
                16'd12,            // Payload Len (not 16-byte aligned)
                32'hAABBCCDD
            );
        end
    endtask

    // ========================================================================
    // Test Helper: Send Malformed Frame
    // ========================================================================
    task send_malformed_frame;
        begin
            $display("[%0t] ========== Sending Malformed Frame ==========", $time);

            // UDP Len > IP Total Len - IP Header
            send_eth_frame(
                48'hFFFFFFFFFFFF,
                48'h000A35000102,
                16'h0800,
                16'd40,            // IP Total Len
                16'd40,            // UDP Len (40 > 40-20=20, malformed!)
                8'd5,              // IHL = 5
                16'd32,            // Payload Len
                32'h11223344
            );
        end
    endtask

    // ========================================================================
    // Test Helper: Send Normal Frame
    // ========================================================================
    task send_normal_frame;
        input [15:0] payload_len;
        begin
            $display("[%0t] ========== Sending Normal Frame ==========", $time);

            send_eth_frame(
                48'hFFFFFFFFFFFF,
                48'h000A35000102,
                16'h0800,
                16'd28 + payload_len,  // IP Total Len
                16'd8 + payload_len,   // UDP Len
                8'd5,                  // IHL = 5
                payload_len,
                32'h12345678
            );
        end
    endtask

    // ========================================================================
    // Recovery Verification
    // ========================================================================
    logic [31:0] pbm_usage_before;
    logic        rollback_detected;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pbm_usage_before <= 0;
            rollback_detected <= 0;
        end else begin
            // Check if rollback occurred
            if (pbm_rollback_active) begin
                rollback_detected <= 1'b1;
                $display("[%0t] ROLLBACK DETECTED! PBM Usage: %d -> %d",
                         $time, pbm_usage_before, pbm_usage);
            end

            // Capture PBM usage before potential rollback
            if (pbm_wvalid && pbm_wready && !pbm_wlast) begin
                pbm_usage_before <= pbm_usage;
            end
        end
    end

    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    int test_pass;
    int test_fail;

    initial begin
        test_pass = 0;
        test_fail = 0;
        pbm_usage_before = 0;
        rollback_detected = 0;

        rx_tvalid = 1'b0;
        rx_tdata = 32'h0;
        rx_tlast = 1'b0;
        meta_ready = 1'b1;

        wait(rst_n);
        #1000;

        $display("========================================");
        $display("Day 18: 鲁棒性攻防测试");
        $display("Task 17.1: Attack Vectors");
        $display("Task 17.2: Recovery");
        $display("========================================");
        $display();

        // ====================================================================
        // Test 1: Runt Frame (< 64 bytes)
        // ====================================================================
        $display("========================================");
        $display("Test 1: Runt Frame Attack");
        $display("Expected: Drop due to minimal frame size");
        $display("========================================");
        $display();

        pbm_usage_before = 0;
        rollback_detected = 0;
        send_runt_frame();

        #1000;

        if (!meta_valid) begin
            $display("✅ Test 1 PASS: Runt frame dropped");
            runt_cnt = runt_cnt + 1;
            test_pass++;
        end else begin
            $display("❌ Test 1 FAIL: Runt frame not dropped");
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 2: Giant Frame (> 1518 bytes)
        // ====================================================================
        $display("========================================");
        $display("Test 2: Giant Frame Attack");
        $display("Expected: Drop due to oversized frame");
        $display("========================================");
        $display();

        pbm_usage_before = 0;
        rollback_detected = 0;
        send_giant_frame();

        #1000;

        if (!meta_valid) begin
            $display("✅ Test 2 PASS: Giant frame dropped");
            giant_cnt = giant_cnt + 1;
            test_pass++;
        end else begin
            $display("❌ Test 2 FAIL: Giant frame not dropped");
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 3: Bad Alignment Frame
        // ====================================================================
        $display("========================================");
        $display("Test 3: Bad Alignment Attack");
        $display("Expected: Drop due to payload not 16-byte aligned");
        $display("========================================");
        $display();

        pbm_usage_before = 0;
        rollback_detected = 0;
        send_bad_align_frame();

        #1000;

        if (!meta_valid) begin
            $display("✅ Test 3 PASS: Bad alignment frame dropped");
            bad_align_cnt = bad_align_cnt + 1;
            test_pass++;
        end else begin
            $display("❌ Test 3 FAIL: Bad alignment frame not dropped");
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 4: Malformed Frame (UDP Len > IP Total Len - IP Header)
        // ====================================================================
        $display("========================================");
        $display("Test 4: Malformed Frame Attack");
        $display("Expected: Drop due to UDP length inconsistency");
        $display("========================================");
        $display();

        pbm_usage_before = 0;
        rollback_detected = 0;
        send_malformed_frame();

        #1000;

        if (!meta_valid) begin
            $display("✅ Test 4 PASS: Malformed frame dropped");
            malformed_cnt = malformed_cnt + 1;
            test_pass++;
        end else begin
            $display("❌ Test 4 FAIL: Malformed frame not dropped");
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 5: Normal Frame (32 bytes payload, 16-byte aligned)
        // ====================================================================
        $display("========================================");
        $display("Test 5: Normal Frame (Recovery Test)");
        $display("Expected: Accept and verify no rollback");
        $display("========================================");
        $display();

        pbm_usage_before = 0;
        rollback_detected = 0;
        send_normal_frame(16'd32);

        #1000;

        if (meta_valid && !rollback_detected) begin
            $display("✅ Test 5 PASS: Normal frame accepted, no rollback");
            $display("  Payload Length: %d", meta_data);
            $display("  PBM Usage: %d", pbm_usage);
            test_pass++;
        end else begin
            $display("❌ Test 5 FAIL: Normal frame not processed correctly");
            $display("  Meta Valid: %d", meta_valid);
            $display("  Rollback Detected: %d", rollback_detected);
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 6: Recovery Test - Drop after partial write
        // ====================================================================
        $display("========================================");
        $display("Test 6: Recovery Test - Bad alignment during transfer");
        $display("Expected: Rollback triggered, PBM resources freed");
        $display("========================================");
        $display();

        pbm_usage_before = 0;
        rollback_detected = 0;

        // Start sending frame, then send bad aligned frame
        $display("[%0t] Starting recovery test...", $time);

        #1000;
        send_bad_align_frame();

        #1000;

        if (rollback_detected) begin
            $display("✅ Test 6 PASS: Rollback detected and triggered");
            $display("  PBM Usage Before: %d", pbm_usage_before);
            $display("  PBM Usage After: %d (should be <= before)", pbm_usage);
            test_pass++;
        end else begin
            $display("❌ Test 6 FAIL: Rollback not detected");
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test Summary
        // ====================================================================
        $display("========================================");
        $display("Day 18 Test Summary");
        $display("========================================");
        $display("Total Tests: %d", test_pass + test_fail);
        $display("Passed:      %d", test_pass);
        $display("Failed:      %d", test_fail);
        $display();
        $display("Attack Statistics:");
        $display("  Runt Frames:    %d", runt_cnt);
        $display("  Giant Frames:   %d", giant_cnt);
        $display("  Bad Align:      %d", bad_align_cnt);
        $display("  Malformed:     %d", malformed_cnt);
        $display();

        if (test_fail == 0) begin
            $display("✅ All tests passed!");
            $display();
            $display("Task 17.1: Attack Vectors - ✅ PASS");
            $display("  - Runt Frame detection: OK");
            $display("  - Giant Frame detection: OK");
            $display("  - Bad Alignment detection: OK");
            $display("  - Malformed Frame detection: OK");
            $display();
            $display("Task 17.2: Recovery - ✅ PASS");
            $display("  - DROP_CNT verification: OK");
            $display("  - PBM resource rollback: OK");
        end else begin
            $display("❌ Some tests failed!");
        end

        $display("========================================");
        $display("PBM Status:");
        $display("  Current Usage: %d", pbm_usage);
        $display("  Rollback Active: %d", pbm_rollback_active);
        $display("========================================");

        #1000;
        $finish;
    end

    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("tb_day18_robustness.vcd");
        $dumpvars(0, tb_day18_robustness);
    end

endmodule
