`timescale 1ns/1ps

module tb_sm4_debug2();
    
    localparam CLK_PERIOD = 10;
    
    logic clk, rst_n;
    
    logic sm4_enable_in, sm4_encdec_enable_in, sm4_encdec_sel_in, sm4_valid_in;
    logic sm4_enable_key_exp_in, sm4_user_key_valid_in;
    logic [127:0] sm4_user_key_in, sm4_data_in, sm4_result_out;
    logic sm4_ready_out, sm4_key_exp_ready_out;
    
    logic [1:0] key_exp_current, key_exp_next;
    logic [4:0] key_exp_count, key_exp_reg_count;
    logic key_exp_finished;
    logic reg_user_key_valid;
    
    localparam [127:0] SM4_KEY = 128'h0123456789abcdeffedcba9876543210;
    
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
    assign key_exp_next = u_sm4_top.u_key.next;
    assign key_exp_count = u_sm4_top.u_key.count_round;
    assign key_exp_reg_count = u_sm4_top.u_key.reg_count_round;
    assign key_exp_finished = u_sm4_top.u_key.key_exp_finished_out;
    assign reg_user_key_valid = u_sm4_top.u_key.reg_user_key_valid;
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    initial begin
        $display("========================================");
        $display("  SM4 State Machine Debug Test");
        $display("========================================");
        
        rst_n = 0;
        sm4_enable_in = 0;
        sm4_encdec_enable_in = 0;
        sm4_encdec_sel_in = 1;
        sm4_valid_in = 0;
        sm4_enable_key_exp_in = 0;
        sm4_user_key_valid_in = 0;
        sm4_user_key_in = 0;
        sm4_data_in = 0;
        
        #100 rst_n = 1;
        repeat(3) @(posedge clk);
        
        $display("\n=== Testing Key Expansion State Machine ===");
        $display("State encoding: IDLE=0, KEY_EXPANSION=1");
        
        sm4_user_key_in = SM4_KEY;
        sm4_data_in = 128'h0123456789abcdeffedcba9876543210;
        sm4_encdec_sel_in = 1'b1;
        
        $display("\n[Phase 1] Enable signals...");
        sm4_enable_in = 1'b1;
        sm4_enable_key_exp_in = 1'b1;
        
        #1;
        $display("  After setting enables (combinatorial):");
        $display("    sm4_enable_in=%b, enable_key_exp_in=%b", sm4_enable_in, sm4_enable_key_exp_in);
        $display("    current=%0d, next=%0d", key_exp_current, key_exp_next);
        $display("    reg_user_key_valid=%b, user_key_valid_in=%b", reg_user_key_valid, sm4_user_key_valid_in);
        $display("    Condition check: enable_key_exp=%b, ~reg_valid=%b, valid_in=%b",
                 sm4_enable_key_exp_in, ~reg_user_key_valid, sm4_user_key_valid_in);
        
        @(posedge clk);
        #1;
        $display("\n[Phase 2] After first clock edge:");
        $display("    current=%0d, next=%0d", key_exp_current, key_exp_next);
        $display("    reg_user_key_valid=%b", reg_user_key_valid);
        
        $display("\n[Phase 3] Setting user_key_valid pulse...");
        sm4_user_key_valid_in = 1'b1;
        
        #1;
        $display("  After setting user_key_valid (combinatorial):");
        $display("    current=%0d, next=%0d", key_exp_current, key_exp_next);
        $display("    reg_user_key_valid=%b, user_key_valid_in=%b", reg_user_key_valid, sm4_user_key_valid_in);
        $display("    Condition: enable_key_exp=%b && ~reg_valid=%b && valid=%b = %b",
                 sm4_enable_key_exp_in, ~reg_user_key_valid, sm4_user_key_valid_in,
                 (sm4_enable_key_exp_in && ~reg_user_key_valid && sm4_user_key_valid_in));
        
        @(posedge clk);
        #1;
        $display("\n[Phase 4] After clock edge with user_key_valid=1:");
        $display("    current=%0d, next=%0d", key_exp_current, key_exp_next);
        $display("    reg_user_key_valid=%b", reg_user_key_valid);
        $display("    count_round=%0d, reg_count_round=%0d", key_exp_count, key_exp_reg_count);
        
        sm4_user_key_valid_in = 1'b0;
        
        @(posedge clk);
        #1;
        $display("\n[Phase 5] After clock edge with user_key_valid=0:");
        $display("    current=%0d, next=%0d", key_exp_current, key_exp_next);
        $display("    count_round=%0d, reg_count_round=%0d", key_exp_count, key_exp_reg_count);
        
        repeat(5) @(posedge clk);
        #1;
        $display("\n[Phase 6] After 5 more cycles:");
        $display("    current=%0d, next=%0d", key_exp_current, key_exp_next);
        $display("    count_round=%0d, reg_count_round=%0d", key_exp_count, key_exp_reg_count);
        $display("    key_exp_finished=%b, key_exp_ready=%b", key_exp_finished, sm4_key_exp_ready_out);
        
        $display("\n========================================");
        $finish;
    end

endmodule
