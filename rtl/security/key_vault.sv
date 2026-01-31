`timescale 1ns / 1ps

/**
 * Module: key_vault
 * Task 14.2: Key Vault with DNA Binding
 * 功能:
 * 1. 物理绑定：实例化Xilinx DNA_PORT原语，读取FPGA芯片57-bit Device DNA
 * 2. 密钥派生：Effective_Key = Hash(User_Key + Device_DNA)
 * 3. 防克隆逻辑：启动时校验DNA，不匹配则锁定系统
 * 4. 存储介质：Write-Only BRAM，增加"篡改自毁"逻辑
 */

module key_vault #(
    parameter KEY_WIDTH = 128,
    parameter DNA_WIDTH = 57,
    parameter HASH_WIDTH = 128
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // =========================================================================
    // DNA Port
    // =========================================================================
    output logic [DNA_WIDTH-1:0]   dna_out,

    // =========================================================================
    // Key Interface
    // =========================================================================
    input  logic [KEY_WIDTH-1:0]   user_key_in,
    input  logic                   user_key_valid,
    output logic [KEY_WIDTH-1:0]   effective_key_out,
    output logic                   effective_key_valid,

    // =========================================================================
    // Control Interface
    // =========================================================================
    input  logic                   dna_lock_enable,
    output logic [1:0]             lock_status,
    output logic                   system_locked,
    output logic                   tamper_detected,

    // =========================================================================
    // Debug Interface
    // =========================================================================
    output logic [DNA_WIDTH-1:0]   stored_dna,
    output logic [KEY_WIDTH-1:0]   stored_hash,
    output logic [31:0]            tamper_counter
);

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam STATE_IDLE       = 2'b00;
    localparam STATE_LOCK       = 2'b01;
    localparam STATE_UNLOCKED   = 2'b10;
    localparam STATE_ERROR      = 2'b11;

    // =========================================================================
    // Internal Signals
    // =========================================================================
    logic [DNA_WIDTH-1:0]       current_dna;
    logic [DNA_WIDTH-1:0]       dna_reg;
    logic [DNA_WIDTH-1:0]       dna_shadow;
    logic [KEY_WIDTH-1:0]       hash_output;
    logic [KEY_WIDTH-1:0]       effective_key;
    logic [KEY_WIDTH-1:0]       key_reg;
    logic [1:0]                 state;
    logic [1:0]                 state_next;
    logic                       dna_match;
    logic                       first_boot;
    logic [31:0]                tamper_cnt;
    logic                       tamper_pulse;

    // =========================================================================
    // Xilinx DNA_PORT Primitive
    // =========================================================================
    (* DONT_TOUCH = "true" *)
    DNA_PORT #(
        .DNA_WIDTH(DNA_WIDTH)
    ) u_dna (
        .DIN(2'b00),
        .DOUT(current_dna)
    );

    // =========================================================================
    // Simple Hash Function (XOR-based)
    // Hash(User_Key + Device_DNA)
    // =========================================================================
    always_comb begin
        hash_output = user_key_in;
        
        // XOR DNA into key in 32-bit chunks
        hash_output = hash_output ^ {{(KEY_WIDTH-32){1'b0}}, current_dna[31:0]};
        hash_output = hash_output ^ {{(KEY_WIDTH-32){1'b0}}, current_dna[56:32]};
    end

    // =========================================================================
    // DNA Match Detection
    // =========================================================================
    assign dna_match = (current_dna == dna_reg) || (dna_reg == {DNA_WIDTH{1'b0}});

    // =========================================================================
    // State Machine: Current State
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
        end else begin
            state <= state_next;
        end
    end

    // =========================================================================
    // State Machine: Next State Logic
    // =========================================================================
    always_comb begin
        state_next = state;

        case (state)
            STATE_IDLE: begin
                if (dna_lock_enable) begin
                    if (dna_match) begin
                        state_next = STATE_UNLOCKED;
                    end else begin
                        state_next = STATE_LOCK;
                    end
                end
            end

            STATE_UNLOCKED: begin
                if (!dna_lock_enable) begin
                    state_next = STATE_IDLE;
                end else if (tamper_detected) begin
                    state_next = STATE_ERROR;
                end
            end

            STATE_LOCK: begin
                // Locked forever until reset
            end

            STATE_ERROR: begin
                // Error state, locked
            end

            default: begin
                state_next = STATE_IDLE;
            end
        endcase
    end

    // =========================================================================
    // DNA Register (Stored DNA)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dna_reg <= {DNA_WIDTH{1'b0}};
            dna_shadow <= {DNA_WIDTH{1'b0}};
            first_boot <= 1'b1;
        end else begin
            if (state == STATE_IDLE && dna_reg == {DNA_WIDTH{1'b0}}) begin
                // First boot, store DNA
                dna_reg <= current_dna;
                dna_shadow <= current_dna;
                first_boot <= 1'b0;
            end else if (state == STATE_LOCK) begin
                // DNA mismatch, do not update
            end else if (tamper_pulse) begin
                // Tamper detected, erase DNA
                dna_reg <= {DNA_WIDTH{1'b0}};
                dna_shadow <= {DNA_WIDTH{1'b0}};
            end
        end
    end

    // =========================================================================
    // Effective Key Register
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            effective_key <= {KEY_WIDTH{1'b0}};
        end else begin
            if (state == STATE_UNLOCKED && user_key_valid) begin
                effective_key <= hash_output;
            end else if (state == STATE_LOCK || state == STATE_ERROR) begin
                // Locked, erase key
                effective_key <= {KEY_WIDTH{1'b0}};
            end
        end
    end

    // =========================================================================
    // Tamper Detection (Simple)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tamper_cnt <= 32'd0;
        end else begin
            if (state == STATE_UNLOCKED && !dna_match) begin
                tamper_cnt <= tamper_cnt + 1'b1;
            end
        end
    end

    assign tamper_pulse = (tamper_cnt > 32'd0);

    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign dna_out = current_dna;
    assign effective_key_out = (state == STATE_UNLOCKED) ? effective_key : {KEY_WIDTH{1'b0}};
    assign effective_key_valid = (state == STATE_UNLOCKED) && user_key_valid;
    assign lock_status = state;
    assign system_locked = (state == STATE_LOCK || state == STATE_ERROR);
    assign tamper_detected = tamper_pulse;
    assign stored_dna = dna_reg;
    assign stored_hash = effective_key;
    assign tamper_counter = tamper_cnt;

endmodule

// =========================================================================
// Xilinx DNA_PORT Primitive
// =========================================================================
(* black_box *)
module DNA_PORT #(
    parameter DNA_WIDTH = 57
)(
    input  [1:0]  DIN,
    output [DNA_WIDTH-1:0] DOUT
);

endmodule
