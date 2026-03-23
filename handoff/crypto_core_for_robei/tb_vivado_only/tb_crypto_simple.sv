`timescale 1ns / 1ps

module tb_crypto_simple;

    localparam integer CLK_PERIOD = 10;

    localparam [255:0] AES128_KEY_EXT = 256'h00000000000000000000000000000000000102030405060708090A0B0C0D0E0F;
    localparam [127:0] AES128_PT      = 128'h00112233445566778899AABBCCDDEEFF;
    localparam [127:0] AES128_CT      = 128'h69C4E0D86A7B0430D8CDB78070B4C55A;

    localparam [255:0] SM4_KEY_EXT    = 256'h000000000000000000000000000000000123456789ABCDEFFEDCBA9876543210;
    localparam [127:0] SM4_PT         = 128'h0123456789ABCDEFFEDCBA9876543210;
    localparam [127:0] SM4_CT         = 128'h681EDF34D206965E86B3E94F536E4246;

    reg         clk;
    reg         rst_n;
    reg         algo_sel;
    reg         encdec;
    reg         start;
    reg         aes256_en;
    reg [31:0]  i_total_len;
    reg [127:0] i_iv;
    reg [7:0]   s_axil_araddr;
    wire [31:0] s_axil_rdata;
    reg [255:0] key;
    reg [127:0] din;
    wire [127:0] dout;
    wire        done;
    wire        busy;

    integer pass_count;
    integer fail_count;

    crypto_engine u_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .algo_sel      (algo_sel),
        .encdec        (encdec),
        .start         (start),
        .i_total_len   (i_total_len),
        .i_iv          (i_iv),
        .done          (done),
        .busy          (busy),
        .s_axil_araddr (s_axil_araddr),
        .s_axil_rdata  (s_axil_rdata),
        .aes256_en     (aes256_en),
        .key           (key),
        .din           (din),
        .dout          (dout)
    );

    initial begin
        clk = 1'b0;
    end

    always #(CLK_PERIOD / 2) clk = ~clk;

    task system_reset;
        begin
            rst_n         = 1'b0;
            algo_sel      = 1'b0;
            encdec        = 1'b1;
            start         = 1'b0;
            aes256_en     = 1'b0;
            i_total_len   = 32'd128;
            i_iv          = 128'd0;
            s_axil_araddr = 8'd0;
            key           = 256'd0;
            din           = 128'd0;
            repeat (10) @(posedge clk);
            rst_n = 1'b1;
            repeat (4) @(posedge clk);
        end
    endtask

    task drive_block;
        input [255:0] key_in;
        input [127:0] data_in;
        input         algo_in;
        input         encdec_in;
        input         aes256_in;
        begin
            wait (!busy);
            @(posedge clk);
            key       <= key_in;
            din       <= data_in;
            algo_sel  <= algo_in;
            encdec    <= encdec_in;
            aes256_en <= aes256_in;
            start     <= 1'b1;
            @(posedge clk);
            start     <= 1'b0;
        end
    endtask

    task wait_done_timeout;
        input integer max_cycles;
        integer cycle_count;
        begin
            cycle_count = 0;
            while (!done && cycle_count < max_cycles) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end

            if (!done) begin
                $display("[FATAL] Timeout waiting for done after %0d cycles", max_cycles);
                $fatal(1);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        $display("\n========================================");
        $display("  Robei Handoff Crypto Smoke Test");
        $display("========================================");

        system_reset();

        $display("\n[TEST 1] AES-128 Encrypt");
        drive_block(AES128_KEY_EXT, AES128_PT, 1'b0, 1'b1, 1'b0);
        wait_done_timeout(120);
        $display("   Plaintext:  %h", AES128_PT);
        $display("   Ciphertext: %h", dout);
        $display("   Expected:   %h", AES128_CT);
        if (dout === AES128_CT) begin
            $display("   -> [PASS] AES encryption correct");
            pass_count = pass_count + 1;
        end else begin
            $display("   -> [FAIL] AES encryption mismatch");
            fail_count = fail_count + 1;
        end

        repeat (8) @(posedge clk);

        $display("\n[TEST 2] AES-128 Decrypt");
        drive_block(AES128_KEY_EXT, AES128_CT, 1'b0, 1'b0, 1'b0);
        wait_done_timeout(120);
        $display("   Ciphertext: %h", AES128_CT);
        $display("   Decrypted:  %h", dout);
        if (dout === AES128_PT) begin
            $display("   -> [PASS] AES decryption correct");
            pass_count = pass_count + 1;
        end else begin
            $display("   -> [FAIL] AES decryption mismatch");
            fail_count = fail_count + 1;
        end

        repeat (8) @(posedge clk);

        $display("\n[TEST 3] SM4 Encrypt");
        drive_block(SM4_KEY_EXT, SM4_PT, 1'b1, 1'b1, 1'b0);
        wait_done_timeout(240);
        $display("   Plaintext:  %h", SM4_PT);
        $display("   Ciphertext: %h", dout);
        $display("   Expected:   %h", SM4_CT);
        if (dout === SM4_CT) begin
            $display("   -> [PASS] SM4 encryption correct");
            pass_count = pass_count + 1;
        end else begin
            $display("   -> [FAIL] SM4 encryption mismatch");
            fail_count = fail_count + 1;
        end

        repeat (8) @(posedge clk);

        $display("\n[TEST 4] SM4 Decrypt");
        drive_block(SM4_KEY_EXT, SM4_CT, 1'b1, 1'b0, 1'b0);
        wait_done_timeout(240);
        $display("   Ciphertext: %h", SM4_CT);
        $display("   Decrypted:  %h", dout);
        if (dout === SM4_PT) begin
            $display("   -> [PASS] SM4 decryption correct");
            pass_count = pass_count + 1;
        end else begin
            $display("   -> [FAIL] SM4 decryption mismatch");
            fail_count = fail_count + 1;
        end

        $display("\n========================================");
        $display("  Test Summary");
        $display("========================================");
        $display("   Passed: %0d", pass_count);
        $display("   Failed: %0d", fail_count);

        if (fail_count == 0) begin
            $display("\n  *** ALL TESTS PASSED ***");
        end else begin
            $display("\n  *** SOME TESTS FAILED ***");
        end

        $finish;
    end

endmodule
