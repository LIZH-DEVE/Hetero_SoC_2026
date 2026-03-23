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
    output logic [47:0] o_reply_dst_mac,
    input  logic [47:0] i_local_mac,
    input  logic [31:0] i_local_ip,
    input  logic        i_arp_enable
);

    localparam [31:0] ARP_WORD0_REQUEST = 32'h0001_0800;
    localparam [31:0] ARP_WORD1_REQUEST = 32'h0604_0001;
    localparam [31:0] ARP_WORD0_REPLY   = 32'h0001_0800;
    localparam [31:0] ARP_WORD1_REPLY   = 32'h0604_0002;
    localparam [2:0]  REPLY_LAST_WORD   = 3'd6;

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
    logic [31:0] tx_data_reg;
    logic        tx_valid_reg;
    logic        request_matches;

    assign request_matches =
        i_arp_enable &&
        (req_word0 == ARP_WORD0_REQUEST) &&
        (req_word1 == ARP_WORD1_REQUEST) &&
        (req_dst_ip == i_local_ip);

    assign i_arp_ready = i_arp_enable && ((state == IDLE) || (state == CAPTURE_REQ));
    assign o_tx_valid = tx_valid_reg;
    assign o_reply_dst_mac = {req_word2[31:16], req_word3};

    function automatic logic [31:0] reply_word(input logic [2:0] word_idx);
        begin
            case (word_idx)
                3'd0: reply_word = ARP_WORD0_REPLY;
                3'd1: reply_word = ARP_WORD1_REPLY;
                3'd2: reply_word = i_local_mac[47:16];
                3'd3: reply_word = {i_local_mac[15:0], i_local_ip[31:16]};
                3'd4: reply_word = {i_local_ip[15:0], req_word2[31:16]};
                3'd5: reply_word = req_word3;
                3'd6: reply_word = req_src_ip;
                default: reply_word = 32'h0;
            endcase
        end
    endfunction

    assign o_tx_data = tx_data_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            req_word0 <= 32'd0;
            req_word1 <= 32'd0;
            req_word2 <= 32'd0;
            req_word3 <= 32'd0;
            req_src_ip <= 32'd0;
            req_dst_ip <= 32'd0;
            req_word_cnt <= 3'd0;
            tx_word_cnt <= 3'd0;
            tx_data_reg <= 32'd0;
            tx_valid_reg <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    req_word_cnt <= 3'd0;
                    tx_word_cnt <= 3'd0;
                    tx_data_reg <= 32'd0;
                    tx_valid_reg <= 1'b0;
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
                            req_word_cnt <= req_word_cnt + 3'd1;
                        end
                    end
                end

                CHECK_REQ: begin
                    tx_word_cnt <= 3'd0;
                    if (request_matches) begin
                        tx_data_reg <= reply_word(3'd0);
                        tx_valid_reg <= 1'b1;
                        state <= SEND_REPLY;
                    end else begin
                        tx_data_reg <= 32'd0;
                        tx_valid_reg <= 1'b0;
                        state <= IDLE;
                    end
                end

                SEND_REPLY: begin
                    if (tx_valid_reg && o_tx_ready) begin
                        if (tx_word_cnt == REPLY_LAST_WORD) begin
                            tx_word_cnt <= 3'd0;
                            tx_data_reg <= 32'd0;
                            tx_valid_reg <= 1'b0;
                            state <= IDLE;
                        end else begin
                            tx_word_cnt <= tx_word_cnt + 3'd1;
                            tx_data_reg <= reply_word(tx_word_cnt + 3'd1);
                        end
                    end
                end

                default: begin
                    state <= IDLE;
                    tx_data_reg <= 32'd0;
                    tx_valid_reg <= 1'b0;
                end
            endcase
        end
    end

endmodule
