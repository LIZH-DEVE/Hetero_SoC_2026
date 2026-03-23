`timescale 1ns / 1ps
`default_nettype none

module crypto_engine (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         algo_sel,
    input  wire         encdec,
    input  wire         start,
    input  wire [31:0]  i_total_len,
    input  wire [127:0] i_iv,
    output reg          done,
    output reg          busy,
    input  wire [7:0]   s_axil_araddr,
    output reg  [31:0]  s_axil_rdata,
    input  wire         aes256_en,
    input  wire [255:0] key,
    input  wire [127:0] din,
    output reg  [127:0] dout
);

    localparam ST_IDLE          = 4'd0;
    localparam ST_AES_INIT      = 4'd1;
    localparam ST_AES_WAIT_KEY  = 4'd2;
    localparam ST_AES_NEXT      = 4'd3;
    localparam ST_AES_WAIT_DONE = 4'd4;
    localparam ST_SM4_KEY       = 4'd5;
    localparam ST_SM4_WAIT_KEY  = 4'd6;
    localparam ST_SM4_RUN       = 4'd7;
    localparam ST_SM4_WAIT_DONE = 4'd8;

    reg [3:0]   state;
    reg         algo_reg;
    reg         encdec_reg;
    reg         aes256_reg;
    reg [255:0] key_reg;
    reg [127:0] data_reg;
    reg         aes_keylen;
    reg [255:0] aes_key_bus;

    reg         aes_init_signal;
    reg         aes_next_signal;
    wire        aes_ready_reg;
    wire        aes_done;
    wire [127:0] aes_result;

    reg         sm4_enable_key_exp;
    reg         sm4_user_key_valid;
    reg         sm4_valid_in;
    reg         sm4_encdec_enable;
    reg [2:0]   sm4_state;
    wire        sm4_key_exp_ready;
    wire        sm4_done;
    wire [127:0] sm4_result;

    wire [31:0] status_word;

    assign status_word = {29'd0, aes256_reg, encdec_reg, algo_reg};

    always @(*) begin
        aes_init_signal    = 1'b0;
        aes_next_signal    = 1'b0;
        sm4_enable_key_exp = 1'b0;
        sm4_user_key_valid = 1'b0;
        sm4_valid_in       = 1'b0;
        sm4_encdec_enable  = 1'b0;

        case (state)
            ST_AES_INIT: begin
                aes_init_signal = 1'b1;
            end
            ST_AES_NEXT: begin
                aes_next_signal = 1'b1;
            end
            ST_SM4_KEY: begin
                sm4_enable_key_exp = 1'b1;
                sm4_user_key_valid = 1'b1;
                sm4_encdec_enable  = 1'b1;
            end
            ST_SM4_WAIT_KEY: begin
                sm4_enable_key_exp = 1'b1;
                sm4_encdec_enable  = 1'b1;
            end
            ST_SM4_RUN: begin
                sm4_enable_key_exp = 1'b1;
                sm4_valid_in       = 1'b1;
                sm4_encdec_enable  = 1'b1;
            end
            ST_SM4_WAIT_DONE: begin
                sm4_enable_key_exp = 1'b1;
                sm4_valid_in       = 1'b1;
                sm4_encdec_enable  = 1'b1;
            end
            default: begin
            end
        endcase
    end

    always @(*) begin
        if (aes256_reg === 1'b1) begin
            aes_keylen = 1'b1;
        end else if (aes256_reg === 1'b0) begin
            aes_keylen = 1'b0;
        end else begin
            aes_keylen = |key_reg[255:128];
        end
    end

    always @(*) begin
        if (aes_keylen) begin
            aes_key_bus = key_reg;
        end else begin
            aes_key_bus = {key_reg[127:0], 128'd0};
        end
    end

    always @(*) begin
        case (state)
            ST_SM4_KEY:       sm4_state = 3'd1;
            ST_SM4_WAIT_KEY:  sm4_state = 3'd2;
            ST_SM4_RUN:       sm4_state = 3'd3;
            ST_SM4_WAIT_DONE: sm4_state = 3'd3;
            default:          sm4_state = 3'd0;
        endcase
    end

    always @(*) begin
        case (s_axil_araddr)
            8'h10:   s_axil_rdata = status_word;
            default: s_axil_rdata = 32'd0;
        endcase
    end

    aes_core u_aes_core (
        .clk          (clk),
        .reset_n      (rst_n),
        .encdec       (encdec_reg),
        .init         (aes_init_signal),
        .next         (aes_next_signal),
        .ready        (aes_ready_reg),
        .key          (aes_key_bus),
        .keylen       (aes_keylen),
        .block        (data_reg),
        .result       (aes_result),
        .result_valid (aes_done)
    );

    sm4_top u_sm4_core (
        .clk               (clk),
        .reset_n           (rst_n),
        .sm4_enable_in     (1'b1),
        .encdec_enable_in  (sm4_encdec_enable),
        .encdec_sel_in     (~encdec_reg),
        .valid_in          (sm4_valid_in),
        .data_in           (data_reg),
        .enable_key_exp_in (sm4_enable_key_exp),
        .user_key_valid_in (sm4_user_key_valid),
        .user_key_in       (key_reg[127:0]),
        .key_exp_ready_out (sm4_key_exp_ready),
        .ready_out         (sm4_done),
        .result_out        (sm4_result)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            algo_reg   <= 1'b0;
            encdec_reg <= 1'b1;
            aes256_reg <= 1'b0;
            key_reg    <= 256'd0;
            data_reg   <= 128'd0;
            dout       <= 128'd0;
            busy       <= 1'b0;
            done       <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        algo_reg   <= algo_sel;
                        encdec_reg <= encdec;
                        aes256_reg <= aes256_en;
                        key_reg    <= key;
                        data_reg   <= din;
                        busy       <= 1'b1;
                        if (algo_sel) begin
                            state <= ST_SM4_KEY;
                        end else begin
                            state <= ST_AES_INIT;
                        end
                    end
                end

                ST_AES_INIT: begin
                    state <= ST_AES_WAIT_KEY;
                end

                ST_AES_WAIT_KEY: begin
                    if (aes_ready_reg) begin
                        state <= ST_AES_NEXT;
                    end
                end

                ST_AES_NEXT: begin
                    state <= ST_AES_WAIT_DONE;
                end

                ST_AES_WAIT_DONE: begin
                    if (aes_done) begin
                        dout <= aes_result;
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                ST_SM4_KEY: begin
                    state <= ST_SM4_WAIT_KEY;
                end

                ST_SM4_WAIT_KEY: begin
                    if (sm4_key_exp_ready) begin
                        state <= ST_SM4_RUN;
                    end
                end

                ST_SM4_RUN: begin
                    state <= ST_SM4_WAIT_DONE;
                end

                ST_SM4_WAIT_DONE: begin
                    if (sm4_done) begin
                        dout <= sm4_result;
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
