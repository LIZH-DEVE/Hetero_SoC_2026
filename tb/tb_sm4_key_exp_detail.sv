`timescale 1ns/1ps

module tb_sm4_key_exp_detail();
    
    localparam CLK_PERIOD = 10;
    
    logic clk, rst_n;
    
    logic sm4_enable_in, enable_key_exp_in, user_key_valid_in;
    logic encdec_sel_in;
    logic [127:0] user_key_in;
    logic key_exp_ready_out;
    
    logic [31:0] rk [0:31];
    logic [127:0] reg_data_after_round;
    logic [1:0] current_state;
    logic [4:0] count_round_val;
    logic [4:0] reg_count_round_val;
    logic [31:0] cki_val;
    logic [127:0] data_after_round_val;
    
    localparam [127:0] SM4_KEY = 128'h0123456789abcdeffedcba9876543210;
    
    key_expansion u_key_exp (
        .clk(clk),
        .reset_n(rst_n),
        .sm4_enable_in(sm4_enable_in),
        .encdec_sel_in(encdec_sel_in),
        .enable_key_exp_in(enable_key_exp_in),
        .user_key_valid_in(user_key_valid_in),
        .user_key_in(user_key_in),
        .key_exp_finished_out(key_exp_ready_out),
        .rk00_out(rk[0]),
        .rk01_out(rk[1]),
        .rk02_out(rk[2]),
        .rk03_out(rk[3]),
        .rk04_out(rk[4]),
        .rk05_out(rk[5]),
        .rk06_out(rk[6]),
        .rk07_out(rk[7]),
        .rk08_out(rk[8]),
        .rk09_out(rk[9]),
        .rk10_out(rk[10]),
        .rk11_out(rk[11]),
        .rk12_out(rk[12]),
        .rk13_out(rk[13]),
        .rk14_out(rk[14]),
        .rk15_out(rk[15]),
        .rk16_out(rk[16]),
        .rk17_out(rk[17]),
        .rk18_out(rk[18]),
        .rk19_out(rk[19]),
        .rk20_out(rk[20]),
        .rk21_out(rk[21]),
        .rk22_out(rk[22]),
        .rk23_out(rk[23]),
        .rk24_out(rk[24]),
        .rk25_out(rk[25]),
        .rk26_out(rk[26]),
        .rk27_out(rk[27]),
        .rk28_out(rk[28]),
        .rk29_out(rk[29]),
        .rk30_out(rk[30]),
        .rk31_out(rk[31])
    );
    
    assign reg_data_after_round = u_key_exp.reg_data_after_round;
    assign current_state = u_key_exp.current;
    assign count_round_val = u_key_exp.count_round;
    assign reg_count_round_val = u_key_exp.reg_count_round;
    assign cki_val = u_key_exp.cki;
    assign data_after_round_val = u_key_exp.data_after_round;
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    integer cycle_count;
    
    initial begin
        $display("========================================");
        $display("  SM4 Key Expansion Detailed Test");
        $display("========================================");
        
        rst_n = 0;
        sm4_enable_in = 0;
        enable_key_exp_in = 0;
        user_key_valid_in = 0;
        user_key_in = 0;
        encdec_sel_in = 0;
        
        #100 rst_n = 1;
        repeat(5) @(posedge clk);
        
        $display("\nKey: %h", SM4_KEY);
        $display("\nExpected rk0 = F09279A1 (from standard)");
        
        user_key_in = SM4_KEY;
        encdec_sel_in = 0;
        
        $display("\n[1] Starting key expansion...");
        
        @(negedge clk);
        sm4_enable_in = 1'b1;
        enable_key_exp_in = 1'b1;
        user_key_valid_in = 1'b1;
        
        @(posedge clk);
        $display("    Cycle 0: current=%b, reg_count_round=%0d, cki=%h, data_after_round=%h", 
            current_state, count_round_val, reg_count_round_val, cki_val, data_after_round_val);
        
        user_key_valid_in = 1'b0;
        
        cycle_count = 0;
        while (!key_exp_ready_out && cycle_count < 40) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            $display("    Cycle %0d: current=%b, reg_count_round=%0d, cki=%h, data_after_round=%h", 
                current_state, count_round_val, reg_count_round_val, cki_val, data_after_round_val);
        end
        
        if (cycle_count >= 40) begin
            $display("    TIMEOUT!");
            $finish;
        end
        
        $display("\n[2] Key expansion complete!");
        $display("\n    Generated round keys:");
        for (int i = 0; i < 8; i++) begin
            $display("    rk%0d = %h", i, rk[i]);
        end
        
        $display("\n    Expected (from standard):");
        $display("    rk0  = F09279A1");
        $display("    rk1  = 0A2F3E83");
        $display("    rk22 = A1B9C978");
        $display("    rk3  = E7C3E25A");
        
        $display("\n========================================");
        $finish;
    end

endmodule
