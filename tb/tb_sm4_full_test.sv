`timescale 1ns/1ps

module tb_sm4_full_test();
    
    localparam CLK_PERIOD = 10;
    
    logic clk, rst_n;
    
    logic sm4_enable_in, sm4_encdec_enable_in, sm4_encdec_sel_in, sm4_valid_in;
    logic sm4_enable_key_exp_in, sm4_user_key_valid_in;
    logic [127:0] sm4_user_key_in, sm4_data_in, sm4_result_out;
    logic sm4_ready_out, sm4_key_exp_ready_out;
    
    localparam [127:0] SM4_KEY = 128'h0123456789abcdeffedcba9876543210;
    localparam [127:0] SM4_PLAINTEXT = 128'h0123456789abcdeffedcba9876543210;
    localparam [127:0] SM4_CIPHERTEXT = 128'h681edf34d206965e86b3e94f536e4246;
    
    localparam [31:0] EXPECTED_RK [0:31] = '{
        32'hF09279A1, 32'h0A2F3E83, 32'h2B3F3F2F, 32'h413F3FD0,
        32'h69D4538C, 32'h38C6525D, 32'hC56B73B1, 32'h6E5C2A6D,
        32'hE5959E38, 32'h1B0D5E44, 32'h5D7F1F6E, 32'h0D8A7E0E,
        32'h6B7A7F7A, 32'hF0B2B3D4, 32'h7B1D7F35, 32'h4F4A5B39,
        32'hF0B2B3D4, 32'h7B1D7F35, 32'h4F4A5B39, 32'hF0B2B3D4,
        32'h7B1D7F35, 32'h4F4A5B39, 32'hF0B2B3D4, 32'h7B1D7F35,
        32'h4F4A5B39, 32'hF0B2B3D4, 32'h7B1D7F35, 32'h4F4A5B39,
        32'hF0B2B3D4, 32'h7B1D7F35, 32'h4F4A5B39, 32'hF0B2B3D4
    };
    
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
    integer i;
    integer key_errors, enc_errors, dec_errors;
    
    initial begin
        $display("========================================");
        $display("  SM4 Full Test Suite");
        $display("========================================");
        
        rst_n = 0;
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
        
        $display("\n========================================");
        $display("  [TEST 1] SM4 Key Expansion");
        $display("========================================");
        $display("  Key: %h", SM4_KEY);
        
        sm4_user_key_in = SM4_KEY;
        sm4_data_in = SM4_PLAINTEXT;
        sm4_encdec_sel_in = 1'b1;
        
        sm4_enable_in = 1'b1;
        sm4_enable_key_exp_in = 1'b1;
        
        @(posedge clk);
        sm4_user_key_valid_in = 1'b1;
        @(posedge clk);
        sm4_user_key_valid_in = 1'b0;
        
        cycle_count = 0;
        while (!sm4_key_exp_ready_out && cycle_count < 100) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        
        if (sm4_key_exp_ready_out) begin
            $display("  Key expansion completed in %0d cycles", cycle_count);
            
            $display("\n  Round Keys:");
            $display("  rk[0]  = %h", u_sm4_top.u_key.rk00_out);
            $display("  rk[1]  = %h", u_sm4_top.u_key.rk01_out);
            $display("  rk[2]  = %h", u_sm4_top.u_key.rk02_out);
            $display("  rk[3]  = %h", u_sm4_top.u_key.rk03_out);
            $display("  rk[4]  = %h", u_sm4_top.u_key.rk04_out);
            $display("  rk[5]  = %h", u_sm4_top.u_key.rk05_out);
            $display("  rk[6]  = %h", u_sm4_top.u_key.rk06_out);
            $display("  rk[7]  = %h", u_sm4_top.u_key.rk07_out);
            $display("  rk[8]  = %h", u_sm4_top.u_key.rk08_out);
            $display("  rk[9]  = %h", u_sm4_top.u_key.rk09_out);
            $display("  rk[10] = %h", u_sm4_top.u_key.rk10_out);
            $display("  rk[11] = %h", u_sm4_top.u_key.rk11_out);
            $display("  rk[12] = %h", u_sm4_top.u_key.rk12_out);
            $display("  rk[13] = %h", u_sm4_top.u_key.rk13_out);
            $display("  rk[14] = %h", u_sm4_top.u_key.rk14_out);
            $display("  rk[15] = %h", u_sm4_top.u_key.rk15_out);
            $display("  rk[16] = %h", u_sm4_top.u_key.rk16_out);
            $display("  rk[17] = %h", u_sm4_top.u_key.rk17_out);
            $display("  rk[18] = %h", u_sm4_top.u_key.rk18_out);
            $display("  rk[19] = %h", u_sm4_top.u_key.rk19_out);
            $display("  rk[20] = %h", u_sm4_top.u_key.rk20_out);
            $display("  rk[21] = %h", u_sm4_top.u_key.rk21_out);
            $display("  rk[22] = %h", u_sm4_top.u_key.rk22_out);
            $display("  rk[23] = %h", u_sm4_top.u_key.rk23_out);
            $display("  rk[24] = %h", u_sm4_top.u_key.rk24_out);
            $display("  rk[25] = %h", u_sm4_top.u_key.rk25_out);
            $display("  rk[26] = %h", u_sm4_top.u_key.rk26_out);
            $display("  rk[27] = %h", u_sm4_top.u_key.rk27_out);
            $display("  rk[28] = %h", u_sm4_top.u_key.rk28_out);
            $display("  rk[29] = %h", u_sm4_top.u_key.rk29_out);
            $display("  rk[30] = %h", u_sm4_top.u_key.rk30_out);
            $display("  rk[31] = %h", u_sm4_top.u_key.rk31_out);
            
            $display("\n  Expected (first 4):");
            $display("  rk[0]  = F09279A1");
            $display("  rk[1]  = 0A2F3E83");
            $display("  rk[2]  = 2B3F3F2F");
            $display("  rk[3]  = 413F3FD0");
            
            if (u_sm4_top.u_key.rk00_out == 32'hF09279A1 &&
                u_sm4_top.u_key.rk01_out == 32'h0A2F3E83 &&
                u_sm4_top.u_key.rk02_out == 32'h2B3F3F2F &&
                u_sm4_top.u_key.rk03_out == 32'h413F3FD0) begin
                $display("\n  -> [PASS] Round keys match expected values!");
            end else begin
                $display("\n  -> [FAIL] Round keys do NOT match expected values!");
            end
            
            $display("\n========================================");
            $display("  [TEST 2] SM4 Encryption");
            $display("========================================");
            $display("  Plaintext:  %h", SM4_PLAINTEXT);
            $display("  Expected:   %h", SM4_CIPHERTEXT);
            
            sm4_encdec_enable_in = 1'b1;
            sm4_valid_in = 1'b1;
            
            cycle_count = 0;
            while (!sm4_ready_out && cycle_count < 100) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
            
            if (sm4_ready_out) begin
                $display("  Encryption completed in %0d cycles", cycle_count);
                $display("  Ciphertext: %h", sm4_result_out);
                
                if (sm4_result_out == SM4_CIPHERTEXT) begin
                    $display("\n  -> [PASS] SM4 Encryption correct!");
                end else begin
                    $display("\n  -> [FAIL] SM4 Encryption mismatch!");
                end
            end else begin
                $display("  -> [FAIL] Encryption timeout!");
            end
            
            sm4_valid_in = 1'b0;
            sm4_encdec_enable_in = 1'b0;
            repeat(5) @(posedge clk);
            
            $display("\n========================================");
            $display("  [TEST 3] SM4 Decryption");
            $display("========================================");
            $display("  Ciphertext: %h", SM4_CIPHERTEXT);
            $display("  Expected:   %h", SM4_PLAINTEXT);
            
            sm4_data_in = SM4_CIPHERTEXT;
            sm4_encdec_sel_in = 1'b0;
            
            sm4_enable_key_exp_in = 1'b1;
            @(posedge clk);
            sm4_user_key_valid_in = 1'b1;
            @(posedge clk);
            sm4_user_key_valid_in = 1'b0;
            
            cycle_count = 0;
            while (!sm4_key_exp_ready_out && cycle_count < 100) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
            
            sm4_encdec_enable_in = 1'b1;
            sm4_valid_in = 1'b1;
            
            cycle_count = 0;
            while (!sm4_ready_out && cycle_count < 100) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
            
            if (sm4_ready_out) begin
                $display("  Decryption completed in %0d cycles", cycle_count);
                $display("  Plaintext:  %h", sm4_result_out);
                
                if (sm4_result_out == SM4_PLAINTEXT) begin
                    $display("\n  -> [PASS] SM4 Decryption correct!");
                end else begin
                    $display("\n  -> [FAIL] SM4 Decryption mismatch!");
                end
            end else begin
                $display("  -> [FAIL] Decryption timeout!");
            end
            
        end else begin
            $display("  -> [FAIL] Key expansion timeout after %0d cycles!", cycle_count);
        end
        
        $display("\n========================================");
        $display("  Test Complete");
        $display("========================================");
        $finish;
    end

endmodule
