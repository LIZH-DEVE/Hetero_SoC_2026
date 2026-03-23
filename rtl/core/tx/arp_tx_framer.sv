`timescale 1ns / 1ps

module arp_tx_framer (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] i_body_data,
    input  logic        i_body_valid,
    output logic        i_body_ready,
    input  logic [47:0] i_dst_mac,
    input  logic [47:0] i_src_mac,
    output logic [31:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    output logic        m_axis_tlast,
    output logic [3:0]  m_axis_tkeep,
    input  logic        m_axis_tready
);

    localparam int BODY_WORDS  = 7;
    localparam int FRAME_WORDS = 11;

    typedef enum logic [1:0] {
        CAPTURE_BODY,
        PREP_FRAME,
        SEND_FRAME
    } state_t;

    state_t state;
    logic [31:0] body_words [0:BODY_WORDS-1];
    logic [2:0]  body_count;
    logic [3:0]  send_idx;
    logic [47:0] dst_mac_reg;
    logic [47:0] src_mac_reg;
    logic [31:0] tx_data_reg;
    logic        tx_valid_reg;

    function automatic logic [31:0] frame_word(
        input logic [3:0]  idx,
        input logic [47:0] dst_mac,
        input logic [47:0] src_mac
    );
        begin
            case (idx)
                4'd0: frame_word = dst_mac[47:16];
                4'd1: frame_word = {dst_mac[15:0], src_mac[47:32]};
                4'd2: frame_word = src_mac[31:0];
                4'd3: frame_word = 32'h0806_0000;
                4'd4: frame_word = body_words[0];
                4'd5: frame_word = body_words[1];
                4'd6: frame_word = body_words[2];
                4'd7: frame_word = body_words[3];
                4'd8: frame_word = body_words[4];
                4'd9: frame_word = body_words[5];
                4'd10: frame_word = body_words[6];
                default: frame_word = 32'h0;
            endcase
        end
    endfunction

    assign i_body_ready = (state == CAPTURE_BODY);
    assign m_axis_tdata = tx_data_reg;
    assign m_axis_tvalid = tx_valid_reg;
    assign m_axis_tlast = (state == SEND_FRAME) && tx_valid_reg && (send_idx == FRAME_WORDS-1);
    assign m_axis_tkeep = 4'hF;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= CAPTURE_BODY;
            body_count <= '0;
            send_idx <= '0;
            dst_mac_reg <= '0;
            src_mac_reg <= '0;
            tx_data_reg <= '0;
            tx_valid_reg <= 1'b0;
        end else begin
            case (state)
                CAPTURE_BODY: begin
                    send_idx <= '0;
                    tx_valid_reg <= 1'b0;
                    tx_data_reg <= 32'd0;
                    if (i_body_valid && i_body_ready) begin
                        body_words[body_count] <= i_body_data;
                        if (body_count == BODY_WORDS-1) begin
                            dst_mac_reg <= i_dst_mac;
                            src_mac_reg <= i_src_mac;
                            body_count <= '0;
                            state <= PREP_FRAME;
                        end else begin
                            body_count <= body_count + 3'd1;
                        end
                    end
                end

                PREP_FRAME: begin
                    send_idx <= 4'd0;
                    tx_data_reg <= frame_word(4'd0, dst_mac_reg, src_mac_reg);
                    tx_valid_reg <= 1'b1;
                    state <= SEND_FRAME;
                end

                SEND_FRAME: begin
                    if (tx_valid_reg && m_axis_tready) begin
                        if (send_idx == FRAME_WORDS-1) begin
                            send_idx <= '0;
                            tx_data_reg <= 32'd0;
                            tx_valid_reg <= 1'b0;
                            state <= CAPTURE_BODY;
                        end else begin
                            send_idx <= send_idx + 4'd1;
                            tx_data_reg <= frame_word(send_idx + 4'd1, dst_mac_reg, src_mac_reg);
                        end
                    end
                end

                default: begin
                    state <= CAPTURE_BODY;
                    body_count <= '0;
                    send_idx <= '0;
                    dst_mac_reg <= '0;
                    src_mac_reg <= '0;
                    tx_data_reg <= '0;
                    tx_valid_reg <= 1'b0;
                end
            endcase
        end
    end

endmodule
