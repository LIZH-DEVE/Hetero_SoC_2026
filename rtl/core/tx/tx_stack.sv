`timescale 1ns / 1ps

module tx_stack #(
    // 本机参数可以是静态的，但目标参数必须动态
    parameter logic [47:0] LOCAL_MAC = 48'h00_0A_35_00_01_02,
    parameter logic [31:0] LOCAL_IP  = 32'hC0_A8_01_0A  // 192.168.1.10
)(
    input  logic        clk,
    input  logic        rst_n,

    // --- Control Interface ---
    input  logic        i_tx_start,
    input  logic [15:0] i_payload_len,
    
    // [Day 10 Perfect] 动态目标信息接口
    input  logic [47:0] i_dst_mac,
    input  logic [31:0] i_dst_ip,
    input  logic [15:0] i_dst_port,

    output logic        o_tx_done,
    output logic        o_tx_busy,

    // --- PBM Read Interface ---
    output logic [31:0] o_pbm_addr,
    output logic        o_pbm_ren,
    input  logic [31:0] i_pbm_rdata,

    // --- AXI-Stream TX Interface ---
    output logic [31:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    output logic        m_axis_tlast,
    output logic [3:0]  m_axis_tkeep,
    input  logic        m_axis_tready
);

    // =========================================================
    // 1. 常量与动态计算
    // =========================================================
    localparam logic [15:0] ETH_TYPE = 16'h0800;
    localparam logic [15:0] IP_VER   = 16'h4500;
    localparam logic [15:0] IP_ID    = 16'h1234;
    localparam logic [15:0] IP_FLAG  = 16'h4000;
    localparam logic [7:0]  IP_TTL   = 8'h40;
    localparam logic [7:0]  IP_PROTO = 8'h11; // UDP
    localparam logic [15:0] UDP_SRC  = 16'h1234; // FPGA Port

    // 状态机
    typedef enum logic [3:0] {
        IDLE, CALC_CSUM,
        SEND_ETH_0, SEND_ETH_1, SEND_ETH_2,
        SEND_IP_0,  SEND_IP_1,  SEND_IP_2, SEND_IP_3, SEND_IP_4, SEND_IP_5,
        SEND_UDP_0, SEND_UDP_1,
        SEND_PAYLOAD, SEND_PAD, DONE
    } state_t;
    state_t state;

    logic [15:0] ip_total_len;
    logic [15:0] udp_total_len;
    logic [15:0] ip_checksum;
    logic [31:0] csum_acc;
    
    logic [15:0] payload_sent_cnt;
    logic [15:0] total_bytes_sent;
    logic [15:0] axis_leftover; 
    logic [31:0] pbm_addr_ptr;

    assign udp_total_len = i_payload_len + 16'd8;
    assign ip_total_len  = i_payload_len + 16'd28;
    assign o_pbm_addr = pbm_addr_ptr;

    // =========================================================
    // 2. [Perfect] 完全动态 Checksum 计算逻辑
    // =========================================================
    // 算法: 把所有 16-bit 头部字段相加，然后取反
    // 为了时序收敛，我们还是用组合逻辑，但公式变了
    always_comb begin
        csum_acc = 32'd0;
        // 固定部分
        csum_acc = csum_acc + {16'h0, IP_VER} + {16'h0, IP_ID} + {16'h0, IP_FLAG};
        csum_acc = csum_acc + {16'h0, IP_TTL, IP_PROTO};
        csum_acc = csum_acc + {16'h0, LOCAL_IP[31:16]} + {16'h0, LOCAL_IP[15:0]};
        // 动态部分 (来自输入)
        csum_acc = csum_acc + {16'h0, i_dst_ip[31:16]} + {16'h0, i_dst_ip[15:0]};
        csum_acc = csum_acc + {16'h0, ip_total_len}; // 长度也是动态的

        // 进位折叠 (Folding)
        csum_acc = (csum_acc[31:16] + csum_acc[15:0]);
        csum_acc = (csum_acc[31:16] + csum_acc[15:0]);
        
        ip_checksum = ~csum_acc[15:0];
    end

    // =========================================================
    // 3. PBM 控制 (保持不变，已验证)
    // =========================================================
    always_comb begin
        o_pbm_ren = 0;
        if (state == SEND_UDP_0 && m_axis_tready) o_pbm_ren = 1;
        if (state == SEND_UDP_1 && m_axis_tready) o_pbm_ren = 1; 
        if (state == SEND_PAYLOAD && m_axis_tready && (payload_sent_cnt + 4 < i_payload_len)) o_pbm_ren = 1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pbm_addr_ptr <= 0;
        else if (state == IDLE) pbm_addr_ptr <= 0;
        else if (o_pbm_ren) pbm_addr_ptr <= pbm_addr_ptr + 4;
    end

    // =========================================================
    // 4. 主状态机
    // =========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            payload_sent_cnt <= 0;
            total_bytes_sent <= 0;
            axis_leftover <= 0;
            o_tx_done <= 0;
            o_tx_busy <= 0;
        end else begin
            case (state)
                IDLE: begin
                    o_tx_done <= 0;
                    if (i_tx_start) begin
                        state <= CALC_CSUM;
                        o_tx_busy <= 1;
                    end
                end

                CALC_CSUM: begin
                    state <= SEND_ETH_0;
                    total_bytes_sent <= 0;
                end

                // --- Ethernet Header (使用 i_dst_mac) ---
                SEND_ETH_0: if (m_axis_tready) begin state <= SEND_ETH_1; total_bytes_sent <= total_bytes_sent + 4; end
                SEND_ETH_1: if (m_axis_tready) begin state <= SEND_ETH_2; total_bytes_sent <= total_bytes_sent + 4; end
                SEND_ETH_2: if (m_axis_tready) begin state <= SEND_IP_0;  total_bytes_sent <= total_bytes_sent + 4; end

                // --- IP Header ---
                SEND_IP_0: if (m_axis_tready) begin state <= SEND_IP_1; total_bytes_sent <= total_bytes_sent + 4; end
                SEND_IP_1: if (m_axis_tready) begin state <= SEND_IP_2; total_bytes_sent <= total_bytes_sent + 4; end
                SEND_IP_2: if (m_axis_tready) begin state <= SEND_IP_3; total_bytes_sent <= total_bytes_sent + 4; end
                SEND_IP_3: if (m_axis_tready) begin state <= SEND_IP_4; total_bytes_sent <= total_bytes_sent + 4; end
                SEND_IP_4: if (m_axis_tready) begin state <= SEND_IP_5; total_bytes_sent <= total_bytes_sent + 4; end
                
                // --- UDP Header ---
                SEND_IP_5: if (m_axis_tready) begin state <= SEND_UDP_0; total_bytes_sent <= total_bytes_sent + 4; end
                
                SEND_UDP_0: if (m_axis_tready) begin 
                    state <= SEND_UDP_1; 
                    total_bytes_sent <= total_bytes_sent + 4; 
                end

                SEND_UDP_1: if (m_axis_tready) begin
                    axis_leftover <= i_pbm_rdata[15:0]; 
                    if (i_payload_len <= 2) begin
                        payload_sent_cnt <= i_payload_len;
                        total_bytes_sent <= total_bytes_sent + i_payload_len;
                        state <= SEND_PAD;
                    end else begin
                        payload_sent_cnt <= 2;
                        total_bytes_sent <= total_bytes_sent + 4;
                        state <= SEND_PAYLOAD;
                    end
                end

                SEND_PAYLOAD: if (m_axis_tready) begin
                    axis_leftover <= i_pbm_rdata[15:0];
                    if (payload_sent_cnt + 4 >= i_payload_len) begin
                        logic [15:0] remaining;
                        remaining = i_payload_len - payload_sent_cnt;
                        total_bytes_sent <= total_bytes_sent + remaining;
                        state <= SEND_PAD;
                    end else begin
                        payload_sent_cnt <= payload_sent_cnt + 4;
                        total_bytes_sent <= total_bytes_sent + 4;
                    end
                end

                SEND_PAD: if (m_axis_tready) begin
                    if (total_bytes_sent >= 60) state <= DONE;
                    else total_bytes_sent <= total_bytes_sent + 4;
                end

                DONE: begin
                    o_tx_done <= 1;
                    o_tx_busy <= 0;
                    if (!i_tx_start) state <= IDLE;
                end
            endcase
        end
    end

    // =========================================================
    // 5. Output Mux (使用动态 i_dst_xx)
    // =========================================================
    always_comb begin
        m_axis_tdata  = 32'h0;
        m_axis_tvalid = 0;
        m_axis_tlast  = 0;
        m_axis_tkeep  = 4'hF; 

        case (state)
            // Eth: Dest MAC = i_dst_mac
            SEND_ETH_0: begin m_axis_tvalid=1; m_axis_tdata = {i_dst_mac[47:16]}; end
            SEND_ETH_1: begin m_axis_tvalid=1; m_axis_tdata = {i_dst_mac[15:0], LOCAL_MAC[47:32]}; end
            SEND_ETH_2: begin m_axis_tvalid=1; m_axis_tdata = {LOCAL_MAC[31:0]}; end

            // IP: Src=Local, Dst=i_dst_ip
            SEND_IP_0:  begin m_axis_tvalid=1; m_axis_tdata = {ETH_TYPE, IP_VER}; end
            SEND_IP_1:  begin m_axis_tvalid=1; m_axis_tdata = {ip_total_len, IP_ID}; end
            SEND_IP_2:  begin m_axis_tvalid=1; m_axis_tdata = {IP_FLAG, IP_TTL, IP_PROTO}; end
            SEND_IP_3:  begin m_axis_tvalid=1; m_axis_tdata = {ip_checksum, LOCAL_IP[31:16]}; end
            SEND_IP_4:  begin m_axis_tvalid=1; m_axis_tdata = {LOCAL_IP[15:0], i_dst_ip[31:16]}; end
            
            // UDP: Dst=i_dst_port
            SEND_IP_5:  begin m_axis_tvalid=1; m_axis_tdata = {i_dst_ip[15:0], UDP_SRC}; end
            SEND_UDP_0: begin m_axis_tvalid=1; m_axis_tdata = {i_dst_port, udp_total_len}; end
            
            // 下面的逻辑与之前一致 (Stitching)
            SEND_UDP_1: begin
                m_axis_tvalid = 1;
                m_axis_tdata = {16'h0000, i_pbm_rdata[31:16]};
                if (i_payload_len <= 2 && total_bytes_sent + i_payload_len >= 60) begin
                    m_axis_tlast = 1;
                    if (i_payload_len == 1) m_axis_tkeep = 4'b1110;
                end
            end

            SEND_PAYLOAD: begin
                m_axis_tvalid = 1;
                m_axis_tdata = {axis_leftover, i_pbm_rdata[31:16]};
                if (payload_sent_cnt + 4 >= i_payload_len) begin
                    logic [15:0] rem_bytes;
                    rem_bytes = i_payload_len - payload_sent_cnt;
                    if (total_bytes_sent + rem_bytes >= 60) begin
                        m_axis_tlast = 1;
                        case (rem_bytes)
                            1: m_axis_tkeep = 4'b1000;
                            2: m_axis_tkeep = 4'b1100;
                            3: m_axis_tkeep = 4'b1110;
                            4: m_axis_tkeep = 4'b1111;
                        endcase
                    end
                end
            end

            SEND_PAD: begin
                m_axis_tvalid = 1;
                m_axis_tdata  = 32'h0;
                if (total_bytes_sent >= 60) begin
                    m_axis_tlast = 1;
                    m_axis_tkeep = 4'b1111; 
                end
            end
        endcase
    end

endmodule