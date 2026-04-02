`timescale 1ns / 1ps

module tb_crypto_bridge_tx_last_sanity;

    logic clk;
    logic rst_n;

    logic [31:0]  o_tx_data;
    logic         o_tx_last;
    logic         o_tx_empty;
    logic         tx_rd_en;

    integer       tx_count;
    logic [31:0]  tx_words [0:15];
    logic         tx_lasts [0:15];
    logic [31:0]  forced_word_data;
    logic         forced_word_last;

    crypto_bridge_top #(
        .NUM_INSTANCES(4)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_algo_sel(1'b0),
        .i_encdec(1'b1),
        .i_aes256_en(1'b0),
        .i_key(128'd0),
        .i_key_hi(128'd0),
        .o_system_ready(),
        .o_debug_last_plaintext(),
        .o_debug_key_lo_active(),
        .i_pbm_data(32'd0),
        .i_pbm_empty(1'b1),
        .i_pbm_valid(1'b0),
        .o_pbm_rd_en(),
        .o_tx_data(o_tx_data),
        .o_tx_last(o_tx_last),
        .o_tx_empty(o_tx_empty),
        .i_tx_rd_en(tx_rd_en)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_count <= 0;
            for (int i = 0; i < 16; i++) begin
                tx_words[i] <= 32'd0;
                tx_lasts[i] <= 1'b0;
            end
        end else if (!o_tx_empty && tx_rd_en) begin
            tx_words[tx_count] <= o_tx_data;
            tx_lasts[tx_count] <= o_tx_last;
            tx_count <= tx_count + 1;
        end
    end

    task automatic reset_case;
        begin
            rst_n = 1'b0;
            tx_rd_en = 1'b0;
            repeat (12) @(posedge clk);
            rst_n = 1'b1;
            repeat (12) @(posedge clk);
        end
    endtask

    task automatic inject_tx_word(input [31:0] data, input bit last);
        begin
            forced_word_data = data;
            forced_word_last = last;
            @(negedge clk);
            force dut.gb_dout       = forced_word_data;
            force dut.gb_dout_last  = forced_word_last;
            force dut.gb_dout_valid = 1'b1;
            @(posedge clk);
            release dut.gb_dout;
            release dut.gb_dout_last;
            release dut.gb_dout_valid;
        end
    endtask

    task automatic inject_blocks(input integer block_count);
        integer total_words;
        begin
            total_words = block_count * 4;
            for (int i = 0; i < total_words; i++) begin
                inject_tx_word(32'h4000_0000 + i, ((i % 4) == 3));
            end
        end
    endtask

    task automatic wait_for_tx_words(input integer expected_words, input string case_name);
        integer guard_cycles;
        begin
            guard_cycles = 0;
            while (tx_count < expected_words) begin
                @(posedge clk);
                guard_cycles = guard_cycles + 1;
                if (guard_cycles > 2000) begin
                    $fatal(1, "%s timeout waiting for %0d words, saw %0d", case_name, expected_words, tx_count);
                end
            end
        end
    endtask

    task automatic check_last_positions(input integer expected_words, input integer last0, input integer last1, input string case_name);
        begin
            for (int i = 0; i < expected_words; i++) begin
                bit expected_last;
                expected_last = ((i + 1) == last0) || ((i + 1) == last1);
                if (tx_lasts[i] !== expected_last) begin
                    $fatal(1, "%s wrong last at beat %0d: expected %0d got %0d", case_name, i + 1, expected_last, tx_lasts[i]);
                end
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        tx_rd_en = 1'b0;

        reset_case();
        inject_blocks(1);
        tx_rd_en = 1'b1;
        wait_for_tx_words(4, "single_block");
        check_last_positions(4, 4, -1, "single_block");

        reset_case();
        inject_blocks(2);
        tx_rd_en = 1'b1;
        wait_for_tx_words(8, "double_block");
        check_last_positions(8, 4, 8, "double_block");

        reset_case();
        inject_blocks(1);
        tx_rd_en = 1'b0;
        repeat (8) @(posedge clk);
        if (tx_count != 0) begin
            $fatal(1, "backpressure_hold advanced while rd_en=0, saw %0d words", tx_count);
        end
        tx_rd_en = 1'b1;
        wait_for_tx_words(4, "backpressure_after_resume");
        check_last_positions(4, 4, -1, "backpressure_after_resume");

        $display("PASS: crypto_bridge_top propagated tx_last through output FIFO");
        $finish;
    end

endmodule
