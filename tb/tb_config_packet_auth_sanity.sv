`timescale 1ns / 1ps

module tb_config_packet_auth_sanity;

    logic clk;
    logic rst_n;

    logic [31:0] s_axis_tdata;
    logic [3:0]  s_axis_tkeep;
    logic        s_axis_tlast;
    logic        s_axis_tvalid;
    logic        s_axis_tready;

    logic [31:0] m_axis_tdata;
    logic [3:0]  m_axis_tkeep;
    logic        m_axis_tlast;
    logic        m_axis_tvalid;
    logic        m_axis_tready;

    logic [31:0] auth_success_cnt;
    logic [31:0] auth_fail_cnt;
    logic [31:0] replay_fail_cnt;
    logic [15:0] last_seq_id;
    logic        error_flag;

    int out_words_seen;

    config_packet_auth dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .auth_success_cnt(auth_success_cnt),
        .auth_fail_cnt(auth_fail_cnt),
        .replay_fail_cnt(replay_fail_cnt),
        .last_seq_id(last_seq_id),
        .error_flag(error_flag)
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
            out_words_seen <= 0;
        end else if (m_axis_tvalid && m_axis_tready) begin
            out_words_seen <= out_words_seen + 1;
        end
    end

    task automatic drive_word(
        input [31:0] data,
        input        last
    );
        begin
            s_axis_tdata  <= data;
            s_axis_tkeep  <= 4'hF;
            s_axis_tlast  <= last;
            s_axis_tvalid <= 1'b1;
            do @(posedge clk); while (!s_axis_tready);
            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
            s_axis_tdata  <= '0;
        end
    endtask

    task automatic send_valid_packet(input [15:0] seq_id);
        begin
            drive_word(32'hDEAD_BEEF, 1'b0);
            drive_word({16'hCAFE, seq_id}, 1'b0);
            drive_word(32'h1111_2222, 1'b0);
            drive_word(32'h3333_4444, 1'b1);
        end
    endtask

    task automatic send_invalid_magic_packet(input [15:0] seq_id);
        begin
            drive_word(32'hBAAD_BEEF, 1'b0);
            drive_word({16'hCAFE, seq_id}, 1'b0);
            drive_word(32'hAAAA_BBBB, 1'b1);
        end
    endtask

    initial begin
        s_axis_tdata  = '0;
        s_axis_tkeep  = '0;
        s_axis_tlast  = 1'b0;
        s_axis_tvalid = 1'b0;
        m_axis_tready = 1'b1;

        wait(rst_n);
        repeat (4) @(posedge clk);

        $display("=== config_packet_auth sanity ===");

        send_valid_packet(16'd1);
        repeat (4) @(posedge clk);
        if (auth_success_cnt != 32'd1 || auth_fail_cnt != 32'd0 || replay_fail_cnt != 32'd0 ||
            last_seq_id != 16'd1 || out_words_seen != 4) begin
            $fatal(1, "Valid packet check failed: success=%0d fail=%0d replay=%0d seq=%0d out_words=%0d",
                   auth_success_cnt, auth_fail_cnt, replay_fail_cnt, last_seq_id, out_words_seen);
        end

        send_invalid_magic_packet(16'd2);
        repeat (4) @(posedge clk);
        if (auth_success_cnt != 32'd1 || auth_fail_cnt != 32'd1 || replay_fail_cnt != 32'd0 ||
            out_words_seen != 4) begin
            $fatal(1, "Invalid magic check failed: success=%0d fail=%0d replay=%0d out_words=%0d",
                   auth_success_cnt, auth_fail_cnt, replay_fail_cnt, out_words_seen);
        end

        send_valid_packet(16'd1);
        repeat (4) @(posedge clk);
        if (replay_fail_cnt != 32'd1 || auth_success_cnt != 32'd1) begin
            $fatal(1, "Replay check failed: success=%0d fail=%0d replay=%0d",
                   auth_success_cnt, auth_fail_cnt, replay_fail_cnt);
        end

        send_valid_packet(16'd2);
        repeat (4) @(posedge clk);
        if (auth_success_cnt != 32'd2 || last_seq_id != 16'd2 || out_words_seen != 8) begin
            $fatal(1, "Second valid packet check failed: success=%0d seq=%0d out_words=%0d",
                   auth_success_cnt, last_seq_id, out_words_seen);
        end

        $display("PASS: config_packet_auth sanity");
        $finish;
    end

endmodule
