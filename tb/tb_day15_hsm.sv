`timescale 1ns / 1ps

/**
 * Day 15: Hardware Security Module verification
 *
 * Scope:
 * - Config packet authentication
 * - Key vault DNA binding and key derivation
 */

module tb_day15_hsm;

    logic clk;
    logic rst_n;

    logic [31:0] cfg_s_tdata;
    logic [3:0]  cfg_s_tkeep;
    logic        cfg_s_tlast;
    logic        cfg_s_tvalid;
    logic        cfg_s_tready;

    logic [31:0] cfg_m_tdata;
    logic [3:0]  cfg_m_tkeep;
    logic        cfg_m_tlast;
    logic        cfg_m_tvalid;
    logic        cfg_m_tready;

    logic [31:0] auth_success_cnt;
    logic [31:0] auth_fail_cnt;
    logic [31:0] replay_fail_cnt;
    logic [15:0] last_seq_id;
    logic        error_flag;

    logic [56:0]  dna_out;
    logic [127:0] user_key_in;
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

    int out_words_seen;
    int test_pass;
    int test_fail;

    config_packet_auth u_config_auth (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(cfg_s_tdata),
        .s_axis_tkeep(cfg_s_tkeep),
        .s_axis_tlast(cfg_s_tlast),
        .s_axis_tvalid(cfg_s_tvalid),
        .s_axis_tready(cfg_s_tready),
        .m_axis_tdata(cfg_m_tdata),
        .m_axis_tkeep(cfg_m_tkeep),
        .m_axis_tlast(cfg_m_tlast),
        .m_axis_tvalid(cfg_m_tvalid),
        .m_axis_tready(cfg_m_tready),
        .auth_success_cnt(auth_success_cnt),
        .auth_fail_cnt(auth_fail_cnt),
        .replay_fail_cnt(replay_fail_cnt),
        .last_seq_id(last_seq_id),
        .error_flag(error_flag)
    );

    key_vault u_key_vault (
        .clk(clk),
        .rst_n(rst_n),
        .dna_out(dna_out),
        .user_key_in(user_key_in),
        .user_key_valid(user_key_valid),
        .effective_key_out(effective_key_out),
        .effective_key_valid(effective_key_valid),
        .dna_lock_enable(dna_lock_enable),
        .lock_status(lock_status),
        .system_locked(system_locked),
        .tamper_detected(tamper_detected),
        .stored_dna(stored_dna),
        .stored_hash(stored_hash),
        .tamper_counter(tamper_counter)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        #40;
        rst_n = 1'b1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_words_seen <= 0;
        end else if (cfg_m_tvalid && cfg_m_tready) begin
            out_words_seen <= out_words_seen + 1;
        end
    end

    task automatic record_result(
        input bit cond,
        input string pass_msg,
        input string fail_msg
    );
        begin
            if (cond) begin
                $display("[PASS] %s", pass_msg);
                test_pass++;
            end else begin
                $display("[FAIL] %s", fail_msg);
                test_fail++;
            end
        end
    endtask

    task automatic drive_cfg_word(
        input [31:0] data,
        input        last
    );
        begin
            cfg_s_tdata  <= data;
            cfg_s_tkeep  <= 4'hF;
            cfg_s_tlast  <= last;
            cfg_s_tvalid <= 1'b1;
            do @(posedge clk); while (!cfg_s_tready);
            cfg_s_tvalid <= 1'b0;
            cfg_s_tlast  <= 1'b0;
            cfg_s_tdata  <= '0;
        end
    endtask

    task automatic send_valid_packet(input [15:0] seq_id);
        begin
            drive_cfg_word(32'hDEAD_BEEF, 1'b0);
            drive_cfg_word({16'hCAFE, seq_id}, 1'b0);
            drive_cfg_word(32'h1111_2222, 1'b0);
            drive_cfg_word(32'h3333_4444, 1'b1);
        end
    endtask

    task automatic send_invalid_magic_packet(input [15:0] seq_id);
        begin
            drive_cfg_word(32'hBAAD_BEEF, 1'b0);
            drive_cfg_word({16'hCAFE, seq_id}, 1'b0);
            drive_cfg_word(32'hAAAA_BBBB, 1'b1);
        end
    endtask

    task automatic send_user_key(input [127:0] key);
        begin
            $display("[%0t] Sending user key: 0x%h", $time, key);
            user_key_in <= key;
            user_key_valid <= 1'b1;
            @(posedge clk);
            user_key_valid <= 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        cfg_s_tdata  = '0;
        cfg_s_tkeep  = '0;
        cfg_s_tlast  = 1'b0;
        cfg_s_tvalid = 1'b0;
        cfg_m_tready = 1'b1;
        user_key_in = '0;
        user_key_valid = 1'b0;
        dna_lock_enable = 1'b0;
        test_pass = 0;
        test_fail = 0;

        wait(rst_n);
        repeat (4) @(posedge clk);

        $display("========================================");
        $display("Day 15: Hardware Security Module");
        $display("========================================");

        send_valid_packet(16'd1);
        repeat (4) @(posedge clk);
        record_result(
            auth_success_cnt == 32'd1 && auth_fail_cnt == 32'd0 && replay_fail_cnt == 32'd0 &&
            last_seq_id == 16'd1 && out_words_seen == 4,
            "Config packet auth accepted a valid packet",
            $sformatf("Valid packet mismatch: success=%0d fail=%0d replay=%0d seq=%0d out_words=%0d",
                      auth_success_cnt, auth_fail_cnt, replay_fail_cnt, last_seq_id, out_words_seen)
        );

        send_invalid_magic_packet(16'd2);
        repeat (4) @(posedge clk);
        record_result(
            auth_success_cnt == 32'd1 && auth_fail_cnt == 32'd1 && replay_fail_cnt == 32'd0 &&
            out_words_seen == 4,
            "Config packet auth rejected an invalid magic packet",
            $sformatf("Invalid magic mismatch: success=%0d fail=%0d replay=%0d out_words=%0d",
                      auth_success_cnt, auth_fail_cnt, replay_fail_cnt, out_words_seen)
        );

        send_valid_packet(16'd1);
        repeat (4) @(posedge clk);
        record_result(
            auth_success_cnt == 32'd1 && replay_fail_cnt == 32'd1,
            "Config packet auth detected replayed sequence ID",
            $sformatf("Replay mismatch: success=%0d fail=%0d replay=%0d seq=%0d",
                      auth_success_cnt, auth_fail_cnt, replay_fail_cnt, last_seq_id)
        );

        send_valid_packet(16'd2);
        repeat (4) @(posedge clk);
        record_result(
            auth_success_cnt == 32'd2 && last_seq_id == 16'd2 && out_words_seen == 8,
            "Config packet auth accepted the next valid sequence ID",
            $sformatf("Second valid packet mismatch: success=%0d fail=%0d replay=%0d seq=%0d out_words=%0d",
                      auth_success_cnt, auth_fail_cnt, replay_fail_cnt, last_seq_id, out_words_seen)
        );

        dna_lock_enable <= 1'b1;
        repeat (4) @(posedge clk);
        record_result(
            stored_dna != '0 && !system_locked,
            "Key vault bound DNA and remained unlocked on the matching device",
            $sformatf("DNA bind mismatch: stored_dna=%h system_locked=%0d lock_status=%0d",
                      stored_dna, system_locked, lock_status)
        );

        send_user_key(128'h0011_2233_4455_6677_8899_AABB_CCDD_EEFF);
        record_result(
            effective_key_out != '0 && stored_hash != '0 && !system_locked,
            "Key vault derived a non-zero effective key",
            $sformatf("Derived key mismatch: valid=%0d out=%h stored=%h",
                      effective_key_valid, effective_key_out, stored_hash)
        );

        dna_lock_enable <= 1'b0;
        repeat (2) @(posedge clk);
        record_result(
            effective_key_out == '0 && !tamper_detected && tamper_counter == 32'd0,
            "Key vault cleared the effective key when lock was disabled",
            $sformatf("Lock disable mismatch: out=%h tamper=%0d count=%0d",
                      effective_key_out, tamper_detected, tamper_counter)
        );

        $display("========================================");
        $display("Day 15 Test Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_pass + test_fail);
        $display("Passed:      %0d", test_pass);
        $display("Failed:      %0d", test_fail);

        if (test_fail != 0) begin
            $fatal(1, "Day 15 HSM verification failed with %0d failing tests", test_fail);
        end

        $display("[PASS] Day 15 HSM combined sanity completed");
        $finish;
    end

endmodule
