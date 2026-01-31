`timescale 1ns / 1ps

module rx_parser #(
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
    
    // [Day 10 新增] Info Extraction Interface (提取发送者信息)
    output logic [47:0]            o_rec_src_mac,  // 抓到的源 MAC
    output logic [31:0]            o_rec_src_ip,   // 抓到的源 IP
    output logic [15:0]            o_rec_src_port, // 抓到的源 Port (UDP)
    output logic                   o_rec_valid,    // 抓取有效标志

    // ARP Interface (保留)
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
    
    assign payload_len = udp_len - 16'd8;
    assign ip_header_bytes = ihl * 4;
    assign malformed_check = (udp_len > (ip_total_len - ip_header_bytes));
    
    assign o_meta_data  = payload_len;
    assign o_meta_valid = s_axis_tlast && (state == PAYLOAD) && !s_axis_tuser && 
                           (payload_len[3:0] == 4'h0) && !malformed_check;
    
    // Info Output
    assign o_rec_src_mac  = src_mac_reg;
    assign o_rec_src_ip   = src_ip_reg;
    assign o_rec_src_port = src_port_reg;
    // 只有当包完整结束且合法时，才通知 TX 更新目标地址
    assign o_rec_valid    = s_axis_tlast && (state == PAYLOAD) && !s_axis_tuser;

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
                        // 注意：这里其实还在 IP 尾部，但紧接着是 UDP
                        if (global_word_cnt == 9) src_port_reg <= s_axis_tdata[15:0];
                        
                        // Word 10: UDP DstPort, UDP Len
                        if (global_word_cnt == 10) begin
                            udp_len <= s_axis_tdata[15:0];
                            // [Day 2 Patch] Alignment check: payload must be 16-byte aligned
                            if (((s_axis_tdata[15:0] - 16'd8) & 16'h000F) != 16'd0)
                                state <= DROP;
                            else if (malformed_check)
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

    // ARP Logic (Dummy for now)
    assign o_arp_valid = 0;
    assign o_arp_data = 0;

endmodule