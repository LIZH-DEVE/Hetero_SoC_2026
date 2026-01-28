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
    output logic [PBM_ADDR_WIDTH:0] o_buffer_usage
);
    // BRAM 定义
    localparam DEPTH = 1 << (PBM_ADDR_WIDTH - 2); 
    logic [DATA_WIDTH-1:0] ram [0:DEPTH-1];
    
    // 初始化 RAM (消灭红线的关键！虽然综合时不生效，但仿真会让波形变绿)
    initial begin
        for(int i=0; i<DEPTH; i++) ram[i] = 0;
    end

    // 指针
    logic [PBM_ADDR_WIDTH-3:0] ptr_head_commit, ptr_head_reserve, ptr_tail;

    // 逻辑
    logic [PBM_ADDR_WIDTH-2:0] usage_calc;
    assign usage_calc = ptr_head_reserve - ptr_tail;
    logic full;
    assign full = (usage_calc >= (DEPTH - 16)); 
    assign o_wr_ready = !full;
    assign o_rd_empty = (ptr_tail == ptr_head_commit);

    // Write
    always_ff @(posedge clk) begin
        if (i_wr_valid && !full) ram[ptr_head_reserve] <= i_wr_data;
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin ptr_head_commit <= 0; ptr_head_reserve <= 0; end
        else begin
            if (i_wr_valid && o_wr_ready) ptr_head_reserve <= ptr_head_reserve + 1;
            if (i_wr_last) begin
                if (i_wr_error) ptr_head_reserve <= ptr_head_commit; // Rollback
                else ptr_head_commit <= ptr_head_reserve + 1; // Commit
            end
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