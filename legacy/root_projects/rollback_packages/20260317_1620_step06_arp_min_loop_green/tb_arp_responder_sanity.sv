`timescale 1ns / 1ps

module tb_arp_responder_sanity;

    logic clk;
    logic rst_n;
    logic [31:0] i_arp_data;
    logic        i_arp_valid;
    logic        i_arp_ready;
    logic [31:0] o_tx_data;
    logic        o_tx_valid;
    logic        o_tx_ready;
    logic [47:0] i_local_mac;
    logic [31:0] i_local_ip;
    logic        i_arp_enable;

    logic [31:0] reply_words [0:15];
    integer reply_seen;
    integer reply_seen_base;

    arp_responder dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_arp_data(i_arp_data),
        .i_arp_valid(i_arp_valid),
        .i_arp_ready(i_arp_ready),
        .o_tx_data(o_tx_data),
        .o_tx_valid(o_tx_valid),
        .o_tx_ready(o_tx_ready),
        .i_local_mac(i_local_mac),
        .i_local_ip(i_local_ip),
        .i_arp_enable(i_arp_enable)
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

    task automatic clear_drive;
        begin
            i_arp_data <= '0;
            i_arp_valid <= 1'b0;
        end
    endtask

    task automatic send_request_word(input [31:0] word);
        begin
            i_arp_data <= word;
            i_arp_valid <= 1'b1;
            do @(posedge clk); while (!i_arp_ready);
        end
    endtask

    task automatic send_local_ip_request;
        begin
            send_request_word(32'h0001_0800);
            send_request_word(32'h0604_0001);
            send_request_word(32'h1234_0000);
            send_request_word(32'h5678_9ABC);
            send_request_word(32'hC0A8_0102);
            send_request_word(32'hC0A8_010A);
            clear_drive();
        end
    endtask

    task automatic send_non_local_ip_request;
        begin
            send_request_word(32'h0001_0800);
            send_request_word(32'h0604_0001);
            send_request_word(32'h1234_0000);
            send_request_word(32'h5678_9ABC);
            send_request_word(32'hC0A8_0102);
            send_request_word(32'hC0A8_010B);
            clear_drive();
        end
    endtask

    initial begin
        i_arp_data = '0;
        i_arp_valid = 1'b0;
        o_tx_ready = 1'b1;
        i_local_mac = 48'h0011_2233_4455;
        i_local_ip = 32'hC0A8_010A;
        i_arp_enable = 1'b1;

        wait(rst_n);
        repeat (4) @(posedge clk);

        send_local_ip_request();
        repeat (10) @(posedge clk);
        if (reply_seen != 6) begin
            $fatal(1, "Expected 6 reply words for local-IP request, saw %0d", reply_seen);
        end
        if (reply_words[0] != 32'h0001_0800 || reply_words[1] != 32'h0604_0002) begin
            $fatal(1, "Unexpected ARP reply header: %h %h", reply_words[0], reply_words[1]);
        end

        reply_seen_base = reply_seen;
        repeat (2) @(posedge clk);
        send_non_local_ip_request();
        repeat (8) @(posedge clk);
        if ((reply_seen - reply_seen_base) != 0) begin
            $fatal(1, "Unexpected reply for non-local request, saw %0d words", reply_seen - reply_seen_base);
        end

        reply_seen_base = reply_seen;
        i_arp_enable <= 1'b0;
        repeat (2) @(posedge clk);
        i_arp_data <= 32'h0001_0800;
        i_arp_valid <= 1'b1;
        repeat (6) @(posedge clk);
        clear_drive();
        if (i_arp_ready !== 1'b0 || (reply_seen - reply_seen_base) != 0) begin
            $fatal(1, "Unexpected activity while responder disabled: i_arp_ready=%0d new_words=%0d",
                   i_arp_ready, reply_seen - reply_seen_base);
        end

        reply_seen_base = reply_seen;
        i_arp_enable <= 1'b1;
        o_tx_ready <= 1'b0;
        repeat (2) @(posedge clk);
        send_local_ip_request();
        repeat (8) @(posedge clk);
        if ((reply_seen - reply_seen_base) != 0 || o_tx_valid !== 1'b1) begin
            $fatal(1, "Expected reply to pause under o_tx_ready=0: new_words=%0d o_tx_valid=%0d",
                   reply_seen - reply_seen_base, o_tx_valid);
        end
        o_tx_ready <= 1'b1;
        repeat (10) @(posedge clk);
        if ((reply_seen - reply_seen_base) != 6) begin
            $fatal(1, "Expected paused reply to finish after ready restore, saw %0d words", reply_seen - reply_seen_base);
        end

        repeat (2) @(posedge clk);
        send_local_ip_request();
        rst_n <= 1'b0;
        repeat (2) @(posedge clk);
        rst_n <= 1'b1;
        clear_drive();
        repeat (6) @(posedge clk);
        if (reply_seen != 0 || o_tx_valid !== 1'b0 || i_arp_ready !== 1'b1) begin
            $fatal(1, "Expected clean reset recovery: reply_seen=%0d o_tx_valid=%0d i_arp_ready=%0d",
                   reply_seen, o_tx_valid, i_arp_ready);
        end

        $display("PASS: arp_responder generated reply only for valid local-IP requests");
        $finish;
    end

endmodule
