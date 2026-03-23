`timescale 1ns / 1ps

module tb_arp_chain_sanity;

    logic clk;
    logic rst_n;
    logic [31:0] s_axis_tdata;
    logic        s_axis_tvalid;
    logic        s_axis_tlast;
    logic        s_axis_tuser;
    logic        s_axis_tready;
    logic [31:0] o_arp_data;
    logic        o_arp_valid;
    logic        i_arp_ready;
    logic [31:0] o_tx_data;
    logic        o_tx_valid;
    logic        o_tx_ready;

    logic [31:0] reply_words [0:15];
    integer reply_seen;

    rx_parser u_parser (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tuser(s_axis_tuser),
        .s_axis_tready(s_axis_tready),
        .o_pbm_wdata(),
        .o_pbm_wvalid(),
        .o_pbm_wlast(),
        .o_pbm_werror(),
        .i_pbm_ready(1'b1),
        .o_meta_data(),
        .o_meta_valid(),
        .i_meta_ready(1'b1),
        .o_rec_src_mac(),
        .o_rec_src_ip(),
        .o_rec_src_port(),
        .o_rec_valid(),
        .o_arp_data(o_arp_data),
        .o_arp_valid(o_arp_valid),
        .i_arp_ready(i_arp_ready)
    );

    arp_responder u_responder (
        .clk(clk),
        .rst_n(rst_n),
        .i_arp_data(o_arp_data),
        .i_arp_valid(o_arp_valid),
        .i_arp_ready(i_arp_ready),
        .o_tx_data(o_tx_data),
        .o_tx_valid(o_tx_valid),
        .o_tx_ready(o_tx_ready),
        .i_local_mac(48'h0011_2233_4455),
        .i_local_ip(32'hC0A8_010A),
        .i_arp_enable(1'b1)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        #40;
        rst_n = 1'b1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reply_seen <= 0;
        end else if (o_tx_valid && o_tx_ready) begin
            if (reply_seen < 16) begin
                reply_words[reply_seen] <= o_tx_data;
            end
            reply_seen <= reply_seen + 1;
        end
    end

    task automatic clear_stream;
        begin
            s_axis_tdata = '0;
            s_axis_tvalid = 1'b0;
            s_axis_tlast = 1'b0;
            s_axis_tuser = 1'b0;
        end
    endtask

    task automatic send_word(input [31:0] word, input bit last, input bit user);
        begin
            @(negedge clk);
            s_axis_tdata = word;
            s_axis_tvalid = 1'b1;
            s_axis_tlast = last;
            s_axis_tuser = user;
            do @(posedge clk); while (!s_axis_tready);
        end
    endtask

    task automatic send_arp_frame(input [31:0] dst_ip, input bit user_flag);
        begin
            send_word(32'hDEAD_BEEF, 1'b0, user_flag);
            send_word(32'hAAAA_1122, 1'b0, user_flag);
            send_word(32'h3344_5566, 1'b0, user_flag);
            send_word(32'h0806_0000, 1'b0, user_flag);
            send_word(32'h0001_0800, 1'b0, user_flag);
            send_word(32'h0604_0001, 1'b0, user_flag);
            send_word(32'h1234_0000, 1'b0, user_flag);
            send_word(32'h5678_9ABC, 1'b0, user_flag);
            send_word(32'hC0A8_0102, 1'b0, user_flag);
            send_word(dst_ip, 1'b1, user_flag);
            @(negedge clk);
            clear_stream();
        end
    endtask

    task automatic expect_reply_words(input integer start_index);
        begin
            if ((reply_seen - start_index) != 7) begin
                $fatal(1, "Expected exactly 7 ARP reply words, saw %0d", reply_seen - start_index);
            end
            if (reply_words[start_index + 0] != 32'h0001_0800 ||
                reply_words[start_index + 1] != 32'h0604_0002 ||
                reply_words[start_index + 2] != 32'h0011_2233 ||
                reply_words[start_index + 3] != 32'h4455_C0A8 ||
                reply_words[start_index + 4] != 32'h010A_1234 ||
                reply_words[start_index + 5] != 32'h5678_9ABC ||
                reply_words[start_index + 6] != 32'hC0A8_0102) begin
                $fatal(1, "Unexpected integrated ARP reply payload");
            end
        end
    endtask

    initial begin
        integer base_seen;

        clear_stream();
        o_tx_ready = 1'b1;

        wait(rst_n);
        repeat (4) @(posedge clk);

        send_arp_frame(32'hC0A8_010A, 1'b0);
        repeat (14) @(posedge clk);
        expect_reply_words(0);

        base_seen = reply_seen;
        send_arp_frame(32'hC0A8_010B, 1'b0);
        repeat (8) @(posedge clk);
        if ((reply_seen - base_seen) != 0) begin
            $fatal(1, "Non-local ARP request unexpectedly produced reply words");
        end

        base_seen = reply_seen;
        send_arp_frame(32'hC0A8_010A, 1'b1);
        repeat (8) @(posedge clk);
        if ((reply_seen - base_seen) != 0) begin
            $fatal(1, "Errored ARP frame unexpectedly produced reply words");
        end

        base_seen = reply_seen;
        @(negedge clk);
        o_tx_ready = 1'b0;
        fork : arp_chain_bp_case
            begin
                send_arp_frame(32'hC0A8_010A, 1'b0);
            end
        join_none
        repeat (14) @(posedge clk);
        if ((reply_seen - base_seen) != 0 || o_tx_valid !== 1'b1) begin
            $fatal(1, "Expected integrated reply to stall cleanly under o_tx_ready=0");
        end
        @(negedge clk);
        o_tx_ready = 1'b1;
        wait (reply_seen == (base_seen + 7));
        expect_reply_words(base_seen);
        disable arp_chain_bp_case;

        $display("PASS: rx_parser -> arp_responder chain preserved back-pressure and generated full 7-word replies");
        $finish;
    end

endmodule
