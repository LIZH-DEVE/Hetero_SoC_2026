`timescale 1ns/1ps

module tb_sm4_debug();
    
    localparam CLK_PERIOD = 10;
    
    logic clk, rst_n;
    
    logic sm4_enable_in, sm4_encdec_enable_in, sm4_encdec_sel_in, sm4_valid_in;
    logic sm4_enable_key_exp_in, sm4_user_key_valid_in;
    logic [127:0] sm4_user_key_in, sm4_data_in, sm4_result_out;
    logic sm4_ready_out, sm4_key_exp_ready_out;
    
    logic [2:0] key_exp_state;
    logic [4:0] key_exp_count;
    logic key_exp_finished;
    
    localparam [127:0] SM4_KEY = 128'h0123456789abcdeffedcba9876543210;
    localparam [127:0] SM4_PLAINTEXT = 128'h0123456789abcdeffedcba9876543210;
    localparam [127:0] SM4_CIPHERTEXT = 128'h681edf34d206965e86b3e94f536e4246;
    
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
    
    assign key_exp_state = u_sm4_top.u_key.current;
    assign key_exp_count = u_sm4_top.u_key.count_round;
    assign key_exp_finished = u_sm4_top.u_key.key_exp_finished_out;
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    integer cycle_count;
    
    initial begin
        $display("========================================");
        $display("  SM4 Debug Test");
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
        
        $display("\n[Step 1] Setting up key expansion...");
        sm4_user_key_in = SM4_KEY;
        sm4_data_in = SM4_PLAINTEXT;
        sm4_encdec_sel_in = 1'b1;
        
        $display("  Key: %h", SM4_KEY);
        $display("  Initial state: enable=%b, key_exp=%b, user_key_valid=%b", 
                 sm4_enable_in, sm4_enable_key_exp_in, sm4_user_key_valid_in);
        
        $display("\n[Step 2] Enabling SM4 and key expansion...");
        sm4_enable_in = 1'b1;
        sm4_enable_key_exp_in = 1'b1;
        
        $display("  After enable: state=%0d, count=%0d, finished=%b", 
                 key_exp_state, key_exp_count, key_exp_finished);
        
        @(posedge clk);
        $display("  Cycle 1: state=%0d, count=%0d, finished=%b, ready=%b", 
                 key_exp_state, key_exp_count, key_exp_finished, sm4_key_exp_ready_out);
        
        $display("\n[Step 3] Triggering user_key_valid pulse...");
        sm4_user_key_valid_in = 1'b1;
        
        @(posedge clk);
        $display("  Cycle 2: state=%0d, count=%0d, finished=%b, ready=%b", 
                 key_exp_state, key_exp_count, key_exp_finished, sm4_key_exp_ready_out);
        
        sm4_user_key_valid_in = 1'b0;
        
        $display("\n[Step 4] Waiting for key expansion to complete...");
        cycle_count = 0;
        while (!sm4_key_exp_ready_out && cycle_count < 50) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            if (cycle_count <= 5 || cycle_count % 10 == 0) begin
                $display("  Cycle %0d: state=%0d, count=%0d, finished=%b, ready=%b", 
                         cycle_count, key_exp_state, key_exp_count, key_exp_finished, sm4_key_exp_ready_out);
            end
        end
        
        if (sm4_key_exp_ready_out) begin
            $display("\n  Key expansion completed after %0d cycles", cycle_count);
            
            $display("\n[Step 5] Reading round keys...");
            $display("  rk[0] = %h (expected: F09279A1)", u_sm4_top.u_key.rk00_out);
            $display("  rk[1] = %h (expected: 0A2F3E83)", u_sm4_top.u_key.rk01_out);
            $display("  rk[2] = %h (expected: 2B3F3F2F)", u_sm4_top.u_key.rk02_out);
            $display("  rk[3] = %h (expected: 413F3FD0)", u_sm4_top.u_key.rk03_out);
            
            $display("\n[Step 6] Starting encryption...");
            sm4_encdec_enable_in = 1'b1;
            sm4_valid_in = 1'b1;
            
            cycle_count = 0;
            while (!sm4_ready_out && cycle_count < 50) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
            
            if (sm4_ready_out) begin
                $display("\n  Encryption completed after %0d cycles", cycle_count);
                $display("  Result:   %h", sm4_result_out);
                $display("  Expected: %h", SM4_CIPHERTEXT);
                
                if (sm4_result_out === SM4_CIPHERTEXT) begin
                    $display("\n  *** SM4 ENCRYPTION PASSED! ***");
                end else begin
                    $display("\n  *** SM4 ENCRYPTION FAILED! ***");
                end
            end else begin
                $display("\n  TIMEOUT waiting for encryption!");
            end
        end else begin
            $display("\n  TIMEOUT waiting for key expansion!");
            $display("  Final state: state=%0d, count=%0d, finished=%b", 
                     key_exp_state, key_exp_count, key_exp_finished);
        end
        
        $display("\n========================================");
        $finish;
    end

endmodule
