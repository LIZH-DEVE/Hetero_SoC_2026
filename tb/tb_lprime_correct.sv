`timescale 1ns/1ps

module tb_lprime_correct();
    
    logic [31:0] data_in;
    logic [31:0] data_out;
    
    transform_for_key_exp u_transform (
        .data_in(data_in),
        .data_after_linear_key_out(data_out)
    );
    
    wire [31:0] word_replaced = u_transform.word_replaced;
    wire [31:0] b_rol13 = {word_replaced[18:0], word_replaced[31:19]};
    wire [31:0] b_rol23 = {word_replaced[8:0], word_replaced[31:9]};
    wire [31:0] expected_lprime = word_replaced ^ b_rol13 ^ b_rol23;
    
    initial begin
        $display("========================================");
        $display("  L' Transform Correct Test");
        $display("========================================");
        
        $display("\nL'(B) = B XOR (B <<< 13) XOR (B <<< 23)");
        
        data_in = 32'h8283CB69;
        #1;
        
        $display("\n=== Test 1: Input = 0x%08h ===", data_in);
        $display("After S-box: 0x%08h", word_replaced);
        $display("B <<< 13:   0x%08h", b_rol13);
        $display("B <<< 23:   0x%08h", b_rol23);
        $display("Expected L': 0x%08h", expected_lprime);
        $display("RTL Output:  0x%08h", data_out);
        
        if (data_out == expected_lprime) begin
            $display("-> [PASS] L' transform correct!");
        end else begin
            $display("-> [FAIL] L' transform incorrect!");
            $display("Difference: 0x%08h", data_out ^ expected_lprime);
        end
        
        $display("\n=== Expected SM4 rk[0] Calculation ===");
        $display("rk[0] = L'(8283CB69) XOR k0");
        $display("rk[0] = 0x%08h XOR 0xA292FFA1 = 0x%08h", 
                 expected_lprime, expected_lprime ^ 32'hA292FFA1);
        $display("Expected rk[0] = 0xF09279A1");
        
        if ((expected_lprime ^ 32'hA292FFA1) == 32'hF09279A1) begin
            $display("-> [PASS] rk[0] calculation correct!");
        end else begin
            $display("-> [FAIL] rk[0] calculation incorrect!");
        end
        
        $display("\n========================================");
        $finish;
    end

endmodule
