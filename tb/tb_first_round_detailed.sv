`timescale 1ns/1ps

module tb_first_round_detailed();
    
    localparam CLK_PERIOD = 10;
    
    logic clk, rst_n;
    
    logic sm4_enable_in, sm4_encdec_enable_in, sm4_encdec_sel_in, sm4_valid_in;
    logic sm4_enable_key_exp_in, sm4_user_key_valid_in;
    logic [127:0] sm4_user_key_in, sm4_data_in, sm4_result_out;
    logic sm4_ready_out, sm4_key_exp_ready_out;
    
    localparam [127:0] SM4_KEY = 128'h0123456789abcdeffedcba9876543210;
    
    wire [1:0] key_exp_current;
    wire [4:0] key_exp_count;
    wire [4:0] key_exp_reg_count;
    wire [127:0] data_for_round;
    wire [127:0] data_after_round;
    wire [31:0] cki;
    
    wire [31:0] word_0;
    wire [31:0] word_1;
    wire [31:0] word_2;
    wire [31:0] word_3;
    wire [31:0] k0, k1, k2, k3;
    wire [31:0] data_for_transform;
    wire [31:0] data_after_transform_key;
    wire [4:0] count_round_in;
    
    sm4_top u_sm4_top (
        .clk(clk),
        .reset_n(rst_n),
        .sm4_enable_in(sm4_enable_in),
        .encdec_enable_in(sm4_encdec_enable_in),
        .encdec_sel_in(sm4_encdec_sel_in),
        .valid_in(sm4_valid_in),
        .data_in(sm4_data_in),
        .enable_key_exp_in(sm4_enable_key_exp_in),
        .user_key_valid_in(sm4_user_key_valid_in),
        .user_key_in(sm4_user_key_in),
        .key_exp_ready_out(sm4_key_exp_ready_out),
        .ready_out(sm4_ready_out),
        .result_out(sm4_result_out)
    );
    
    assign key_exp_current = u_sm4_top.u_key.current;
    assign key_exp_count = u_sm4_top.u_key.count_round;
    assign key_exp_reg_count = u_sm4_top.u_key.reg_count_round;
    assign data_for_round = u_sm4_top.u_key.data_for_round;
    assign data_after_round = u_sm4_top.u_key.data_after_round;
    assign cki = u_sm4_top.u_key.cki;
    
    assign word_0 = u_sm4_top.u_key.u_one_round.word_0;
    assign word_1 = u_sm4_top.u_key.u_one_round.word_1;
    assign word_2 = u_sm4_top.u_key.u_one_round.word_2;
    assign word_3 = u_sm4_top.u_key.u_one_round.word_3;
    assign k0 = u_sm4_top.u_key.u_one_round.k0;
    assign k1 = u_sm4_top.u_key.u_one_round.k1;
    assign k2 = u_sm4_top.u_key.u_one_round.k2;
    assign k3 = u_sm4_top.u_key.u_one_round.k3;
    assign data_for_transform = u_sm4_top.u_key.u_one_round.data_for_transform;
    assign data_after_transform_key = u_sm4_top.u_key.u_one_round.data_after_transform_key;
    assign count_round_in = u_sm4_top.u_key.u_one_round.count_round_in;
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    initial begin
        $display("========================================");
        $display("  First Round Detailed Test");
        $display("========================================");
        
        rst_n = 0;
        sm4_enable_in = 0;
        sm4_encdec_enable_in = 0;
        sm4_encdec_sel_in = 0;
        sm4_valid_in = 0;
        sm4_enable_key_exp_in = 0;
        sm4_user_key_valid_in = 0;
        sm4_user_key_in = 0;
        sm4_data_in = 0;
        
        #100 rst_n = 1;
        repeat(3) @(posedge clk);
        
        sm4_user_key_in = SM4_KEY;
        sm4_enable_in = 1'b1;
        sm4_enable_key_exp_in = 1'b1;
        
        @(posedge clk);
        sm4_user_key_valid_in = 1'b1;
        
        #1;
        $display("\n=== Before first clock edge ===");
        $display("  user_key_valid_in=%b, reg_user_key_valid=%b", 
                 sm4_user_key_valid_in, u_sm4_top.u_key.reg_user_key_valid);
        $display("  current=%0d, next=%0d", key_exp_current, u_sm4_top.u_key.next);
        $display("  count=%0d, reg_count=%0d", key_exp_count, key_exp_reg_count);
        $display("  data_for_round = %h", data_for_round);
        $display("  cki = %h (expected: 00070E15)", cki);
        $display("  count_round_in to one_round = %0d", count_round_in);
        $display("  word_0=%h, word_1=%h, word_2=%h, word_3=%h", word_0, word_1, word_2, word_3);
        $display("  k0=%h, k1=%h, k2=%h, k3=%h", k0, k1, k2, k3);
        $display("  data_for_transform = %h", data_for_transform);
        $display("  data_after_transform_key = %h", data_after_transform_key);
        $display("  data_after_round = %h", data_after_round);
        
        @(posedge clk);
        sm4_user_key_valid_in = 1'b0;
        
        #1;
        $display("\n=== After first clock edge ===");
        $display("  current=%0d, next=%0d", key_exp_current, u_sm4_top.u_key.next);
        $display("  count=%0d, reg_count=%0d", key_exp_count, key_exp_reg_count);
        $display("  data_for_round = %h", data_for_round);
        $display("  cki = %h", cki);
        $display("  count_round_in to one_round = %0d", count_round_in);
        $display("  data_after_round = %h", data_after_round);
        
        $display("\n========================================");
        $finish;
    end

endmodule
