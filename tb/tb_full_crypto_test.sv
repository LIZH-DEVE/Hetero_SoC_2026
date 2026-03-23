`timescale 1ns/1ps

module tb_full_crypto_test();
    
    localparam CLK_PERIOD = 10;
    
    logic clk, rst_n;
    
    // AES signals
    logic aes_encdec, aes_init, aes_next, aes_ready;
    logic [255:0] aes_key;
    logic [127:0] aes_block_in, aes_result;
    logic aes_result_valid;
    
    // SM4 signals
    logic sm4_enable_in, sm4_encdec_enable_in, sm4_encdec_sel_in, sm4_valid_in;
    logic sm4_enable_key_exp_in, sm4_user_key_valid_in;
    logic [127:0] sm4_user_key_in, sm4_data_in, sm4_result_out;
    logic sm4_ready_out, sm4_key_exp_ready_out;
    
    // Test counters
    integer tests_passed;
    integer tests_failed;
    
    // FIPS 197 Test Vector
    localparam [127:0] AES_KEY = 128'h2b7e151628aed2a6abf7158809cf4f3c;
    localparam [127:0] AES_PLAINTEXT = 128'h3243f6a8885a308d313198a2e0370734;
    localparam [127:0] AES_CIPHERTEXT = 128'h3925841d02dc09fbdc118597196a0b32;
    
    // SM4 Test Vector (GM/T 0002-2012)
    localparam [127:0] SM4_KEY = 128'h0123456789abcdeffedcba9876543210;
    localparam [127:0] SM4_PLAINTEXT = 128'h0123456789abcdeffedcba9876543210;
    localparam [127:0] SM4_CIPHERTEXT = 128'h681edf34d206965e86b3e94f536e4246;
    
    // AES Core instance
    aes_core u_aes_core (
        .clk(clk), 
        .reset_n(rst_n),
        .encdec(aes_encdec),
        .keylen(1'b0),
        .init(aes_init),
        .next(aes_next), 
        .ready(aes_ready),
        .key(aes_key), 
        .block(aes_block_in),
        .result(aes_result), 
        .result_valid(aes_result_valid)
    );
    
    // SM4 Top instance
    sm4_top u_sm4_top (
        .clk(clk),
        .reset_n(rst_n),
        .sm4_enable_in(sm4_enable_in),
        .encdec_enable_in(sm4_encdec_enable_in),
        .encdec_sel_in(sm4_encdec_sel_in),
        .valid_in(sm4_valid_in),
        .data_in(sm4_data_in),
        .enable_key_exp_in(sm4_enable_key_exp_in),
        .user_key_valid_in(sm4_user_key_valid_in),
        .user_key_in(sm4_user_key_in),
        .key_exp_ready_out(sm4_key_exp_ready_out),
        .ready_out(sm4_ready_out),
        .result_out(sm4_result_out)
    );
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    integer cycle_count;
    
    // AES test task
    task test_aes(input [127:0] key, input [127:0] plaintext, input [127:0] expected, input encrypt, output [127:0] result, output logic pass);
        begin
            $display("\n  [AES %s Test]", encrypt ? "Encrypt" : "Decrypt");
            $display("    Key: %h", key);
            $display("    Input: %h", plaintext);
            $display("    Expected: %h", expected);
            
            aes_key = {key, 128'd0};
            aes_encdec = encrypt;
            
            // Init key expansion
            @(posedge clk);
            aes_init = 1;
            @(posedge clk);
            aes_init = 0;
            
            // Wait for key expansion
            cycle_count = 0;
            while (aes_ready && cycle_count < 50) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
            cycle_count = 0;
            while (!aes_ready && cycle_count < 50) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
            
            repeat(2) @(posedge clk);
            
            // Start encryption/decryption
            aes_block_in = plaintext;
            @(posedge clk);
            aes_next = 1;
            @(posedge clk);
            aes_next = 0;
            
            // Wait for result
            cycle_count = 0;
            while (aes_ready && cycle_count < 100) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
            cycle_count = 0;
            while (!aes_result_valid && cycle_count < 100) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
            
            result = aes_result;
            
            if (result === expected) begin
                $display("    Result: %h -> [PASS]", result);
                pass = 1;
            end else begin
                $display("    Result: %h -> [FAIL]", result);
                pass = 0;
            end
        end
    endtask
    
    // SM4 test task
    task test_sm4(input [127:0] key, input [127:0] plaintext, input [127:0] expected, input encrypt, output [127:0] result, output logic pass);
        begin
            $display("\n  [SM4 %s Test]", encrypt ? "Encrypt" : "Decrypt");
            $display("    Key: %h", key);
            $display("    Input: %h", plaintext);
            $display("    Expected: %h", expected);
            
            sm4_user_key_in = key;
            sm4_data_in = plaintext;
            sm4_encdec_sel_in = encrypt ? 1'b1 : 1'b0;
            sm4_enable_in = 1'b0;
            sm4_encdec_enable_in = 1'b0;
            sm4_valid_in = 1'b0;
            sm4_enable_key_exp_in = 1'b0;
            sm4_user_key_valid_in = 1'b0;
            
            repeat(2) @(posedge clk);
            
            // Step 1: Key expansion (sm4_enable_in must be high for key expansion to work)
            $display("    Starting key expansion...");
            sm4_enable_in = 1'b1;
            sm4_enable_key_exp_in = 1'b1;
            @(posedge clk);
            sm4_user_key_valid_in = 1'b1;
            @(posedge clk);
            sm4_user_key_valid_in = 1'b0;
            
            // Wait for key expansion to complete
            cycle_count = 0;
            while (!sm4_key_exp_ready_out && cycle_count < 100) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
            
            if (cycle_count >= 100) begin
                $display("    TIMEOUT waiting for key expansion!");
                result = 0;
                pass = 0;
                return;
            end
            
            $display("    Key expansion done after %0d cycles", cycle_count);
            
            // Keep enable_key_exp high during encryption
            repeat(2) @(posedge clk);
            
            // Step 2: Start encryption/decryption
            $display("    Starting %s...", encrypt ? "encryption" : "decryption");
            sm4_enable_in = 1'b1;
            sm4_encdec_enable_in = 1'b1;
            sm4_valid_in = 1'b1;
            @(posedge clk);
            sm4_valid_in = 1'b0;
            
            // Wait for result
            cycle_count = 0;
            while (!sm4_ready_out && cycle_count < 200) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
            
            if (cycle_count >= 200) begin
                $display("    TIMEOUT waiting for result!");
                result = 0;
                pass = 0;
                return;
            end
            
            result = sm4_result_out;
            
            // Reset signals
            sm4_enable_in = 1'b0;
            sm4_encdec_enable_in = 1'b0;
            sm4_enable_key_exp_in = 1'b0;
            
            if (result === expected) begin
                $display("    Result: %h -> [PASS]", result);
                pass = 1;
            end else begin
                $display("    Result: %h -> [FAIL]", result);
                pass = 0;
            end
        end
    endtask
    
    logic [127:0] test_result;
    logic test_pass;
    
    initial begin
        $display("========================================");
        $display("  Full Crypto Test Suite");
        $display("========================================");
        
        tests_passed = 0;
        tests_failed = 0;
        
        // Initialize
        rst_n = 0;
        aes_init = 0;
        aes_next = 0;
        aes_encdec = 1;
        aes_key = 0;
        aes_block_in = 0;
        sm4_enable_in = 0;
        sm4_encdec_enable_in = 0;
        sm4_encdec_sel_in = 1;
        sm4_valid_in = 0;
        sm4_enable_key_exp_in = 0;
        sm4_user_key_valid_in = 0;
        sm4_user_key_in = 0;
        sm4_data_in = 0;
        
        #100 rst_n = 1;
        repeat(5) @(posedge clk);
        
        // Test 1: AES Encrypt
        $display("\n========================================");
        $display("  Test 1: AES-128 Encryption");
        $display("========================================");
        test_aes(AES_KEY, AES_PLAINTEXT, AES_CIPHERTEXT, 1, test_result, test_pass);
        if (test_pass) tests_passed = tests_passed + 1;
        else tests_failed = tests_failed + 1;
        
        // Test 2: AES Decrypt
        $display("\n========================================");
        $display("  Test 2: AES-128 Decryption");
        $display("========================================");
        test_aes(AES_KEY, AES_CIPHERTEXT, AES_PLAINTEXT, 0, test_result, test_pass);
        if (test_pass) tests_passed = tests_passed + 1;
        else tests_failed = tests_failed + 1;
        
        // Test 3: SM4 Encrypt
        $display("\n========================================");
        $display("  Test 3: SM4 Encryption");
        $display("========================================");
        test_sm4(SM4_KEY, SM4_PLAINTEXT, SM4_CIPHERTEXT, 1, test_result, test_pass);
        if (test_pass) tests_passed = tests_passed + 1;
        else tests_failed = tests_failed + 1;
        
        // Test 4: SM4 Decrypt
        $display("\n========================================");
        $display("  Test 4: SM4 Decryption");
        $display("========================================");
        test_sm4(SM4_KEY, SM4_CIPHERTEXT, SM4_PLAINTEXT, 0, test_result, test_pass);
        if (test_pass) tests_passed = tests_passed + 1;
        else tests_failed = tests_failed + 1;
        
        // Summary
        $display("\n========================================");
        $display("  Test Summary");
        $display("========================================");
        $display("  Passed: %0d", tests_passed);
        $display("  Failed: %0d", tests_failed);
        
        if (tests_failed == 0) begin
            $display("\n  *** ALL TESTS PASSED ***");
        end else begin
            $display("\n  *** SOME TESTS FAILED ***");
        end
        
        $display("\n========================================");
        $finish;
    end

endmodule
