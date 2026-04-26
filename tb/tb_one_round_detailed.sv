`timescale 1ns/1ps

module tb_one_round_detailed();
    
    logic [127:0] data_in;
    logic [31:0] ck_parameter_in;
    logic [4:0] count_round_in;
    logic [127:0] result_out;
    
    one_round_for_key_exp u_dut (
        .count_round_in(count_round_in),
        .data_in(data_in),
        .ck_parameter_in(ck_parameter_in),
        .result_out(result_out)
    );
    
    wire [31:0] word_0 = u_dut.word_0;
    wire [31:0] word_1 = u_dut.word_1;
    wire [31:0] word_2 = u_dut.word_2;
    wire [31:0] word_3 = u_dut.word_3;
    wire [31:0] k0 = u_dut.k0;
    wire [31:0] k1 = u_dut.k1;
    wire [31:0] k2 = u_dut.k2;
    wire [31:0] k3 = u_dut.k3;
    wire [31:0] data_for_transform = u_dut.data_for_transform;
    wire [31:0] data_after_transform_key = u_dut.data_after_transform_key;
    
    localparam [127:0] SM4_KEY = 128'h0123456789abcdeffedcba9876543210;
    localparam [31:0] FK0 = 32'hA3B1BAC6;
    localparam [31:0] FK1 = 32'h56AA3350;
    localparam [31:0] FK2 = 32'h677D9197;
    localparam [31:0] FK3 = 32'hB27022DC;
    localparam [31:0] CK0 = 32'h00070E15;
    
    initial begin
        $display("========================================");
        $display("  one_round_for_key_exp Detailed Test");
        $display("========================================");
        
        data_in = SM4_KEY;
        ck_parameter_in = CK0;
        count_round_in = 5'd0;
        #1;
        
        $display("\n=== Round 0 (First Round) ===");
        $display("Input data: %h", data_in);
        $display("CK: %h", ck_parameter_in);
        
        $display("\nWord split:");
        $display("  word_0 = %h (MK0)", word_0);
        $display("  word_1 = %h (MK1)", word_1);
        $display("  word_2 = %h (MK2)", word_2);
        $display("  word_3 = %h (MK3)", word_3);
        
        $display("\nK = MK XOR FK:");
        $display("  k0 = %h (expected: A292FFA1)", k0);
        $display("  k1 = %h (expected: DF01FEBF)", k1);
        $display("  k2 = %h (expected: 99A12B0F)", k2);
        $display("  k3 = %h (expected: C42410CC)", k3);
        
        $display("\nData for transform:");
        $display("  k1 XOR k2 XOR k3 XOR CK0 = %h", data_for_transform);
        $display("  Expected: DF01FEBF XOR 99A12B0F XOR C42410CC XOR 00070E15 = 8283CB69");
        
        $display("\nAfter L' transform: %h", data_after_transform_key);
        
        $display("\nResult: %h", result_out);
        $display("  result[127:96] = %h (should be k1)", result_out[127:96]);
        $display("  result[95:64] = %h (should be k2)", result_out[95:64]);
        $display("  result[63:32] = %h (should be k3)", result_out[63:32]);
        $display("  result[31:0] = %h (should be rk[0])", result_out[31:0]);
        
        $display("\nExpected rk[0] = L'(8283CB69) XOR k0 = F09279A1");
        
        $display("\n=== Round 1 ===");
        count_round_in = 5'd1;
        data_in = result_out;
        ck_parameter_in = 32'h1c232a31;
        #1;
        
        $display("Input data: %h", data_in);
        $display("CK: %h", ck_parameter_in);
        $display("Result: %h", result_out);
        $display("  result[31:0] = %h (should be rk[1])", result_out[31:0]);
        
        $display("\n========================================");
        $finish;
    end

endmodule
