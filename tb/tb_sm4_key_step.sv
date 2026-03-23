`timescale 1ns/1ps

module tb_sm4_key_step();
    
    localparam CLK_PERIOD = 10;
    
    logic clk, rst_n;
    
    logic sm4_enable_in, sm4_encdec_enable_in, sm4_encdec_sel_in, sm4_valid_in;
    logic sm4_enable_key_exp_in, sm4_user_key_valid_in;
    logic [127:0] sm4_user_key_in, sm4_data_in, sm4_result_out;
    logic sm4_ready_out, sm4_key_exp_ready_out;
    
    localparam [127:0] SM4_KEY = 128'h0123456789abcdeffedcba9876543210;
    
    localparam [31:0] FK0 = 32'hA3B1BAC6;
    localparam [31:0] FK1 = 32'h56AA3350;
    localparam [31:0] FK2 = 32'h677D9197;
    localparam [31:0] FK3 = 32'hB27022DC;
    
    localparam [31:0] CK0 = 32'h00070E15;
    
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
    
    wire [31:0] mk0 = sm4_user_key_in[127:96];
    wire [31:0] mk1 = sm4_user_key_in[95:64];
    wire [31:0] mk2 = sm4_user_key_in[63:32];
    wire [31:0] mk3 = sm4_user_key_in[31:0];
    
    wire [31:0] k0_calc = mk0 ^ FK0;
    wire [31:0] k1_calc = mk1 ^ FK1;
    wire [31:0] k2_calc = mk2 ^ FK2;
    wire [31:0] k3_calc = mk3 ^ FK3;
    
    wire [31:0] xor_for_rk0 = k1_calc ^ k2_calc ^ k3_calc ^ CK0;
    
    wire [31:0] data_for_transform = u_sm4_top.u_key.data_for_round[63:32] ^ 
                                      u_sm4_top.u_key.data_for_round[31:0] ^
                                      u_sm4_top.u_key.cki;
    
    wire [127:0] data_after_round = u_sm4_top.u_key.data_after_round;
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    integer cycle_count;
    
    initial begin
        $display("========================================");
        $display("  SM4 Key Expansion Step-by-Step Test");
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
        
        $display("\n=== Manual Calculation ===");
        $display("MK = %h", SM4_KEY);
        $display("MK0 = %h, MK1 = %h", mk0, mk1);
        $display("MK2 = %h, MK3 = %h", mk2, mk3);
        
        sm4_user_key_in = SM4_KEY;
        
        $display("\nFK values:");
        $display("FK0 = %h, FK1 = %h", FK0, FK1);
        $display("FK2 = %h, FK3 = %h", FK2, FK3);
        
        $display("\nK = MK XOR FK:");
        $display("K0 = MK0 XOR FK0 = %h XOR %h = %h", mk0, FK0, k0_calc);
        $display("K1 = MK1 XOR FK1 = %h XOR %h = %h", mk1, FK1, k1_calc);
        $display("K2 = MK2 XOR FK2 = %h XOR %h = %h", mk2, FK2, k2_calc);
        $display("K3 = MK3 XOR FK3 = %h XOR %h = %h", mk3, FK3, k3_calc);
        
        $display("\nCK0 = %h", CK0);
        $display("K1 XOR K2 XOR K3 XOR CK0 = %h", xor_for_rk0);
        
        $display("\nExpected K values:");
        $display("K0 = A292FFA1");
        $display("K1 = DF01FEBF");
        $display("K2 = 99A12B0F");
        $display("K3 = C42410CC");
        $display("XOR for rk0 = 5B83EBD5");
        
        $display("\n=== Hardware Simulation ===");
        
        sm4_enable_in = 1'b1;
        sm4_enable_key_exp_in = 1'b1;
        
        @(posedge clk);
        sm4_user_key_valid_in = 1'b1;
        @(posedge clk);
        sm4_user_key_valid_in = 1'b0;
        
        $display("\nMonitoring first round...");
        
        for (cycle_count = 0; cycle_count < 5; cycle_count++) begin
            @(posedge clk);
            #1;
            $display("\nCycle %0d:", cycle_count+1);
            $display("  data_for_round = %h", u_sm4_top.u_key.data_for_round);
            $display("  data_after_round = %h", data_after_round);
            $display("  count_round = %0d", u_sm4_top.u_key.count_round);
            $display("  reg_count_round = %0d", u_sm4_top.u_key.reg_count_round);
            $display("  cki = %h", u_sm4_top.u_key.cki);
        end
        
        while (!sm4_key_exp_ready_out && cycle_count < 40) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        
        $display("\n=== Final Round Keys ===");
        $display("rk[0] = %h (expected: F09279A1)", u_sm4_top.u_key.rk00_out);
        $display("rk[1] = %h (expected: 0A2F3E83)", u_sm4_top.u_key.rk01_out);
        $display("rk[2] = %h (expected: 2B3F3F2F)", u_sm4_top.u_key.rk02_out);
        $display("rk[3] = %h (expected: 413F3FD0)", u_sm4_top.u_key.rk03_out);
        
        $display("\n========================================");
        $finish;
    end

endmodule
