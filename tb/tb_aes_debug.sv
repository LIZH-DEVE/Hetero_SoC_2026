`timescale 1ns/1ps

module tb_aes_debug();
    
    localparam CLK_PERIOD = 10;
    
    logic clk, rst_n;
    logic encdec, init, next, ready;
    logic keylen;
    logic [255:0] key;
    logic [127:0] block_in, result;
    logic result_valid;
    
    // FIPS 197 Appendix B Test Vector
    localparam [127:0] AES_KEY = 128'h2b7e151628aed2a6abf7158809cf4f3c;
    localparam [127:0] AES_PLAINTEXT = 128'h3243f6a8885a308d313198a2e0370734;
    localparam [127:0] AES_CIPHERTEXT = 128'h3925841d02dc09fbdc118597196a0b32;
    
    aes_core u_aes_core (
        .clk(clk), 
        .reset_n(rst_n),
        .encdec(encdec),
        .keylen(keylen),
        .init(init),
        .next(next), 
        .ready(ready),
        .key(key), 
        .block(block_in),
        .result(result), 
        .result_valid(result_valid)
    );
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    integer cycle_count;
    
    initial begin
        $display("========================================");
        $display("  AES Core Debug Test");
        $display("========================================");
        
        rst_n = 0;
        encdec = 1;
        keylen = 0;
        init = 0;
        next = 0;
        key = {AES_KEY, 128'd0};
        block_in = 0;
        
        #100 rst_n = 1;
        repeat(5) @(posedge clk);
        
        $display("\nKey: %h", AES_KEY);
        $display("Plaintext: %h", AES_PLAINTEXT);
        $display("Expected Ciphertext: %h", AES_CIPHERTEXT);
        
        // Step 1: Key expansion
        $display("\n[1] Starting key expansion...");
        @(posedge clk);
        init = 1;
        @(posedge clk);
        init = 0;
        
        // Wait for ready to go low then high again
        $display("[2] Waiting for key expansion to complete...");
        cycle_count = 0;
        
        // First wait for ready to go low
        while (ready && cycle_count < 50) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        $display("    Ready went low after %0d cycles", cycle_count);
        
        // Then wait for ready to go high
        cycle_count = 0;
        while (!ready && cycle_count < 50) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        
        if (cycle_count >= 50) begin
            $display("    TIMEOUT waiting for key expansion!");
            $finish;
        end
        
        $display("    Key expansion complete after %0d cycles", cycle_count);
        
        // Wait for signals to stabilize
        repeat(3) @(posedge clk);
        
        // Step 2: Encryption
        $display("\n[3] Starting encryption...");
        $display("    Before: ready=%b", ready);
        
        block_in = AES_PLAINTEXT;
        
        // Send next pulse
        @(posedge clk);
        next = 1;
        @(posedge clk);
        next = 0;
        
        $display("    After next pulse: ready=%b", ready);
        
        // Wait for result_valid
        $display("[4] Waiting for result...");
        cycle_count = 0;
        
        // First wait for ready to go low
        while (ready && cycle_count < 100) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        $display("    Ready went low after %0d cycles", cycle_count);
        
        // Then wait for result_valid
        cycle_count = 0;
        while (!result_valid && cycle_count < 100) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        
        if (cycle_count >= 100) begin
            $display("    TIMEOUT waiting for result!");
            $finish;
        end
        
        $display("\n========================================");
        $display("  Results");
        $display("========================================");
        $display("Ciphertext: %h", result);
        $display("Expected:   %h", AES_CIPHERTEXT);
        
        if (result === AES_CIPHERTEXT) begin
            $display("-> [PASS] AES encryption correct!");
        end else begin
            $display("-> [FAIL] AES encryption mismatch!");
        end
        
        $display("\n========================================");
        $finish;
    end

endmodule
