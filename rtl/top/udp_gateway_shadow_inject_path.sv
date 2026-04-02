`timescale 1ns / 1ps

module udp_gateway_shadow_inject_path (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        i_network_enable,
    input  logic        i_ingress_inject_sel,
    input  logic        i_inj_clear,
    input  logic        i_inj_push,
    input  logic [31:0] i_inj_data,
    input  logic [15:0] i_inj_expected_words,
    output logic [31:0] o_inj_status,
    output logic [31:0] o_inject_tdata,
    output logic        o_inject_tvalid,
    output logic        o_inject_tlast,
    input  logic        i_inject_tready
);

    localparam int INJ_DEPTH = 32;
    localparam int INJ_COUNT_W = $clog2(INJ_DEPTH + 1);

    logic [32:0] inj_din;
    logic [32:0] inj_dout;
    logic [INJ_COUNT_W-1:0] inj_count;
    logic [15:0] inj_word_progress;
    logic        inj_overflow;
    logic        inj_done;
    logic        inj_packet_complete;
    logic        inj_fifo_full;
    logic        inj_fifo_empty;
    logic        inj_fifo_overflow;
    logic        inj_rst;
    logic        inj_tvalid;

    logic        inj_push_fire;
    logic        inj_pop_fire;

    assign inj_rst = !rst_n || !i_network_enable || i_inj_clear;
    assign inj_din = {
        (i_inj_expected_words != 16'd0) &&
        (inj_word_progress + 16'd1 == i_inj_expected_words),
        i_inj_data
    };
    assign inj_push_fire = i_inj_push && !inj_fifo_full && !inj_rst;
    assign inj_pop_fire = o_inject_tvalid && i_inject_tready;

    assign o_inject_tdata = inj_dout[31:0];
    assign o_inject_tlast = inj_dout[32];
    assign o_inject_tvalid = i_network_enable && i_ingress_inject_sel && inj_tvalid;
    assign o_inj_status = {13'd0, inj_overflow, inj_done, (inj_count != 0), 16'(inj_count)};

    assign inj_tvalid = (inj_count != 0) && inj_packet_complete && !inj_fifo_empty;

    xpm_fifo_sync #(
        .CASCADE_HEIGHT(0),
        .DOUT_RESET_VALUE("0"),
        .ECC_MODE("no_ecc"),
        .FIFO_MEMORY_TYPE("block"),
        .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH(INJ_DEPTH),
        .FULL_RESET_VALUE(0),
        .PROG_EMPTY_THRESH(10),
        .PROG_FULL_THRESH(10),
        .RD_DATA_COUNT_WIDTH(INJ_COUNT_W),
        .READ_DATA_WIDTH(33),
        .READ_MODE("fwft"),
        .SIM_ASSERT_CHK(0),
        .USE_ADV_FEATURES("0004"),
        .WAKEUP_TIME(0),
        .WRITE_DATA_WIDTH(33),
        .WR_DATA_COUNT_WIDTH(INJ_COUNT_W)
    ) u_inj_fifo (
        .rst(inj_rst),
        .wr_clk(clk),
        .wr_en(i_inj_push),
        .din(inj_din),
        .full(inj_fifo_full),
        .overflow(inj_fifo_overflow),
        .wr_rst_busy(),
        .rd_en(inj_pop_fire),
        .dout(inj_dout),
        .empty(inj_fifo_empty),
        .rd_data_count(),
        .rd_rst_busy(),
        .data_valid(),
        .underflow(),
        .wr_ack(),
        .almost_empty(),
        .almost_full(),
        .dbiterr(),
        .prog_empty(),
        .prog_full(),
        .sbiterr(),
        .wr_data_count(inj_count)
    );

    // Keep packet-complete bookkeeping synchronous so the XPM FIFO BRAM
    // control pins are not driven by async-reset flops.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            inj_word_progress <= 16'd0;
            inj_overflow <= 1'b0;
            inj_done <= 1'b0;
            inj_packet_complete <= 1'b0;
        end else begin
            inj_done <= 1'b0;
            if (!i_network_enable || i_inj_clear) begin
                inj_word_progress <= 16'd0;
                inj_overflow <= 1'b0;
                inj_packet_complete <= 1'b0;
            end else begin
                if (inj_fifo_overflow) begin
                    inj_overflow <= 1'b1;
                end

                if (inj_push_fire) begin
                    if ((i_inj_expected_words != 16'd0) &&
                        (inj_word_progress + 16'd1 == i_inj_expected_words)) begin
                        inj_word_progress <= 16'd0;
                        inj_done <= 1'b1;
                        inj_packet_complete <= 1'b1;
                    end else begin
                        inj_word_progress <= inj_word_progress + 16'd1;
                    end
                end

                if (inj_pop_fire && inj_dout[32]) begin
                    if (inj_count == INJ_COUNT_W'(1)) begin
                        inj_packet_complete <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
