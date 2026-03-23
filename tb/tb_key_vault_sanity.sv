`timescale 1ns / 1ps

module tb_key_vault_sanity;

    logic clk;
    logic rst_n;
    logic [56:0] dna_out;
    logic [127:0] user_key_in;
    logic user_key_valid;
    logic [127:0] effective_key_out;
    logic effective_key_valid;
    logic dna_lock_enable;
    logic [1:0] lock_status;
    logic system_locked;
    logic tamper_detected;
    logic [56:0] stored_dna;
    logic [127:0] stored_hash;
    logic [31:0] tamper_counter;

    key_vault dut (
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

    initial begin
        user_key_in = '0;
        user_key_valid = 1'b0;
        dna_lock_enable = 1'b0;

        wait(rst_n);
        repeat (4) @(posedge clk);

        dna_lock_enable <= 1'b1;
        repeat (4) @(posedge clk);

        if (stored_dna == '0 || system_locked) begin
            $fatal(1, "DNA bind/unlock failed: stored_dna=%h system_locked=%0d lock_status=%0d",
                   stored_dna, system_locked, lock_status);
        end

        user_key_in <= 128'h0011_2233_4455_6677_8899_AABB_CCDD_EEFF;
        user_key_valid <= 1'b1;
        @(posedge clk);
        #1;
        if (!effective_key_valid) begin
            $fatal(1, "Derived key valid pulse missing during request: valid=%0d state=%0d",
                   effective_key_valid, lock_status);
        end

        user_key_valid <= 1'b0;
        @(posedge clk);
        #1;

        if (effective_key_out == '0 || stored_hash == '0 || effective_key_out != stored_hash) begin
            $fatal(1, "Derived key generation failed: out=%h stored=%h",
                   effective_key_out, stored_hash);
        end

        dna_lock_enable <= 1'b0;
        repeat (2) @(posedge clk);

        if (effective_key_out != '0) begin
            $fatal(1, "Key should be cleared when lock is disabled: out=%h", effective_key_out);
        end

        if (tamper_detected || tamper_counter != 32'd0) begin
            $fatal(1, "Unexpected tamper detection: tamper=%0d count=%0d",
                   tamper_detected, tamper_counter);
        end

        $display("PASS: key_vault sanity");
        $finish;
    end

endmodule
