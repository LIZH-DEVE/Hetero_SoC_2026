`timescale 1ns / 1ps
`default_nettype none

module gearbox_128_to_32(
    input  wire         clk,
    input  wire         rst_n,
    input  wire [127:0] din,
    input  wire         din_valid,
    output wire         din_ready,
    output reg  [31:0]  dout,
    output reg          dout_valid,
    output reg          dout_last
);

    reg [127:0] data_reg;
    reg [1:0]   word_index;
    reg         active;

    assign din_ready = !active;

    always @(*) begin
        dout = 32'd0;
        dout_valid = 1'b0;
        dout_last = 1'b0;

        if (active) begin
            dout_valid = 1'b1;
            case (word_index)
                2'd0: dout = data_reg[127:96];
                2'd1: dout = data_reg[95:64];
                2'd2: dout = data_reg[63:32];
                2'd3: dout = data_reg[31:0];
                default: dout = 32'd0;
            endcase

            if (word_index == 2'd3) begin
                dout_last = 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_reg   <= 128'd0;
            word_index <= 2'd0;
            active     <= 1'b0;
        end else if (!active) begin
            if (din_valid) begin
                data_reg   <= din;
                word_index <= 2'd0;
                active     <= 1'b1;
            end
        end else begin
            if (word_index == 2'd3) begin
                word_index <= 2'd0;
                active     <= 1'b0;
            end else begin
                word_index <= word_index + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
