`timescale 1ns/1ps

module tb_lprime_detailed();
    
    logic [31:0] data_in;
    logic [31:0] data_out;
    
    transform_for_key_exp u_transform (
        .data_in(data_in),
        .data_after_linear_key_out(data_out)
    );
    
    wire [31:0] word_replaced = u_transform.word_replaced;
    wire [31:0] b_rol13 = {word_replaced[18:0], word_replaced[31:19]};
    wire [31:0] b_rol23 = {word_replaced[8:0], word_replaced[31:9]};
    
    initial begin
        $display("========================================");
        $display("  L' Transform Detailed Test");
        $display("========================================");
        
        data_in = 32'h8283CB69;
        #1;
        
        $display("\nInput: 0x%08h", data_in);
        $display("After S-box: 0x%08h", word_replaced);
        $display("Expected S-box result: 0x8A8A4122");
        
        $display("\nB = 0x%08h", word_replaced);
        $display("B <<< 13 = 0x%08h", b_rol13);
        $display("B <<< 23 = 0x%08h", b_rol23);
        
        $display("\nManual calculation:");
        $display("B XOR (B<<<13) = 0x%08h", word_replaced ^ b_rol13);
        $display("(B XOR (B<<<13)) XOR (B<<<23) = 0x%08h", 
                 (word_replaced ^ b_rol13) ^ b_rol23);
        
        $display("\nOutput: 0x%08h", data_out);
        $display("Expected: 0x52CCEC6C");
        
        if (data_out == 32'h52CCEC6C) begin
            $display("\n-> [PASS] L' transform correct!");
        end else begin
            $display("\n-> [FAIL] L' transform incorrect!");
            $display("Difference: 0x%08h", data_out ^ 32'h52CCEC6C);
        end
        
        $display("\n========================================");
        $finish;
    end

endmodule
