`ifndef KEY_VAULT_SV
`define KEY_VAULT_SV

`timescale 1ns / 1ps

/**
 * Module: key_vault
 * Task 14.2: Key Vault with DNA Binding
 * - Binds key usage to device DNA (fail-closed when lock enabled)
 * - Effective key = nonlinear KDF(user_key, dna)
 */
module key_vault #(
    parameter KEY_WIDTH = 128,
    parameter DNA_WIDTH = 57,
    parameter HASH_WIDTH = 128,
    parameter [56:0] SIM_DNA_VALUE = 57'h1234_5678_9ABCD_E
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // DNA Port
    output logic [DNA_WIDTH-1:0]   dna_out,

    // Key Interface
    input  logic [KEY_WIDTH-1:0]   user_key_in,
    input  logic                   user_key_valid,
    output logic [KEY_WIDTH-1:0]   effective_key_out,
    output logic                   effective_key_valid,

    // Control Interface
    input  logic                   dna_lock_enable,
    output logic [1:0]             lock_status,
    output logic                   system_locked,
    output logic                   tamper_detected,

    // Debug Interface
    output logic [DNA_WIDTH-1:0]   stored_dna,
    output logic [KEY_WIDTH-1:0]   stored_hash,
    output logic [31:0]            tamper_counter
);

    localparam logic [1:0] STATE_IDLE     = 2'b00;
    localparam logic [1:0] STATE_LOCK     = 2'b01;
    localparam logic [1:0] STATE_UNLOCKED = 2'b10;
    localparam logic [1:0] STATE_ERROR    = 2'b11;

    logic [DNA_WIDTH-1:0] current_dna;
    logic [DNA_WIDTH-1:0] dna_reg;
    logic                 dna_bound_valid;
    logic                 dna_ready;

    logic [KEY_WIDTH-1:0] effective_key;
    logic [KEY_WIDTH-1:0] hash_output;

    logic [1:0] state, state_next;
    logic dna_match;
    logic [31:0] tamper_cnt;

`ifdef SYNTHESIS
    // 7-series DNA_PORT is serial. Read once after reset.
    logic dna_dout;
    logic dna_read;
    logic dna_shift;
    logic [6:0] dna_cnt;
    logic dna_busy;

    DNA_PORT u_dna (
        .DOUT(dna_dout),
        .CLK(clk),
        .DIN(1'b0),
        .READ(dna_read),
        .SHIFT(dna_shift)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_dna <= '0;
            dna_read <= 1'b1;
            dna_shift <= 1'b0;
            dna_cnt <= 7'd0;
            dna_busy <= 1'b1;
        end else if (dna_busy) begin
            if (dna_read) begin
                dna_read <= 1'b0;
                dna_shift <= 1'b1;
            end else if (dna_shift) begin
                current_dna <= {current_dna[DNA_WIDTH-2:0], dna_dout};
                dna_cnt <= dna_cnt + 1'b1;
                if (dna_cnt == (DNA_WIDTH-1)) begin
                    dna_shift <= 1'b0;
                    dna_busy <= 1'b0;
                end
            end
        end
    end

    assign dna_ready = ~dna_busy;
`else
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_dna <= SIM_DNA_VALUE;
        end
    end

    assign dna_ready = 1'b1;
`endif

    function automatic [KEY_WIDTH-1:0] rotl(
        input [KEY_WIDTH-1:0] value,
        input int unsigned shift
    );
        rotl = (value << shift) | (value >> (KEY_WIDTH - shift));
    endfunction

    // KDF: nonlinear mix (ARX + DNA expansion), stronger than XOR-only derivation.
    always_comb begin
        logic [KEY_WIDTH-1:0] dna_mix;
        logic [KEY_WIDTH-1:0] kconst;
        logic [KEY_WIDTH-1:0] s0;
        logic [KEY_WIDTH-1:0] s1;
        logic [KEY_WIDTH-1:0] s2;

        for (int i = 0; i < KEY_WIDTH; i++) begin
            dna_mix[i] = current_dna[i % DNA_WIDTH] ^ current_dna[(i * 7 + 11) % DNA_WIDTH];
        end

        kconst = '0;
        if (KEY_WIDTH >   0) kconst[31:0]    = 32'hA5A5_5A5A;
        if (KEY_WIDTH >  32) kconst[63:32]   = 32'h3C6E_F372;
        if (KEY_WIDTH >  64) kconst[95:64]   = 32'h9E37_79B9;
        if (KEY_WIDTH >  96) kconst[127:96]  = 32'hD1B5_4A32;
        if (KEY_WIDTH > 128) kconst[159:128] = 32'h94D0_49BB;
        if (KEY_WIDTH > 160) kconst[191:160] = 32'h7F4A_7C15;
        if (KEY_WIDTH > 192) kconst[223:192] = 32'hF39C_C060;
        if (KEY_WIDTH > 224) kconst[255:224] = 32'h106A_A070;

        s0 = user_key_in ^ dna_mix ^ kconst;
        s1 = rotl(s0, 13) ^ (s0 >> 11) ^ dna_mix;
        s2 = rotl(s1, 29) + (dna_mix ^ (kconst >> 3));

        hash_output = rotl(s2, 47) ^ (s2 >> 17) ^ (dna_mix << 5) ^ kconst;
    end

    // Fail-closed DNA policy: no bypass when stored DNA is zero/uninitialized.
    assign dna_match = dna_bound_valid && (current_dna == dna_reg);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
        end else begin
            state <= state_next;
        end
    end

    always_comb begin
        state_next = state;
        case (state)
            STATE_IDLE: begin
                if (dna_lock_enable) begin
                    if (!dna_bound_valid || !dna_ready) begin
                        state_next = STATE_IDLE;
                    end else if (dna_match) begin
                        state_next = STATE_UNLOCKED;
                    end else begin
                        state_next = STATE_LOCK;
                    end
                end else begin
                    state_next = STATE_IDLE;
                end
            end

            STATE_UNLOCKED: begin
                if (!dna_lock_enable) begin
                    state_next = STATE_IDLE;
                end else if (!dna_ready || !dna_match) begin
                    state_next = STATE_ERROR;
                end
            end

            STATE_LOCK: begin
                state_next = STATE_LOCK;
            end

            STATE_ERROR: begin
                state_next = STATE_ERROR;
            end

            default: begin
                state_next = STATE_IDLE;
            end
        endcase
    end

    // Bind DNA once when available.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dna_reg <= '0;
            dna_bound_valid <= 1'b0;
        end else if (!dna_bound_valid && dna_ready) begin
            dna_reg <= current_dna;
            dna_bound_valid <= 1'b1;
        end
    end

    // Store only derived key; clear when locked/error/disabled.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            effective_key <= '0;
        end else begin
            if (state == STATE_UNLOCKED && user_key_valid) begin
                effective_key <= hash_output;
            end else if (state == STATE_LOCK || state == STATE_ERROR || !dna_lock_enable) begin
                effective_key <= '0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tamper_cnt <= 32'd0;
        end else if (state == STATE_UNLOCKED && dna_lock_enable && dna_bound_valid && !dna_match) begin
            tamper_cnt <= tamper_cnt + 1'b1;
        end
    end

    assign dna_out = current_dna;
    assign effective_key_out = (state == STATE_UNLOCKED) ? effective_key : {KEY_WIDTH{1'b0}};
    assign effective_key_valid = (state == STATE_UNLOCKED) && user_key_valid && dna_bound_valid;

    assign lock_status = state;
    assign system_locked = (state == STATE_LOCK || state == STATE_ERROR);
    assign tamper_detected = (tamper_cnt != 32'd0);

    assign stored_dna = dna_reg;
    assign stored_hash = effective_key;
    assign tamper_counter = tamper_cnt;

endmodule
`endif
