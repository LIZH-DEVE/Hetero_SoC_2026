`timescale 1ns / 1ps

/**
 * Day 15: Hardware Security Module (HSM) Testbench
 * Task 14.1: Config Packet Authentication
 * Task 14.2: Key Vault with DNA Binding
 */

module tb_day15_hsm;

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
    // Config Packet Auth Testbench
    // ========================================================================
    logic [31:0]  cfg_s_tdata;
    logic [3:0]   cfg_s_tkeep;
    logic         cfg_s_tlast;
    logic         cfg_s_tvalid;
    logic         cfg_s_tready;

    logic [31:0]  cfg_m_tdata;
    logic [3:0]   cfg_m_tkeep;
    logic         cfg_m_tlast;
    logic         cfg_m_tvalid;
    logic         cfg_m_tready;

    logic [31:0]  auth_success_cnt;
    logic [31:0]  auth_fail_cnt;
    logic [31:0]  replay_fail_cnt;
    logic [15:0]  last_seq_id;
    logic         error_flag;

    // ========================================================================
    // Key Vault Testbench
    // ========================================================================
    logic [56:0]  dna_out;
    logic [127:0]  user_key_in;
    logic         user_key_valid;
    logic [127:0] effective_key_out;
    logic         effective_key_valid;
    logic         dna_lock_enable;
    logic [1:0]   lock_status;
    logic         system_locked;
    logic         tamper_detected;
    logic [56:0]  stored_dna;
    logic [127:0] stored_hash;
    logic [31:0]  tamper_counter;

    // ========================================================================
    // DNA Simulation
    // ========================================================================
    logic [56:0]  simulated_dna;

    assign simulated_dna = 57'h123456789ABCDE;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    config_packet_auth u_config_auth (
        .clk                 (clk),
        .rst_n               (rst_n),
        .s_axis_tdata        (cfg_s_tdata),
        .s_axis_tkeep       (cfg_s_tkeep),
        .s_axis_tlast       (cfg_s_tlast),
        .s_axis_tvalid      (cfg_s_tvalid),
        .s_axis_tready      (cfg_s_tready),
        .m_axis_tdata       (cfg_m_tdata),
        .m_axis_tkeep       (cfg_m_tkeep),
        .m_axis_tlast       (cfg_m_tlast),
        .m_axis_tvalid      (cfg_m_tvalid),
        .m_axis_tready      (cfg_m_tready),
        .auth_success_cnt   (auth_success_cnt),
        .auth_fail_cnt     (auth_fail_cnt),
        .replay_fail_cnt   (replay_fail_cnt),
        .last_seq_id       (last_seq_id),
        .error_flag        (error_flag)
    );

    key_vault u_key_vault (
        .clk               (clk),
        .rst_n             (rst_n),
        .dna_out           (dna_out),
        .user_key_in       (user_key_in),
        .user_key_valid    (user_key_valid),
        .effective_key_out (effective_key_out),
        .effective_key_valid(effective_key_valid),
        .dna_lock_enable   (dna_lock_enable),
        .lock_status       (lock_status),
        .system_locked     (system_locked),
        .tamper_detected  (tamper_detected),
        .stored_dna        (stored_dna),
        .stored_hash       (stored_hash),
        .tamper_counter   (tamper_counter)
    );

    // ========================================================================
    // Task: Send Config Packet
    // ========================================================================
    task send_config_packet;
        input [31:0] magic;
        input [15:0] seq_id;
        input [15:0] payload_len;
        begin
            $display("[%0t] Sending config packet: Magic=0x%h, SeqID=%d, Len=%d",
                     $time, magic, seq_id, payload_len);

            // Send magic number and seq_id
            cfg_s_tdata = {seq_id, magic[15:0]};
            cfg_s_tkeep = 4'hF;
            cfg_s_tlast = 1'b0;
            cfg_s_tvalid = 1'b1;
            @(posedge clk);
            while (!cfg_s_tready) @(posedge clk);
            cfg_s_tvalid = 1'b0;

            // Send magic number upper
            cfg_s_tdata = {16'h0, magic[31:16]};
            cfg_s_tkeep = 4'hF;
            cfg_s_tlast = 1'b0;
            cfg_s_tvalid = 1'b1;
            @(posedge clk);
            while (!cfg_s_tready) @(posedge clk);
            cfg_s_tvalid = 1'b0;

            // Send payload
            for (int i = 0; i < payload_len; i++) begin
                cfg_s_tdata = 32'hAABBCC00 + i;
                cfg_s_tkeep = 4'hF;
                cfg_s_tlast = (i == payload_len - 1);
                cfg_s_tvalid = 1'b1;
                @(posedge clk);
                while (!cfg_s_tready) @(posedge clk);
                cfg_s_tvalid = 1'b0;
            end

            $display("[%0t] Config packet sent", $time);
        end
    endtask

    // ========================================================================
    // Task: Send User Key
    // ========================================================================
    task send_user_key;
        input [127:0] key;
        begin
            $display("[%0t] Sending user key: 0x%h", $time, key);

            user_key_in = key;
            user_key_valid = 1'b1;
            @(posedge clk);
            @(posedge clk);
            user_key_valid = 1'b0;

            $display("[%0t] User key sent", $time);
        end
    endtask

    // ========================================================================
    // Test Cases
    // ========================================================================
    int test_pass;
    int test_fail;

    initial begin
        test_pass = 0;
        test_fail = 0;
        cfg_s_tvalid = 1'b0;
        cfg_s_tdata = 32'h0;
        cfg_s_tkeep = 4'h0;
        cfg_s_tlast = 1'b0;
        cfg_m_tready = 1'b1;
        dna_lock_enable = 1'b0;
        user_key_in = 128'h0;
        user_key_valid = 1'b0;

        wait(rst_n);
        #1000;

        $display("========================================");
        $display("Day 15: Hardware Security Module");
        $display("========================================");
        $display();

        // ====================================================================
        // Test 1: Config Packet Auth - Valid Magic
        // ====================================================================
        $display("========================================");
        $display("Test 1: Config Packet Auth - Valid Magic");
        $display("========================================");
        $display();

        send_config_packet(32'hDEADBEEF, 16'd1, 16'd4);

        #500;

        if (auth_success_cnt == 32'd1 && auth_fail_cnt == 32'd0) begin
            $display("[%0t] ✅ Test 1 PASS: Valid magic accepted", $time);
            test_pass++;
        end else begin
            $display("[%0t] ❌ Test 1 FAIL: Expected success_cnt=1, got %d",
                     $time, auth_success_cnt);
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 2: Config Packet Auth - Invalid Magic
        // ====================================================================
        $display("========================================");
        $display("Test 2: Config Packet Auth - Invalid Magic");
        $display("========================================");
        $display();

        send_config_packet(32'hBADBEEF, 16'd2, 16'd4);

        #500;

        if (auth_fail_cnt == 32'd1) begin
            $display("[%0t] ✅ Test 2 PASS: Invalid magic rejected", $time);
            test_pass++;
        end else begin
            $display("[%0t] ❌ Test 2 FAIL: Expected fail_cnt=1, got %d",
                     $time, auth_fail_cnt);
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 3: Config Packet Auth - Anti-Replay
        // ====================================================================
        $display("========================================");
        $display("Test 3: Config Packet Auth - Anti-Replay");
        $display("========================================");
        $display();

        send_config_packet(32'hDEADBEEF, 16'd1, 16'd4);

        #500;

        if (replay_fail_cnt > 32'd0) begin
            $display("[%0t] ✅ Test 3 PASS: Replay detected", $time);
            test_pass++;
        end else begin
            $display("[%0t] ❌ Test 3 FAIL: Expected replay detection", $time);
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 4: Config Packet Auth - Sequential IDs
        // ====================================================================
        $display("========================================");
        $display("Test 4: Config Packet Auth - Sequential IDs");
        $display("========================================");
        $display();

        send_config_packet(32'hDEADBEEF, 16'd3, 16'd4);
        #500;
        send_config_packet(32'hDEADBEEF, 16'd4, 16'd4);
        #500;

        if (auth_success_cnt == 32'd3) begin
            $display("[%0t] ✅ Test 4 PASS: Sequential IDs accepted", $time);
            test_pass++;
        end else begin
            $display("[%0t] ❌ Test 4 FAIL: Expected success_cnt=3, got %d",
                     $time, auth_success_cnt);
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 5: Key Vault - DNA Binding
        // ====================================================================
        $display("========================================");
        $display("Test 5: Key Vault - DNA Binding");
        $display("========================================");
        $display();

        dna_lock_enable = 1'b1;
        #1000;

        if (!system_locked) begin
            $display("[%0t] ✅ Test 5 PASS: DNA matched, system unlocked", $time);
            test_pass++;
        end else begin
            $display("[%0t] ❌ Test 5 FAIL: System locked unexpectedly", $time);
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test 6: Key Vault - User Key Derivation
        // ====================================================================
        $display("========================================");
        $display("Test 6: Key Vault - User Key Derivation");
        $display("========================================");
        $display();

        send_user_key(128'h0123456789ABCDEF0123456789ABCDEF);
        #500;

        if (effective_key_valid && effective_key_out != 128'h0) begin
            $display("[%0t] ✅ Test 6 PASS: Effective key derived", $time);
            $display("[%0t]    Effective Key: 0x%h", $time, effective_key_out);
            test_pass++;
        end else begin
            $display("[%0t] ❌ Test 6 FAIL: Key derivation failed", $time);
            test_fail++;
        end
        $display();

        // ====================================================================
        // Test Summary
        // ====================================================================
        $display("========================================");
        $display("Day 15 Test Summary");
        $display("========================================");
        $display("Total Tests: %d", test_pass + test_fail);
        $display("Passed:      %d", test_pass);
        $display("Failed:      %d", test_fail);
        $display();

        if (test_fail == 0) begin
            $display("✅ All tests passed!");
            $display();
            $display("Task 14.1: Config Packet Auth - ✅ PASS");
            $display("  - Magic Number Authentication: OK");
            $display("  - Anti-Replay Protection: OK");
            $display();
            $display("Task 14.2: Key Vault - ✅ PASS");
            $display("  - DNA Binding: OK");
            $display("  - Key Derivation: OK");
            $display("  - System Lock: OK");
        end else begin
            $display("❌ Some tests failed!");
        end

        $display("========================================");
        $display("Config Auth Statistics:");
        $display("  Success: %d", auth_success_cnt);
        $display("  Fail:    %d", auth_fail_cnt);
        $display("  Replay:  %d", replay_fail_cnt);
        $display("  Last Seq:%d", last_seq_id);
        $display();
        $display("Key Vault Status:");
        $display("  Locked:   %d", system_locked);
        $display("  Lock St:  %d", lock_status);
        $display("  Tamper:   %d", tamper_detected);
        $display("  Stored DNA: 0x%h", stored_dna);
        $display("========================================");

        #1000;
        $finish;
    end

    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("tb_day15_hsm.vcd");
        $dumpvars(0, tb_day15_hsm);
    end

endmodule
