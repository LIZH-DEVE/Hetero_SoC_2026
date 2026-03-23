`timescale 1ns / 1ps

module crypto_engine (
    input  logic           clk,
    input  logic           rst_n,

    input  logic           algo_sel,      // 0: AES, 1: SM4
    input  logic           encdec,        // 0: Decrypt, 1: Encrypt
    input  logic           start,
    input  logic [31:0]    i_total_len,
    input  logic [127:0]   i_iv,
    output logic           done,
    output logic           busy,

    input  logic [7:0]     s_axil_araddr,
    output logic [31:0]    s_axil_rdata,

    // Optional explicit AES-256 mode selector.
    // If left floating in legacy instantiations, mode auto-detects from key[255:128].
    input  logic           aes256_en,
    input  logic [255:0]   key,
    input  logic [127:0]   din,
    output logic [127:0]   dout
);

    logic start_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) start_r <= 1'b0;
        else        start_r <= start;
    end

    wire start_pulse   = start && !start_r;
    wire is_aligned    = (i_total_len[3:0] == 4'd0);
    wire valid_trigger = start_pulse && is_aligned && !busy;

    reg [31:0] acl_err_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acl_err_cnt <= 32'd0;
        end else if (start_pulse && !is_aligned) begin
            acl_err_cnt <= acl_err_cnt + 1'b1;
        end
    end

    always_comb begin
        case (s_axil_araddr)
            8'h10:   s_axil_rdata = {30'd0, encdec, algo_sel};
            8'h44:   s_axil_rdata = acl_err_cnt;
            default: s_axil_rdata = 32'd0;
        endcase
    end

    // -------------------------------------------------------------------------
    // Secure key handling (avoid long-lived plain-text key storage)
    // -------------------------------------------------------------------------
    logic [255:0] key_shadow;
    logic [255:0] key_mask_latched;
    logic [255:0] key_lfsr;
    logic [255:0] active_key;
    logic         aes_keylen;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_lfsr        <= 256'h1;
            key_shadow      <= 256'd0;
            key_mask_latched<= 256'd0;
        end else begin
            // Free-running mask source.
            key_lfsr <= {key_lfsr[254:0], key_lfsr[255] ^ key_lfsr[21] ^ key_lfsr[1] ^ key_lfsr[0]};

            if (valid_trigger) begin
                key_shadow       <= key ^ key_lfsr;
                key_mask_latched <= key_lfsr;
            end else if (done) begin
                key_shadow       <= 256'd0;
                key_mask_latched <= 256'd0;
            end
        end
    end

    assign active_key = key_shadow ^ key_mask_latched;

    always_comb begin
        if (aes256_en === 1'b1) begin
            aes_keylen = 1'b1;
        end else if (aes256_en === 1'b0) begin
            aes_keylen = 1'b0;
        end else begin
            aes_keylen = |active_key[255:128];
        end
    end

    // -------------------------------------------------------------------------
    // CBC data path
    // -------------------------------------------------------------------------
    logic [127:0] r_iv;
    logic [127:0] w_core_din;
    logic [127:0] w_core_dout_raw;
    logic         first_block;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            first_block <= 1'b1;
        end else if (done) begin
            first_block <= 1'b0;
        end else if (valid_trigger && first_block) begin
            first_block <= 1'b0;
        end
    end

    // Encrypt: XOR with IV before crypto core
    // Decrypt: pass ciphertext to core; XOR after crypto core
    assign w_core_din = encdec ? (din ^ r_iv) : din;

    logic [127:0] aes_din_gated, sm4_din_gated;
    logic [127:0] w_aes_dout, w_sm4_dout;
    logic         aes_done, sm4_done;

    assign aes_din_gated = (algo_sel == 1'b0) ? w_core_din : 128'd0;
    assign sm4_din_gated = (algo_sel == 1'b1) ? w_core_din : 128'd0;

    // -------------------------------------------------------------------------
    // AES state machine
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        AES_IDLE,
        AES_INIT,
        AES_WAIT_INIT_DONE,
        AES_TRIGGER_NEXT,
        AES_WAIT_DONE
    } aes_state_t;

    aes_state_t aes_state, aes_next_state;
    logic aes_init_signal, aes_next_signal;
    logic aes_ready_reg;
    logic aes_key_initialized;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) aes_state <= AES_IDLE;
        else        aes_state <= aes_next_state;
    end

    always_comb begin
        aes_next_state = AES_IDLE;
        case (aes_state)
            AES_IDLE: begin
                if (algo_sel == 1'b0 && valid_trigger) begin
                    if (!aes_key_initialized) aes_next_state = AES_INIT;
                    else                      aes_next_state = AES_TRIGGER_NEXT;
                end else begin
                    aes_next_state = AES_IDLE;
                end
            end
            AES_INIT:           aes_next_state = AES_WAIT_INIT_DONE;
            AES_WAIT_INIT_DONE: aes_next_state = aes_ready_reg ? AES_TRIGGER_NEXT : AES_WAIT_INIT_DONE;
            AES_TRIGGER_NEXT:   aes_next_state = AES_WAIT_DONE;
            AES_WAIT_DONE:      aes_next_state = aes_done ? AES_IDLE : AES_WAIT_DONE;
            default:            aes_next_state = AES_IDLE;
        endcase
    end

    assign aes_init_signal = (aes_state == AES_INIT);
    assign aes_next_signal = (aes_state == AES_TRIGGER_NEXT);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aes_key_initialized <= 1'b0;
        end else if (aes_state == AES_WAIT_INIT_DONE && aes_ready_reg) begin
            aes_key_initialized <= 1'b1;
        end else if (algo_sel == 1'b1) begin
            aes_key_initialized <= 1'b0;
        end
    end

    aes_core u_aes_core (
        .clk          (clk),
        .reset_n      (rst_n),
        .encdec       (encdec),
        .keylen       (aes_keylen),
        .init         (aes_init_signal),
        .next         (aes_next_signal),
        .ready        (aes_ready_reg),
        .key          (active_key),
        .block        (aes_din_gated),
        .result       (w_aes_dout),
        .result_valid (aes_done)
    );

    // -------------------------------------------------------------------------
    // SM4 state machine
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        SM4_IDLE,
        SM4_KEY_EXP_TRIGGER,
        SM4_KEY_EXP_WAIT,
        SM4_ENCRYPT_WAIT
    } sm4_state_t;

    sm4_state_t sm4_state, sm4_next_state;

    logic sm4_key_exp_ready;
    logic [127:0] sm4_data_reg;
    logic sm4_encdec_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sm4_encdec_reg <= 1'b1;
        end else if (sm4_state == SM4_IDLE) begin
            sm4_encdec_reg <= encdec;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) sm4_state <= SM4_IDLE;
        else        sm4_state <= sm4_next_state;
    end

    always_comb begin
        sm4_next_state = SM4_IDLE;
        case (sm4_state)
            SM4_IDLE:           sm4_next_state = (algo_sel == 1'b1 && valid_trigger) ? SM4_KEY_EXP_TRIGGER : SM4_IDLE;
            SM4_KEY_EXP_TRIGGER:sm4_next_state = SM4_KEY_EXP_WAIT;
            SM4_KEY_EXP_WAIT:   sm4_next_state = sm4_key_exp_ready ? SM4_ENCRYPT_WAIT : SM4_KEY_EXP_WAIT;
            SM4_ENCRYPT_WAIT:   sm4_next_state = sm4_done ? SM4_IDLE : SM4_ENCRYPT_WAIT;
            default:            sm4_next_state = SM4_IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sm4_data_reg <= 128'd0;
        end else if (sm4_state == SM4_IDLE && algo_sel == 1'b1 && valid_trigger) begin
            sm4_data_reg <= sm4_din_gated;
        end
    end

    logic sm4_enable_key_exp;
    logic sm4_user_key_valid;
    logic sm4_valid_in;
    logic sm4_encdec_enable;

    assign sm4_enable_key_exp = (sm4_state == SM4_KEY_EXP_TRIGGER) ||
                                (sm4_state == SM4_KEY_EXP_WAIT) ||
                                (sm4_state == SM4_ENCRYPT_WAIT);

    assign sm4_user_key_valid = (sm4_state == SM4_KEY_EXP_TRIGGER);
    assign sm4_encdec_enable  = (sm4_state != SM4_IDLE);
    assign sm4_valid_in       = (sm4_state == SM4_ENCRYPT_WAIT);

    sm4_top u_sm4_core (
        .clk               (clk),
        .reset_n           (rst_n),
        .sm4_enable_in     (1'b1),
        .encdec_enable_in  (sm4_encdec_enable),
        .enable_key_exp_in (sm4_enable_key_exp),
        .encdec_sel_in     (~encdec),
        .valid_in          (sm4_valid_in),
        .data_in           (sm4_data_reg),
        .user_key_in       (active_key[127:0]),
        .user_key_valid_in (sm4_user_key_valid),
        .result_out        (w_sm4_dout),
        .ready_out         (sm4_done),
        .key_exp_ready_out (sm4_key_exp_ready)
    );

    assign w_core_dout_raw = (algo_sel == 1'b1) ? w_sm4_dout : w_aes_dout;

    assign done = (algo_sel == 1'b1) ? (sm4_state == SM4_ENCRYPT_WAIT && sm4_done)
                                     : (aes_state == AES_WAIT_DONE && aes_done);

    // Encrypt: core output
    // Decrypt: core output XOR previous IV
    assign dout = encdec ? w_core_dout_raw : (w_core_dout_raw ^ r_iv);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_iv  <= 128'd0;
            busy  <= 1'b0;
        end else begin
            if (algo_sel == 1'b0) begin
                if (aes_state != AES_IDLE) begin
                    busy <= 1'b1;
                    if (aes_state == AES_INIT && first_block) begin
                        r_iv <= i_iv;
                    end
                end else begin
                    busy <= 1'b0;
                    if (aes_done) begin
                        r_iv <= encdec ? w_core_dout_raw : din;
                    end
                end
            end else begin
                if (sm4_state != SM4_IDLE) begin
                    busy <= 1'b1;
                    if (sm4_state == SM4_KEY_EXP_TRIGGER && first_block) begin
                        r_iv <= i_iv;
                    end
                end else begin
                    busy <= 1'b0;
                    if (sm4_done) begin
                        r_iv <= encdec ? w_core_dout_raw : sm4_data_reg;
                    end
                end
            end
        end
    end

endmodule
