`timescale 1ns/1ps

module tb_sm4_byte_swap();
    
    localparam [31:0] FK0 = 32'ha3b1bac6;
    localparam [31:0] FK1 = 32'h56aa3350;
    localparam [31:0] FK2 = 32'h677d9197;
    localparam [31:0] FK3 = 32'hb27022dc;
    
    localparam [31:0] MK0_orig = 32'h01234567;
    localparam [31:0] MK1_orig = 32'h89abcdef;
    localparam [31:0] MK2_orig = 32'hfedcba98;
    localparam [31:0] MK3_orig = 32'h76543210;
    
    localparam [31:0] MK0_swap = 32'h67452301;
    localparam [31:0] MK1_swap = 32'hefcdab89;
    localparam [31:0] MK2_swap = 32'h98badcfe;
    localparam [31:0] MK3_swap = 32'h10325476;
    
    localparam [31:0] FK0_s = 32'hc6bab1a3;
    localparam [31:0] FK1_s = 32'h5033aa56;
    localparam [31:0] FK2_s = 32'h97917d67;
    localparam [31:0] FK3_s = 32'hdc2270b2;
    
    initial begin
        $display("========================================");
        $display("  SM4 Byte Order Investigation");
        $display("========================================");
        
        $display("\n[1] Original interpretation (no byte swap):");
        $display("    MK[0] = %h, FK0 = %h, K[0] = %h", MK0_orig, FK0, MK0_orig ^ FK0);
        $display("    MK[1] = %h, FK1 = %h, K[1] = %h", MK1_orig, FK1, MK1_orig ^ FK1);
        $display("    MK[2] = %h, FK2 = %h, K[2] = %h", MK2_orig, FK2, MK2_orig ^ FK2);
        $display("    MK[3] = %h, FK3 = %h, K[3] = %h", MK3_orig, FK3, MK3_orig ^ FK3);
        
        $display("\n[2] Byte-swapped interpretation:");
        $display("    MK[0] = %h, FK0 = %h, K[0] = %h", MK0_swap, FK0, MK0_swap ^ FK0);
        $display("    MK[1] = %h, FK1 = %h, K[1] = %h", MK1_swap, FK1, MK1_swap ^ FK1);
        $display("    MK[2] = %h, FK2 = %h, K[2] = %h", MK2_swap, FK2, MK2_swap ^ FK2);
        $display("    MK[3] = %h, FK3 = %h, K[3] = %h", MK3_swap, FK3, MK3_swap ^ FK3);
        
        $display("\n[3] Original MK with swapped FK:");
        $display("    K[0] = %h", MK0_orig ^ FK0_s);
        $display("    K[1] = %h", MK1_orig ^ FK1_s);
        $display("    K[2] = %h", MK2_orig ^ FK2_s);
        $display("    K[3] = %h", MK3_orig ^ FK3_s);
        
        $display("\n[4] Swapped MK with swapped FK:");
        $display("    K[0] = %h", MK0_swap ^ FK0_s);
        $display("    K[1] = %h", MK1_swap ^ FK1_s);
        $display("    K[2] = %h", MK2_swap ^ FK2_s);
        $display("    K[3] = %h", MK3_swap ^ FK3_s);
        
        $display("\n========================================");
        $display("  Expected rk0 = F09279A1");
        $display("========================================");
        $finish;
    end

endmodule
