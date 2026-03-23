`timescale 1ns / 1ps

module rx_parser #(
    parameter DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic [DATA_WIDTH-1:0]  s_axis_tdata,
    input  logic                   s_axis_tvalid,
    input  logic                   s_axis_tlast,
    input  logic                   s_axis_tuser,
    output logic                   s_axis_tready,

    output logic [DATA_WIDTH-1:0]  o_pbm_wdata,
    output logic                   o_pbm_wvalid,
    output logic                   o_pbm_wlast,
    output logic                   o_pbm_werror,
    input  logic                   i_pbm_ready,

    output logic [15:0]            o_meta_data,
    output logic                   o_meta_valid,
    input  logic                   i_meta_ready,

    output logic [47:0]            o_rec_src_mac,
    output logic [31:0]            o_rec_src_ip,
    output logic [15:0]            o_rec_src_port,
    output logic                   o_rec_valid,

    output logic [31:0]            o_arp_data,
    output logic                   o_arp_valid,
    input  logic                   i_arp_ready
);

    typedef enum logic [2:0] {
        IDLE,
        ETH_HDR,
        IP_HDR,
        UDP_HDR,
        PAYLOAD,
        ARP_PAYLOAD,
        DROP
    } state_t;

    state_t state;

    logic [15:0] global_word_cnt;
    logic [15:0] ip_total_len;
    logic [15:0] udp_len;
    logic [3:0]  ihl;
    logic [47:0] src_mac_reg;
    logic [31:0] src_ip_reg;
    logic [15:0] src_port_reg;
    logic        arp_stream_ready;
    logic        stream_fire;

    logic [15:0] payload_len;
    logic [15:0] ip_header_bytes;
    logic        malformed_check;
    logic        malformed_this_cycle;
    logic        frame_len_invalid_this_cycle;

    localparam logic [15:0] MIN_IPV4_TOTAL_LEN = 16'd50;   // 64B Ethernet frame - 14B Ethernet header
    localparam logic [15:0] MAX_IPV4_TOTAL_LEN = 16'd1504; // 1518B Ethernet frame - 14B Ethernet header

    assign arp_stream_ready = i_pbm_ready && i_arp_ready;
    assign s_axis_tready = (state == ARP_PAYLOAD) ? arp_stream_ready : i_pbm_ready;
    assign stream_fire = s_axis_tvalid && s_axis_tready;

    assign o_pbm_wdata  = s_axis_tdata;
    assign o_pbm_wvalid = (state == PAYLOAD) && stream_fire;
    assign o_pbm_wlast  = s_axis_tlast && (state == PAYLOAD) && stream_fire;
    assign o_pbm_werror = s_axis_tuser;

    assign payload_len = udp_len - 16'd8;
    assign ip_header_bytes = ihl * 4;
    assign malformed_check = (udp_len > (ip_total_len - ip_header_bytes));
    assign malformed_this_cycle = (s_axis_tdata[15:0] > (ip_total_len - ip_header_bytes));
    assign frame_len_invalid_this_cycle =
        (s_axis_tdata[31:16] < MIN_IPV4_TOTAL_LEN) ||
        (s_axis_tdata[31:16] > MAX_IPV4_TOTAL_LEN);

    assign o_meta_data  = payload_len;
    assign o_meta_valid = s_axis_tlast && (state == PAYLOAD) && stream_fire &&
                          !s_axis_tuser && (payload_len[3:0] == 4'h0) &&
                          !malformed_check;

    assign o_rec_src_mac  = src_mac_reg;
    assign o_rec_src_ip   = src_ip_reg;
    assign o_rec_src_port = src_port_reg;
    assign o_rec_valid    = s_axis_tlast && (state == PAYLOAD) && stream_fire && !s_axis_tuser;

    assign o_arp_valid = (state == ARP_PAYLOAD) && stream_fire && !s_axis_tuser;
    assign o_arp_data  = s_axis_tdata;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            global_word_cnt <= 16'd0;
            ip_total_len <= 16'd0;
            udp_len <= 16'd0;
            ihl <= 4'd0;
            src_mac_reg <= 48'd0;
            src_ip_reg <= 32'd0;
            src_port_reg <= 16'd0;
        end else begin
            case (state)
                IDLE: begin
                    global_word_cnt <= 16'd0;
                    if (stream_fire) begin
                        state <= ETH_HDR;
                        global_word_cnt <= 16'd1;
                    end
                end

                ETH_HDR: begin
                    if (stream_fire) begin
                        global_word_cnt <= global_word_cnt + 16'd1;

                        if (global_word_cnt == 16'd1) begin
                            src_mac_reg[47:32] <= s_axis_tdata[15:0];
                        end

                        if (global_word_cnt == 16'd2) begin
                            src_mac_reg[31:0] <= s_axis_tdata[31:0];
                        end

                        if (global_word_cnt == 16'd3) begin
                            if (s_axis_tdata[31:16] == 16'h0800) begin
                                state <= IP_HDR;
                            end else if (s_axis_tdata[31:16] == 16'h0806) begin
                                state <= ARP_PAYLOAD;
                            end else begin
                                state <= DROP;
                            end
                        end
                    end
                end

                IP_HDR: begin
                    if (stream_fire) begin
                        global_word_cnt <= global_word_cnt + 16'd1;

                        if (global_word_cnt == 16'd4) begin
                            ip_total_len <= s_axis_tdata[31:16];
                            ihl <= s_axis_tdata[3:0];
                            if (frame_len_invalid_this_cycle) begin
                                state <= DROP;
                            end
                        end

                        if (global_word_cnt == 16'd7 && state == IP_HDR) begin
                            src_ip_reg[31:16] <= s_axis_tdata[15:0];
                        end

                        if (global_word_cnt == 16'd8 && state == IP_HDR) begin
                            src_ip_reg[15:0] <= s_axis_tdata[31:16];
                            state <= UDP_HDR;
                        end
                    end
                end

                UDP_HDR: begin
                    if (stream_fire) begin
                        global_word_cnt <= global_word_cnt + 16'd1;

                        if (global_word_cnt == 16'd9) begin
                            src_port_reg <= s_axis_tdata[15:0];
                        end

                        if (global_word_cnt == 16'd10) begin
                            udp_len <= s_axis_tdata[15:0];
                            if (((s_axis_tdata[15:0] - 16'd8) & 16'h000F) != 16'd0) begin
                                state <= DROP;
                            end else if (malformed_this_cycle) begin
                                state <= DROP;
                            end else begin
                                state <= PAYLOAD;
                            end
                        end
                    end
                end

                PAYLOAD: begin
                    if (stream_fire && s_axis_tlast) begin
                        state <= IDLE;
                    end
                end

                ARP_PAYLOAD: begin
                    if (stream_fire) begin
                        global_word_cnt <= global_word_cnt + 16'd1;
                        if (s_axis_tlast) begin
                            state <= IDLE;
                        end
                    end
                end

                DROP: begin
                    if (stream_fire && s_axis_tlast) begin
                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
