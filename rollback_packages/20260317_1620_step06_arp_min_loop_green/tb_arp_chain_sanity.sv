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

    integer reply_seen;
    logic [31:0] first_reply_word;
    logic [31:0] second_reply_word;

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
        .o_arp_valid(o_arp_valid)
    );

    arp_responder u_responder (
        .clk(clk),
        .rst_n(rst_n),
        .i_arp_data(o_arp_data),
        .i_arp_valid(o_arp_valid),
        .i_arp_ready(i_arp_ready),
        .o_tx_data(o_tx_data),
        .o_tx_valid(o_tx_valid),
        .o_tx_ready(1'b1),
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
            first_reply_word <= 32'h0;
            second_reply_word <= 32'h0;
        end else if (o_tx_valid) begin
            if (reply_seen == 0) begin
                first_reply_word <= o_tx_data;
            end
            if (reply_seen == 1) begin
                second_reply_word <= o_tx_data;
            end
            reply_seen <= reply_seen + 1;
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

        send_word(32'hDEAD_BEEF, 1'b0);
        send_word(32'hAAAA_1122, 1'b0);
        send_word(32'h3344_5566, 1'b0);
        send_word(32'h0806_0000, 1'b0);
        send_word(32'h0001_0800, 1'b0);
        send_word(32'h0604_0001, 1'b0);
        send_word(32'h1234_0000, 1'b0);
        send_word(32'h5678_9ABC, 1'b0);
        send_word(32'hC0A8_0102, 1'b0);
        send_word(32'hC0A8_010A, 1'b1);
        s_axis_tvalid <= 1'b0;
        s_axis_tlast <= 1'b0;

        repeat (12) @(posedge clk);

        if (reply_seen < 2) begin
            $fatal(1, "Expected integrated ARP reply, saw %0d words", reply_seen);
        end

        if (first_reply_word != 32'h0001_0800 || second_reply_word != 32'h0604_0002) begin
            $fatal(1, "Unexpected integrated ARP reply header: %h %h", first_reply_word, second_reply_word);
        end

        $display("PASS: rx_parser -> arp_responder minimal chain produced ARP reply");
        $finish;
    end

endmodule
