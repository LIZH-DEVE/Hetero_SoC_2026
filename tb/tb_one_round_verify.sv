`timescale 1ns/1ps

module tb_one_round_verify();
    
    logic [127:0] data_in;
    logic [31:0] ck_parameter_in;
    logic [4:0] count_round_in;
    logic [127:0] result_out;
    
    localparam FK0 = 32'ha3b1bac6;
    localparam FK1 = 32'h56aa3350;
    localparam FK2 = 32'h677d9197;
    localparam FK3 = 32'hb27022dc;
    
    one_round_for_key_exp u_dut (
        .count_round_in(count_round_in),
        .data_in(data_in),
        .ck_parameter_in(ck_parameter_in),
        .result_out(result_out)
    );
    
    initial begin
        $display("========================================");
        $display("  One Round Key Expansion Verification");
        $display("========================================");
        
        data_in = 128'h0123456789abcdeffedcba9876543210;
        ck_parameter_in = 32'h00070e15;
        count_round_in = 0;
        
        #1;
        
        $display("\n--- Round 0 (count_round_in = 0) ---");
        $display("data_in = 0x%032h", data_in);
        $display("ck_parameter_in = 0x%08h", ck_parameter_in);
        $display("result_out = 0x%032h", result_out);
        
        $display("\nExpected calculation:");
        $display("word_0 = 0x%08h", data_in[127:96]);
        $display("word_1 = 0x%08h", data_in[95:64]);
        $display("word_2 = 0x%08h", data_in[63:32]);
        $display("word_3 = 0x%08h", data_in[31:0]);
        
        logic [31:0] k0 = data_in[127:96] ^ FK0;
        logic [31:0] k1 = data_in[95:64] ^ FK1;
        logic [31:0] k2 = data_in[63:32] ^ FK2;
        logic [31:0] k3 = data_in[31:0] ^ FK3;
        
        $display("\nk0 = word_0 ^ FK0 = 0x%08h ^ 0x%08h = 0x%08h", data_in[127:96], FK0, k0);
        $display("k1 = word_1 ^ FK1 = 0x%08h ^ 0x%08h = 0x%08h", data_in[95:64], FK1, k1);
        $display("k2 = word_2 ^ FK2 = 0x%08h ^ 0x%08h = 0x%08h", data_in[63:32], FK2, k2);
        $display("k3 = word_3 ^ FK3 = 0x%08h ^ 0x%08h = 0x%08h", data_in[31:0], FK3, k3);
        
        $display("\nresult_out should be: {k1, k2, k3, K4}");
        $display("result_out[127:96] = 0x%08h (should be k1 = 0x%08h)", result_out[127:96], k1);
        $display("result_out[95:64]  = 0x%08h (should be k2 = 0x%08h)", result_out[95:64], k2);
        $display("result_out[63:32]  = 0x%08h (should be k3 = 0x%08h)", result_out[63:32], k3);
        $display("result_out[31:0]   = 0x%08h (this is K4 = rk[0])", result_out[31:0]);
        
        if (result_out[127:96] == k1 && result_out[95:64] == k2 && result_out[63:32] == k3) begin
            $display("\nPASS: k1, k2, k3 are correct!");
        end else begin
            $display("\nFAIL: k1, k2, k3 are incorrect!");
        end
        
        $display("\nExpected rk[0] = F09279A1");
        $display("Actual rk[0]   = 0x%08h", result_out[31:0]);
        
        if (result_out[31:0] == 32'hF09279A1) begin
            $display("PASS: rk[0] is correct!");
        end else begin
            $display("FAIL: rk[0] is incorrect!");
        end
        
        $display("\n========================================");
        $finish;
    end

endmodule
