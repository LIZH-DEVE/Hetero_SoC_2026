`timescale 1ns / 1ps

/**
 * Module: five_tuple_extractor
 * Task 15.1: 5-Tuple Extraction
 *
 * Current contract:
 * - Input stream is a simplified IPv4 packet without Ethernet header.
 * - Word 0 carries version/IHL in bits [31:24].
 * - Word 3 carries {TTL, protocol, header_checksum}.
 * - Word 4 carries source IP.
 * - Word 5 carries destination IP.
 * - Word 6 carries {source_port, destination_port}.
 */

module five_tuple_extractor #(
    parameter AXI_DATA_WIDTH = 32
)(
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic [AXI_DATA_WIDTH-1:0]   s_axis_tdata,
    input  logic [AXI_DATA_WIDTH/8-1:0] s_axis_tkeep,
    input  logic                        s_axis_tlast,
    input  logic                        s_axis_tvalid,
    output logic                        s_axis_tready,
    output logic [31:0]                 src_ip,
    output logic [15:0]                 src_port,
    output logic [31:0]                 dst_ip,
    output logic [15:0]                 dst_port,
    output logic [7:0]                  protocol,
    output logic                        tuple_valid,
    output logic                        tuple_last
);

    logic [3:0] word_idx;
    logic       ipv4_frame;

    logic [31:0] src_ip_reg;
    logic [31:0] dst_ip_reg;
    logic [15:0] src_port_reg;
    logic [15:0] dst_port_reg;
    logic [7:0]  protocol_reg;

    assign s_axis_tready = 1'b1;
    assign src_ip = src_ip_reg;
    assign dst_ip = dst_ip_reg;
    assign src_port = src_port_reg;
    assign dst_port = dst_port_reg;
    assign protocol = protocol_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            word_idx <= 4'd0;
            ipv4_frame <= 1'b0;
            src_ip_reg <= 32'd0;
            dst_ip_reg <= 32'd0;
            src_port_reg <= 16'd0;
            dst_port_reg <= 16'd0;
            protocol_reg <= 8'd0;
            tuple_valid <= 1'b0;
            tuple_last <= 1'b0;
        end else begin
            tuple_valid <= 1'b0;
            tuple_last <= 1'b0;

            if (s_axis_tvalid) begin
                case (word_idx)
                    4'd0: begin
                        ipv4_frame <= (s_axis_tdata[31:28] == 4'd4);
                    end

                    4'd3: begin
                        if (ipv4_frame) begin
                            protocol_reg <= s_axis_tdata[23:16];
                        end
                    end

                    4'd4: begin
                        if (ipv4_frame) begin
                            src_ip_reg <= s_axis_tdata;
                        end
                    end

                    4'd5: begin
                        if (ipv4_frame) begin
                            dst_ip_reg <= s_axis_tdata;
                        end
                    end

                    4'd6: begin
                        if (ipv4_frame) begin
                            src_port_reg <= s_axis_tdata[31:16];
                            dst_port_reg <= s_axis_tdata[15:0];
                            tuple_valid <= 1'b1;
                            tuple_last <= s_axis_tlast;
                        end
                    end

                    default: begin
                    end
                endcase

                if (s_axis_tlast) begin
                    word_idx <= 4'd0;
                    ipv4_frame <= 1'b0;
                end else begin
                    word_idx <= word_idx + 1'b1;
                end
            end
        end
    end

endmodule
