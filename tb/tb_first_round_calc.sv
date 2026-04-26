`timescale 1ns/1ps

module tb_first_round_calc();
    
    logic [31:0] data_in;
    logic [31:0] data_out;
    
    transform_for_key_exp u_transform (
        .data_in(data_in),
        .data_after_linear_key_out(data_out)
    );
    
    wire [31:0] word_replaced = u_transform.word_replaced;
    
    initial begin
        $display("========================================");
        $display("  First Round Calculation Test");
        $display("========================================");
        
        $display("\n=== SM4 Key Expansion First Round ===");
        $display("MK = 0123456789abcdeffedcba9876543210");
        
        $display("\nMK0 = 01234567, MK1 = 89abcdef, MK2 = fedcba98, MK3 = 76543210");
        
        $display("\nFK0 = A3B1BAC6, FK1 = 56AA3350, FK2 = 677D9197, FK3 = B27022DC");
        
        $display("\nK0 = MK0 XOR FK0 = 01234567 XOR A3B1BAC6 = A292FFA1");
        $display("K1 = MK1 XOR FK1 = 89abcdef XOR 56aa3350 = DF01FEBF");
        $display("K2 = MK2 XOR FK2 = fedcba98 XOR 677d9197 = 99A12B0F");
        $display("K3 = MK3 XOR FK3 = 76543210 XOR b27022dc = C42410CC");
        
        $display("\nCK0 = 00070E15");
        
        $display("\nK1 XOR K2 XOR K3 XOR CK0:");
        $display("  DF01FEBF XOR 99A12B0F = 46A1D5B0");
        $display("  46A1D5B0 XOR C42410CC = 8285C57C");
        $display("  8285C57C XOR 00070E15 = 8282CB69");
        
        data_in = 32'h8282CB69;
        #1;
        
        $display("\nL' transform of 8282CB69:");
        $display("  After S-box: %h", word_replaced);
        $display("  L' output: %h", data_out);
        
        $display("\nFirst round key rk[0] = L'(8282CB69) XOR K0");
        $display("  = %h XOR A292FFA1", data_out);
        $display("  = %h", data_out ^ 32'hA292FFA1);
        
        $display("\nExpected rk[0] = F09279A1");
        
        $display("\n========================================");
        $finish;
    end

endmodule
