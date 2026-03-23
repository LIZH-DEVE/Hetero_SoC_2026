`timescale 1ns / 1ps

/**
 * Module: tb_crypto_simple
 * Description: Simple test for AES and SM4 core encryption/decryption
 * Tests ECB mode (no IV) to verify core functionality
 */

module tb_crypto_simple();

    localparam CLK_PERIOD = 10;
    
    // AES Test Vectors (FIPS 197 - ECB mode)
    localparam [127:0] AES_KEY = 128'h2b7e151628aed2a6abf7158809cf4f3c;
    localparam [127:0] AES_PLAINTEXT = 128'h6bc1bee22e409f96e93d7e117393172a;
    localparam [127:0] AES_CIPHERTEXT = 128'h7649abac8119b246cee98e9b12e9197d;

    logic           clk, rst_n;
    logic           algo_sel, encdec, start, done, busy;
    logic [31:0]    i_total_len;
    logic [127:0]   i_iv;
    logic [7:0]     s_axil_araddr;
    logic [31:0]    s_axil_rdata;
    logic [127:0]   key, din, dout;

    logic [127:0] encrypted_data;
    integer pass_count, fail_count;
    
    // Debug monitors
    logic [2:0] sm4_state_monitor;

    crypto_engine u_dut (
        .clk(clk), .rst_n(rst_n),
        .algo_sel(algo_sel), .encdec(encdec),
        .start(start), .i_total_len(i_total_len),
        .i_iv(i_iv),
        .done(done), .busy(busy),
        .s_axil_araddr(s_axil_araddr), .s_axil_rdata(s_axil_rdata),
        .key(key), .din(din), .dout(dout)
    );

    assign sm4_state_monitor = u_dut.sm4_state;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task system_reset();
        begin
            rst_n = 0; start = 0; algo_sel = 0; encdec = 1;
            i_total_len = 0; i_iv = 128'd0; key = AES_KEY; din = 0;
            #100 rst_n = 1;
            #20;
        end
    endtask

    task drive_block(input [127:0] data_in, input encrypt_mode);
        begin
            wait(!busy);
            @(posedge clk);
            din     <= data_in;
            encdec  <= encrypt_mode;
            i_iv    <= 128'd0;  // ECB mode: IV = 0
            start   <= 1;
            @(posedge clk);
            start   <= 0;
        end
    endtask

    task wait_done_timeout(input integer max_cycles);
        integer cycle_count;
        begin
            cycle_count = 0;
            fork
                begin : wait_loop
                    while (!done && cycle_count < max_cycles) begin
                        @(posedge clk);
                        cycle_count = cycle_count + 1;
                    end
                end
                begin : timeout_monitor
                    repeat(max_cycles) @(posedge clk);
                    $display("\n[FATAL] Timeout after %0d cycles!", max_cycles);
                    $display("        SM4 state=%0d, busy=%b", sm4_state_monitor, busy);
                    $stop;
                end
            join_any
            disable fork;
        end
    endtask

    initial begin
        $display("\n========================================");
        $display("  AES and SM4 Simple Test (ECB Mode)");
        $display("========================================");
        
        pass_count = 0;
        fail_count = 0;
        
        system_reset();
        
        // Test 1: AES Encrypt
        $display("\n[TEST 1] AES-128-ECB Encrypt");
        algo_sel = 0; i_total_len = 128;
        key = AES_KEY;
        
        drive_block(AES_PLAINTEXT, 1);
        wait_done_timeout(100);
        encrypted_data = dout;
        $display("   Plaintext:  %h", AES_PLAINTEXT);
        $display("   Ciphertext: %h", encrypted_data);
        $display("   Expected:   %h", AES_CIPHERTEXT);
        
        if (encrypted_data === AES_CIPHERTEXT) begin
            $display("   -> [PASS] AES encryption correct");
            pass_count = pass_count + 1;
        end else begin
            $display("   -> [FAIL] AES encryption mismatch");
            fail_count = fail_count + 1;
        end
        
        #50;
        
        // Test 2: AES Decrypt
        $display("\n[TEST 2] AES-128-ECB Decrypt");
        drive_block(encrypted_data, 0);
        wait_done_timeout(100);
        $display("   Ciphertext: %h", encrypted_data);
        $display("   Decrypted:  %h", dout);
        
        if (dout === AES_PLAINTEXT) begin
            $display("   -> [PASS] AES decryption correct");
            pass_count = pass_count + 1;
        end else begin
            $display("   -> [FAIL] AES decryption mismatch");
            fail_count = fail_count + 1;
        end
        
        #50;
        
        // Test 3: SM4 Encrypt
        $display("\n[TEST 3] SM4-ECB Encrypt");
        algo_sel = 1; i_total_len = 128;
        key = 128'h0123456789abcdeffedcba9876543210;
        
        drive_block(128'h0123456789abcdeffedcba9876543210, 1);
        wait_done_timeout(200);
        encrypted_data = dout;
        $display("   Plaintext:  %h", 128'h0123456789abcdeffedcba9876543210);
        $display("   Ciphertext: %h", encrypted_data);
        
        if (encrypted_data != 128'd0 && encrypted_data != 128'h0123456789abcdeffedcba9876543210) begin
            $display("   -> [PASS] SM4 encryption produced output");
            pass_count = pass_count + 1;
        end else begin
            $display("   -> [FAIL] SM4 encryption failed");
            fail_count = fail_count + 1;
        end
        
        #50;
        
        // Test 4: SM4 Decrypt
        $display("\n[TEST 4] SM4-ECB Decrypt");
        drive_block(encrypted_data, 0);
        wait_done_timeout(200);
        $display("   Ciphertext: %h", encrypted_data);
        $display("   Decrypted:  %h", dout);
        
        if (dout === 128'h0123456789abcdeffedcba9876543210) begin
            $display("   -> [PASS] SM4 decryption correct");
            pass_count = pass_count + 1;
        end else begin
            $display("   -> [FAIL] SM4 decryption mismatch");
            fail_count = fail_count + 1;
        end

        // Final Summary
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
