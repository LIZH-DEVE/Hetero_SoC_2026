`timescale 1ns/1ps

module tb_lprime_transform();
    
    logic [31:0] data_in;
    logic [31:0] data_out;
    
    transform_for_key_exp u_transform (
        .data_in(data_in),
        .data_after_linear_key_out(data_out)
    );
    
    wire [31:0] word_replaced = u_transform.word_replaced;
    wire [31:0] b_rol13 = {word_replaced[18:0], word_replaced[31:19]};
    wire [31:0] b_rol23 = {word_replaced[8:0], word_replaced[31:23]};
    wire [31:0] expected = word_replaced ^ b_rol13 ^ b_rol23;
    
    initial begin
        $display("========================================");
        $display("  L' Transform Verification Test");
        $display("========================================");
        
        $display("\nL'(B) = B XOR (B <<< 13) XOR (B <<< 23)");
        
        data_in = 32'h00000000;
        #1;
        $display("\nTest 1: Input = 0x%08h", data_in);
        $display("  After S-box: 0x%08h", word_replaced);
        $display("  B <<< 13:    0x%08h", b_rol13);
        $display("  B <<< 23:    0x%08h", b_rol23);
        $display("  Output:      0x%08h", data_out);
        $display("  Expected:    0x%08h", expected);
        $display("  Match: %s", (data_out == expected) ? "YES" : "NO");
        
        data_in = 32'hA3B1BAC6;
        #1;
        $display("\nTest 2: Input = 0x%08h (FK0)", data_in);
        $display("  After S-box: 0x%08h", word_replaced);
        $display("  B <<< 13:    0x%08h", b_rol13);
        $display("  B <<< 23:    0x%08h", b_rol23);
        $display("  Output:      0x%08h", data_out);
        $display("  Expected:    0x%08h", expected);
        $display("  Match: %s", (data_out == expected) ? "YES" : "NO");
        
        data_in = 32'h12345678;
        #1;
        $display("\nTest 3: Input = 0x%08h", data_in);
        $display("  After S-box: 0x%08h", word_replaced);
        $display("  B <<< 13:    0x%08h", b_rol13);
        $display("  B <<< 23:    0x%08h", b_rol23);
        $display("  Output:      0x%08h", data_out);
        $display("  Expected:    0x%08h", expected);
        $display("  Match: %s", (data_out == expected) ? "YES" : "NO");
        
        data_in = 32'hFFFFFFFF;
        #1;
        $display("\nTest 4: Input = 0x%08h", data_in);
        $display("  After S-box: 0x%08h", word_replaced);
        $display("  B <<< 13:    0x%08h", b_rol13);
        $display("  B <<< 23:    0x%08h", b_rol23);
        $display("  Output:      0x%08h", data_out);
        $display("  Expected:    0x%08h", expected);
        $display("  Match: %s", (data_out == expected) ? "YES" : "NO");
        
        $display("\n========================================");
        $display("  Verifying S-box values");
        $display("========================================");
        
        data_in = 32'h01010101;
        #1;
        $display("\nInput = 0x%08h", data_in);
        $display("  S(0x01) should be 0x90");
        $display("  After S-box: 0x%08h (should be 0x90909090)", word_replaced);
        
        data_in = 32'hA3B1BAC6;
        #1;
        $display("\nInput = 0x%08h (FK0)", data_in);
        $display("  S(0xA3) = 0x%02h, S(0xB1) = 0x%02h, S(0xBA) = 0x%02h, S(0xC6) = 0x%02h",
                 u_transform.byte_0_replaced, u_transform.byte_1_replaced,
                 u_transform.byte_2_replaced, u_transform.byte_3_replaced);
        
        $display("\n========================================");
        $finish;
    end

endmodule
