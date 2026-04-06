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
    localparam integer PBM_WORD_ADDR_WIDTH = PBM_ADDR_WIDTH - 2;
    localparam integer EFFECTIVE_HIGH_WATER_MARGIN =
        (HIGH_WATER_MARGIN >= (DEPTH - 16)) ? (DEPTH - 16) : HIGH_WATER_MARGIN;

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
    logic                      pbm_wr_en;
    logic [0:0]                pbm_wr_wea;
    logic [PBM_WORD_ADDR_WIDTH-1:0] pbm_wr_addr;
    (* DONT_TOUCH = "true", KEEP = "true" *) logic                      pbm_wr_cmd_q;
    (* DONT_TOUCH = "true", KEEP = "true" *) logic [0:0]                pbm_wr_wea_q;
    (* DONT_TOUCH = "true", KEEP = "true" *) logic [PBM_WORD_ADDR_WIDTH-1:0] pbm_wr_addr_q;
    (* DONT_TOUCH = "true", KEEP = "true" *) logic [DATA_WIDTH-1:0]     pbm_wr_data_q;
    logic                      pbm_rd_fire;
    logic                      pbm_rd_pending;
    logic [DATA_WIDTH-1:0]     pbm_rd_data;

    assign usage_calc = ptr_head_reserve - ptr_tail;
    assign full = (usage_calc >= (DEPTH - 16));
    assign high_water = (usage_calc >= (DEPTH - EFFECTIVE_HIGH_WATER_MARGIN));
    assign o_wr_ready = !full && (state == ALLOC_META || state == ALLOC_PBM);
    assign o_rd_empty = (ptr_tail == ptr_head_commit);
    assign o_rollback_active = (state == ROLLBACK);
    assign o_high_water = high_water;
    assign pbm_wr_en = i_wr_valid && o_wr_ready;
    assign pbm_wr_wea = {pbm_wr_en};
    assign pbm_wr_addr = (state == ALLOC_META) ? ptr_head_commit : ptr_head_reserve;
    assign pbm_rd_fire = i_rd_en && !o_rd_empty;

    // Isolate the BRAM write control from upstream async-reset state.
    // REQP-1839 is triggered when ENBWREN is driven directly from logic whose
    // fan-in includes async-reset registers in u_crypto_bridge/u_csr. Capture
    // the write command through a local synchronous stage before driving XPM.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pbm_wr_cmd_q <= 1'b0;
            pbm_wr_wea_q <= '0;
            pbm_wr_addr_q <= '0;
            pbm_wr_data_q <= '0;
        end else begin
            pbm_wr_cmd_q <= pbm_wr_en;
            pbm_wr_wea_q <= {pbm_wr_en};
            if (pbm_wr_en) begin
                pbm_wr_addr_q <= pbm_wr_addr;
                pbm_wr_data_q <= i_wr_data;
            end
        end
    end

    // Force the PBM payload store into true block RAM. Attribute-only inference
    // left this array in LUTRAM during OOC synth, so the active path now uses an
    // explicit simple dual-port memory primitive.
    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(PBM_WORD_ADDR_WIDTH),
        .ADDR_WIDTH_B(PBM_WORD_ADDR_WIDTH),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(DATA_WIDTH),
        .CASCADE_HEIGHT(0),
        .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(DEPTH * DATA_WIDTH),
        .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_B(DATA_WIDTH),
        .READ_LATENCY_B(1),
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC"),
        .SIM_ASSERT_CHK(0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(0),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(DATA_WIDTH),
        .WRITE_MODE_B("read_first")
    ) u_pbm_mem (
        .sleep(1'b0),
        .clka(clk),
        .ena(pbm_wr_cmd_q),
        .wea(pbm_wr_wea_q),
        .addra(pbm_wr_addr_q),
        .dina(pbm_wr_data_q),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .clkb(clk),
        .rstb(!rst_n),
        .enb(pbm_rd_fire),
        .regceb(1'b1),
        .addrb(ptr_tail),
        .doutb(pbm_rd_data),
        .sbiterrb(),
        .dbiterrb()
    );

    // State/register update and pointer maintenance.
    // Keep PBM head state synchronous so BRAM write/read control pins are not
    // sourced from async-reset registers.
    always_ff @(posedge clk) begin
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

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ptr_tail <= '0;
            o_rd_valid <= 1'b0;
            o_rd_data <= '0;
            pbm_rd_pending <= 1'b0;
        end else begin
            pbm_rd_pending <= pbm_rd_fire;
            o_rd_valid <= pbm_rd_pending;
            if (pbm_rd_pending) begin
                o_rd_data <= pbm_rd_data;
            end

            if (pbm_rd_fire) begin
                ptr_tail <= ptr_tail + 1'b1;
            end
        end
    end

    assign o_buffer_usage = {1'b0, ptr_head_commit} - {1'b0, ptr_tail};
endmodule
