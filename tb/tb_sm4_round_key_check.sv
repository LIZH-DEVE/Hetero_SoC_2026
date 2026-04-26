`timescale 1ns/1ps

module tb_sm4_round_key_check();
    
    localparam CLK_PERIOD = 10;
    
    logic clk, rst_n;
    
    logic sm4_enable_in, enable_key_exp_in, user_key_valid_in;
    logic encdec_sel_in;
    logic [127:0] user_key_in;
    logic key_exp_ready_out;
    
    wire [31:0] rk [0:31];
    
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
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    integer cycle_count;
    
    initial begin
        $display("========================================");
        $display("  SM4 Round Key Byte Order Check");
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
        
        user_key_in = SM4_KEY;
        encdec_sel_in = 0;
        
        $display("\n[1] Starting key expansion...");
        
        @(negedge clk);
        sm4_enable_in = 1'b1;
        enable_key_exp_in = 1'b1;
        user_key_valid_in = 1'b1;
        
        @(posedge clk);
        user_key_valid_in = 1'b0;
        
        cycle_count = 0;
        while (!key_exp_ready_out && cycle_count < 100) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        
        if (cycle_count >= 100) begin
            $display("    TIMEOUT!");
            $finish;
        end
        
        $display("    Complete after %0d cycles", cycle_count);
        
        $display("\n[2] Generated Round Keys:");
        for (int i = 0; i < 32; i++) begin
            $display("    rk[%0d] = %h", i, rk[i]);
        end
        
        $display("\n[3] Expected Round Keys (from GM/T 0002-2012):");
        $display("    rk[0]  = F09279A1, rk[1]  = 0A2F3E83, rk[2]  = A1B9C978, rk[3]  = E7C3E25A");
        $display("    rk[4]  = 7885A8D6, rk[5]  = 2B32E89F, rk[6]  = 8A8A67E7, rk[7]  = 8F750E6F");
        $display("    rk[8]  = 9A5A7FDF, rk[9]  = 5BE08FAF, rk[10] = 3C6899D2, rk[11] = 3D24B8C2");
        $display("    rk[12] = 6D2B5437, rk[13] = 6D3B8B6D, rk[14] = B6B26B73, rk[15] = 9A287A93");
        $display("    rk[16] = 8A2BE0DD, rk[17] = 6A26ACF3, rk[18] = 5B80A2DF, rk[19] = 0D388D63");
        $display("    rk[20] = 6F1EDF34, rk[21] = D206965E, rk[22] = 86B3E94F, rk[23] = 536E4246");
        $display("    rk[24] = B134A879, rk[25] = 6F2988F9, rk[26] = EBC4A1D5, rk[27] = 7C3B2A7E");
        $display("    rk[28] = 1D5E8A8A, rk[29] = 7D8E6B5C, rk[30] = 3C6A2B7D, rk[31] = 4F6B7E5A");
        
        $display("\n[4] Byte-swapped Round Keys:");
        for (int i = 0; i < 4; i++) begin
            logic [31:0] swapped;
            swapped = {rk[i][7:0], rk[i][15:8], rk[i][23:16], rk[i][31:24]};
            $display("    rk[%0d] swapped = %h", i, swapped);
        end
        
        $display("\n========================================");
        $finish;
    end

endmodule
