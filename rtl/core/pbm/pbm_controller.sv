`timescale 1ns / 1ps
module pbm_controller #(
    parameter PBM_ADDR_WIDTH = 14, // 16KB
    parameter DATA_WIDTH     = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // [Write Port] From Gearbox
    input  logic                   i_wr_valid,
    input  logic [DATA_WIDTH-1:0]  i_wr_data,
    input  logic                   i_wr_last,
    input  logic                   i_wr_error,
    output logic                   o_wr_ready,

    // [Read Port] To DMA
    input  logic                   i_rd_en,
    output logic [DATA_WIDTH-1:0]  o_rd_data,
    output logic                   o_rd_valid,
    output logic                   o_rd_empty,

    // [Status]
    output logic [PBM_ADDR_WIDTH:0] o_buffer_usage,
    output logic                   o_rollback_active  // Rollback状态指示
);
    // BRAM 定义
    localparam DEPTH = 1 << (PBM_ADDR_WIDTH - 2); 
    logic [DATA_WIDTH-1:0] ram [0:DEPTH-1];
    
    // 初始化 RAM (消灭红线的关键！虽然综合时不生效，但仿真会让波形变绿)
    initial begin
        for(int i=0; i<DEPTH; i++) ram[i] = 0;
    end

    // 状态机定义
    typedef enum logic [1:0] {
        ALLOC_META,   // 分配Meta索引，等待数据
        ALLOC_PBM,    // 分配PBM空间，写入数据
        COMMIT,        // 提交：last且无错误
        ROLLBACK       // 回滚：last且有错误
    } state_t;
    state_t state, next_state;

    // 指针
    logic [PBM_ADDR_WIDTH-3:0] ptr_head_commit, ptr_head_reserve, ptr_tail;

    // 逻辑
    logic [PBM_ADDR_WIDTH-2:0] usage_calc;
    assign usage_calc = ptr_head_reserve - ptr_tail;
    logic full;
    assign full = (usage_calc >= (DEPTH - 16)); 
    assign o_wr_ready = !full;
    assign o_rd_empty = (ptr_tail == ptr_head_commit);
    assign o_rollback_active = (state == ROLLBACK);

    // 状态机时序逻辑
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ALLOC_META;
            ptr_head_commit <= 0;
            ptr_head_reserve <= 0;
        end else begin
            state <= next_state;
        end
    end

    // 状态机组合逻辑
    always_comb begin
        next_state = state;
        case (state)
            ALLOC_META: begin
                // 等待有效数据
                if (i_wr_valid && o_wr_ready) next_state = ALLOC_PBM;
            end
            ALLOC_PBM: begin
                // 写入数据
                if (i_wr_last) begin
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
            default: next_state = ALLOC_META;
        endcase
    end

    // Write Logic
    always_ff @(posedge clk) begin
        if (i_wr_valid && o_wr_ready && (state == ALLOC_PBM)) begin
            ram[ptr_head_reserve] <= i_wr_data;
        end
    end

    // Pointer Update Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptr_head_reserve <= 0;
            ptr_head_commit <= 0;
        end else begin
            case (state)
                ALLOC_META: begin
                    ptr_head_reserve <= ptr_head_commit;
                end
                ALLOC_PBM: begin
                    ptr_head_reserve <= ptr_head_reserve + 1;
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

    // Read
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin ptr_tail <= 0; o_rd_valid <= 0; end
        else begin
            o_rd_valid <= 0;
            if (i_rd_en && !o_rd_empty) begin
                ptr_tail <= ptr_tail + 1;
                o_rd_valid <= 1;
                o_rd_data <= ram[ptr_tail];
            end
        end
    end
    
    assign o_buffer_usage = {1'b0, ptr_head_commit} - {1'b0, ptr_tail};
endmodule