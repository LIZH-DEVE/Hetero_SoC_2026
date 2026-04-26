`timescale 1ns / 1ps

module tb_rx_parser_arp_sanity;

    logic clk;
    logic rst_n;
    logic [31:0] s_axis_tdata;
    logic        s_axis_tvalid;
    logic        s_axis_tlast;
    logic        s_axis_tuser;
    logic        s_axis_tready;
    logic [31:0] o_pbm_wdata;
    logic        o_pbm_wvalid;
    logic        o_pbm_wlast;
    logic        o_pbm_werror;
    logic [15:0] o_meta_data;
    logic        o_meta_valid;
    logic [47:0] o_rec_src_mac;
    logic [31:0] o_rec_src_ip;
    logic [15:0] o_rec_src_port;
    logic        o_rec_valid;
    logic [31:0] o_arp_data;
    logic        o_arp_valid;
    logic        i_arp_ready;

    logic [31:0] arp_words [0:5];
    integer arp_seen;
    integer pbm_word_seen;
    integer meta_seen;

    rx_parser dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tuser(s_axis_tuser),
        .s_axis_tready(s_axis_tready),
        .o_pbm_wdata(o_pbm_wdata),
        .o_pbm_wvalid(o_pbm_wvalid),
        .o_pbm_wlast(o_pbm_wlast),
        .o_pbm_werror(o_pbm_werror),
        .i_pbm_ready(1'b1),
        .o_meta_data(o_meta_data),
        .o_meta_valid(o_meta_valid),
        .i_meta_ready(1'b1),
        .o_rec_src_mac(o_rec_src_mac),
        .o_rec_src_ip(o_rec_src_ip),
        .o_rec_src_port(o_rec_src_port),
        .o_rec_valid(o_rec_valid),
        .o_arp_data(o_arp_data),
        .o_arp_valid(o_arp_valid),
        .i_arp_ready(i_arp_ready)
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
            arp_seen <= 0;
            pbm_word_seen <= 0;
            meta_seen <= 0;
        end else if (o_arp_valid && i_arp_ready) begin
            if (arp_seen < 6) begin
                arp_words[arp_seen] <= o_arp_data;
            end
            arp_seen <= arp_seen + 1;
            if (o_pbm_wvalid) begin
                pbm_word_seen <= pbm_word_seen + 1;
            end
            if (o_meta_valid) begin
                meta_seen <= meta_seen + 1;
            end
        end else begin
            if (o_pbm_wvalid) begin
                pbm_word_seen <= pbm_word_seen + 1;
            end
            if (o_meta_valid) begin
                meta_seen <= meta_seen + 1;
            end
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

    task automatic send_non_arp_frame(input [15:0] eth_type);
        begin
            send_word(32'hDEAD_BEEF, 1'b0, 1'b0);
            send_word(32'hAAAA_1122, 1'b0, 1'b0);
            send_word(32'h3344_5566, 1'b0, 1'b0);
            send_word({eth_type, 16'h0000}, 1'b0, 1'b0);
            send_word(32'h1111_2222, 1'b0, 1'b0);
            send_word(32'h3333_4444, 1'b1, 1'b0);
            @(negedge clk);
            clear_stream();
        end
    endtask

    task automatic expect_no_new_arp(input integer base_seen, input [255:0] label);
        begin
            repeat (6) @(posedge clk);
            if ((arp_seen - base_seen) != 0) begin
                $fatal(1, "%0s unexpectedly produced %0d ARP words", label, arp_seen - base_seen);
            end
        end
    endtask

    task automatic send_udp_frame(
        input [15:0] ip_total_len_word,
        input [15:0] udp_len_word,
        input integer payload_words
    );
        integer idx;
        begin
            send_word(32'hDEAD_BEEF, 1'b0, 1'b0);
            send_word(32'hAAAA_1122, 1'b0, 1'b0);
            send_word(32'h3344_5566, 1'b0, 1'b0);
            send_word(32'h0800_0000, 1'b0, 1'b0);
            send_word({ip_total_len_word, 12'h000, 4'h5}, 1'b0, 1'b0);
            send_word(32'h0000_0000, 1'b0, 1'b0);
            send_word(32'h0000_0000, 1'b0, 1'b0);
            send_word(32'h0000_C0A8, 1'b0, 1'b0);
            send_word(32'h0102_0000, 1'b0, 1'b0);
            send_word(32'h0000_1234, 1'b0, 1'b0);
            send_word({16'h5678, udp_len_word}, payload_words == 0, 1'b0);
            for (idx = 0; idx < payload_words; idx = idx + 1) begin
                send_word(32'hCAFE_BABE ^ idx, idx == (payload_words - 1), 1'b0);
            end
            @(negedge clk);
            clear_stream();
        end
    endtask

    initial begin
        integer base_seen;

        clear_stream();
        i_arp_ready = 1'b1;

        wait(rst_n);
        repeat (4) @(posedge clk);

        send_arp_frame(32'hC0A8_010A, 1'b0);
        repeat (4) @(posedge clk);
        if (arp_seen != 6) begin
            $fatal(1, "Expected 6 ARP payload words, saw %0d", arp_seen);
        end
        if (arp_words[0] != 32'h0001_0800 ||
            arp_words[1] != 32'h0604_0001 ||
            arp_words[2] != 32'h1234_0000 ||
            arp_words[3] != 32'h5678_9ABC ||
            arp_words[4] != 32'hC0A8_0102 ||
            arp_words[5] != 32'hC0A8_010A) begin
            $fatal(1, "ARP payload forwarding mismatch");
        end

        base_seen = arp_seen;
        send_non_arp_frame(16'h0800);
        expect_no_new_arp(base_seen, "IPv4 frame");

        base_seen = arp_seen;
        send_non_arp_frame(16'h8100);
        expect_no_new_arp(base_seen, "non-ARP EthType frame");

        base_seen = arp_seen;
        send_arp_frame(32'hC0A8_010A, 1'b1);
        expect_no_new_arp(base_seen, "errored ARP frame");

        base_seen = arp_seen;
        i_arp_ready = 1'b0;
        fork : arp_bp_case
            begin
                send_arp_frame(32'hC0A8_010A, 1'b0);
            end
        join_none
        repeat (12) @(posedge clk);
        if (s_axis_tready !== 1'b0 ||
            s_axis_tvalid !== 1'b1 ||
            s_axis_tdata !== 32'h0001_0800 ||
            (arp_seen - base_seen) != 0) begin
            $fatal(1, "Expected parser to stall on first ARP payload word: tready=%0d tvalid=%0d data=%h new_words=%0d",
                   s_axis_tready, s_axis_tvalid, s_axis_tdata, arp_seen - base_seen);
        end
        i_arp_ready = 1'b1;
        wait (arp_seen == (base_seen + 6));
        @(negedge clk);
        clear_stream();
        disable arp_bp_case;

        base_seen = pbm_word_seen;
        send_udp_frame(16'd40, 16'd32, 1);
        repeat (4) @(posedge clk);
        if (pbm_word_seen != base_seen) begin
            $fatal(1, "Expected malformed first UDP frame to be dropped before payload");
        end

        base_seen = pbm_word_seen;
        send_udp_frame(16'd60, 16'd40, 8);
        repeat (6) @(posedge clk);
        if ((pbm_word_seen - base_seen) != 8 || meta_seen == 0) begin
            $fatal(1, "Expected second UDP frame to avoid stale malformed drop: pbm_delta=%0d meta_seen=%0d",
                   pbm_word_seen - base_seen, meta_seen);
        end

        $display("PASS: rx_parser forwarded ARP words, blocked bad frames, and honored ARP back-pressure");
        $finish;
    end

endmodule
