`timescale 1ns/1ps

module tb_transform_internal();
    
    logic [31:0] data_in;
    logic [31:0] data_out;
    
    transform_for_key_exp u_dut (
        .data_in(data_in),
        .data_after_linear_key_out(data_out)
    );
    
    wire [31:0] word_replaced = u_dut.word_replaced;
    wire [31:0] rtl_rol13 = {word_replaced[18:0], word_replaced[31:19]};
    wire [31:0] rtl_rol23 = {word_replaced[8:0], word_replaced[31:9]};
    wire [31:0] rtl_xor1 = word_replaced ^ rtl_rol13;
    wire [31:0] rtl_final = rtl_xor1 ^ rtl_rol23;
    
    initial begin
        $display("========================================");
        $display("  Transform Internal Signal Test");
        $display("========================================");
        
        data_in = 32'h8283CB69;
        #1;
        
        $display("\nInput: 0x%08h", data_in);
        $display("\nS-box output:");
        $display("  word_replaced = 0x%08h", word_replaced);
        
        $display("\nRotate Left calculations:");
        $display("  RTL B <<< 13 = 0x%08h", rtl_rol13);
        $display("  RTL B <<< 23 = 0x%08h", rtl_rol23);
        
        $display("\nXOR calculations:");
        $display("  B ^ (B<<<13) = 0x%08h", rtl_xor1);
        $display("  (B^B<<<13) ^ (B<<<23) = 0x%08h", rtl_final);
        
        $display("\nRTL Output: 0x%08h", data_out);
        
        $display("\nExpected:");
        $display("  B <<< 13 = 0x4824515A");
        $display("  B <<< 23 = 0x91456920");
        $display("  L'(B) = 0x53B37958");
        
        $display("\n========================================");
        $finish;
    end

endmodule
