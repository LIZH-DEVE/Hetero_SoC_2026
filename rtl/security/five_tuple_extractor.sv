`timescale 1ns / 1ps

/**
 * Module: five_tuple_extractor
 * Task 15.1: 5-Tuple Extraction
 * 功能: 提取五元组（5-Tuple）
 * 五元组包括:
 *   - Source IP (32-bit)
 *   - Source Port (16-bit)
 *   - Destination IP (32-bit)
 *   - Destination Port (16-bit)
 *   Protocol (8-bit)
 */

module five_tuple_extractor #(
    parameter AXI_DATA_WIDTH = 32,
    parameter IPV4_HEADER_OFFSET = 14  // 以太网头后是IP头
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // =========================================================================
    // AXI-Stream Input
    // =========================================================================
    input  logic [AXI_DATA_WIDTH-1:0] s_axis_tdata,
    input  logic [AXI_DATA_WIDTH/8-1:0]  s_axis_tkeep,
    input  logic                         s_axis_tlast,
    input  logic                         s_axis_tvalid,
    output logic                         s_axis_tready,

    // =========================================================================
    // 5-Tuple Output
    // =========================================================================
    output logic [31:0]              src_ip,
    output logic [15:0]              src_port,
    output logic [31:0]              dst_ip,
    output logic [15:0]              dst_port,
    output logic [7:0]               protocol,
    output logic                       tuple_valid,
    output logic                       tuple_last
);

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam IDLE            = 3'd0;
    localparam IP_VERSION       = 3'd1;
    localparam IP_IHL          = 3'd2;
    localparam IP_TOS          = 3'd3;
    localparam IP_TOTAL_LEN    = 3'd4;
    localparam IP_ID           = 3'd5;
    localparam IP_FLAGS        = 3'd6;
    localparam IP_FRAG_OFFSET  = 3'd7;
    localparam IP_TTL          = 3'd8;
    localparam IP_PROTOCOL     = 3'd9;
    localparam IP_CHECKSUM     = 3'd10;
    localparam IP_SRC_IP       = 3'd11;
    localparam IP_DST_IP       = 3'd12;

    // =========================================================================
    // Internal Signals
    // =========================================================================
    logic [2:0]               state, state_next;
    logic [3:0]               ihl;
    logic [7:0]               ip_version_ihl;
    logic [7:0]               ip_protocol;
    logic [31:0]              ip_src_ip;
    logic [31:0]              ip_dst_ip;
    logic [3:0]               word_cnt;
    logic                      is_udp;
    logic                      is_tcp;

    // Output registers
    logic [31:0]              src_ip_reg;
    logic [15:0]              src_port_reg;
    logic [31:0]              dst_ip_reg;
    logic [15:0]              dst_port_reg;
    logic [7:0]               protocol_reg;

    // =========================================================================
    // State Machine: Current State
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= state_next;
        end
    end

    // =========================================================================
    // State Machine: Next State Logic
    // =========================================================================
    always_comb begin
        state_next = state;

        case (state)
            IDLE: begin
                if (s_axis_tvalid) begin
                    // 检查是否为IP包（假设以太网头已跳过）
                    ip_version_ihl = s_axis_tdata[31:24];
                    if (ip_version_ihl[7:4] == 4'd4) begin  // IPv4
                        state_next = IP_IHL;
                    end
                end
            end

            IP_IHL: begin
                ihl = ip_version_ihl[3:0];
                if (ihl > 0) begin
                    state_next = IP_PROTOCOL;
                end
            end

            IP_PROTOCOL: begin
                if (s_axis_tvalid) begin
                    ip_protocol = s_axis_tdata[31:24];
                    state_next = IP_SRC_IP;
                end
            end

            IP_SRC_IP: begin
                if (s_axis_tvalid) begin
                    ip_src_ip = s_axis_tdata;
                    state_next = IP_DST_IP;
                end
            end

            IP_DST_IP: begin
                if (s_axis_tvalid) begin
                    ip_dst_ip = s_axis_tdata;
                    // 根据协议决定是否提取端口
                    if (ip_protocol == 8'd6 || ip_protocol == 8'd17) begin
                        // TCP or UDP
                        state_next = IP_FLAGS;
                    end else begin
                        // 其他协议，不需要端口
                        state_next = IDLE;
                    end
                end
            end

            IP_FLAGS: begin
                // 跳过IP头中的其他字段
                if (s_axis_tvalid) begin
                    word_cnt <= 4'd1;
                    state_next = IP_FRAG_OFFSET;
                end
            end

            IP_FRAG_OFFSET: begin
                if (s_axis_tvalid) begin
                    if (word_cnt == ihl - 1) begin
                        // IP头结束，开始提取端口
                        state_next = IP_TOTAL_LEN;
                    end else begin
                        word_cnt <= word_cnt + 1'b1;
                    end
                end
            end

            IP_TOTAL_LEN: begin
                if (s_axis_tvalid) begin
                    // TCP/UDP端口在此字段
                    if (ip_protocol == 8'd6) begin  // TCP
                        src_port_reg <= s_axis_tdata[31:16];
                        dst_port_reg <= s_axis_tdata[15:0];
                    end else if (ip_protocol == 8'd17) begin  // UDP
                        src_port_reg <= s_axis_tdata[31:16];
                        dst_port_reg <= s_axis_tdata[15:0];
                    end
                    state_next = IDLE;
                end
            end

            default: begin
                state_next = IDLE;
            end
        endcase
    end

    // =========================================================================
    // Output Registers
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            src_ip_reg <= 32'd0;
            dst_ip_reg <= 32'd0;
            src_port_reg <= 16'd0;
            dst_port_reg <= 16'd0;
            protocol_reg <= 8'd0;
        end else begin
            if (state == IP_SRC_IP && s_axis_tvalid) begin
                src_ip_reg <= ip_src_ip;
            end
            if (state == IP_DST_IP && s_axis_tvalid) begin
                dst_ip_reg <= ip_dst_ip;
                protocol_reg <= ip_protocol;
            end
            if (state == IP_TOTAL_LEN && s_axis_tvalid) begin
                if (ip_protocol == 8'd6 || ip_protocol == 8'd17) begin
                    src_port_reg <= s_axis_tdata[31:16];
                    dst_port_reg <= s_axis_tdata[15:0];
                end
            end
        end
    end

    // =========================================================================
    // Protocol Detection
    // =========================================================================
    assign is_tcp = (protocol_reg == 8'd6);
    assign is_udp = (protocol_reg == 8'd17);

    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign src_ip = src_ip_reg;
    assign dst_ip = dst_ip_reg;
    assign src_port = (is_tcp || is_udp) ? src_port_reg : 16'd0;
    assign dst_port = (is_tcp || is_udp) ? dst_port_reg : 16'd0;
    assign protocol = protocol_reg;

    assign tuple_valid = (state == IP_TOTAL_LEN && s_axis_tvalid) ||
                        ((protocol_reg != 8'd6 && protocol_reg != 8'd17) &&
                         state == IP_DST_IP && s_axis_tvalid);
    assign tuple_last = tuple_valid;

    assign s_axis_tready = 1'b1;

endmodule
