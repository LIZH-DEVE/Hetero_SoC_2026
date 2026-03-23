`timescale 1ns/1ps

module tb_sm4_detailed();
    
    localparam CLK_PERIOD = 10;
    
    logic clk, rst_n;
    
    // SM4 signals
    logic sm4_enable_in, sm4_encdec_enable_in, sm4_encdec_sel_in, sm4_valid_in;
    logic sm4_enable_key_exp_in, sm4_user_key_valid_in;
    logic [127:0] sm4_user_key_in, sm4_data_in, sm4_result_out;
    logic sm4_ready_out, sm4_key_exp_ready_out;
    
    // Internal signals for debug
    wire [31:0] rk00, rk01, rk02, rk03;
    
    // SM4 Test Vector (GM/T 0002-2012)
    // The standard shows data in big-endian format
    localparam [127:0] SM4_KEY = 128'h0123456789abcdeffedcba9876543210;
    localparam [127:0] SM4_PLAINTEXT = 128'h0123456789abcdeffedcba9876543210;
    localparam [127:0] SM4_CIPHERTEXT = 128'h681edf34d206965e86b3e94f536e4246;
    
    // Expected round keys (first 4) from standard
    // rk0 = AEE9C73B, rk1 = 833EF20A, rk2 = 78C9B9A1, rk3 = 5AE2C3E7
    localparam [31:0] EXP_RK00 = 32'hf09279a1;  // After byte swap
    localparam [31:0] EXP_RK01 = 32'h0a2f3e83;
    localparam [31:0] EXP_RK02 = 32'ha1b9c978;
    localparam [31:0] EXP_RK03 = 32'he7c3e25a;
    
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
    
    assign rk00 = u_sm4_top.rk_00;
    assign rk01 = u_sm4_top.rk_01;
    assign rk02 = u_sm4_top.rk_02;
    assign rk03 = u_sm4_top.rk_03;
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    integer cycle_count;
    
    initial begin
        $display("========================================");
        $display("  SM4 Detailed Debug Test");
        $display("========================================");
        
        // Initialize
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
        
        $display("\nKey: %h", SM4_KEY);
        $display("Plaintext: %h", SM4_PLAINTEXT);
        $display("Expected Ciphertext: %h", SM4_CIPHERTEXT);
        
        // Set up key and data
        sm4_user_key_in = SM4_KEY;
        sm4_data_in = SM4_PLAINTEXT;
        sm4_encdec_sel_in = 1'b0;  // Encrypt (0 = normal key order for encryption!)
        
        $display("\n[1] Starting key expansion...");
        
        @(negedge clk);
        sm4_enable_in = 1'b1;
        sm4_enable_key_exp_in = 1'b1;
        sm4_user_key_valid_in = 1'b1;
        
        @(posedge clk);
        sm4_user_key_valid_in = 1'b0;
        
        // Wait for key expansion
        cycle_count = 0;
        while (!sm4_key_exp_ready_out && cycle_count < 100) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        
        if (cycle_count >= 100) begin
            $display("    TIMEOUT waiting for key expansion!");
            $finish;
        end
        
        $display("    Key expansion complete after %0d cycles", cycle_count);
        
        // Print round keys
        $display("\n    Round Keys:");
        $display("    rk00 = %h", rk00);
        $display("    rk01 = %h", rk01);
        $display("    rk02 = %h", rk02);
        $display("    rk03 = %h", rk03);
        
        // Start encryption
        $display("\n[2] Starting encryption...");
        
        sm4_encdec_enable_in = 1'b1;
        repeat(2) @(posedge clk);
        
        sm4_valid_in = 1'b1;
        repeat(32) @(posedge clk);
        sm4_valid_in = 1'b0;
        
        $display("\n========================================");
        $display("  Results");
        $display("========================================");
        $display("Ciphertext: %h", sm4_result_out);
        $display("Expected:   %h", SM4_CIPHERTEXT);
        
        // Try byte-swapped result
        $display("\nByte-swapped result: %h", 
            {sm4_result_out[7:0], sm4_result_out[15:8], sm4_result_out[23:16], sm4_result_out[31:24],
             sm4_result_out[39:32], sm4_result_out[47:40], sm4_result_out[55:48], sm4_result_out[63:56],
             sm4_result_out[71:64], sm4_result_out[79:72], sm4_result_out[87:80], sm4_result_out[95:88],
             sm4_result_out[103:96], sm4_result_out[111:104], sm4_result_out[119:112], sm4_result_out[127:120]});
        
        if (sm4_result_out === SM4_CIPHERTEXT) begin
            $display("-> [PASS] SM4 encryption correct!");
        end else begin
            $display("-> [FAIL] SM4 encryption mismatch!");
        end
        
        $display("\n========================================");
        $finish;
    end

endmodule
