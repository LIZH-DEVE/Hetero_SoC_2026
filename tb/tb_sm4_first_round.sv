`timescale 1ns/1ps

module tb_sm4_first_round();
    
    localparam CLK_PERIOD = 10;
    logic clk;
    
    // Test one_round
    logic [127:0] round_data_in;
    logic [31:0] round_key_in;
    logic [127:0] round_out;
    
    // Test transform
    logic [31:0] trans_in;
    logic [31:0] trans_out;
    
    // SM4 Test Vector
    // Key: 0123456789abcdeffedcba9876543210
    // After XOR with FK: 
    // K0 = 01234567 ^ A3B1BAC6 = A29279A1
    // K1 = 89ABCDEF ^ 56AA3350 = DF018EBF  
    // K2 = FEDCBA98 ^ 677D9197 = 99A0220F
    // K3 = 76543210 ^ B27022DC = C42410CC
    
    // First round key (rk0) calculation:
    // L' = T(K1^K2^K3^CK[0]) = T(DF018EBF^99A0220F^C42410CC^00070E15)
    // Need to compute this step by step
    
    one_round_for_encdec u_round (
        .data_in(round_data_in),
        .round_key_in(round_key_in),
        .result_out(round_out)
    );
    
    transform_for_encdec u_trans (
        .data_in(trans_in),
        .result_out(trans_out)
    );
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    initial begin
        $display("========================================");
        $display("  SM4 First Round Test");
        $display("========================================");
        
        // Test transform function
        $display("\n[1] Transform Function Test:");
        
        // T(0x00000000) should give a specific result
        trans_in = 32'h00000000;
        #10;
        $display("    T(0x%08h) = 0x%08h", trans_in, trans_out);
        
        // Test with a known value
        trans_in = 32'hd6d6d6d6;  // All S-box outputs are d6
        #10;
        $display("    T(0x%08h) = 0x%08h (all bytes same, expect linear combination)", trans_in, trans_out);
        
        // Test one round
        $display("\n[2] One Round Test:");
        
        // Input: X = (X0, X1, X2, X3) = (01234567, 89ABCDEF, FEDCBA98, 76543210)
        // But in Verilog, 128'h0123456789abcdeffedcba9876543210 means:
        // bits[127:96] = 01, bits[95:64] = 23, bits[63:32] = 45, bits[31:0] = 67
        // So the 128-bit value is stored in big-endian format in the literal
        
        round_data_in = 128'h01234567_89abcdef_fedcba98_76543210;
        
        // First round key after key expansion
        // rk0 should be computed from the key expansion
        // For now, let's use a test value
        round_key_in = 32'h00070e15;  // CK[0]
        
        #10;
        
        $display("    Input X:  %h", round_data_in);
        $display("    Key rk:  %h", round_key_in);
        $display("    Output:  %h", round_out);
        
        // Check the output format
        // In SM4: X' = (X1, X2, X3, X0 ^ L)
        // Where L = T(X1 ^ X2 ^ X3 ^ rk)
        
        $display("\n========================================");
        $display("  Test complete");
        $display("========================================");
        $finish;
    end

endmodule
