`timescale 1ns / 1ps

module axis_packet_fifo_bram #(
    parameter integer DATA_WIDTH = 32,
    parameter integer FIFO_DEPTH = 512
)(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   i_clear,

    input  logic [DATA_WIDTH-1:0]  s_axis_tdata,
    input  logic                   s_axis_tvalid,
    input  logic                   s_axis_tlast,
    output logic                   s_axis_tready,

    output logic [DATA_WIDTH-1:0]  m_axis_tdata,
    output logic                   m_axis_tvalid,
    output logic                   m_axis_tlast,
    input  logic                   m_axis_tready,

    output logic                   o_empty,
    output logic                   o_full,
    output logic [$clog2(FIFO_DEPTH+1)-1:0] o_level
);

    localparam integer PTR_WIDTH = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH);

    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] data_mem [0:FIFO_DEPTH-1];
    (* ram_style = "block" *) logic                  last_mem [0:FIFO_DEPTH-1];

    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] rd_ptr;
    logic [PTR_WIDTH:0]   level_q;
    logic                 push;
    logic                 pop;

    assign push = s_axis_tvalid && s_axis_tready;
    assign pop  = m_axis_tvalid && m_axis_tready;

    assign o_empty = (level_q == 0);
    assign o_full  = (level_q == FIFO_DEPTH);
    assign o_level = level_q[$clog2(FIFO_DEPTH+1)-1:0];

    assign s_axis_tready = !o_full;
    assign m_axis_tvalid = !o_empty;
    assign m_axis_tdata  = data_mem[rd_ptr];
    assign m_axis_tlast  = last_mem[rd_ptr];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr  <= '0;
            rd_ptr  <= '0;
            level_q <= '0;
        end else if (i_clear) begin
            wr_ptr  <= '0;
            rd_ptr  <= '0;
            level_q <= '0;
        end else begin
            if (push) begin
                data_mem[wr_ptr] <= s_axis_tdata;
                last_mem[wr_ptr] <= s_axis_tlast;
                if (wr_ptr == FIFO_DEPTH-1) begin
                    wr_ptr <= '0;
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end

            if (pop) begin
                if (rd_ptr == FIFO_DEPTH-1) begin
                    rd_ptr <= '0;
                end else begin
                    rd_ptr <= rd_ptr + 1'b1;
                end
            end

            case ({push, pop})
                2'b10: level_q <= level_q + 1'b1;
                2'b01: level_q <= level_q - 1'b1;
                default: begin end
            endcase
        end
    end

endmodule
