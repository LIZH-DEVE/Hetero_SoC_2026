`timescale 1ns / 1ps

/**
 * Module: fast_path
 * Task 16.1: FastPath Rules (Patch)
 * 功能: 零拷贝快速通道
 * 
 * FastPath 规则:
 * 1. Dst_Port != CRYPTO && Dst_Port != CONFIG
 * 2. !drop_flag (未被 ACL 拦截)
 * 3. payload_len 合法
 * 
 * 动作: PBM 直通 TX (Zero-Copy)
 * Checksum: 由于 FastPath 不改 Payload，直接透传原 Checksum
 */

module fast_path #(
    parameter AXI_DATA_WIDTH = 32,
    parameter CRYPTO_PORT   = 16'h1234,  // Crypto 端口
    parameter CONFIG_PORT   = 16'h4321   // Config 端口
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // =========================================================================
    // RX Path Input (From Parser)
    // =========================================================================
    input  logic [AXI_DATA_WIDTH-1:0] s_axis_tdata,
    input  logic [AXI_DATA_WIDTH/8-1:0]  s_axis_tkeep,
    input  logic                         s_axis_tlast,
    input  logic                         s_axis_tvalid,
    output logic                         s_axis_tready,

    // =========================================================================
    // Control Signals
    // =========================================================================
    input  logic [15:0]                  dst_port,      // 目标端口
    input  logic [15:0]                  payload_len,   // Payload 长度
    input  logic                         drop_flag,      // ACL 拦截标志
    input  logic                         meta_valid,    // Meta 数据有效

    // =========================================================================
    // Checksum Signals (Original Checksums from RX)
    // =========================================================================
    input  logic [15:0]                  ip_checksum,    // 原始 IP Checksum
    input  logic [15:0]                  udp_checksum,  // 原始 UDP Checksum
    input  logic                         checksum_valid,

    // =========================================================================
    // PBM Interface (Write - from FastPath)
    // =========================================================================
    output logic [AXI_DATA_WIDTH-1:0]  pbm_wdata,
    output logic                        pbm_wvalid,
    output logic                        pbm_wlast,
    input  logic                        pbm_ready,

    // =========================================================================
    // TX Path Output (Direct to TX Stack)
    // =========================================================================
    output logic [AXI_DATA_WIDTH-1:0]  m_axis_tdata,
    output logic [AXI_DATA_WIDTH/8-1:0]  m_axis_tkeep,
    output logic                         m_axis_tlast,
    output logic                         m_axis_tvalid,
    input  logic                         m_axis_tready,

    // =========================================================================
    // Meta Data Output (To TX Stack)
    // =========================================================================
    output logic [15:0]                 meta_out_data,  // Payload Length
    output logic                        meta_out_valid,
    output logic [15:0]                 meta_out_checksum, // Original Checksum
    output logic                        meta_out_checksum_valid,

    // =========================================================================
    // Status and Statistics
    // =========================================================================
    output logic                        fast_path_enable,   // FastPath 是否启用
    output logic [31:0]                 fast_path_cnt,     // FastPath 计数
    output logic [31:0]                 bypass_cnt,        // 绕过计数 (到 Crypto)
    output logic                        drop_cnt,          // 丢弃计数
    output logic [31:0]                 checksum_pass_cnt  // Checksum 透传计数
);

    // =========================================================================
    // Internal Signals
    // =========================================================================
    logic [15:0]                    port_check;
    logic                           acl_check;
    logic                           payload_check;
    logic                           fast_path_condition;
    logic                           fast_path_active;

    logic                           port_crypto;
    logic                           port_config;

    // Counters
    logic [31:0]                    fp_cnt;
    logic [31:0]                    bp_cnt;
    logic [31:0]                    dp_cnt;
    logic [31:0]                    cs_pass_cnt;

    // =========================================================================
    // FastPath Rule Check Logic
    // =========================================================================
    // 规则 1: Dst_Port != CRYPTO && Dst_Port != CONFIG
    assign port_crypto  = (dst_port == CRYPTO_PORT);
    assign port_config  = (dst_port == CONFIG_PORT);
    assign port_check   = (!port_crypto) && (!port_config);

    // 规则 2: !drop_flag (未被 ACL 拦截)
    assign acl_check    = !drop_flag;

    // 规则 3: payload_len 合法 (16-byte aligned 且 > 0)
    assign payload_check = (payload_len > 0) && ((payload_len & 16'h000F) == 16'h0000);

    // 综合条件
    assign fast_path_condition = port_check && acl_check && payload_check && meta_valid;

    // =========================================================================
    // FastPath State Machine
    // =========================================================================
    typedef enum logic [1:0] {
        IDLE,
        CHECK_PATH,
        FAST_PATH_TX,
        BYPASS_CRYPTO
    } state_t;

    state_t state, state_next;

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
                if (meta_valid && s_axis_tvalid) begin
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
                if (s_axis_tlast && s_axis_tvalid) begin
                    state_next = IDLE;
                end
            end

            BYPASS_CRYPTO: begin
                if (s_axis_tlast && s_axis_tvalid) begin
                    state_next = IDLE;
                end
            end

            default: begin
                state_next = IDLE;
            end
        endcase
    end

    assign fast_path_active = (state == FAST_PATH_TX);
    assign fast_path_enable = fast_path_active;

    // =========================================================================
    // PBM Write Interface (Direct passthrough in FastPath mode)
    // =========================================================================
    assign pbm_wdata  = s_axis_tdata;
    assign pbm_wvalid = (state == FAST_PATH_TX) && s_axis_tvalid;
    assign pbm_wlast  = s_axis_tlast && (state == FAST_PATH_TX);

    // =========================================================================
    // TX Path Output (Direct passthrough to TX Stack)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata  <= {AXI_DATA_WIDTH{1'b0}};
            m_axis_tkeep  <= {(AXI_DATA_WIDTH/8){1'b0}};
            m_axis_tlast  <= 1'b0;
            m_axis_tvalid <= 1'b0;
        end else begin
            if (state == FAST_PATH_TX) begin
                m_axis_tdata  <= s_axis_tdata;
                m_axis_tkeep  <= s_axis_tkeep;
                m_axis_tlast  <= s_axis_tlast;
                m_axis_tvalid <= s_axis_tvalid;
            end else begin
                m_axis_tvalid <= 1'b0;
            end
        end
    end

    assign s_axis_tready = (state == FAST_PATH_TX) ? (m_axis_tready && pbm_ready) :
                           (state == BYPASS_CRYPTO) ? 1'b0 : 1'b1;

    // =========================================================================
    // Meta Data Output (To TX Stack)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta_out_data <= 16'd0;
            meta_out_valid <= 1'b0;
            meta_out_checksum <= 16'd0;
            meta_out_checksum_valid <= 1'b0;
        end else begin
            meta_out_valid <= 1'b0;
            meta_out_checksum_valid <= 1'b0;

            if (state == FAST_PATH_TX && s_axis_tlast && s_axis_tvalid) begin
                meta_out_data <= payload_len;
                meta_out_valid <= 1'b1;
                
                // Checksum 透传: 由于 FastPath 不改 Payload，直接透传原 Checksum
                if (checksum_valid) begin
                    meta_out_checksum <= udp_checksum;
                    meta_out_checksum_valid <= 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // Counters
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fp_cnt <= 32'd0;
            bp_cnt <= 32'd0;
            dp_cnt <= 32'd0;
            cs_pass_cnt <= 32'd0;
        end else begin
            // FastPath counter: increment when packet completes in FAST_PATH_TX
            if (state == FAST_PATH_TX && s_axis_tlast && s_axis_tvalid) begin
                fp_cnt <= fp_cnt + 1'b1;
            end

            // Bypass counter: increment when packet completes in BYPASS_CRYPTO
            if (state == BYPASS_CRYPTO && s_axis_tlast && s_axis_tvalid) begin
                bp_cnt <= bp_cnt + 1'b1;
            end

            // Drop counter: increment when drop_flag is set during meta_valid
            if (drop_flag && meta_valid) begin
                dp_cnt <= dp_cnt + 1'b1;
            end

            // Checksum pass counter: increment when FastPath completes with checksum
            if (state == FAST_PATH_TX && s_axis_tlast && checksum_valid) begin
                cs_pass_cnt <= cs_pass_cnt + 1'b1;
            end
        end
    end

    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign fast_path_cnt        = fp_cnt;
    assign bypass_cnt           = bp_cnt;
    assign drop_cnt             = dp_cnt;
    assign checksum_pass_cnt    = cs_pass_cnt;

endmodule
