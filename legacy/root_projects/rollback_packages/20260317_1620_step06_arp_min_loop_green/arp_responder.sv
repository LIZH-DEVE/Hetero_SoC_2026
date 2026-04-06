`timescale 1ns / 1ps

module arp_responder (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] i_arp_data,
    input  logic        i_arp_valid,
    output logic        i_arp_ready,
    output logic [31:0] o_tx_data,
    output logic        o_tx_valid,
    input  logic        o_tx_ready,
    input  logic [47:0] i_local_mac,
    input  logic [31:0] i_local_ip,
    input  logic        i_arp_enable
);

    localparam [31:0] ARP_WORD0_REQUEST = 32'h0001_0800;
    localparam [31:0] ARP_WORD1_REQUEST = 32'h0604_0001;
    localparam [31:0] ARP_WORD0_REPLY   = 32'h0001_0800;
    localparam [31:0] ARP_WORD1_REPLY   = 32'h0604_0002;

    typedef enum logic [1:0] {
        IDLE,
        CAPTURE_REQ,
        CHECK_REQ,
        SEND_REPLY
    } state_t;

    state_t state;

    logic [31:0] req_word0;
    logic [31:0] req_word1;
    logic [31:0] req_word2;
    logic [31:0] req_word3;
    logic [31:0] req_src_ip;
    logic [31:0] req_dst_ip;
    logic [2:0]  req_word_cnt;
    logic [2:0]  tx_word_cnt;
    logic        request_matches;

    assign request_matches =
        i_arp_enable &&
        (req_word0 == ARP_WORD0_REQUEST) &&
        (req_word1 == ARP_WORD1_REQUEST) &&
        (req_dst_ip == i_local_ip);

    assign i_arp_ready = i_arp_enable && ((state == IDLE) || (state == CAPTURE_REQ));
    assign o_tx_valid  = (state == SEND_REPLY);

    always_comb begin
        case (tx_word_cnt)
            3'd0: o_tx_data = ARP_WORD0_REPLY;
            3'd1: o_tx_data = ARP_WORD1_REPLY;
            3'd2: o_tx_data = {i_local_mac[47:32], 16'h0000};
            3'd3: o_tx_data = i_local_mac[31:0];
            3'd4: o_tx_data = i_local_ip;
            3'd5: o_tx_data = req_src_ip;
            default: o_tx_data = 32'h0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            req_word0 <= 32'h0;
            req_word1 <= 32'h0;
            req_word2 <= 32'h0;
            req_word3 <= 32'h0;
            req_src_ip <= 32'h0;
            req_dst_ip <= 32'h0;
            req_word_cnt <= 3'd0;
            tx_word_cnt <= 3'd0;
        end else begin
            case (state)
                IDLE: begin
                    req_word_cnt <= 3'd0;
                    tx_word_cnt <= 3'd0;
                    if (i_arp_valid && i_arp_ready) begin
                        req_word0 <= i_arp_data;
                        req_word_cnt <= 3'd1;
                        state <= CAPTURE_REQ;
                    end
                end

                CAPTURE_REQ: begin
                    if (i_arp_valid && i_arp_ready) begin
                        case (req_word_cnt)
                            3'd1: req_word1 <= i_arp_data;
                            3'd2: req_word2 <= i_arp_data;
                            3'd3: req_word3 <= i_arp_data;
                            3'd4: req_src_ip <= i_arp_data;
                            3'd5: req_dst_ip <= i_arp_data;
                            default: ;
                        endcase

                        if (req_word_cnt == 3'd5) begin
                            req_word_cnt <= 3'd0;
                            state <= CHECK_REQ;
                        end else begin
                            req_word_cnt <= req_word_cnt + 1'b1;
                        end
                    end
                end

                CHECK_REQ: begin
                    tx_word_cnt <= 3'd0;
                    if (request_matches) begin
                        state <= SEND_REPLY;
                    end else begin
                        state <= IDLE;
                    end
                end

                SEND_REPLY: begin
                    if (o_tx_ready) begin
                        if (tx_word_cnt == 3'd5) begin
                            tx_word_cnt <= 3'd0;
                            state <= IDLE;
                        end else begin
                            tx_word_cnt <= tx_word_cnt + 1'b1;
                        end
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
