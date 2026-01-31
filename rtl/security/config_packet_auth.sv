`timescale 1ns / 1ps

/**
 * Module: config_packet_auth
 * Task 14.1: Config Packet Authentication
 * 功能:
 * 1. 简单认证：配置包Payload前4字节必须匹配0xDEADBEEF
 * 2. 防重放：检查配置包seq_id必须递增
 */

module config_packet_auth #(
    parameter AXI_DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // =========================================================================
    // AXI-Stream Input (Config Packets)
    // =========================================================================
    input  logic [AXI_DATA_WIDTH-1:0] s_axis_tdata,
    input  logic [AXI_DATA_WIDTH/8-1:0]  s_axis_tkeep,
    input  logic                         s_axis_tlast,
    input  logic                         s_axis_tvalid,
    output logic                         s_axis_tready,

    // =========================================================================
    // AXI-Stream Output (Authenticated Packets)
    // =========================================================================
    output logic [AXI_DATA_WIDTH-1:0] m_axis_tdata,
    output logic [AXI_DATA_WIDTH/8-1:0]  m_axis_tkeep,
    output logic                         m_axis_tlast,
    output logic                         m_axis_tvalid,
    input  logic                         m_axis_tready,

    // =========================================================================
    // Status and Control
    // =========================================================================
    output logic [31:0]                 auth_success_cnt,
    output logic [31:0]                 auth_fail_cnt,
    output logic [31:0]                 replay_fail_cnt,
    output logic [15:0]                 last_seq_id,
    output logic                         error_flag
);

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam MAGIC_NUMBER = 32'hDEADBEEF;

    // =========================================================================
    // State Machine
    // =========================================================================
    typedef enum logic [2:0] {
        IDLE,
        CHECK_MAGIC,
        CHECK_SEQ,
        FORWARD,
        DROP
    } state_t;

    state_t state, state_next;

    // =========================================================================
    // Internal Signals
    // =========================================================================
    logic [31:0] magic_word;
    logic [15:0] packet_seq_id;
    logic [15:0] seq_id_reg;
    logic [15:0] seq_id_next;
    logic magic_match;
    logic seq_valid;
    logic packet_valid;

    // FIFO for packet buffering
    logic [AXI_DATA_WIDTH-1:0] fifo_tdata;
    logic [AXI_DATA_WIDTH/8-1:0]  fifo_tkeep;
    logic fifo_tlast;
    logic fifo_tvalid;
    logic fifo_tready;
    logic fifo_empty;
    logic fifo_full;

    // Counters
    logic [31:0] success_cnt;
    logic [31:0] fail_cnt;
    logic [31:0] replay_cnt;

    // =========================================================================
    // Magic Number Check
    // =========================================================================
    assign magic_word = s_axis_tdata;
    assign magic_match = (magic_word == MAGIC_NUMBER);

    // =========================================================================
    // Sequence ID Check (Anti-Replay)
    // =========================================================================
    assign packet_seq_id = s_axis_tdata[15:0];
    assign seq_valid = (packet_seq_id > seq_id_reg) || (seq_id_reg == 16'hFFFF);

    // =========================================================================
    // Packet Valid
    // =========================================================================
    assign packet_valid = magic_match && seq_valid;

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
                    state_next = CHECK_MAGIC;
                end
            end

            CHECK_MAGIC: begin
                if (magic_match) begin
                    state_next = CHECK_SEQ;
                end else begin
                    state_next = DROP;
                end
            end

            CHECK_SEQ: begin
                if (seq_valid) begin
                    state_next = FORWARD;
                end else begin
                    state_next = DROP;
                end
            end

            FORWARD: begin
                if (s_axis_tvalid && s_axis_tlast) begin
                    state_next = IDLE;
                end
            end

            DROP: begin
                if (s_axis_tvalid && s_axis_tlast) begin
                    state_next = IDLE;
                end
            end

            default: begin
                state_next = IDLE;
            end
        endcase
    end

    // =========================================================================
    // Sequence ID Register
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seq_id_reg <= 16'h0000;
        end else begin
            seq_id_reg <= seq_id_next;
        end
    end

    assign seq_id_next = (state == CHECK_SEQ && seq_valid) ? packet_seq_id : seq_id_reg;

    // =========================================================================
    // Counters
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            success_cnt <= 32'd0;
            fail_cnt <= 32'd0;
            replay_cnt <= 32'd0;
        end else begin
            if (state == CHECK_MAGIC && !magic_match) begin
                fail_cnt <= fail_cnt + 1'b1;
            end else if (state == CHECK_SEQ && !seq_valid) begin
                replay_cnt <= replay_cnt + 1'b1;
            end else if (state == FORWARD && s_axis_tvalid && s_axis_tlast) begin
                success_cnt <= success_cnt + 1'b1;
            end
        end
    end

    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign auth_success_cnt = success_cnt;
    assign auth_fail_cnt = fail_cnt;
    assign replay_fail_cnt = replay_cnt;
    assign last_seq_id = seq_id_reg;
    assign error_flag = (state == DROP);

    // =========================================================================
    // AXI-Stream Output Logic
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata <= {AXI_DATA_WIDTH{1'b0}};
            m_axis_tkeep <= {(AXI_DATA_WIDTH/8){1'b0}};
            m_axis_tlast <= 1'b0;
            m_axis_tvalid <= 1'b0;
        end else begin
            if (state == FORWARD && m_axis_tready) begin
                m_axis_tdata <= s_axis_tdata;
                m_axis_tkeep <= s_axis_tkeep;
                m_axis_tlast <= s_axis_tlast;
                m_axis_tvalid <= s_axis_tvalid;
            end else begin
                m_axis_tvalid <= 1'b0;
            end
        end
    end

    assign s_axis_tready = (state != DROP) && m_axis_tready;

endmodule
