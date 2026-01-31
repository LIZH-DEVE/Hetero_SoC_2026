`timescale 1ns / 1ps

/**
 * Module: rx_parser_enhanced
 * Day 18 Enhanced Version - with drop statistics
 * 功能: 支持DROP_CNT统计和多种drop原因
 */

module rx_parser_enhanced #(
    parameter DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // AXI-Stream RX Input
    input  logic [DATA_WIDTH-1:0]  s_axis_tdata,
    input  logic                   s_axis_tvalid,
    input  logic                   s_axis_tlast,
    input  logic                   s_axis_tuser, // 1=Error
    output logic                   s_axis_tready,

    // PBM Write Interface
    output logic [DATA_WIDTH-1:0]  o_pbm_wdata,
    output logic                   o_pbm_wvalid,
    output logic                   o_pbm_wlast,
    output logic                   o_pbm_werror,
    input  logic                   i_pbm_ready,

    // Meta Data Interface
    output logic [15:0]            o_meta_data, // Payload Length
    output logic                   o_meta_valid,
    input  logic                   i_meta_ready,

    // [Day 18] Drop Statistics Interface
    output logic [31:0]            drop_cnt,
    output logic [31:0]            bad_align_cnt,
    output logic [31:0]            malformed_cnt,
    output logic [31:0]            runt_cnt,
    output logic [31:0]            giant_cnt,
    output logic [31:0]            normal_cnt,
    output logic [31:0]            accepted_cnt,
    output logic [2:0]            drop_reason, // 0=none,1=bad_align,2=malformed,3=runt,4=giant,5=user_error

    // [Day 10] Info Extraction Interface
    output logic [47:0]            o_rec_src_mac,
    output logic [31:0]            o_rec_src_ip,
    output logic [15:0]            o_rec_src_port,
    output logic                   o_rec_valid,

    // ARP Interface
    output logic [31:0]            o_arp_data,
    output logic                   o_arp_valid
);

    // 状态机
    typedef enum logic [2:0] {IDLE, ETH_HDR, IP_HDR, UDP_HDR, PAYLOAD, DROP} state_t;
    state_t state;

    logic [15:0] global_word_cnt;
    logic [15:0] ip_total_len;
    logic [15:0] udp_len;
    logic [3:0]  ihl;

    // 内部寄存器用于锁存提取的信息
    logic [47:0] src_mac_reg;
    logic [31:0] src_ip_reg;
    logic [15:0] src_port_reg;

    assign s_axis_tready = i_pbm_ready;

    // Passthrough to PBM
    assign o_pbm_wdata  = s_axis_tdata;
    assign o_pbm_wvalid = (state == PAYLOAD) && s_axis_tvalid;
    assign o_pbm_wlast  = s_axis_tlast && (state == PAYLOAD);
    assign o_pbm_werror = s_axis_tuser;

    // Meta Output
    logic [15:0] payload_len;
    logic [15:0] ip_header_bytes;
    logic       malformed_check;
    logic       bad_align_check;
    logic       frame_size_check;
    logic       runt_check;
    logic       giant_check;

    assign payload_len = udp_len - 16'd8;
    assign ip_header_bytes = ihl * 4;
    assign malformed_check = (udp_len > (ip_total_len - ip_header_bytes));
    assign bad_align_check = (payload_len[3:0] != 4'h0);
    assign runt_check = (ip_total_len < 16'd64); // < 64 bytes
    assign giant_check = (ip_total_len > 16'd1518); // > 1518 bytes

    assign o_meta_data  = payload_len;
    assign o_meta_valid = s_axis_tlast && (state == PAYLOAD) && !s_axis_tuser &&
                           (payload_len[3:0] == 4'h0) && !malformed_check;

    // Info Output
    assign o_rec_src_mac  = src_mac_reg;
    assign o_rec_src_ip   = src_ip_reg;
    assign o_rec_src_port = src_port_reg;
    assign o_rec_valid    = s_axis_tlast && (state == PAYLOAD) && !s_axis_tuser;

    // Drop Reason Assignment
    logic [2:0] current_drop_reason;
    always_comb begin
        current_drop_reason = 3'd0;

        if (state == DROP) begin
            if (s_axis_tuser) begin
                current_drop_reason = 3'd5; // user_error
            end else if (giant_check) begin
                current_drop_reason = 3'd4; // giant
            end else if (runt_check) begin
                current_drop_reason = 3'd3; // runt
            end else if (bad_align_check) begin
                current_drop_reason = 3'd1; // bad_align
            end else if (malformed_check) begin
                current_drop_reason = 3'd2; // malformed
            end
        end
    end

    assign drop_reason = current_drop_reason;

    // FSM & Extraction Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            global_word_cnt <= 0;
            ip_total_len <= 0;
            udp_len <= 0;
            src_mac_reg <= 0;
            src_ip_reg <= 0;
            src_port_reg <= 0;
        end else begin
            case (state)
                IDLE: begin
                    global_word_cnt <= 0;
                    if (s_axis_tvalid) begin
                        state <= ETH_HDR;
                        global_word_cnt <= 1;
                    end
                end

                ETH_HDR: begin
                    if (s_axis_tvalid) begin
                        global_word_cnt <= global_word_cnt + 1;
                        // Word 1: DstMacLo, SrcMacHi
                        if (global_word_cnt == 1) src_mac_reg[47:32] <= s_axis_tdata[15:0];
                        // Word 2: SrcMacLo
                        if (global_word_cnt == 2) src_mac_reg[31:0]  <= s_axis_tdata[31:0];

                        // Word 3: EthType (Check 0800)
                        if (global_word_cnt == 3) begin
                            if (s_axis_tdata[31:16] == 16'h0800) state <= IP_HDR;
                            else state <= DROP;
                        end
                    end
                end

                IP_HDR: begin
                    if (s_axis_tvalid) begin
                        global_word_cnt <= global_word_cnt + 1;
                        if (global_word_cnt == 4) ip_total_len <= s_axis_tdata[31:16];
                        if (global_word_cnt == 4) ihl <= s_axis_tdata[3:0];

                        // Word 7: Checksum, SrcIP Hi
                        if (global_word_cnt == 7) src_ip_reg[31:16] <= s_axis_tdata[15:0];
                        // Word 8: SrcIP Lo, DstIP Hi
                        if (global_word_cnt == 8) src_ip_reg[15:0]  <= s_axis_tdata[31:16];

                        if (global_word_cnt == 8) state <= UDP_HDR; // Simplify jump
                    end
                end

                UDP_HDR: begin
                    if (s_axis_tvalid) begin
                        global_word_cnt <= global_word_cnt + 1;
                        // Word 9: DstIP Lo, UDP SrcPort
                        if (global_word_cnt == 9) src_port_reg <= s_axis_tdata[15:0];

                        // Word 10: UDP DstPort, UDP Len
                        if (global_word_cnt == 10) begin
                            udp_len <= s_axis_tdata[15:0];

                            // [Day 18] Frame size checks
                            if (runt_check || giant_check) begin
                                state <= DROP;
                            end else if (bad_align_check) begin
                                state <= DROP;
                            end else if (malformed_check) begin
                                state <= DROP;
                            else
                                state <= PAYLOAD;
                        end
                    end
                end

                PAYLOAD: begin
                    if (s_axis_tvalid) begin
                        if (s_axis_tlast) state <= IDLE;
                    end
                end

                DROP: begin
                    if (s_axis_tvalid && s_axis_tlast) state <= IDLE;
                end
            endcase
        end
    end

    // [Day 18] Counters
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drop_cnt <= 32'd0;
            bad_align_cnt <= 32'd0;
            malformed_cnt <= 32'd0;
            runt_cnt <= 32'd0;
            giant_cnt <= 32'd0;
            normal_cnt <= 32'd0;
            accepted_cnt <= 32'd0;
        end else begin
            // Drop counters
            if (state == DROP && s_axis_tlast && s_axis_tvalid) begin
                drop_cnt <= drop_cnt + 1'b1;

                case (current_drop_reason)
                    3'd1: bad_align_cnt <= bad_align_cnt + 1'b1;
                    3'd2: malformed_cnt <= malformed_cnt + 1'b1;
                    3'd3: runt_cnt <= runt_cnt + 1'b1;
                    3'd4: giant_cnt <= giant_cnt + 1'b1;
                    default: ;
                endcase
            end

            // Normal packet counters
            if (state == PAYLOAD && s_axis_tlast && s_axis_tvalid) begin
                normal_cnt <= normal_cnt + 1'b1;

                if (o_meta_valid && i_meta_ready) begin
                    accepted_cnt <= accepted_cnt + 1'b1;
                end
            end
        end
    end

    // ARP Logic (Dummy for now)
    assign o_arp_valid = 0;
    assign o_arp_data = 0;

endmodule
