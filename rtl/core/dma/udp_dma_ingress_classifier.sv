`timescale 1ns / 1ps

module udp_dma_ingress_classifier #(
    parameter integer DATA_WIDTH = 32
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic [DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                  s_axis_tvalid,
    input  logic                  s_axis_tlast,
    output logic                  s_axis_tready,

    output logic [DATA_WIDTH-1:0] m_axis_dma_tdata,
    output logic                  m_axis_dma_tvalid,
    output logic                  m_axis_dma_tlast,
    output logic                  m_axis_dma_terror,
    output logic                  m_axis_dma_pkt_start,
    output logic                  m_axis_dma_pkt_end,
    output logic                  m_axis_dma_cbc_mode,
    output logic [127:0]          m_axis_dma_iv_header,
    input  logic                  m_axis_dma_tready,

    output logic [31:0]           o_drop_wrong_port_count,
    output logic [31:0]           o_drop_unaligned_count,
    output logic [31:0]           o_drop_cbc_length_invalid_count,
    output logic                  o_dma_idle
);

    localparam logic [15:0] UDP_PORT_AES = 16'd4660;
    localparam logic [15:0] UDP_PORT_SM4 = 16'd4661;
    localparam logic [15:0] ETHERTYPE_IPV4 = 16'h0800;

    localparam int WORD_IDX_ETHERTYPE = 3;
    localparam int WORD_IDX_UDP_PORTS = 9;
    localparam int WORD_IDX_UDP_META = 10;

    typedef enum logic [1:0] {
        STATE_IDLE    = 2'd0,
        STATE_PARSE   = 2'd1,
        STATE_PAYLOAD = 2'd2,
        STATE_DROP    = 2'd3
    } classifier_state_t;

    classifier_state_t state_q;
    logic [15:0] word_index_q;
    logic        ipv4_seen_q;
    logic        accept_frame_q;
    logic        drop_wrong_port_frame_q;
    logic        drop_unaligned_frame_q;
    logic [15:0] udp_dst_port_q;
    logic [15:0] payload_bytes_remaining_q;
    logic [15:0] payload_word_index_q;
    logic [15:0] udp_payload_bytes_now;
    logic        length_error_q;
    logic        length_error_now;
    logic        cbc_length_invalid_now;
    logic        cbc_mode_q;
    logic [127:0] iv_header_q;

    logic stream_fire;

    // wrong-port frames must never drive DMA tvalid
    // unaligned frames must never drive DMA tvalid
    // every rejected frame must be consumed to TLAST before returning to idle
    // CBC payload requires a 16-byte IV plus 16-byte aligned data
    // CBC readiness metadata must not alter current shadow datapath admission
    // until the downstream bridge exposes explicit packet-atomic CBC mode.
    assign s_axis_tready  = (state_q == STATE_PAYLOAD) ? m_axis_dma_tready : 1'b1;
    assign stream_fire    = s_axis_tvalid && s_axis_tready;
    assign m_axis_dma_tdata  = s_axis_tdata;
    assign m_axis_dma_tvalid = s_axis_tvalid && accept_frame_q && (state_q == STATE_PAYLOAD);
    assign m_axis_dma_tlast  = s_axis_tlast;
    assign m_axis_dma_pkt_start = m_axis_dma_tvalid && (payload_word_index_q == 16'd0);
    assign m_axis_dma_pkt_end = m_axis_dma_tvalid && s_axis_tlast;
    assign m_axis_dma_cbc_mode = m_axis_dma_tvalid && cbc_mode_q;
    assign m_axis_dma_iv_header = iv_header_q;
    assign udp_payload_bytes_now = (s_axis_tdata[15:0] >= 16'd8) ? (s_axis_tdata[15:0] - 16'd8) : 16'd0;
    assign length_error_now = (state_q == STATE_PAYLOAD) && accept_frame_q &&
        (((payload_bytes_remaining_q > 16'd4) && s_axis_tlast) ||
         ((payload_bytes_remaining_q <= 16'd4) && (payload_bytes_remaining_q != 16'd0) && !s_axis_tlast) ||
         (payload_bytes_remaining_q == 16'd0));
    assign cbc_length_invalid_now = (udp_payload_bytes_now < 16'd32) ||
        (((udp_payload_bytes_now - 16'd16) & 16'h000F) != 16'd0);
    assign m_axis_dma_terror = s_axis_tvalid && accept_frame_q && (state_q == STATE_PAYLOAD) && s_axis_tlast && (length_error_q || length_error_now);
    assign o_dma_idle = !m_axis_dma_tvalid;

    // Keep ingress classification state/control synchronous so downstream DMA
    // RAM enable/control paths are not driven from async-reset flops.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q <= STATE_IDLE;
            word_index_q <= 16'd0;
            ipv4_seen_q <= 1'b0;
            accept_frame_q <= 1'b0;
            drop_wrong_port_frame_q <= 1'b0;
            drop_unaligned_frame_q <= 1'b0;
            udp_dst_port_q <= 16'd0;
            payload_bytes_remaining_q <= 16'd0;
            payload_word_index_q <= 16'd0;
            length_error_q <= 1'b0;
            cbc_mode_q <= 1'b0;
            iv_header_q <= 128'd0;
            o_drop_wrong_port_count <= 32'd0;
            o_drop_unaligned_count <= 32'd0;
            o_drop_cbc_length_invalid_count <= 32'd0;
        end else if (stream_fire) begin
            case (state_q)
                STATE_IDLE: begin
                    state_q <= s_axis_tlast ? STATE_IDLE : STATE_PARSE;
                    word_index_q <= 16'd1;
                    ipv4_seen_q <= 1'b0;
                    accept_frame_q <= 1'b0;
                    drop_wrong_port_frame_q <= 1'b0;
                    drop_unaligned_frame_q <= 1'b0;
                    udp_dst_port_q <= 16'd0;
                    payload_bytes_remaining_q <= 16'd0;
                    payload_word_index_q <= 16'd0;
                    length_error_q <= 1'b0;
                    cbc_mode_q <= 1'b0;
                    iv_header_q <= 128'd0;
                end

                STATE_PARSE: begin
                    if (word_index_q == WORD_IDX_ETHERTYPE[15:0]) begin
                        ipv4_seen_q <= (s_axis_tdata[31:16] == ETHERTYPE_IPV4);
                    end

                    if (word_index_q == WORD_IDX_UDP_PORTS[15:0]) begin
                        udp_dst_port_q <= s_axis_tdata[31:16];
                    end

                    if (word_index_q == WORD_IDX_UDP_META[15:0]) begin
                        if (!ipv4_seen_q ||
                            ((udp_dst_port_q != UDP_PORT_AES) && (udp_dst_port_q != UDP_PORT_SM4))) begin
                            state_q <= STATE_DROP;
                            drop_wrong_port_frame_q <= 1'b1;
                        end else if ((udp_payload_bytes_now & 16'h0003) != 16'd0) begin
                            state_q <= STATE_DROP;
                            drop_unaligned_frame_q <= 1'b1;
                        end else begin
                            state_q <= STATE_PAYLOAD;
                            accept_frame_q <= 1'b1;
                            payload_bytes_remaining_q <= udp_payload_bytes_now;
                            payload_word_index_q <= 16'd0;
                            length_error_q <= 1'b0;
                            cbc_mode_q <= !cbc_length_invalid_now;
                            iv_header_q <= 128'd0;
                        end
                    end

                    if (s_axis_tlast) begin
                        state_q <= STATE_IDLE;
                        word_index_q <= 16'd0;
                        ipv4_seen_q <= 1'b0;
                        accept_frame_q <= 1'b0;
                        drop_wrong_port_frame_q <= 1'b0;
                        drop_unaligned_frame_q <= 1'b0;
                        payload_bytes_remaining_q <= 16'd0;
                        payload_word_index_q <= 16'd0;
                        length_error_q <= 1'b0;
                        cbc_mode_q <= 1'b0;
                        iv_header_q <= 128'd0;
                    end else begin
                        word_index_q <= word_index_q + 16'd1;
                    end
                end

                STATE_PAYLOAD: begin
                    if (length_error_now) begin
                        length_error_q <= 1'b1;
                    end
                    if (payload_word_index_q < 16'd4) begin
                        iv_header_q <= {iv_header_q[95:0], s_axis_tdata};
                    end
                    if (payload_bytes_remaining_q > 16'd4) begin
                        payload_bytes_remaining_q <= payload_bytes_remaining_q - 16'd4;
                    end else begin
                        payload_bytes_remaining_q <= 16'd0;
                    end
                    if (s_axis_tlast) begin
                        state_q <= STATE_IDLE;
                        word_index_q <= 16'd0;
                        ipv4_seen_q <= 1'b0;
                        accept_frame_q <= 1'b0;
                        drop_wrong_port_frame_q <= 1'b0;
                        drop_unaligned_frame_q <= 1'b0;
                        payload_bytes_remaining_q <= 16'd0;
                        payload_word_index_q <= 16'd0;
                        length_error_q <= 1'b0;
                        cbc_mode_q <= 1'b0;
                    end else begin
                        word_index_q <= word_index_q + 16'd1;
                        payload_word_index_q <= payload_word_index_q + 16'd1;
                    end
                end

                STATE_DROP: begin
                    if (s_axis_tlast) begin
                        if (drop_wrong_port_frame_q) begin
                            o_drop_wrong_port_count <= o_drop_wrong_port_count + 32'd1;
                        end
                        if (drop_unaligned_frame_q) begin
                            o_drop_unaligned_count <= o_drop_unaligned_count + 32'd1;
                        end
                        state_q <= STATE_IDLE;
                        word_index_q <= 16'd0;
                        ipv4_seen_q <= 1'b0;
                        accept_frame_q <= 1'b0;
                        drop_wrong_port_frame_q <= 1'b0;
                        drop_unaligned_frame_q <= 1'b0;
                        payload_bytes_remaining_q <= 16'd0;
                        payload_word_index_q <= 16'd0;
                        length_error_q <= 1'b0;
                        cbc_mode_q <= 1'b0;
                        iv_header_q <= 128'd0;
                    end else begin
                        word_index_q <= word_index_q + 16'd1;
                    end
                end

                default: begin
                    state_q <= STATE_IDLE;
                    word_index_q <= 16'd0;
                    ipv4_seen_q <= 1'b0;
                    accept_frame_q <= 1'b0;
                    drop_wrong_port_frame_q <= 1'b0;
                    drop_unaligned_frame_q <= 1'b0;
                    payload_bytes_remaining_q <= 16'd0;
                    payload_word_index_q <= 16'd0;
                    length_error_q <= 1'b0;
                    cbc_mode_q <= 1'b0;
                    iv_header_q <= 128'd0;
                end
            endcase
        end
    end

endmodule
