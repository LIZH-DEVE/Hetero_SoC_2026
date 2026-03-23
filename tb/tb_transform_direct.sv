`timescale 1ns/1ps

module tb_transform_direct();
    
    logic [31:0] data_in;
    logic [31:0] data_out;
    
    transform_for_key_exp u_dut (
        .data_in(data_in),
        .data_after_linear_key_out(data_out)
    );
    
    wire [31:0] word_replaced = u_dut.word_replaced;
    wire [31:0] b_rol13 = {word_replaced[18:0], word_replaced[31:19]};
    wire [31:0] b_rol23 = {word_replaced[8:0], word_replaced[31:9]};
    wire [31:0] expected_lprime = word_replaced ^ b_rol13 ^ b_rol23;
    
    initial begin
        $display("========================================");
        $display("  Transform Direct Test");
        $display("========================================");
        
        data_in = 32'h8283CB69;
        #1;
        
        $display("\nInput: 0x%08h", data_in);
        $display("After S-box: 0x%08h", word_replaced);
        $display("B <<< 13: 0x%08h", b_rol13);
        $display("B <<< 23: 0x%08h", b_rol23);
        $display("Expected L': 0x%08h", expected_lprime);
        $display("RTL Output: 0x%08h", data_out);
        
        if (data_out == expected_lprime) begin
            $display("\n-> [PASS] Transform correct!");
        end else begin
            $display("\n-> [FAIL] Transform mismatch!");
            $display("Difference: 0x%08h", data_out ^ expected_lprime);
        end
        
        $display("\n========================================");
        $finish;
    end

endmodule
