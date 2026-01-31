`timescale 1ns / 1ps

/**
 * Module: arp_responder
 * Description: 完整的ARP应答器
 * Task 8.3: ARP Responder
 */
module arp_responder (
    input  logic        clk,
    input  logic        rst_n,
    
    // --- AXI-Stream Input (ARP Request) ---
    input  logic [31:0] i_arp_data,
    input  logic        i_arp_valid,
    output logic        i_arp_ready,
    
    // --- AXI-Stream Output (ARP Reply) ---
    output logic [31:0] o_tx_data,
    output logic        o_tx_valid,
    input  logic        o_tx_ready,
    
    // --- Configuration ---
    input  logic [47:0] i_local_mac,   // 本机MAC地址
    input  logic [31:0] i_local_ip,    // 本机IP地址
    input  logic        i_arp_enable   // 使能ARP响应
);

    // =========================================================
    // ARP协议字段定义
    // =========================================================
    localparam [15:0] ARP_HTYPE_ETHER = 16'h0001;  // Ethernet
    localparam [15:0] ARP_PTYPE_IPV4 = 16'h0800;  // IPv4
    localparam [15:0] ARP_HLEN_MAC  = 16'h0006;   // MAC地址长度
    localparam [15:0] ARP_PLEN_IP  = 16'h0004;   // IP地址长度
    localparam [15:0] ARP_OP_REQUEST= 16'h0001;  // ARP请求
    localparam [15:0] ARP_OP_REPLY  = 16'h0002;  // ARP响应

    // =========================================================
    // 状态机定义
    // =========================================================
    typedef enum logic [2:0] {IDLE, PARSE_HT, PARSE_PT, PARSE_OP, CHECK_IP, BUILD_REPLY, SEND_REPLY} state_t;
    state_t state, next_state;

    // =========================================================
    // 内部信号定义
    // =========================================================
    logic [15:0] arp_htype;
    logic [15:0] arp_ptype;
    logic [7:0]  arp_hlen;
    logic [7:0]  arp_plen;
    logic [15:0] arp_operation;
    logic [47:0] arp_src_mac;
    logic [31:0] arp_src_ip;
    logic [31:0] arp_dst_ip;
    logic [47:0] arp_dst_mac;

    logic [15:0] word_cnt;
    logic        is_arp_request;
    logic        ip_match;

    // =========================================================
    // ARP协议解析
    // =========================================================
    assign is_arp_request = (arp_operation == ARP_OP_REQUEST);
    assign ip_match = (arp_dst_ip == i_local_ip) && i_arp_enable;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            word_cnt <= 0;
            arp_htype <= 0;
            arp_ptype <= 0;
            arp_hlen <= 0;
            arp_plen <= 0;
            arp_operation <= 0;
            arp_src_mac <= 0;
            arp_src_ip <= 0;
            arp_dst_ip <= 0;
            arp_dst_mac <= 0;
        end else begin
            state <= next_state;

            case (state)
                IDLE: begin
                    word_cnt <= 0;
                    if (i_arp_valid && i_arp_enable) begin
                        next_state <= PARSE_HT;
                    end
                end

                PARSE_HT: begin
                    if (i_arp_valid && i_arp_ready) begin
                        word_cnt <= word_cnt + 1'b1;
                        if (word_cnt == 0) begin
                            arp_htype <= i_arp_data[31:16];
                            arp_ptype <= i_arp_data[15:0];
                        end
                        if (word_cnt == 1) begin
                            arp_hlen <= i_arp_data[31:24];
                            arp_plen <= i_arp_data[23:16];
                            arp_operation <= i_arp_data[15:0];
                        end
                        if (word_cnt == 2) begin
                            arp_src_mac[47:32] <= i_arp_data[31:16];
                        end
                        if (word_cnt == 3) begin
                            arp_src_mac[31:0] <= i_arp_data[31:0];
                        end
                        if (word_cnt == 4) begin
                            arp_src_ip <= i_arp_data[31:0];
                        end
                        if (word_cnt == 5) begin
                            arp_dst_ip <= i_arp_data[31:0];
                            next_state <= CHECK_IP;
                        end
                    end
                end

                CHECK_IP: begin
                    if (is_arp_request && ip_match) begin
                        next_state <= BUILD_REPLY;
                    end else begin
                        next_state <= IDLE;
                    end
                end

                BUILD_REPLY: begin
                    next_state <= SEND_REPLY;
                end

                SEND_REPLY: begin
                    next_state <= IDLE;
                end

                default: next_state <= IDLE;
            endcase
        end
    end

    // =========================================================
    // 数据输出多路复用
    // =========================================================
    always_comb begin
        i_arp_ready = (state == PARSE_HT) && i_arp_enable;
        
        case (state)
            IDLE, PARSE_HT, CHECK_IP: begin
                o_tx_valid = 1'b0;
                o_tx_data = 32'h0;
            end
            BUILD_REPLY: begin
                o_tx_valid = 1'b1;
                o_tx_data = 32'h0;
            end
            SEND_REPLY: begin
                if (word_cnt == 0) begin
                    o_tx_data = {16'h0000, ARP_HTYPE_ETHER};
                end else if (word_cnt == 1) begin
                    o_tx_data = {16'h0000, ARP_PTYPE_IPV4};
                end else if (word_cnt == 2) begin
                    o_tx_data = {8'h0000, ARP_HLEN_MAC, 8'h0000, ARP_PLEN_IP};
                end else if (word_cnt == 3) begin
                    o_tx_data = {16'h0002, i_local_mac[47:32]};
                end else if (word_cnt == 4) begin
                    o_tx_data = {i_local_mac[31:0], 16'h0000};
                end else if (word_cnt == 5) begin
                    o_tx_data = {16'h0000, i_local_mac[47:32]};
                end else if (word_cnt == 6) begin
                    o_tx_data = {i_local_mac[31:0], 16'h0000};
                end else if (word_cnt == 7) begin
                    o_tx_data = {arp_src_ip, 16'h0000};
                end else if (word_cnt == 8) begin
                    o_tx_data = {arp_src_mac[47:32], 16'h0000};
                end else if (word_cnt == 9) begin
                    o_tx_data = {arp_src_mac[31:0], ARP_OP_REPLY};
                end else begin
                    o_tx_data = 32'h0;
                end
            end
            default: begin
                o_tx_valid = 1'b0;
                o_tx_data = 32'h0;
            end
        endcase
    end

endmodule
