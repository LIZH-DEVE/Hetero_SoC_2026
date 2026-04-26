`timescale 1ns / 1ps

module tb_decrypt_verification();

    localparam CLK_PERIOD = 10;
    
    localparam [127:0] TEST_KEY   = 128'h2b7e151628aed2a6abf7158809cf4f3c;
    localparam [127:0] TEST_PLAINTEXT = 128'h6bc1bee22e409f96e93d7e117393172a;
    localparam [127:0] EXPECTED_CIPHERTEXT = 128'h7649abac8119b246cee98e9b12e9197d;

    logic           clk, rst_n;
    logic           algo_sel, encdec, start, done, busy;
    logic [31:0]    i_total_len;
    logic [7:0]     s_axil_araddr;
    logic [31:0]    s_axil_rdata;
    logic [127:0]   key, din, dout;

    logic [127:0] encrypted_data;
    integer pass_count, fail_count;
    integer i;
    integer roundtrip_pass;
    logic [127:0] temp_enc, temp_dec;
    logic [127:0] test_data [0:3];
    
    // Debug: track SM4 state machine
    logic [2:0] sm4_state_monitor;
    logic sm4_key_exp_ready_monitor;
    logic sm4_done_monitor;

    crypto_engine u_dut (
        .clk(clk), .rst_n(rst_n),
        .algo_sel(algo_sel), .encdec(encdec),
        .start(start), .i_total_len(i_total_len),
        .done(done), .busy(busy),
        .s_axil_araddr(s_axil_araddr), .s_axil_rdata(s_axil_rdata),
        .key(key), .din(din), .dout(dout)
    );

    // Monitor SM4 internal state for debugging
    assign sm4_state_monitor = u_dut.sm4_state;
    assign sm4_key_exp_ready_monitor = u_dut.sm4_key_exp_ready;
    assign sm4_done_monitor = u_dut.sm4_done;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task system_reset();
        begin
            rst_n = 0; start = 0; algo_sel = 0; encdec = 1;
            i_total_len = 0; key = TEST_KEY; din = 0;
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
            start   <= 1;
            @(posedge clk);
            start   <= 0;
            $display("   [DEBUG] drive_block started, encdec=%b, algo_sel=%b", encrypt_mode, algo_sel);
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
                        // Debug: print state every 10 cycles
                        if (algo_sel == 1'b1 && (cycle_count % 10 == 0)) begin
                            $display("   [DEBUG] Cycle %0d: sm4_state=%0d, key_exp_ready=%b, sm4_done=%b, busy=%b", 
                                     cycle_count, sm4_state_monitor, sm4_key_exp_ready_monitor, sm4_done_monitor, busy);
                        end
                    end
                    if (done) begin
                        $display("   [DEBUG] Operation completed at cycle %0d", cycle_count);
                    end
                end
                begin : timeout_monitor
                    repeat(max_cycles) @(posedge clk);
                    $display("\n[FATAL] Timeout after %0d cycles!", max_cycles);
                    $display("        Current state: busy=%b, algo_sel=%b", busy, algo_sel);
                    $display("        SM4 state=%0d, key_exp_ready=%b, sm4_done=%b", 
                             sm4_state_monitor, sm4_key_exp_ready_monitor, sm4_done_monitor);
                    $stop;
                end
            join_any
            disable fork;
        end
    endtask

    initial begin
        $display("\n=== Decrypt Verification Test Start ===");
        $display("Test Key:   %h", TEST_KEY);
        $display("Test Plain: %h", TEST_PLAINTEXT);
        pass_count = 0;
        fail_count = 0;
        
        system_reset();
        
        // Test 1: AES Encrypt
        $display("\n[TEST 1] AES Encrypt");
        algo_sel = 0; i_total_len = 128;
        drive_block(TEST_PLAINTEXT, 1);
        wait_done_timeout(100);
        encrypted_data = dout;
        $display("   Plaintext:  %h", TEST_PLAINTEXT);
        $display("   Ciphertext: %h", encrypted_data);
        
        if (encrypted_data === EXPECTED_CIPHERTEXT) begin
            $display("   -> [PASS] Encryption matches expected ciphertext");
            pass_count = pass_count + 1;
        end else begin
            $display("   -> [FAIL] Encryption mismatch!");
            $display("              Expected: %h", EXPECTED_CIPHERTEXT);
            fail_count = fail_count + 1;
        end
        
        #50;
        
        // Test 2: AES Decrypt
        $display("\n[TEST 2] AES Decrypt");
        drive_block(encrypted_data, 0);
        wait_done_timeout(100);
        $display("   Ciphertext: %h", encrypted_data);
        $display("   Decrypted:  %h", dout);
        
        if (dout === TEST_PLAINTEXT) begin
            $display("   -> [PASS] Decryption matches original plaintext");
            pass_count = pass_count + 1;
        end else begin
            $display("   -> [FAIL] Decryption mismatch!");
            fail_count = fail_count + 1;
        end
        
        #50;
        
        // Test 3: SM4 Encrypt (needs more time for key expansion)
        $display("\n[TEST 3] SM4 Encrypt");
        $display("   [DEBUG] Starting SM4 encryption test...");
        algo_sel = 1; i_total_len = 128;
        drive_block(TEST_PLAINTEXT, 1);
        // SM4 needs ~32 cycles for key expansion + 32 cycles for encryption
        wait_done_timeout(200);
        encrypted_data = dout;
        $display("   Plaintext:  %h", TEST_PLAINTEXT);
        $display("   SM4 Ciphertext: %h", encrypted_data);
        
        if (encrypted_data != 128'h0 && encrypted_data != TEST_PLAINTEXT) begin
            $display("   -> [PASS] SM4 encryption produced output");
            pass_count = pass_count + 1;
        end else begin
            $display("   -> [FAIL] SM4 encryption failed!");
            fail_count = fail_count + 1;
        end
        
        #50;
        
        // Test 4: SM4 Decrypt
        $display("\n[TEST 4] SM4 Decrypt");
        $display("   [DEBUG] Starting SM4 decryption test...");
        drive_block(encrypted_data, 0);
        wait_done_timeout(200);
        $display("   SM4 Ciphertext: %h", encrypted_data);
        $display("   SM4 Decrypted:  %h", dout);
        
        if (dout === TEST_PLAINTEXT) begin
            $display("   -> [PASS] SM4 round-trip successful");
            pass_count = pass_count + 1;
        end else begin
            $display("   -> [FAIL] SM4 round-trip failed!");
            $display("              Expected: %h", TEST_PLAINTEXT);
            fail_count = fail_count + 1;
        end

        #50;
        
        // Test 5: Multiple AES Round-trips
        $display("\n[TEST 5] Multiple AES Round-trips");
        algo_sel = 0; i_total_len = 128;
        
        test_data[0] = 128'h000102030405060708090a0b0c0d0e0f;
        test_data[1] = 128'hdeadbeefcafebabe1234567890abcdef;
        test_data[2] = 128'hffffffff00000000ffffffff00000000;
        test_data[3] = 128'h01020304050607080910111213141516;
        
        roundtrip_pass = 0;
        
        for (i = 0; i < 4; i++) begin
            $display("   [DEBUG] AES round-trip test %0d", i);
            // Encrypt
            drive_block(test_data[i], 1);
            wait_done_timeout(100);
            temp_enc = dout;
            
            // Decrypt
            drive_block(temp_enc, 0);
            wait_done_timeout(100);
            temp_dec = dout;
            
            if (temp_dec === test_data[i]) begin
                roundtrip_pass = roundtrip_pass + 1;
                $display("   [DEBUG] Round-trip %0d passed", i);
            end else begin
                $display("   [DEBUG] Round-trip %0d failed: expected %h, got %h", i, test_data[i], temp_dec);
            end
        end
        
        if (roundtrip_pass == 4) begin
            $display("   -> [PASS] All 4 AES round-trips successful");
            pass_count = pass_count + 1;
        end else begin
            $display("   -> [FAIL] Only %d/4 AES round-trips passed", roundtrip_pass);
            fail_count = fail_count + 1;
        end

        // Final Summary
        $display("\n=== Test Summary ===");
        $display("   Passed: %d", pass_count);
        $display("   Failed: %d", fail_count);
        
        if (fail_count == 0) begin
            $display("\n=== ALL TESTS PASSED SUCCESSFULLY! ===");
        end else begin
            $display("\n=== SOME TESTS FAILED ===");
        end
        
        $finish;
    end

endmodule
