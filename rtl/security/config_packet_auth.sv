`ifndef CONFIG_PACKET_AUTH_SV
`define CONFIG_PACKET_AUTH_SV

`timescale 1ns / 1ps

/**
 * Module: config_packet_auth
 * Function:
 * 1. Magic check: first word must be 0xDEADBEEF
 * 2. Anti-replay: second word[15:0] must be strictly increasing
 * 3. On pass: forward full packet (including first two words)
 * 4. On fail: drop full packet
 */
module config_packet_auth #(
    parameter AXI_DATA_WIDTH = 32
)(
    input  logic                           clk,
    input  logic                           rst_n,

    // AXI-Stream Input
    input  logic [AXI_DATA_WIDTH-1:0]      s_axis_tdata,
    input  logic [AXI_DATA_WIDTH/8-1:0]    s_axis_tkeep,
    input  logic                           s_axis_tlast,
    input  logic                           s_axis_tvalid,
    output logic                           s_axis_tready,

    // AXI-Stream Output
    output logic [AXI_DATA_WIDTH-1:0]      m_axis_tdata,
    output logic [AXI_DATA_WIDTH/8-1:0]    m_axis_tkeep,
    output logic                           m_axis_tlast,
    output logic                           m_axis_tvalid,
    input  logic                           m_axis_tready,

    // Status
    output logic [31:0]                    auth_success_cnt,
    output logic [31:0]                    auth_fail_cnt,
    output logic [31:0]                    replay_fail_cnt,
    output logic [15:0]                    last_seq_id,
    output logic                           error_flag
);

    localparam logic [31:0] MAGIC_NUMBER = 32'hDEADBEEF;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_WAIT_SEQ,
        ST_DECIDE,
        ST_FLUSH_HDR0,
        ST_FLUSH_HDR1,
        ST_STREAM,
        ST_DROP
    } state_t;

    state_t state;

    logic [31:0] hdr0_data, hdr1_data;
    logic [3:0]  hdr0_keep, hdr1_keep;
    logic        hdr0_last, hdr1_last;

    logic [15:0] seq_id_reg;
    logic [31:0] success_cnt, fail_cnt, replay_cnt;

    logic magic_match, seq_match, pkt_pass;

    assign magic_match = (hdr0_data == MAGIC_NUMBER);
    assign seq_match   = (hdr1_data[15:0] > seq_id_reg) || (seq_id_reg == 16'hFFFF);
    assign pkt_pass    = magic_match && seq_match;

    always_comb begin
        s_axis_tready = 1'b0;
        m_axis_tdata  = '0;
        m_axis_tkeep  = '0;
        m_axis_tlast  = 1'b0;
        m_axis_tvalid = 1'b0;

        case (state)
            ST_IDLE,
            ST_WAIT_SEQ: begin
                s_axis_tready = 1'b1;
            end

            ST_FLUSH_HDR0: begin
                m_axis_tdata  = hdr0_data;
                m_axis_tkeep  = hdr0_keep;
                m_axis_tlast  = hdr0_last;
                m_axis_tvalid = 1'b1;
            end

            ST_FLUSH_HDR1: begin
                m_axis_tdata  = hdr1_data;
                m_axis_tkeep  = hdr1_keep;
                m_axis_tlast  = hdr1_last;
                m_axis_tvalid = 1'b1;
            end

            ST_STREAM: begin
                s_axis_tready = m_axis_tready;
                m_axis_tdata  = s_axis_tdata;
                m_axis_tkeep  = s_axis_tkeep;
                m_axis_tlast  = s_axis_tlast;
                m_axis_tvalid = s_axis_tvalid;
            end

            ST_DROP: begin
                // Keep draining packet to avoid deadlock
                s_axis_tready = 1'b1;
            end

            default: begin
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            hdr0_data <= '0;
            hdr1_data <= '0;
            hdr0_keep <= '0;
            hdr1_keep <= '0;
            hdr0_last <= 1'b0;
            hdr1_last <= 1'b0;
            seq_id_reg <= 16'h0000;
            success_cnt <= 32'd0;
            fail_cnt <= 32'd0;
            replay_cnt <= 32'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        hdr0_data <= s_axis_tdata;
                        hdr0_keep <= s_axis_tkeep;
                        hdr0_last <= s_axis_tlast;
                        // Packet too short to carry seq -> drop
                        if (s_axis_tlast) begin
                            fail_cnt <= fail_cnt + 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            state <= ST_WAIT_SEQ;
                        end
                    end
                end

                ST_WAIT_SEQ: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        hdr1_data <= s_axis_tdata;
                        hdr1_keep <= s_axis_tkeep;
                        hdr1_last <= s_axis_tlast;
                        state <= ST_DECIDE;
                    end
                end

                ST_DECIDE: begin
                    if (pkt_pass) begin
                        seq_id_reg <= hdr1_data[15:0];
                        success_cnt <= success_cnt + 1'b1;
                        state <= ST_FLUSH_HDR0;
                    end else begin
                        if (!magic_match) begin
                            fail_cnt <= fail_cnt + 1'b1;
                        end else begin
                            replay_cnt <= replay_cnt + 1'b1;
                        end
                        if (hdr1_last) begin
                            state <= ST_IDLE;
                        end else begin
                            state <= ST_DROP;
                        end
                    end
                end

                ST_FLUSH_HDR0: begin
                    if (m_axis_tvalid && m_axis_tready) begin
                        if (hdr0_last) begin
                            state <= ST_IDLE;
                        end else begin
                            state <= ST_FLUSH_HDR1;
                        end
                    end
                end

                ST_FLUSH_HDR1: begin
                    if (m_axis_tvalid && m_axis_tready) begin
                        if (hdr1_last) begin
                            state <= ST_IDLE;
                        end else begin
                            state <= ST_STREAM;
                        end
                    end
                end

                ST_STREAM: begin
                    if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
                        state <= ST_IDLE;
                    end
                end

                ST_DROP: begin
                    if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    assign auth_success_cnt = success_cnt;
    assign auth_fail_cnt    = fail_cnt;
    assign replay_fail_cnt  = replay_cnt;
    assign last_seq_id      = seq_id_reg;
    assign error_flag       = (state == ST_DROP);

endmodule
`endif