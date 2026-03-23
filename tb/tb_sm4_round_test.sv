`timescale 1ns/1ps

module tb_sm4_round_test();
    
    localparam CLK_PERIOD = 10;
    
    logic clk;
    
    // Test S-box
    logic [7:0] sbox_in;
    logic [7:0] sbox_out;
    
    // Test transform
    logic [31:0] trans_in;
    logic [31:0] trans_out;
    
    // Test one_round
    logic [127:0] round_data_in;
    logic [31:0] round_key_in;
    logic [127:0] round_out;
    
    // SM4 Test Vector
    // S(0x00) = 0xd6
    localparam [7:0] SBOX_00 = 8'hd6;
    // S(0x01) = 0x90
    localparam [7:0] SBOX_01 = 8'h90;
    
    sbox_replace u_sbox (
        .data_in(sbox_in),
        .result_out(sbox_out)
    );
    
    transform_for_encdec u_trans (
        .data_in(trans_in),
        .result_out(trans_out)
    );
    
    one_round_for_encdec u_round (
        .data_in(round_data_in),
        .round_key_in(round_key_in),
        .result_out(round_out)
    );
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    initial begin
        $display("========================================");
        $display("  SM4 Component Test");
        $display("========================================");
        
        // Test S-box
        $display("\n[1] S-box Test:");
        sbox_in = 8'h00;
        #10;
        $display("    S(0x%02h) = 0x%02h (expected: 0xd6)", sbox_in, sbox_out);
        
        sbox_in = 8'h01;
        #10;
        $display("    S(0x%02h) = 0x%02h (expected: 0x90)", sbox_in, sbox_out);
        
        // Test transform
        $display("\n[2] Transform Test:");
        trans_in = 32'h00000000;
        #10;
        $display("    T(0x%08h) = 0x%08h", trans_in, trans_out);
        
        trans_in = 32'hd6d6d6d;
        #10;
        $display("    T(0x%08h) = 0x%08h", trans_in, trans_out);
        
        // Test one round
        $display("\n[3] One Round Test:");
        // SM4 round function: X[i+1] = X[i] ^ T(X[i+1] ^ X[i+2] ^ X[i+3] ^ rk[i])
        round_data_in = 128'h01234567_89abcdef_fedcba98_76543210;
        round_key_in = 32'ha3b1bac6;  // First round key (after XOR with FK)
        #10;
        $display("    Input:  %h", round_data_in);
        $display("    Key:    %h", round_key_in);
        $display("    Output: %h", round_out);
        
        $display("\n========================================");
        $finish;
    end

endmodule
