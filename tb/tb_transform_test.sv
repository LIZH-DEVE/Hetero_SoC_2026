`timescale 1ns/1ps

module tb_transform_test();
    
    logic [31:0] data_in;
    logic [31:0] data_out;
    
    transform_for_key_exp u_transform (
        .data_in(data_in),
        .data_after_linear_key_out(data_out)
    );
    
    logic [31:0] expected_lprime;
    logic [31:0] b, b_rol13, b_rol23;
    
    assign b = data_out;
    
    initial begin
        $display("========================================");
        $display("  SM4 L' Transform Test");
        $display("========================================");
        
        $display("\nL'(B) = B XOR (B <<< 13) XOR (B <<< 23)");
        
        data_in = 32'h00000000;
        #1;
        $display("\nInput: 0x%08h", data_in);
        $display("Output: 0x%08h (expected: 0x00000000)", data_out);
        
        data_in = 32'h12345678;
        #1;
        $display("\nInput: 0x%08h", data_in);
        $display("Output: 0x%08h", data_out);
        
        data_in = 32'hA3B1BAC6;
        #1;
        $display("\nInput: 0x%08h (FK0)", data_in);
        $display("Output: 0x%08h", data_out);
        
        data_in = 32'h01234567;
        #1;
        $display("\nInput: 0x%08h (test key word)", data_in);
        $display("Output: 0x%08h", data_out);
        
        $display("\n========================================");
        $display("  Testing S-box values");
        $display("========================================");
        
        data_in = 32'h01010101;
        #1;
        $display("\nInput: 0x%08h", data_in);
        $display("After S-box: should be 0x90909090");
        $display("Output: 0x%08h", data_out);
        
        $display("\n========================================");
        $finish;
    end

endmodule
