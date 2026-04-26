`timescale 1ns/1ps

module tb_key_expansion_debug();
    
    logic clk;
    logic reset_n;
    logic sm4_enable_in;
    logic encdec_sel_in;
    logic enable_key_exp_in;
    logic user_key_valid_in;
    logic [127:0] user_key_in;
    logic key_exp_finished_out;
    logic [31:0] rk00_out;
    
    // Internal signals for debugging
    wire [4:0] count_round;
    wire [4:0] reg_count_round;
    wire [127:0] data_for_round;
    wire [127:0] data_after_round;
    wire [31:0] cki;
    
    key_expansion u_key_expansion (
        .clk(clk),
        .reset_n(reset_n),
        .sm4_enable_in(sm4_enable_in),
        .encdec_sel_in(encdec_sel_in),
        .enable_key_exp_in(enable_key_exp_in),
        .user_key_in(user_key_in),
        .user_key_valid_in(user_key_valid_in),
        .key_exp_finished_out(key_exp_finished_out),
        .rk00_out(rk00_out),
        .rk01_out(),
        .rk02_out(),
        .rk03_out(),
        .rk04_out(),
        .rk05_out(),
        .rk06_out(),
        .rk07_out(),
        .rk08_out(),
        .rk09_out(),
        .rk10_out(),
        .rk11_out(),
        .rk12_out(),
        .rk13_out(),
        .rk14_out(),
        .rk15_out(),
        .rk16_out(),
        .rk17_out(),
        .rk18_out(),
        .rk19_out(),
        .rk20_out(),
        .rk21_out(),
        .rk22_out(),
        .rk23_out(),
        .rk24_out(),
        .rk25_out(),
        .rk26_out(),
        .rk27_out(),
        .rk28_out(),
        .rk29_out(),
        .rk30_out(),
        .rk31_out()
    );
    
    // Bind internal signals
    assign count_round = u_key_expansion.count_round;
    assign reg_count_round = u_key_expansion.reg_count_round;
    assign data_for_round = u_key_expansion.data_for_round;
    assign data_after_round = u_key_expansion.data_after_round;
    assign cki = u_key_expansion.cki;
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    initial begin
        $display("========================================");
        $display("  Key Expansion Debug Test");
        $display("========================================");
        
        reset_n = 0;
        sm4_enable_in = 0;
        encdec_sel_in = 0;
        enable_key_exp_in = 0;
        user_key_valid_in = 0;
        user_key_in = 128'h0123456789abcdeffedcba9876543210;
        
        #20 reset_n = 1;
        #20;
        
        $display("\nStarting key expansion...");
        sm4_enable_in = 1;
        enable_key_exp_in = 1;
        user_key_valid_in = 1;
        
        #10;
        user_key_valid_in = 0;
        
        wait(key_exp_finished_out);
        #20;
        
        $display("\n========================================");
        $display("  Final Results");
        $display("========================================");
        // GM/T 0002-2012: rk0 should be F12186F9 for key 0123456789ABCDEFFEDCBA9876543210.
        // Historical debug value F09279A1 is obsolete and not used as a pass criterion.
        $display("rk[0] = 0x%08h (expected: F12186F9)", rk00_out);
        if (rk00_out == 32'hF12186F9) begin
            $display("PASS: rk[0] is correct!");
        end else begin
            $display("FAIL: rk[0] is incorrect!");
        end
        $display("========================================");
        
        #50;
        $finish;
    end
    
    always @(posedge clk) begin
        if (u_key_expansion.current == 2'b01) begin
            $display("\n--- Cycle: count_round=%0d, reg_count_round=%0d ---", count_round, reg_count_round);
            $display("data_for_round[127:96] = 0x%08h", data_for_round[127:96]);
            $display("data_for_round[95:64]  = 0x%08h", data_for_round[95:64]);
            $display("data_for_round[63:32]  = 0x%08h", data_for_round[63:32]);
            $display("data_for_round[31:0]   = 0x%08h", data_for_round[31:0]);
            $display("data_after_round[127:96] = 0x%08h", data_after_round[127:96]);
            $display("data_after_round[95:64]  = 0x%08h", data_after_round[95:64]);
            $display("data_after_round[63:32]  = 0x%08h", data_after_round[63:32]);
            $display("data_after_round[31:0]   = 0x%08h", data_after_round[31:0]);
            $display("cki = 0x%08h", cki);
        end
    end

endmodule
