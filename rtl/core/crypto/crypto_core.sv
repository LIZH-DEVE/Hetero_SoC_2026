`timescale 1ns / 1ps

module crypto_core #(
    parameter int DATA_WIDTH = 128
)(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   s1_valid,
    input  logic [DATA_WIDTH-1:0]  s1_data,
    input  logic [127:0]           s1_key,
    input  logic [127:0]           s1_iv,
    input  logic [1:0]             s1_op,
    input  logic                   s1_mode,
    output logic                   s1_ready,
    output logic                   s2_valid,
    output logic [DATA_WIDTH-1:0]  s2_data,
    input  logic                   s2_ready,
    output logic [3:0]             error_code
);

    logic engine_done, engine_busy;

    assign s1_ready   = !engine_busy;
    assign error_code = 4'b0;

    crypto_engine u_engine (
        .clk      (clk),
        .rst_n    (rst_n),
        .algo_sel (s1_mode),
        .start    (s1_valid && s1_ready), 
        .done     (engine_done),
        .busy     (engine_busy),
        .key      (s1_key),
        .din      (s1_data),
        .dout     (s2_data)
    );

    assign s2_valid = engine_done;

endmodule