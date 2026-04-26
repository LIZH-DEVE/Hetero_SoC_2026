`timescale 1ns/1ps

module tb_sm4_debug_full();
    
    localparam CLK_PERIOD = 10;
    
    logic clk, rst_n;
    
    logic sm4_enable_in, sm4_encdec_enable_in, sm4_encdec_sel_in, sm4_valid_in;
    logic sm4_enable_key_exp_in, sm4_user_key_valid_in;
    logic [127:0] sm4_user_key_in, sm4_data_in, sm4_result_out;
    logic sm4_ready_out, sm4_key_exp_ready_out;
    
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
    
    wire [1:0] key_exp_current = u_sm4_top.u_key.current;
    wire [1:0] key_exp_next = u_sm4_top.u_key.next;
    wire [4:0] key_exp_count = u_sm4_top.u_key.count_round;
    wire [4:0] key_exp_reg_count = u_sm4_top.u_key.reg_count_round;
    wire key_exp_finished = u_sm4_top.u_key.key_exp_finished_out;
    wire reg_user_key_valid = u_sm4_top.u_key.reg_user_key_valid;
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    integer cycle_count;
    
    initial begin
        $display("========================================");
        $display("  SM4 Debug Full Test");
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
        repeat(5) @(posedge clk);
        
        $display("\n=== Setting up signals ===");
        sm4_user_key_in = SM4_KEY;
        sm4_data_in = 128'h0123456789abcdeffedcba9876543210;
        sm4_encdec_sel_in = 1'b0;
        
        $display("  Key: %h", sm4_user_key_in);
        
        $display("\n=== Step 1: Enable SM4 ===");
        sm4_enable_in = 1'b1;
        @(posedge clk);
        #1;
        $display("  After enable: current=%0d, next=%0d", key_exp_current, key_exp_next);
        $display("  enable_key_exp=%b, reg_valid=%b, valid=%b", 
                 sm4_enable_key_exp_in, reg_user_key_valid, sm4_user_key_valid_in);
        
        $display("\n=== Step 2: Enable key expansion ===");
        sm4_enable_key_exp_in = 1'b1;
        @(posedge clk);
        #1;
        $display("  After key_exp enable: current=%0d, next=%0d", key_exp_current, key_exp_next);
        $display("  enable_key_exp=%b, reg_valid=%b, valid=%b", 
                 sm4_enable_key_exp_in, reg_user_key_valid, sm4_user_key_valid_in);
        $display("  Condition: enable=%b && ~reg_valid=%b && valid=%b = %b",
                 sm4_enable_key_exp_in, ~reg_user_key_valid, sm4_user_key_valid_in,
                 (sm4_enable_key_exp_in && ~reg_user_key_valid && sm4_user_key_valid_in));
        
        $display("\n=== Step 3: Trigger user_key_valid pulse ===");
        sm4_user_key_valid_in = 1'b1;
        #1;
        $display("  Before clock: enable=%b, reg_valid=%b, valid=%b", 
                 sm4_enable_key_exp_in, reg_user_key_valid, sm4_user_key_valid_in);
        $display("  Condition: enable=%b && ~reg_valid=%b && valid=%b = %b",
                 sm4_enable_key_exp_in, ~reg_user_key_valid, sm4_user_key_valid_in,
                 (sm4_enable_key_exp_in && ~reg_user_key_valid && sm4_user_key_valid_in));
        $display("  next = %0d", key_exp_next);
        
        @(posedge clk);
        #1;
        $display("  After clock: current=%0d, next=%0d", key_exp_current, key_exp_next);
        $display("  count=%0d, reg_count=%0d", key_exp_count, key_exp_reg_count);
        $display("  reg_valid=%b, finished=%b, ready=%b", 
                 reg_user_key_valid, key_exp_finished, sm4_key_exp_ready_out);
        
        sm4_user_key_valid_in = 1'b0;
        
        $display("\n=== Step 4: Monitor key expansion (50 cycles) ===");
        for (cycle_count = 0; cycle_count < 50; cycle_count++) begin
            @(posedge clk);
            #1;
            if (cycle_count < 5 || cycle_count % 8 == 0 || key_exp_finished) begin
                $display("  Cycle %2d: state=%0d, count=%2d, reg_count=%2d, finished=%b, ready=%b",
                         cycle_count+1, key_exp_current, key_exp_count, key_exp_reg_count, 
                         key_exp_finished, sm4_key_exp_ready_out);
            end
            if (sm4_key_exp_ready_out) break;
        end
        
        if (sm4_key_exp_ready_out) begin
            $display("\n=== Key Expansion Complete ===");
            $display("rk[0]  = %h (expected: F09279A1)", u_sm4_top.u_key.rk00_out);
            $display("rk[1]  = %h (expected: 0A2F3E83)", u_sm4_top.u_key.rk01_out);
            $display("rk[2]  = %h (expected: 2B3F3F2F)", u_sm4_top.u_key.rk02_out);
            $display("rk[3]  = %h (expected: 413F3FD0)", u_sm4_top.u_key.rk03_out);
            
            if (u_sm4_top.u_key.rk00_out == 32'hF09279A1) begin
                $display("\n  -> [PASS] SM4 key expansion correct!");
            end else begin
                $display("\n  -> [FAIL] SM4 key expansion incorrect!");
            end
        end else begin
            $display("\n=== TIMEOUT ===");
            $display("  Final state: current=%0d, count=%0d, reg_count=%0d", 
                     key_exp_current, key_exp_count, key_exp_reg_count);
        end
        
        $display("\n========================================");
        $finish;
    end

endmodule
