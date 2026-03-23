`timescale 1ns/1ps

module tb_rol_verify();
    
    logic [31:0] b;
    logic [31:0] rol13;
    logic [31:0] rol23;
    
    assign rol13 = {b[18:0], b[31:19]};
    assign rol23 = {b[22:0], b[31:23]};
    
    initial begin
        $display("========================================");
        $display("  Rotate Left Verification Test");
        $display("========================================");
        
        b = 32'h8AD24122;
        #1;
        
        $display("\nB = 0x%08h", b);
        $display("B <<< 13 = 0x%08h", rol13);
        $display("B <<< 23 = 0x%08h", rol23);
        
        $display("\nManual calculation:");
        $display("B[18:0] = 0x%07h (19 bits)", b[18:0]);
        $display("B[31:19] = 0x%04h (13 bits)", b[31:19]);
        $display("B[22:0] = 0x%08h (23 bits)", b[22:0]);
        $display("B[31:23] = 0x%02h (9 bits)", b[31:23]);
        
        $display("\nExpected:");
        $display("B <<< 13 = 0x4824515A");
        $display("B <<< 23 = 0x91456920");
        
        $display("\nL'(B) = B ^ (B<<<13) ^ (B<<<23)");
        $display("L'(B) = 0x%08h ^ 0x%08h ^ 0x%08h", b, rol13, rol23);
        $display("L'(B) = 0x%08h", b ^ rol13 ^ rol23);
        
        $display("\nExpected L'(B) = 0x53B37958");
        
        $display("\n========================================");
        $finish;
    end

endmodule
