`timescale 1ns / 1ps
`default_nettype none

module crypto_core #(
    parameter DATA_WIDTH = 128
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  s1_valid,
    input  wire [DATA_WIDTH-1:0] s1_data,
    input  wire [127:0]          s1_key,
    input  wire [127:0]          s1_iv,
    input  wire [1:0]            s1_op,
    input  wire                  s1_mode,
    output wire                  s1_ready,
    output wire                  s2_valid,
    output wire [DATA_WIDTH-1:0] s2_data,
    input  wire                  s2_ready,
    output wire [3:0]            error_code
);

    wire engine_done;
    wire engine_busy;
    wire [127:0] core_dout;
    reg          encdec_ctrl;

    always @(*) begin
        case (s1_op)
            2'b01: encdec_ctrl = 1'b1;
            2'b10: encdec_ctrl = 1'b0;
            default: encdec_ctrl = 1'b1;
        endcase
    end

    crypto_engine u_engine (
        .clk          (clk),
        .rst_n        (rst_n),
        .algo_sel     (s1_mode),
        .encdec       (encdec_ctrl),
        .start        (s1_valid && s1_ready),
        .i_total_len  (32'd128),
        .i_iv         (s1_iv),
        .done         (engine_done),
        .busy         (engine_busy),
        .s_axil_araddr(8'd0),
        .s_axil_rdata (),
        .aes256_en    (1'b0),
        .key          ({128'd0, s1_key}),
        .din          (s1_data[127:0]),
        .dout         (core_dout)
    );

    assign s1_ready   = !engine_busy;
    assign s2_valid   = engine_done;
    assign s2_data    = {{(DATA_WIDTH-128){1'b0}}, core_dout};
    assign error_code = 4'd0;

endmodule

`default_nettype wire
