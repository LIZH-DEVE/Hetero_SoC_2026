`timescale 1ns / 1ps

module dma_axis_fifo_wrapper #(
    parameter integer DATA_WIDTH = 32,
    parameter integer FIFO_DEPTH = dma_csr_pkg::DMA_RAW_COPY_FIFO_DEPTH
)(
    input  logic                   clk,
    input  logic                   axis_rst_n,
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

    import dma_csr_pkg::*;

`ifdef USE_XILINX_AXIS_DATA_FIFO_IP
    // Board builds should point this wrapper at a generated Xilinx
    // axis_data_fifo IP with:
    //   - BRAM storage
    //   - depth = 512
    //   - TDATA enabled
    //   - TLAST enabled
    dma_raw_copy_axis_data_fifo u_fifo (
        .s_axis_aresetn(axis_rst_n),
        .s_axis_aclk(clk),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tlast(m_axis_tlast)
    );

    assign o_empty = !m_axis_tvalid;
    assign o_full  = !s_axis_tready;
    assign o_level = '0;
`else
    axis_packet_fifo_bram #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_fifo (
        .clk(clk),
        .rst_n(axis_rst_n),
        .i_clear(i_clear),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tready(m_axis_tready),
        .o_empty(o_empty),
        .o_full(o_full),
        .o_level(o_level)
    );
`endif

endmodule
