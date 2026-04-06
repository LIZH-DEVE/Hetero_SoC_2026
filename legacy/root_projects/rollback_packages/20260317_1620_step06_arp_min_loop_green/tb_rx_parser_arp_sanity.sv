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

    logic [31:0] arp_words [0:5];
    integer arp_seen;

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
        .o_arp_valid(o_arp_valid)
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
        end else if (o_arp_valid) begin
            if (arp_seen < 6) begin
                arp_words[arp_seen] <= o_arp_data;
            end
            arp_seen <= arp_seen + 1;
        end
    end

    task automatic send_word(input [31:0] word, input bit last);
        begin
            s_axis_tdata <= word;
            s_axis_tvalid <= 1'b1;
            s_axis_tlast <= last;
            do @(posedge clk); while (!s_axis_tready);
        end
    endtask

    initial begin
        s_axis_tdata = '0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        s_axis_tuser = 1'b0;

        wait(rst_n);
        repeat (4) @(posedge clk);

        // The current parser consumes the first Ethernet word in IDLE, then
        // interprets the next three words in ETH_HDR.
        send_word(32'hDEAD_BEEF, 1'b0);
        send_word(32'hAAAA_1122, 1'b0);
        send_word(32'h3344_5566, 1'b0);
        send_word(32'h0806_0000, 1'b0);
        send_word(32'h0001_0800, 1'b0);
        send_word(32'h0604_0001, 1'b0);
        send_word(32'h1234_5678, 1'b0);
        send_word(32'h9ABC_DEF0, 1'b0);
        send_word(32'hC0A8_0102, 1'b0);
        send_word(32'hC0A8_010A, 1'b1);

        s_axis_tvalid <= 1'b0;
        s_axis_tlast <= 1'b0;
        repeat (4) @(posedge clk);

        if (arp_seen != 6) begin
            $fatal(1, "Expected 6 ARP payload words, saw %0d", arp_seen);
        end

        if (arp_words[0] != 32'h0001_0800 ||
            arp_words[1] != 32'h0604_0001 ||
            arp_words[2] != 32'h1234_5678 ||
            arp_words[3] != 32'h9ABC_DEF0 ||
            arp_words[4] != 32'hC0A8_0102 ||
            arp_words[5] != 32'hC0A8_010A) begin
            $fatal(1, "ARP payload forwarding mismatch");
        end

        $display("PASS: rx_parser forwarded ARP payload words to responder interface");
        $finish;
    end

endmodule
