`timescale 1ns/1ps

module tb_rol_correct();
    
    logic [31:0] b;
    logic [31:0] rol13;
    logic [31:0] rol23;
    
    assign rol13 = {b[18:0], b[31:19]};
    assign rol23 = {b[8:0], b[31:9]};
    
    initial begin
        $display("========================================");
        $display("  Rotate Left Correct Test");
        $display("========================================");
        
        b = 32'h8AD24122;
        #1;
        
        $display("\nB = 0x%08h", b);
        $display("B <<< 13 = 0x%08h", rol13);
        $display("B <<< 23 = 0x%08h", rol23);
        
        $display("\nExpected:");
        $display("B <<< 13 = 0x4824515A");
        $display("B <<< 23 = 0x91456920");
        
        $display("\nL'(B) = B ^ (B<<<13) ^ (B<<<23)");
        $display("L'(B) = 0x%08h ^ 0x%08h ^ 0x%08h", b, rol13, rol23);
        $display("L'(B) = 0x%08h", b ^ rol13 ^ rol23);
        
        $display("\nExpected L'(B) = 0x53B37958");
        
        if ((b ^ rol13 ^ rol23) == 32'h53B37958) begin
            $display("\n-> [PASS] L' calculation correct!");
        end else begin
            $display("\n-> [FAIL] L' calculation incorrect!");
        end
        
        $display("\n========================================");
        $finish;
    end

endmodule
