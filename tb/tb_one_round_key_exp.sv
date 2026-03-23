`timescale 1ns/1ps

module tb_one_round_key_exp();
    
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
        $display("  one_round_for_key_exp Test");
        $display("========================================");
        
        data_in = SM4_KEY;
        ck_parameter_in = CK0;
        
        $display("\n=== Test with count_round_in = 0 ===");
        count_round_in = 5'd0;
        #1;
        
        $display("Input data: %h", data_in);
        $display("word_0 = %h (expected: 01234567)", word_0);
        $display("word_1 = %h (expected: 89abcdef)", word_1);
        $display("word_2 = %h (expected: fedcba98)", word_2);
        $display("word_3 = %h (expected: 76543210)", word_3);
        
        $display("\nK = word XOR FK:");
        $display("k0 = word_0 XOR FK0 = %h XOR %h = %h", word_0, FK0, k0);
        $display("  expected: 01234567 XOR A3B1BAC6 = A292FFA1");
        $display("k1 = word_1 XOR FK1 = %h XOR %h = %h", word_1, FK1, k1);
        $display("  expected: 89ABCDEF XOR 56AA3350 = DF01FEBF");
        $display("k2 = word_2 XOR FK2 = %h XOR %h = %h", word_2, FK2, k2);
        $display("  expected: FEDCBA98 XOR 677D9197 = 99A12B0F");
        $display("k3 = word_3 XOR FK3 = %h XOR %h = %h", word_3, FK3, k3);
        $display("  expected: 76543210 XOR B27022DC = C42410CC");
        
        $display("\nData for transform:");
        $display("k1 XOR k2 XOR k3 XOR CK0 = %h", data_for_transform);
        $display("  expected: DF01FEBF XOR 99A12B0F XOR C42410CC XOR 00070E15 = 5B83EBD5");
        
        $display("\nAfter L' transform: %h", data_after_transform_key);
        
        $display("\nResult: %h", result_out);
        $display("  expected format: {k1, k2, k3, L'(data_for_transform) XOR k0}");
        $display("  expected: {DF01FEBF, 99A12B0F, C42410CC, ?}");
        
        $display("\n=== Test with count_round_in = 1 ===");
        count_round_in = 5'd1;
        #1;
        
        $display("Result: %h", result_out);
        $display("  expected format: {word_1, word_2, word_3, L'(data_for_transform) XOR word_0}");
        
        $display("\n========================================");
        $finish;
    end

endmodule
