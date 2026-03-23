`timescale 1ns/1ps

module tb_sm4_byte_order();
    
    localparam CLK_PERIOD = 10;
    logic clk;
    
    logic [7:0] sbox_in;
    logic [7:0] sbox_out;
    
    sbox_replace u_sbox (
        .data_in(sbox_in),
        .result_out(sbox_out)
    );
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    initial begin
        $display("========================================");
        $display("  SM4 S-box Byte Order Test");
        $display("========================================");
        
        // SM4 S-box standard values
        // S(0x00) = 0xd6, S(0x01) = 0x90, S(0x02) = 0xe9, S(0x03) = 0xfe
        $display("\nTesting S-box values:");
        
        sbox_in = 8'h00; #10;
        $display("    S(0x%02h) = 0x%02h (expected 0xd6)", sbox_in, sbox_out);
        if (sbox_out != 8'hd6) $display("    ERROR!");
        
        sbox_in = 8'h01; #10;
        $display("    S(0x%02h) = 0x%02h (expected 0x90)", sbox_in, sbox_out);
        if (sbox_out != 8'h90) $display("    ERROR!");
        
        sbox_in = 8'h02; #10;
        $display("    S(0x%02h) = 0x%02h (expected 0xe9)", sbox_in, sbox_out);
        if (sbox_out != 8'he9) $display("    ERROR!");
        
        sbox_in = 8'h03; #10;
        $display("    S(0x%02h) = 0x%02h (expected 0xfe)", sbox_in, sbox_out);
        if (sbox_out != 8'hfe) $display("    ERROR!");
        
        // Test a few more values
        sbox_in = 8'hff; #10;
        $display("    S(0x%02h) = 0x%02h (expected 0x48)", sbox_in, sbox_out);
        if (sbox_out != 8'h48) $display("    ERROR!");
        
        $display("\n========================================");
        $display("  S-box test complete");
        $display("========================================");
        $finish;
    end

endmodule
