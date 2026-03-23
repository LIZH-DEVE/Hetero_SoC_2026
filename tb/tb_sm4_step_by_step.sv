`timescale 1ns/1ps

module tb_sm4_step_by_step();
    
    localparam CLK_PERIOD = 10;
    logic clk;
    
    // Test signals
    logic [31:0] test_data;
    logic [31:0] sbox_result;
    logic [31:0] transform_result;
    
    // SM4 FK parameters
    localparam [31:0] FK0 = 32'ha3b1bac6;
    localparam [31:0] FK1 = 32'h56aa3350;
    localparam [31:0] FK2 = 32'h677d9197;
    localparam [31:0] FK3 = 32'hb27022dc;
    
    // SM4 CK[0]
    localparam [31:0] CK0 = 32'h00070e15;
    
    // Test key
    localparam [127:0] SM4_KEY = 128'h0123456789abcdeffedcba9876543210;
    
    // Expected values
    // MK[0] = 01234567, MK[1] = 89abcdef, MK[2] = fedcba98, MK[3] = 76543210
    // K[0] = MK[0] ^ FK0 = 01234567 ^ a3b1bac6 = a29279a1
    // K[1] = MK[1] ^ FK1 = 89abcdef ^ 56aa3350 = df018ebf
    // K[2] = MK[2] ^ FK2 = fedcba98 ^ 677d9197 = 99a0220f
    // K[3] = MK[3] ^ FK3 = 76543210 ^ b27022dc = c42410cc
    
    localparam [31:0] EXP_K0 = 32'ha29279a1;
    localparam [31:0] EXP_K1 = 32'hdf018ebf;
    localparam [31:0] EXP_K2 = 32'h99a0220f;
    localparam [31:0] EXP_K3 = 32'hc42410cc;
    
    // For rk0:
    // data_for_transform = K[1] ^ K[2] ^ K[3] ^ CK[0]
    //                     = df018ebf ^ 99a0220f ^ c42410cc ^ 00070e15
    // Let's compute step by step
    // df018ebf ^ 99a0220f = 46a1a4b0
    // 46a1a4b0 ^ c42410cc = 8285b47c
    // 8285b47c ^ 00070e15 = 8282ba69
    
    localparam [31:0] EXP_DATA_FOR_TRANSFORM = 32'h8282ba69;
    
    sbox_replace u_sbox_0 (.data_in(test_data[31:24]), .result_out(sbox_result[31:24]));
    sbox_replace u_sbox_1 (.data_in(test_data[23:16]), .result_out(sbox_result[23:16]));
    sbox_replace u_sbox_2 (.data_in(test_data[15:8]), .result_out(sbox_result[15:8]));
    sbox_replace u_sbox_3 (.data_in(test_data[7:0]), .result_out(sbox_result[7:0]));
    
    transform_for_key_exp u_trans (.data_in(test_data), .data_after_linear_key_out(transform_result));
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    initial begin
        $display("========================================");
        $display("  SM4 Step-by-Step Verification");
        $display("========================================");
        
        // Step 1: Verify FK XOR
        $display("\n[1] FK XOR Verification:");
        $display("    MK[0] = %h, FK0 = %h, K[0] = %h (expected: %h)", 
            32'h01234567, FK0, 32'h01234567 ^ FK0, EXP_K0);
        $display("    MK[1] = %h, FK1 = %h, K[1] = %h (expected: %h)", 
            32'h89abcdef, FK1, 32'h89abcdef ^ FK1, EXP_K1);
        $display("    MK[2] = %h, FK2 = %h, K[2] = %h (expected: %h)", 
            32'hfedcba98, FK2, 32'hfedcba98 ^ FK2, EXP_K2);
        $display("    MK[3] = %h, FK3 = %h, K[3] = %h (expected: %h)", 
            32'h76543210, FK3, 32'h76543210 ^ FK3, EXP_K3);
        
        // Step 2: Verify data_for_transform
        $display("\n[2] data_for_transform Verification:");
        $display("    K[1] ^ K[2] = %h", EXP_K1 ^ EXP_K2);
        $display("    (K[1] ^ K[2]) ^ K[3] = %h", EXP_K1 ^ EXP_K2 ^ EXP_K3);
        $display("    data_for_transform = (K[1] ^ K[2] ^ K[3]) ^ CK[0] = %h", 
            EXP_K1 ^ EXP_K2 ^ EXP_K3 ^ CK0);
        $display("    Expected: %h", EXP_DATA_FOR_TRANSFORM);
        
        // Step 3: Test S-box
        $display("\n[3] S-box Test:");
        test_data = EXP_K1 ^ EXP_K2 ^ EXP_K3 ^ CK0;
        #10;
        $display("    Input: %h", test_data);
        $display("    After S-box: %h", sbox_result);
        
        // Step 4: Test transform
        $display("\n[4] Transform Test:");
        $display("    Input: %h", test_data);
        $display("    After transform: %h", transform_result);
        
        // Step 5: Calculate rk0
        $display("\n[5] rk0 Calculation:");
        $display("    T'(data_for_transform) = %h", transform_result);
        $display("    rk0 = T' ^ K[0] = %h ^ %h = %h", transform_result, EXP_K0, transform_result ^ EXP_K0);
        $display("    Expected rk0: F09279A1");
        
        $display("\n========================================");
        $finish;
    end

endmodule
