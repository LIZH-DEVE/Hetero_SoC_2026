`timescale 1ns / 1ps

module device_dna_reader #(
    parameter integer DNA_WIDTH = 57,
    parameter integer DNA_CLK_DIV = 16,
    parameter [56:0] SIM_DNA_VALUE = 57'h1234_5678_9ABCD_E
)(
    input  logic        clk,
    input  logic        rst_n,
    output logic [63:0] o_dna_value,
    output logic        o_dna_valid,
    output logic        o_dna_busy
);

    localparam integer DNA_DIV_WIDTH = (DNA_CLK_DIV <= 2) ? 1 : $clog2(DNA_CLK_DIV);

    logic [DNA_DIV_WIDTH-1:0] dna_clk_div_ctr;
    logic                     dna_clk;
    logic                     dna_done_sync_ff1;
    logic                     dna_done_sync_ff2;

`ifdef SYNTHESIS
    logic                   dna_dout;
    logic                   dna_read;
    logic                   dna_shift;
    logic [6:0]             dna_bit_count;
    logic [DNA_WIDTH-1:0]   dna_shift_value;
    logic                   dna_busy_raw;

    DNA_PORT u_dna (
        .DOUT(dna_dout),
        .CLK(dna_clk),
        .DIN(1'b0),
        .READ(dna_read),
        .SHIFT(dna_shift)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dna_clk_div_ctr <= '0;
            dna_clk <= 1'b0;
        end else if (dna_busy_raw) begin
            if (dna_clk_div_ctr == DNA_CLK_DIV - 1) begin
                dna_clk_div_ctr <= '0;
                dna_clk <= ~dna_clk;
            end else begin
                dna_clk_div_ctr <= dna_clk_div_ctr + 1'b1;
            end
        end else begin
            dna_clk_div_ctr <= '0;
            dna_clk <= 1'b0;
        end
    end

    always_ff @(posedge dna_clk or negedge rst_n) begin
        if (!rst_n) begin
            dna_read <= 1'b1;
            dna_shift <= 1'b0;
            dna_bit_count <= 7'd0;
            dna_shift_value <= '0;
            dna_busy_raw <= 1'b1;
        end else if (dna_busy_raw) begin
            if (dna_read) begin
                dna_read <= 1'b0;
                dna_shift <= 1'b1;
            end else if (dna_shift) begin
                dna_shift_value <= {dna_shift_value[DNA_WIDTH-2:0], dna_dout};
                dna_bit_count <= dna_bit_count + 1'b1;
                if (dna_bit_count == (DNA_WIDTH-1)) begin
                    dna_shift <= 1'b0;
                    dna_busy_raw <= 1'b0;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dna_done_sync_ff1 <= 1'b0;
            dna_done_sync_ff2 <= 1'b0;
            o_dna_value <= 64'd0;
            o_dna_valid <= 1'b0;
            o_dna_busy <= 1'b1;
        end else begin
            dna_done_sync_ff1 <= ~dna_busy_raw;
            dna_done_sync_ff2 <= dna_done_sync_ff1;
            if (!o_dna_valid && dna_done_sync_ff1 && dna_done_sync_ff2) begin
                o_dna_value <= {{(64-DNA_WIDTH){1'b0}}, dna_shift_value};
                o_dna_valid <= 1'b1;
                o_dna_busy <= 1'b0;
            end
        end
    end
`else
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dna_clk_div_ctr <= '0;
            dna_clk <= 1'b0;
            dna_done_sync_ff1 <= 1'b0;
            dna_done_sync_ff2 <= 1'b0;
            o_dna_value <= {{(64-DNA_WIDTH){1'b0}}, SIM_DNA_VALUE};
            o_dna_valid <= 1'b1;
            o_dna_busy <= 1'b0;
        end
    end
`endif

endmodule
