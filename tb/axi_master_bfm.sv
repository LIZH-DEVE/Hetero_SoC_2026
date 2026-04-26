`timescale 1ns / 1ps

module axi_master_bfm #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    output logic [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output logic [7:0]             m_axi_awlen,
    output logic [2:0]             m_axi_awsize,
    output logic [1:0]             m_axi_awburst,
    output logic [3:0]             m_axi_awcache,
    output logic [2:0]             m_axi_awprot,
    output logic                   m_axi_awvalid,
    input  logic                   m_axi_awready,

    output logic [DATA_WIDTH-1:0]  m_axi_wdata,
    output logic [DATA_WIDTH/8-1:0] m_axi_wstrb,
    output logic                   m_axi_wlast,
    output logic                   m_axi_wvalid,
    input  logic                   m_axi_wready,
    input  logic [1:0]             m_axi_wresp,
    input  logic                   m_axi_blast,
    input  logic                   m_axi_bvalid,
    output logic                   m_axi_bready,

    output logic [ADDR_WIDTH-1:0]  m_axi_araddr,
    output logic [7:0]             m_axi_arlen,
    output logic [2:0]             m_axi_arsize,
    output logic [1:0]             m_axi_arburst,
    output logic                   m_axi_arvalid,
    input  logic                   m_axi_arready,
    input  logic [DATA_WIDTH-1:0]  m_axi_rdata,
    input  logic [1:0]             m_axi_rresp,
    input  logic                   m_axi_rlast,
    input  logic                   m_axi_rvalid,
    output logic                   m_axi_rready
);

    task automatic check_alignment;
        input logic [ADDR_WIDTH-1:0] test_addr;
        input logic [31:0]            test_len;
        output logic                   error_detected;
        begin
            $display("[BFM] Task: check_alignment started at time %0t", $time);
            $display("[BFM]   Test Address: 0x%0h", test_addr);
            $display("[BFM]   Test Length: %0d bytes", test_len);

            logic [2:0] addr_alignment;
            logic [11:0] offset_in_page;
            logic [12:0] bytes_to_boundary;

            addr_alignment = test_addr[2:0];
            offset_in_page = test_addr[11:0];
            bytes_to_boundary = 13'h1000 - {1'b0, offset_in_page};

            if (addr_alignment != 3'b000) begin
                $display("[BFM]   ERROR: Address is not 4-byte aligned!");
                $display("[BFM]   addr[2:0] = %0b", addr_alignment);
                error_detected = 1'b1;
            end else begin
                $display("[BFM]   PASS: Address is 4-byte aligned");
                error_detected = 1'b0;
            end

            if (({1'b0, offset_in_page} + test_len) > 13'h1000) begin
                $display("[BFM]   WARNING: Transfer crosses 4K boundary!");
                $display("[BFM]   Offset in page: 0x%0h", offset_in_page);
                $display("[BFM]   Bytes to boundary: %0d", bytes_to_boundary);
                $display("[BFM]   Expected: Burst should be split into multiple transactions");
            end

            $display("[BFM] <<< Task Complete: check_alignment", $time);
            $display();
        end
    endtask

endmodule
