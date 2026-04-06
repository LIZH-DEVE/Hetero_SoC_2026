`timescale 1ns / 1ps

/**
 * Module: fast_path
 * Task 16.1: FastPath Rules
 *
 * Current contract:
 * - Eligible packets are consumed locally and forwarded to TX/PBM.
 * - Non-eligible packets are classified as bypass/drop and held until the
 *   external owner of that path takes over and deasserts meta_valid.
 */

module fast_path #(
    parameter AXI_DATA_WIDTH = 32,
    parameter CRYPTO_PORT    = 16'h1234,
    parameter CONFIG_PORT    = 16'h4321
)(
    input  logic                           clk,
    input  logic                           rst_n,

    // RX path input
    input  logic [AXI_DATA_WIDTH-1:0]      s_axis_tdata,
    input  logic [AXI_DATA_WIDTH/8-1:0]    s_axis_tkeep,
    input  logic                           s_axis_tlast,
    input  logic                           s_axis_tvalid,
    output logic                           s_axis_tready,

    // Control signals
    input  logic [15:0]                    dst_port,
    input  logic [15:0]                    payload_len,
    input  logic                           drop_flag,
    input  logic                           meta_valid,

    // Checksum signals
    input  logic [15:0]                    ip_checksum,
    input  logic [15:0]                    udp_checksum,
    input  logic                           checksum_valid,

    // PBM interface
    output logic [AXI_DATA_WIDTH-1:0]      pbm_wdata,
    output logic                           pbm_wvalid,
    output logic                           pbm_wlast,
    input  logic                           pbm_ready,

    // TX path output
    output logic [AXI_DATA_WIDTH-1:0]      m_axis_tdata,
    output logic [AXI_DATA_WIDTH/8-1:0]    m_axis_tkeep,
    output logic                           m_axis_tlast,
    output logic                           m_axis_tvalid,
    input  logic                           m_axis_tready,

    // Meta data output
    output logic [15:0]                    meta_out_data,
    output logic                           meta_out_valid,
    output logic [15:0]                    meta_out_checksum,
    output logic                           meta_out_checksum_valid,

    // Status and statistics
    output logic                           fast_path_enable,
    output logic [31:0]                    fast_path_cnt,
    output logic [31:0]                    bypass_cnt,
    output logic [31:0]                    drop_cnt,
    output logic [31:0]                    checksum_pass_cnt
);

    typedef enum logic [1:0] {
        IDLE,
        CHECK_PATH,
        FAST_PATH_TX,
        BYPASS_CRYPTO
    } state_t;

    state_t state, state_next;

    logic port_crypto;
    logic port_config;
    logic port_check;
    logic acl_check;
    logic payload_check;
    logic fast_path_condition;
    logic fast_path_active;
    logic packet_handshake_done;

    logic [31:0] fp_cnt;
    logic [31:0] bp_cnt;
    logic [31:0] dp_cnt;
    logic [31:0] cs_pass_cnt;

    assign port_crypto         = (dst_port == CRYPTO_PORT);
    assign port_config         = (dst_port == CONFIG_PORT);
    assign port_check          = !port_crypto && !port_config;
    assign acl_check           = !drop_flag;
    assign payload_check       = (payload_len > 0) && ((payload_len & 16'h000F) == 16'h0000);
    assign fast_path_condition = port_check && acl_check && payload_check && meta_valid;
    assign fast_path_active    = (state == FAST_PATH_TX);
    assign fast_path_enable    = fast_path_active;
    assign packet_handshake_done = s_axis_tlast && s_axis_tvalid && s_axis_tready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= state_next;
        end
    end

    always_comb begin
        state_next = state;

        case (state)
            IDLE: begin
                if (meta_valid) begin
                    state_next = CHECK_PATH;
                end
            end

            CHECK_PATH: begin
                if (fast_path_condition) begin
                    state_next = FAST_PATH_TX;
                end else begin
                    state_next = BYPASS_CRYPTO;
                end
            end

            FAST_PATH_TX: begin
                if (packet_handshake_done) begin
                    state_next = IDLE;
                end
            end

            BYPASS_CRYPTO: begin
                if (!meta_valid) begin
                    state_next = IDLE;
                end
            end

            default: begin
                state_next = IDLE;
            end
        endcase
    end

    assign pbm_wdata  = s_axis_tdata;
    assign pbm_wvalid = fast_path_active && s_axis_tvalid;
    assign pbm_wlast  = fast_path_active && s_axis_tlast;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata  <= '0;
            m_axis_tkeep  <= '0;
            m_axis_tlast  <= 1'b0;
            m_axis_tvalid <= 1'b0;
        end else if (fast_path_active) begin
            m_axis_tdata  <= s_axis_tdata;
            m_axis_tkeep  <= s_axis_tkeep;
            m_axis_tlast  <= s_axis_tlast;
            m_axis_tvalid <= s_axis_tvalid;
        end else begin
            m_axis_tvalid <= 1'b0;
        end
    end

    // Hold beat 0 until the path decision is complete. For non-fast-path
    // packets, keep ready low so an external owner can take over.
    assign s_axis_tready = fast_path_active ? (m_axis_tready && pbm_ready) : 1'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta_out_data <= 16'd0;
            meta_out_valid <= 1'b0;
            meta_out_checksum <= 16'd0;
            meta_out_checksum_valid <= 1'b0;
        end else begin
            meta_out_valid <= 1'b0;
            meta_out_checksum_valid <= 1'b0;

            if (fast_path_active && packet_handshake_done) begin
                meta_out_data <= payload_len;
                meta_out_valid <= 1'b1;

                if (checksum_valid) begin
                    meta_out_checksum <= udp_checksum;
                    meta_out_checksum_valid <= 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fp_cnt <= 32'd0;
            bp_cnt <= 32'd0;
            dp_cnt <= 32'd0;
            cs_pass_cnt <= 32'd0;
        end else begin
            if (fast_path_active && packet_handshake_done) begin
                fp_cnt <= fp_cnt + 1'b1;
            end

            // Non-fast-path results are classification events, not local packet
            // completions, because this module has no alternate data output.
            if (state == CHECK_PATH && !fast_path_condition && !drop_flag) begin
                bp_cnt <= bp_cnt + 1'b1;
            end

            if (state == CHECK_PATH && !fast_path_condition && drop_flag) begin
                dp_cnt <= dp_cnt + 1'b1;
            end

            if (fast_path_active && packet_handshake_done && checksum_valid) begin
                cs_pass_cnt <= cs_pass_cnt + 1'b1;
            end
        end
    end

    assign fast_path_cnt     = fp_cnt;
    assign bypass_cnt        = bp_cnt;
    assign drop_cnt          = dp_cnt;
    assign checksum_pass_cnt = cs_pass_cnt;

endmodule
