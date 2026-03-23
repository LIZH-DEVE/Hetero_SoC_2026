`timescale 1ns / 1ps
module pbm_controller #(
    parameter PBM_ADDR_WIDTH = 14, // 16KB
    parameter DATA_WIDTH     = 32,
    parameter integer HIGH_WATER_MARGIN = 384
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // [Write Port] From Gearbox
    input  logic                    i_wr_valid,
    input  logic [DATA_WIDTH-1:0]   i_wr_data,
    input  logic                    i_wr_last,
    input  logic                    i_wr_error,
    output logic                    o_wr_ready,

    // [Read Port] To DMA
    input  logic                    i_rd_en,
    output logic [DATA_WIDTH-1:0]   o_rd_data,
    output logic                    o_rd_valid,
    output logic                    o_rd_empty,

    // [Status]
    output logic [PBM_ADDR_WIDTH:0] o_buffer_usage,
    output logic                    o_rollback_active,
    output logic                    o_high_water,
    output logic                    o_drop_pulse
);
    localparam DEPTH = 1 << (PBM_ADDR_WIDTH - 2);
    localparam integer EFFECTIVE_HIGH_WATER_MARGIN =
        (HIGH_WATER_MARGIN >= (DEPTH - 16)) ? (DEPTH - 16) : HIGH_WATER_MARGIN;
    logic [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    typedef enum logic [1:0] {
        ALLOC_META,
        ALLOC_PBM,
        COMMIT,
        ROLLBACK
    } state_t;
    state_t state, next_state;

    logic [PBM_ADDR_WIDTH-3:0] ptr_head_commit, ptr_head_reserve, ptr_tail;

    logic [PBM_ADDR_WIDTH-2:0] usage_calc;
    logic full;
    logic high_water;

    assign usage_calc = ptr_head_reserve - ptr_tail;
    assign full = (usage_calc >= (DEPTH - 16));
    assign high_water = (usage_calc >= (DEPTH - EFFECTIVE_HIGH_WATER_MARGIN));
    assign o_wr_ready = !full && (state == ALLOC_META || state == ALLOC_PBM);
    assign o_rd_empty = (ptr_tail == ptr_head_commit);
    assign o_rollback_active = (state == ROLLBACK);
    assign o_high_water = high_water;

    // State/register update and pointer maintenance.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ALLOC_META;
            ptr_head_commit <= '0;
            ptr_head_reserve <= '0;
            o_drop_pulse <= 1'b0;
        end else begin
            state <= next_state;
            o_drop_pulse <= 1'b0;

            if (i_wr_valid && !o_wr_ready) begin
                o_drop_pulse <= 1'b1;
            end

            case (state)
                ALLOC_META: begin
                    // Reserve one slot when first beat is accepted.
                    if (i_wr_valid && o_wr_ready) begin
                        ptr_head_reserve <= ptr_head_commit + 1'b1;
                    end else begin
                        ptr_head_reserve <= ptr_head_commit;
                    end
                end
                ALLOC_PBM: begin
                    if (i_wr_valid && o_wr_ready) begin
                        ptr_head_reserve <= ptr_head_reserve + 1'b1;
                    end
                end
                COMMIT: begin
                    ptr_head_commit <= ptr_head_reserve;
                end
                ROLLBACK: begin
                    ptr_head_reserve <= ptr_head_commit;
                end
                default: begin
                    ptr_head_reserve <= ptr_head_commit;
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            ALLOC_META: begin
                if (i_wr_valid && o_wr_ready) begin
                    if (i_wr_last) begin
                        if (i_wr_error) next_state = ROLLBACK;
                        else next_state = COMMIT;
                    end else begin
                        next_state = ALLOC_PBM;
                    end
                end
            end
            ALLOC_PBM: begin
                if (i_wr_valid && o_wr_ready && i_wr_last) begin
                    if (i_wr_error) next_state = ROLLBACK;
                    else next_state = COMMIT;
                end
            end
            COMMIT: begin
                next_state = ALLOC_META;
            end
            ROLLBACK: begin
                next_state = ALLOC_META;
            end
            default: begin
                next_state = ALLOC_META;
            end
        endcase
    end

    // Accept first beat already in ALLOC_META to avoid dropping one word per packet.
    // RAM write logic does not use asynchronous reset to adhere to BRAM mapping guidelines.
    always_ff @(posedge clk) begin
        if (i_wr_valid && o_wr_ready) begin
            if (state == ALLOC_META) begin
                ram[ptr_head_commit] <= i_wr_data;
            end else if (state == ALLOC_PBM) begin
                ram[ptr_head_reserve] <= i_wr_data;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptr_tail <= '0;
            o_rd_valid <= 1'b0;
            o_rd_data <= '0;
        end else begin
            o_rd_valid <= 1'b0;
            if (i_rd_en && !o_rd_empty) begin
                ptr_tail <= ptr_tail + 1'b1;
                o_rd_valid <= 1'b1;
                o_rd_data <= ram[ptr_tail];
            end
        end
    end

    assign o_buffer_usage = {1'b0, ptr_head_commit} - {1'b0, ptr_tail};
endmodule
