`timescale 1ns/1ps

module tb_rol_test();
    
    logic [31:0] b;
    logic [31:0] rol13_direct;
    logic [31:0] rol23_direct;
    
    assign rol13_direct = {b[18:0], b[31:19]};
    assign rol23_direct = {b[8:0], b[31:9]};
    
    initial begin
        $display("========================================");
        $display("  Rotate Left Test");
        $display("========================================");
        
        b = 32'h8AD24122;
        #1;
        
        $display("\nB = 0x%08h", b);
        $display("B <<< 13 (RTL) = 0x%08h", rol13_direct);
        $display("B <<< 23 (RTL) = 0x%08h", rol23_direct);
        
        $display("\nExpected:");
        $display("B <<< 13 = 0x4824515A");
        $display("B <<< 23 = 0x12156922");
        
        $display("\nL'(B) = B ^ (B<<<13) ^ (B<<<23)");
        $display("L'(B) = 0x%08h ^ 0x%08h ^ 0x%08h", b, rol13_direct, rol23_direct);
        $display("L'(B) = 0x%08h", b ^ rol13_direct ^ rol23_direct);
        
        $display("\nExpected L'(B) = 0x53B37958");
        
        $display("\n========================================");
        $finish;
    end

endmodule
