`timescale 1ns / 1ps

module tx_stack #(
    parameter logic [47:0] DEFAULT_LOCAL_MAC = 48'h00_0A_35_00_01_02,
    parameter logic [31:0] DEFAULT_LOCAL_IP  = 32'hC0_A8_01_0A
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        i_tx_start,
    input  logic [15:0] i_payload_len,
    input  logic [47:0] i_dst_mac,
    input  logic [31:0] i_dst_ip,
    input  logic [15:0] i_dst_port,
    input  logic [47:0] i_local_mac,
    input  logic [31:0] i_local_ip,

    output logic        o_tx_done,
    output logic        o_tx_busy,

    output logic [31:0] o_pbm_addr,
    output logic        o_pbm_ren,
    input  logic [31:0] i_pbm_rdata,

    output logic [31:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    output logic        m_axis_tlast,
    output logic [3:0]  m_axis_tkeep,
    input  logic        m_axis_tready
);

    localparam logic [15:0] ETH_TYPE = 16'h0800;
    localparam logic [15:0] IP_VER   = 16'h4500;
    localparam logic [15:0] IP_ID    = 16'h1234;
    localparam logic [15:0] IP_FLAG  = 16'h4000;
    localparam logic [7:0]  IP_TTL   = 8'h40;
    localparam logic [7:0]  IP_PROTO = 8'h11;
    localparam logic [15:0] UDP_SRC  = 16'h1234;

    typedef enum logic [3:0] {
        IDLE,
        CALC_CSUM,
        SEND_ETH_0,
        SEND_ETH_1,
        SEND_ETH_2,
        SEND_IP_0,
        SEND_IP_1,
        SEND_IP_2,
        SEND_IP_3,
        SEND_IP_4,
        SEND_IP_5,
        SEND_UDP_0,
        SEND_UDP_1,
        SEND_PAYLOAD,
        SEND_PAD,
        DONE
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
    logic [47:0] local_mac;
    logic [31:0] local_ip;

    assign local_mac = (i_local_mac == 48'd0) ? DEFAULT_LOCAL_MAC : i_local_mac;
    assign local_ip  = (i_local_ip == 32'd0) ? DEFAULT_LOCAL_IP : i_local_ip;
    assign udp_total_len = i_payload_len + 16'd8;
    assign ip_total_len  = i_payload_len + 16'd28;
    assign o_pbm_addr    = pbm_addr_ptr;

    always_comb begin
        csum_acc = 32'd0;
        csum_acc = csum_acc + {16'h0, IP_VER} + {16'h0, IP_ID} + {16'h0, IP_FLAG};
        csum_acc = csum_acc + {16'h0, IP_TTL, IP_PROTO};
        csum_acc = csum_acc + {16'h0, local_ip[31:16]} + {16'h0, local_ip[15:0]};
        csum_acc = csum_acc + {16'h0, i_dst_ip[31:16]} + {16'h0, i_dst_ip[15:0]};
        csum_acc = csum_acc + {16'h0, ip_total_len};
        csum_acc = csum_acc[31:16] + csum_acc[15:0];
        csum_acc = csum_acc[31:16] + csum_acc[15:0];
        ip_checksum = ~csum_acc[15:0];
    end

    always_comb begin
        o_pbm_ren = 1'b0;
        if (state == SEND_UDP_0 && m_axis_tready) begin
            o_pbm_ren = 1'b1;
        end
        if (state == SEND_UDP_1 && m_axis_tready) begin
            o_pbm_ren = 1'b1;
        end
        if (state == SEND_PAYLOAD && m_axis_tready && (payload_sent_cnt + 4 < i_payload_len)) begin
            o_pbm_ren = 1'b1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pbm_addr_ptr <= 32'd0;
        end else if (state == IDLE) begin
            pbm_addr_ptr <= 32'd0;
        end else if (o_pbm_ren) begin
            pbm_addr_ptr <= pbm_addr_ptr + 32'd4;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            payload_sent_cnt <= 16'd0;
            total_bytes_sent <= 16'd0;
            axis_leftover <= 16'd0;
            o_tx_done <= 1'b0;
            o_tx_busy <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    o_tx_done <= 1'b0;
                    if (i_tx_start) begin
                        state <= CALC_CSUM;
                        o_tx_busy <= 1'b1;
                    end
                end

                CALC_CSUM: begin
                    state <= SEND_ETH_0;
                    total_bytes_sent <= 16'd0;
                end

                SEND_ETH_0: if (m_axis_tready) begin state <= SEND_ETH_1; total_bytes_sent <= total_bytes_sent + 16'd4; end
                SEND_ETH_1: if (m_axis_tready) begin state <= SEND_ETH_2; total_bytes_sent <= total_bytes_sent + 16'd4; end
                SEND_ETH_2: if (m_axis_tready) begin state <= SEND_IP_0;  total_bytes_sent <= total_bytes_sent + 16'd4; end

                SEND_IP_0: if (m_axis_tready) begin state <= SEND_IP_1; total_bytes_sent <= total_bytes_sent + 16'd4; end
                SEND_IP_1: if (m_axis_tready) begin state <= SEND_IP_2; total_bytes_sent <= total_bytes_sent + 16'd4; end
                SEND_IP_2: if (m_axis_tready) begin state <= SEND_IP_3; total_bytes_sent <= total_bytes_sent + 16'd4; end
                SEND_IP_3: if (m_axis_tready) begin state <= SEND_IP_4; total_bytes_sent <= total_bytes_sent + 16'd4; end
                SEND_IP_4: if (m_axis_tready) begin state <= SEND_IP_5; total_bytes_sent <= total_bytes_sent + 16'd4; end
                SEND_IP_5: if (m_axis_tready) begin state <= SEND_UDP_0; total_bytes_sent <= total_bytes_sent + 16'd4; end

                SEND_UDP_0: if (m_axis_tready) begin
                    state <= SEND_UDP_1;
                    total_bytes_sent <= total_bytes_sent + 16'd4;
                end

                SEND_UDP_1: if (m_axis_tready) begin
                    axis_leftover <= i_pbm_rdata[15:0];
                    if (i_payload_len <= 16'd2) begin
                        payload_sent_cnt <= i_payload_len;
                        total_bytes_sent <= total_bytes_sent + i_payload_len;
                        state <= SEND_PAD;
                    end else begin
                        payload_sent_cnt <= 16'd2;
                        total_bytes_sent <= total_bytes_sent + 16'd4;
                        state <= SEND_PAYLOAD;
                    end
                end

                SEND_PAYLOAD: if (m_axis_tready) begin
                    logic [15:0] remaining;
                    axis_leftover <= i_pbm_rdata[15:0];
                    if (payload_sent_cnt + 16'd4 >= i_payload_len) begin
                        remaining = i_payload_len - payload_sent_cnt;
                        total_bytes_sent <= total_bytes_sent + remaining;
                        state <= SEND_PAD;
                    end else begin
                        payload_sent_cnt <= payload_sent_cnt + 16'd4;
                        total_bytes_sent <= total_bytes_sent + 16'd4;
                    end
                end

                SEND_PAD: if (m_axis_tready) begin
                    if (total_bytes_sent >= 16'd60) begin
                        state <= DONE;
                    end else begin
                        total_bytes_sent <= total_bytes_sent + 16'd4;
                    end
                end

                DONE: begin
                    o_tx_done <= 1'b1;
                    o_tx_busy <= 1'b0;
                    if (!i_tx_start) begin
                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    always_comb begin
        logic [15:0] rem_bytes;

        m_axis_tdata  = 32'h0;
        m_axis_tvalid = 1'b0;
        m_axis_tlast  = 1'b0;
        m_axis_tkeep  = 4'hF;
        rem_bytes = i_payload_len - payload_sent_cnt;

        case (state)
            SEND_ETH_0: begin m_axis_tvalid = 1'b1; m_axis_tdata = i_dst_mac[47:16]; end
            SEND_ETH_1: begin m_axis_tvalid = 1'b1; m_axis_tdata = {i_dst_mac[15:0], local_mac[47:32]}; end
            SEND_ETH_2: begin m_axis_tvalid = 1'b1; m_axis_tdata = local_mac[31:0]; end

            SEND_IP_0:  begin m_axis_tvalid = 1'b1; m_axis_tdata = {ETH_TYPE, IP_VER}; end
            SEND_IP_1:  begin m_axis_tvalid = 1'b1; m_axis_tdata = {ip_total_len, IP_ID}; end
            SEND_IP_2:  begin m_axis_tvalid = 1'b1; m_axis_tdata = {IP_FLAG, IP_TTL, IP_PROTO}; end
            SEND_IP_3:  begin m_axis_tvalid = 1'b1; m_axis_tdata = {ip_checksum, local_ip[31:16]}; end
            SEND_IP_4:  begin m_axis_tvalid = 1'b1; m_axis_tdata = {local_ip[15:0], i_dst_ip[31:16]}; end
            SEND_IP_5:  begin m_axis_tvalid = 1'b1; m_axis_tdata = {i_dst_ip[15:0], UDP_SRC}; end
            SEND_UDP_0: begin m_axis_tvalid = 1'b1; m_axis_tdata = {i_dst_port, udp_total_len}; end

            SEND_UDP_1: begin
                m_axis_tvalid = 1'b1;
                m_axis_tdata = {16'h0000, i_pbm_rdata[31:16]};
                if (i_payload_len <= 16'd2 && total_bytes_sent + i_payload_len >= 16'd60) begin
                    m_axis_tlast = 1'b1;
                    if (i_payload_len == 16'd1) begin
                        m_axis_tkeep = 4'b1110;
                    end
                end
            end

            SEND_PAYLOAD: begin
                m_axis_tvalid = 1'b1;
                m_axis_tdata = {axis_leftover, i_pbm_rdata[31:16]};
                if (payload_sent_cnt + 16'd4 >= i_payload_len && total_bytes_sent + rem_bytes >= 16'd60) begin
                    m_axis_tlast = 1'b1;
                    case (rem_bytes)
                        16'd1: m_axis_tkeep = 4'b1000;
                        16'd2: m_axis_tkeep = 4'b1100;
                        16'd3: m_axis_tkeep = 4'b1110;
                        default: m_axis_tkeep = 4'b1111;
                    endcase
                end
            end

            SEND_PAD: begin
                m_axis_tvalid = 1'b1;
                m_axis_tdata  = 32'h0;
                if (total_bytes_sent >= 16'd60) begin
                    m_axis_tlast = 1'b1;
                end
            end

            default: begin
                m_axis_tdata  = 32'h0;
                m_axis_tvalid = 1'b0;
                m_axis_tlast  = 1'b0;
                m_axis_tkeep  = 4'hF;
            end
        endcase
    end

endmodule
