`timescale 1ns / 1ps

/**
 * 模块名称: rx_parser
 * 版本: Day 09 Final Stable
 * 描述: 
 * 1. 实现基于全局计数器的协议解析，消灭时序错位。
 * 2. 严格校验 UDP 长度与 IP 长度的一致性。
 * 3. 修复了信号初始化，消灭波形中的红色不定态(X)。
 */

module rx_parser (
    input  logic           clk,
    input  logic           rst_n,

    // --- [Input] From MAC (AXI-Stream) ---
    input  logic [31:0]    s_axis_tdata,
    input  logic           s_axis_tvalid,
    input  logic           s_axis_tlast,
    input  logic           s_axis_tuser,
    output logic           s_axis_tready,

    // --- [Output] To PBM (Payload) ---
    output logic [31:0]    o_pbm_wdata,
    output logic           o_pbm_wvalid,
    output logic           o_pbm_wlast,
    output logic           o_pbm_werror,
    input  logic           i_pbm_ready,

    // --- [Output] To Meta FIFO ---
    output logic [15:0]    o_meta_data,
    output logic           o_meta_valid,
    input  logic           i_meta_ready,

    // --- [Output] To ARP Responder ---
    output logic [31:0]    o_arp_data,
    output logic           o_arp_valid
);

    // ==========================================================
    // 状态机与寄存器定义
    // ==========================================================
    typedef enum logic [3:0] {
        IDLE        = 4'h0,
        ETH_HDR     = 4'h1,
        IP_HDR      = 4'h2,
        UDP_HDR     = 4'h3,
        PAYLOAD     = 4'h4,
        CHECKSUM    = 4'h5,
        COMMIT      = 4'h6,
        ROLLBACK    = 4'h7,
        WAIT_END    = 4'h8
    } state_t;

    state_t state, next_state;

    // 协议字段寄存器 (增加复位初值以消灭红色 X)
    logic [15:0] eth_type;
    logic [15:0] ip_total_len;
    logic [15:0] udp_len;
    logic [13:0] global_word_cnt;

    // 内部连线
    assign s_axis_tready = i_pbm_ready && i_meta_ready;

    // ==========================================================
    // 1. 全局字计数器 (Absolute Coordinate System)
    // ==========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            global_word_cnt <= 0;
        end else begin
            if (state == IDLE) begin
                if (s_axis_tvalid && s_axis_tready) global_word_cnt <= 1;
                else                                global_word_cnt <= 0;
            end else if (s_axis_tvalid && s_axis_tready) begin
                global_word_cnt <= global_word_cnt + 1;
            end
        end
    end

    // ==========================================================
    // 2. 状态转移逻辑 (FSM)
    // ==========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:    if (s_axis_tvalid && s_axis_tready) next_state = ETH_HDR;
            
            // Eth: Word 0,1,2 (14B). 在 Word 2 结束时跳
            ETH_HDR: if (global_word_cnt == 2) next_state = IP_HDR;
            
            // IP: Word 3..7 (20B). 在 Word 7 结束时跳
            IP_HDR:  begin
                if (eth_type != 16'h0800)      next_state = WAIT_END;
                else if (global_word_cnt == 7) next_state = UDP_HDR;
            end
            
            // UDP: Word 8,9 (8B). 在 Word 9 结束时跳
            UDP_HDR: if (global_word_cnt == 9) next_state = PAYLOAD;
            
            PAYLOAD: if (s_axis_tlast)         next_state = CHECKSUM;
            
            CHECKSUM: begin
                // Task 8.2: 严格校验长度对齐
                if ((udp_len + 16'd20) != ip_total_len) next_state = ROLLBACK;
                else                                    next_state = COMMIT;
            end
            
            COMMIT, ROLLBACK, WAIT_END: next_state = IDLE;
            default: next_state = IDLE;
        endcase

        // 异步错误处理
        if (s_axis_tvalid && s_axis_tlast && s_axis_tuser) next_state = ROLLBACK;
    end

    // ==========================================================
    // 3. 协议字段提取 (Bit-Slicing)
    // ==========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eth_type     <= 16'h0;
            ip_total_len <= 16'h0;
            udp_len      <= 16'h0;
        end else if (s_axis_tvalid && s_axis_tready) begin
            // Word 2: Eth Type (低16位)
            if (global_word_cnt == 2) eth_type <= s_axis_tdata[15:0];
            
            // Word 3: IP Total Len (低16位)
            if (global_word_cnt == 3) ip_total_len <= s_axis_tdata[15:0];
            
            // Word 9: UDP Len (高16位)
            if (global_word_cnt == 9) udp_len <= s_axis_tdata[31:16];
        end
    end

    // ==========================================================
    // 4. 输出驱动 (Output Driver)
    // ==========================================================
    assign o_pbm_wdata  = s_axis_tdata;
    
    // 只有在有效解析期间才往 PBM 写数据
    assign o_pbm_wvalid = s_axis_tvalid && s_axis_tready && 
                          (state != IDLE && state != COMMIT && state != ROLLBACK && state != WAIT_END);
    
    assign o_pbm_wlast  = s_axis_tlast;
    
    // 当状态机进入 ROLLBACK 时，产生一个脉冲告知 PBM 回滚指针
    assign o_pbm_werror = (state == ROLLBACK);

    assign o_meta_data  = {2'b00, udp_len[13:0]};
    assign o_meta_valid = (state == COMMIT);
    
    // ARP 接口预留
    assign o_arp_data   = s_axis_tdata;
    assign o_arp_valid  = (state == ETH_HDR);

endmodule