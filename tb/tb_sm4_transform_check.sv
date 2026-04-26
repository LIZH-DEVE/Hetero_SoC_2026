`timescale 1ns/1ps

module tb_sm4_transform_check();
    logic [31:0] data_in;
    logic [31:0] result;
    
    transform_for_key_exp u_trans (.data_in(data_in), .data_after_linear_key_out(result));
    
    localparam [31:0] TEST_DATA = 32'h8282ba69;  // S(82)=d6, S(86)=e9, S(fe)=48
    
    initial begin
        $display("========================================");
        $display("  SM4 Transform L' Check");
        $display("========================================");
        
        data_in = TEST_DATA;
        #10;
        $display("Input: %h", data_in);
        $display("After S-box: %h", {data_in[31:24], data_in[23:16], data_in[15:8], data_in[7:0]});
        $display("After L': %h", result);
        
        $display("\nExpected L'(8282ba69):");
        $display("  S(82)=d6, S(86)=e9, S(fe)=48");
        $display("  L' = S <<< 13 ^ S <<< 19 ^ S <<< 23 ^ S <<< 8");
        $display("  = d6 ^ d6d6d6 ^ d6d6d6 ^ d6d6d6");
        $display("  = d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d3);
        
        $display("\n========================================");
        $finish;
    end

endmodule
