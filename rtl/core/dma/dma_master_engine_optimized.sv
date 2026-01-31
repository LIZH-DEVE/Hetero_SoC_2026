`timescale 1ns / 1ps

/**
 * Module: dma_master_engine_optimized
 * Day 19: 性能压榨
 * Task 18.1: Burst Efficiency - 调整阈值凑齐128/256 Beats
 * Task 18.2: Outstanding - 开启AXI Outstanding (Depth 4)
 */

module dma_master_engine_optimized #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MAX_OUTSTANDING = 4
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // --- Control Interface ---
    input  logic                   i_start,
    input  logic [ADDR_WIDTH-1:0]  i_base_addr,
    input  logic [31:0]            i_total_len,
    output logic                   o_done,
    output logic                   o_error,  // AXI Error signal

    // --- Data Source (From Crypto Bridge / PBM) ---
    input  logic [DATA_WIDTH-1:0]  i_fifo_rdata,
    input  logic                   i_fifo_empty,
    output logic                   o_fifo_ren,

    // --- AXI4 Master Write Interface ---
    output logic [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output logic [7:0]             m_axi_awlen,
    output logic [2:0]             m_axi_awsize,
    output logic [1:0]             m_axi_awburst,
    output logic [3:0]             m_axi_awcache,
    output logic [2:0]             m_axi_awprot,
    output logic                   m_axi_awvalid,
    input  logic                   m_axi_awready,

    output logic [DATA_WIDTH-1:0]  m_axi_wdata,
    output logic [DATA_WIDTH/8-1:0] m_axi_wstrb,
    output logic                   m_axi_wlast,
    output logic                   m_axi_wvalid,
    input  logic                   m_axi_wready,
    input  logic [1:0]             m_axi_wresp,
    input  logic                   m_axi_blast,
    input  logic                   m_axi_bvalid,
    output logic                   m_axi_bready,

    // --- AXI4 Read Interface (Tie-off) ---
    output logic [ADDR_WIDTH-1:0]  m_axi_araddr,
    output logic [7:0]             m_axi_arlen,
    output logic [2:0]             m_axi_arsize,
    output logic [1:0]             m_axi_arburst,
    output logic                   m_axi_arvalid,
    input  logic                   m_axi_arready,
    input  logic [DATA_WIDTH-1:0]  m_axi_rdata,
    input  logic [1:0]             m_axi_rresp,
    input  logic                   m_axi_rlast,
    input  logic                   m_axi_rvalid,
    output logic                   m_axi_rready
);

    // ========================================================
    // Day 19 Task 18.1: Burst Efficiency
    // 调整阈值凑齐 128/256 Beats
    // ========================================================
    localparam OPTIMAL_BURST_128 = 128;  // 128 beats = 512 bytes
    localparam OPTIMAL_BURST_256 = 256;  // 256 beats = 1024 bytes

    // ========================================================
    // Day 19 Task 18.2: Outstanding Support
    // 支持最多4个outstanding transactions
    // ========================================================

    // ========================================================
    // 状态机与内部信号
    // ========================================================
    typedef enum logic [2:0] {IDLE, CALC, ADDR, DATA, RESP, DONE} state_t;
    state_t state, next_state;

    // 对齐错误检查
    logic addr_unaligned;
    assign addr_unaligned = (i_base_addr[2:0] != 3'b000);

    logic [ADDR_WIDTH-1:0] current_addr;
    logic [31:0]           bytes_remaining;
    logic [31:0]           burst_bytes_calc;
    logic [7:0]            current_awlen;
    logic [8:0]            beat_count;
    logic [12:0]           dist_to_4k;

    // Outstanding transaction tracking
    logic [2:0]            outstanding_cnt;
    logic                   can_issue_new_aw;

    // [Day 19] Performance counters
    logic [31:0]            total_transactions;
    logic [31:0]            burst_256_cnt;
    logic [31:0]            burst_128_cnt;
    logic [31:0]            burst_other_cnt;
    logic [31:0]            split_cnt;  // 4K边界拆包次数

    // --- 4K Boundary Calculation ---
    assign dist_to_4k = 13'h1000 - {1'b0, current_addr[11:0]};

    always_comb begin
        logic [12:0] limit;

        // [Day 19] 优化burst长度：优先选择128或256 beats
        if (dist_to_4k < 1024) begin
            // 跨4K边界，使用剩余距离
            limit = dist_to_4k;
        end else begin
            // 不跨4K边界，尝试凑齐128或256 beats
            if (bytes_remaining >= 1024) begin
                limit = 1024;  // 256 beats
            end else if (bytes_remaining >= 512) begin
                limit = 512;   // 128 beats
            end else if (bytes_remaining >= 256) begin
                limit = 256;   // 64 beats
            end else begin
                limit = bytes_remaining;
            end
        end

        // 最终决定本次传输字节数
        burst_bytes_calc = (bytes_remaining < limit) ? bytes_remaining : limit;
    end

    // Outstanding counter management
    assign can_issue_new_aw = (outstanding_cnt < MAX_OUTSTANDING);

    // --- FSM Sequential Logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_addr <= 0;
            bytes_remaining <= 0;
            current_awlen <= 0;
            beat_count <= 0;
            outstanding_cnt <= 0;
            o_done <= 0;
            o_error <= 0;
            total_transactions <= 0;
            burst_256_cnt <= 0;
            burst_128_cnt <= 0;
            burst_other_cnt <= 0;
            split_cnt <= 0;
        end else begin
            state <= next_state;
            o_done <= (state == DONE);

            // 对齐错误处理
            if (i_start && addr_unaligned) begin
                o_error <= 1;
            end else if (state == IDLE) begin
                o_error <= 0;
            end

            case (state)
                IDLE: begin
                    if (i_start && i_total_len != 0) begin
                        current_addr <= i_base_addr;

                        // [Patch 1: 安全对齐检查]
                        if (i_total_len[1:0] != 2'b00) begin
                            bytes_remaining <= {i_total_len[31:2], 2'b00};
                        end else begin
                            bytes_remaining <= i_total_len;
                        end
                    end
                end

                CALC: begin
                    beat_count <= 0;

                    // [Day 19] 统计burst长度分布
                    if (burst_bytes_calc == 1024) begin
                        burst_256_cnt <= burst_256_cnt + 1;
                    end else if (burst_bytes_calc == 512) begin
                        burst_128_cnt <= burst_128_cnt + 1;
                    end else begin
                        burst_other_cnt <= burst_other_cnt + 1;
                    end

                    // 计算 AXI awlen (N-1)
                    if (burst_bytes_calc[31:2] > 0)
                        current_awlen <= burst_bytes_calc[31:2] - 1;
                    else
                        current_awlen <= 0;

                    // [Day 19] 统计4K边界拆包
                    if (({1'b0, current_addr[11:0]} + burst_bytes_calc) > 13'h1000) begin
                        split_cnt <= split_cnt + 1;
                    end
                end

                // 在 DATA 状态，只要成功握手一次，计数器加 1
                DATA: begin
                    if (m_axi_wvalid && m_axi_wready)
                        beat_count <= beat_count + 1;
                end

                RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        // 更新地址和剩余长度
                        current_addr <= current_addr + burst_bytes_calc;
                        bytes_remaining <= bytes_remaining - burst_bytes_calc;
                    end
                end
            endcase

            // Outstanding transaction tracking
            if (m_axi_awvalid && m_axi_awready) begin
                outstanding_cnt <= outstanding_cnt + 1;
                total_transactions <= total_transactions + 1;
            end

            if (m_axi_bvalid && m_axi_bready) begin
                outstanding_cnt <= outstanding_cnt - 1;
            end
        end
    end

    // --- FSM Combinational Logic ---
    always_comb begin
        next_state = state;
        case (state)
            IDLE: if (i_start && i_total_len != 0) next_state = CALC;

            CALC: if (can_issue_new_aw) next_state = ADDR;

            ADDR: if (m_axi_awvalid && m_axi_awready) next_state = DATA;

            DATA: if (m_axi_wlast && m_axi_wvalid && m_axi_wready) next_state = RESP;

            RESP: if (m_axi_bvalid && m_axi_bready)
                    next_state = (bytes_remaining == burst_bytes_calc) ? DONE : CALC;

            DONE: next_state = IDLE;
        endcase
    end

    // ========================================================
    // AXI4 Master Output Logic
    // ========================================================

    // Address Write (AW)
    assign m_axi_awvalid = (state == ADDR) && can_issue_new_aw;
    assign m_axi_awaddr  = current_addr;
    assign m_axi_awlen   = current_awlen;
    assign m_axi_awsize  = 3'b010; // 4 bytes (32-bit)
    assign m_axi_awburst = 2'b01;  // INCR Type
    assign m_axi_awcache = 4'b0011; // Bufferable
    assign m_axi_awprot  = 3'b000;

    // Data Write (W)
    assign m_axi_wvalid = (state == DATA) && !i_fifo_empty;
    assign m_axi_wdata  = i_fifo_rdata;
    assign m_axi_wstrb  = 4'hF; // 全字节有效
    assign m_axi_wlast  = (state == DATA) && (beat_count == current_awlen);

    // FIFO Read Enable
    assign o_fifo_ren   = (state == DATA) && m_axi_wready && !i_fifo_empty;

    // Write Response (B)
    assign m_axi_bready = (state == RESP);

    // --- Read Channel Tie-offs (Clean-up) ---
    assign m_axi_arvalid = 1'b0;
    assign m_axi_araddr  = {ADDR_WIDTH{1'b0}};
    assign m_axi_arlen   = 8'h00;
    assign m_axi_arsize  = 3'b000;
    assign m_axi_arburst = 2'b00;
    assign m_axi_rready  = 1'b0;

    // ========================================================
    // Performance Statistics Output
    // ========================================================
    // 注意：这些信号可以连接到CSR或ILA用于性能监控

endmodule
