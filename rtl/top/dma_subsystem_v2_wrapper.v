`timescale 1ns / 1ps

module dma_subsystem_v2_wrapper #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer CRYPTO_NUM_INSTANCES = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Interrupt Output
    output wire                   dma_irq,

    // 1. AXI-Lite Slave (CPU Control)
    input  wire [ADDR_WIDTH-1:0]  s_axil_awaddr,
    input  wire                   s_axil_awvalid,
    output wire                   s_axil_awready,
    input  wire [DATA_WIDTH-1:0]  s_axil_wdata,
    input  wire [3:0]             s_axil_wstrb,
    input  wire                   s_axil_wvalid,
    output wire                   s_axil_wready,
    output wire [1:0]             s_axil_bresp,
    output wire                   s_axil_bvalid,
    input  wire                   s_axil_bready,
    input  wire [ADDR_WIDTH-1:0]  s_axil_araddr,
    input  wire                   s_axil_arvalid,
    output wire                   s_axil_arready,
    output wire [DATA_WIDTH-1:0]  s_axil_rdata,
    output wire [1:0]             s_axil_rresp,
    output wire                   s_axil_rvalid,
    input  wire                   s_axil_rready,

    // 2. Stream Interfaces
    input  wire                   rx_wr_valid,
    input  wire [31:0]            rx_wr_data,
    input  wire                   rx_wr_last,
    output wire                   rx_wr_ready,
    output wire [31:0]            tx_axis_tdata,
    output wire                   tx_axis_tvalid,
    output wire                   tx_axis_tlast,
    output wire [3:0]             tx_axis_tkeep,
    input  wire                   tx_axis_tready,

    // 3. AXI Masters (New Architecture)
    // Master A: DMA Write
    output wire [ADDR_WIDTH-1:0]  m_axi_dma_wr_awaddr,
    output wire [7:0]             m_axi_dma_wr_awlen,
    output wire [2:0]             m_axi_dma_wr_awsize,
    output wire [1:0]             m_axi_dma_wr_awburst,
    output wire [3:0]             m_axi_dma_wr_awcache,
    output wire [2:0]             m_axi_dma_wr_awprot,
    output wire                   m_axi_dma_wr_awvalid,
    input  wire                   m_axi_dma_wr_awready,
    output wire [DATA_WIDTH-1:0]  m_axi_dma_wr_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axi_dma_wr_wstrb,
    output wire                   m_axi_dma_wr_wlast,
    output wire                   m_axi_dma_wr_wvalid,
    input  wire                   m_axi_dma_wr_wready,
    input  wire [1:0]             m_axi_dma_wr_bresp,
    input  wire                   m_axi_dma_wr_bvalid,
    output wire                   m_axi_dma_wr_bready,

    // Master B: S2MM
    output wire [ADDR_WIDTH-1:0]  m_axi_s2mm_awaddr,
    output wire [7:0]             m_axi_s2mm_awlen,
    output wire [2:0]             m_axi_s2mm_awsize,
    output wire [1:0]             m_axi_s2mm_awburst,
    output wire [3:0]             m_axi_s2mm_awcache,
    output wire [2:0]             m_axi_s2mm_awprot,
    output wire                   m_axi_s2mm_awvalid,
    input  wire                   m_axi_s2mm_awready,
    output wire [DATA_WIDTH-1:0]  m_axi_s2mm_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axi_s2mm_wstrb,
    output wire                   m_axi_s2mm_wlast,
    output wire                   m_axi_s2mm_wvalid,
    input  wire                   m_axi_s2mm_wready,
    input  wire [1:0]             m_axi_s2mm_bresp,
    input  wire                   m_axi_s2mm_bvalid,
    output wire                   m_axi_s2mm_bready,
    output wire [ADDR_WIDTH-1:0]  m_axi_s2mm_araddr,
    output wire [7:0]             m_axi_s2mm_arlen,
    output wire [2:0]             m_axi_s2mm_arsize,
    output wire [1:0]             m_axi_s2mm_arburst,
    output wire                   m_axi_s2mm_arvalid,
    input  wire                   m_axi_s2mm_arready,
    input  wire [DATA_WIDTH-1:0]  m_axi_s2mm_rdata,
    input  wire [1:0]             m_axi_s2mm_rresp,
    input  wire                   m_axi_s2mm_rlast,
    input  wire                   m_axi_s2mm_rvalid,
    output wire                   m_axi_s2mm_rready,

    // Master C: Fetcher
    output wire [ADDR_WIDTH-1:0]  m_axi_fetcher_araddr,
    output wire [7:0]             m_axi_fetcher_arlen,
    output wire [2:0]             m_axi_fetcher_arsize,
    output wire [1:0]             m_axi_fetcher_arburst,
    output wire                   m_axi_fetcher_arvalid,
    input  wire                   m_axi_fetcher_arready,
    input  wire [DATA_WIDTH-1:0]  m_axi_fetcher_rdata,
    input  wire [1:0]             m_axi_fetcher_rresp,
    input  wire                   m_axi_fetcher_rlast,
    input  wire                   m_axi_fetcher_rvalid,
    output wire                   m_axi_fetcher_rready
);

    dma_subsystem #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .CRYPTO_NUM_INSTANCES(CRYPTO_NUM_INSTANCES)
    ) i_core_sv (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        
        .rx_wr_valid(rx_wr_valid), .rx_wr_data(rx_wr_data), .rx_wr_last(rx_wr_last), .rx_wr_ready(rx_wr_ready),
        .tx_axis_tdata(tx_axis_tdata), .tx_axis_tvalid(tx_axis_tvalid), .tx_axis_tlast(tx_axis_tlast),
        .tx_axis_tkeep(tx_axis_tkeep), .tx_axis_tready(tx_axis_tready),

        .m_axis_awaddr(m_axi_dma_wr_awaddr), .m_axis_awlen(m_axi_dma_wr_awlen), .m_axis_awsize(m_axi_dma_wr_awsize),
        .m_axis_awburst(m_axi_dma_wr_awburst), .m_axis_awcache(m_axi_dma_wr_awcache), .m_axis_awprot(m_axi_dma_wr_awprot),
        .m_axis_awvalid(m_axi_dma_wr_awvalid), .m_axis_awready(m_axi_dma_wr_awready),
        .m_axis_wdata(m_axi_dma_wr_wdata), .m_axis_wstrb(m_axi_dma_wr_wstrb), .m_axis_wlast(m_axi_dma_wr_wlast),
        .m_axis_wvalid(m_axi_dma_wr_wvalid), .m_axis_wready(m_axi_dma_wr_wready),
        .m_axis_bresp(m_axi_dma_wr_bresp), .m_axis_bvalid(m_axi_dma_wr_bvalid), .m_axis_bready(m_axi_dma_wr_bready),

        .m_axis_s2mm_awaddr(m_axi_s2mm_awaddr), .m_axis_s2mm_awlen(m_axi_s2mm_awlen), .m_axis_s2mm_awsize(m_axi_s2mm_awsize),
        .m_axis_s2mm_awburst(m_axi_s2mm_awburst), .m_axis_s2mm_awcache(m_axi_s2mm_awcache), .m_axis_s2mm_awprot(m_axi_s2mm_awprot),
        .m_axis_s2mm_awvalid(m_axi_s2mm_awvalid), .m_axis_s2mm_awready(m_axi_s2mm_awready),
        .m_axis_s2mm_wdata(m_axi_s2mm_wdata), .m_axis_s2mm_wstrb(m_axi_s2mm_wstrb), .m_axis_s2mm_wlast(m_axi_s2mm_wlast),
        .m_axis_s2mm_wvalid(m_axi_s2mm_wvalid), .m_axis_s2mm_wready(m_axi_s2mm_wready),
        .m_axis_s2mm_bresp(m_axi_s2mm_bresp), .m_axis_s2mm_bvalid(m_axi_s2mm_bvalid), .m_axis_s2mm_bready(m_axi_s2mm_bready),
        .m_axis_s2mm_araddr(m_axi_s2mm_araddr), .m_axis_s2mm_arlen(m_axi_s2mm_arlen), .m_axis_s2mm_arsize(m_axi_s2mm_arsize),
        .m_axis_s2mm_arburst(m_axi_s2mm_arburst), .m_axis_s2mm_arvalid(m_axi_s2mm_arvalid), .m_axis_s2mm_arready(m_axi_s2mm_arready),
        .m_axis_s2mm_rdata(m_axi_s2mm_rdata), .m_axis_s2mm_rresp(m_axi_s2mm_rresp), .m_axis_s2mm_rlast(m_axi_s2mm_rlast),
        .m_axis_s2mm_rvalid(m_axi_s2mm_rvalid), .m_axis_s2mm_rready(m_axi_s2mm_rready),

        .m_axis_fetcher_araddr(m_axi_fetcher_araddr), .m_axis_fetcher_arlen(m_axi_fetcher_arlen), .m_axis_fetcher_arsize(m_axi_fetcher_arsize),
        .m_axis_fetcher_arburst(m_axi_fetcher_arburst), .m_axis_fetcher_arvalid(m_axi_fetcher_arvalid), .m_axis_fetcher_arready(m_axi_fetcher_arready),
        .m_axis_fetcher_rdata(m_axi_fetcher_rdata), .m_axis_fetcher_rresp(m_axi_fetcher_rresp), .m_axis_fetcher_rlast(m_axi_fetcher_rlast),
        .m_axis_fetcher_rvalid(m_axi_fetcher_rvalid), .m_axis_fetcher_rready(m_axi_fetcher_rready),

        .dma_irq(dma_irq)
    );
endmodule




