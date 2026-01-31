`timescale 1ns / 1ps
//
// Task 2.1: Master FSM `timescale 1ns / 1ps Burst Logic (Day 3)
// - 拆包逻辑: 跨4K边界且(/width) > 256时拆分
// - 对齐处理: addr[2:0] != 0 触发AXI_ERROR
// - 单ID保序: 确保严格保序传输


//
// Task 2.1: Master FSM  Burst Logic (Day 3)
// - 拆包逻辑: 跨4K边界且(/width) > 256时拆分
// - 对齐处理: addr[2:0] != 0 触发AXI_ERROR
// - 单ID保序: 确保严格保序传输

module dma_master_engine #(
//
// Task 2.1: Master FSM module dma_master_engine #( Burst Logic (Day 3)
// - 拆包逻辑: 跨4K边界且(/width) > 256时拆分
// - 对齐处理: addr[2:0] != 0 触发AXI_ERROR
// - 单ID保序: 确保严格保序传输

    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
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
    // 兼容 FWFT (First-Word Fall-Through) 接口特性
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
    // 将读通道完全禁用，专注于写操作
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

    // --- 4K Boundary Calculation ---
    // 计算当前地址距离下一个 4KB 边界还剩多少字节
    assign dist_to_4k = 13'h1000 - {1'b0, current_addr[11:0]};

    always_comb begin
        logic [12:0] limit;
        // 限制单次突发长度：不超过 4K 边界，且不超过 1024 字节 (256 beats * 4 bytes)
        limit = (dist_to_4k < 1024) ? dist_to_4k : 1024;

        // 最终决定本次传输字节数：取剩余量和限制量的较小值
        burst_bytes_calc = (bytes_remaining < limit) ? bytes_remaining : limit;
    end

    // --- FSM Sequential Logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_addr <= 0;
            bytes_remaining <= 0;
            current_awlen <= 0;
            beat_count <= 0;
            o_done <= 0;
            o_error <= 0;
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
                        // 强制长度对齐到 4 字节边界，防止 AXI 协议错误或死锁
                        // 如果传入 7 字节，强制截断为 4 字节
                        if (i_total_len[1:0] != 2'b00) begin
                            bytes_remaining <= {i_total_len[31:2], 2'b00};
                        end else begin
                            bytes_remaining <= i_total_len;
                        end
                    end
                end

                CALC: begin
                    beat_count <= 0;
                    // 计算 AXI awlen (N-1)
                    // 例如 16 字节 = 4 beats -> awlen = 3
                    if (burst_bytes_calc[31:2] > 0)
                        current_awlen <= burst_bytes_calc[31:2] - 1;
                    else
                        current_awlen <= 0;
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
        end
    end

    // --- FSM Combinational Logic ---
    always_comb begin
        next_state = state;
        case (state)
            IDLE: if (i_start && i_total_len != 0) next_state = CALC;

            CALC: next_state = ADDR;

            ADDR: if (m_axi_awvalid && m_axi_awready) next_state = DATA;

            DATA: if (m_axi_wlast && m_axi_wvalid && m_axi_wready) next_state = RESP;

            RESP: if (m_axi_bvalid && m_axi_bready)
                    // 如果还有剩余数据，继续回去计算下一次拆包，否则完成
                    next_state = (bytes_remaining == burst_bytes_calc) ? DONE : CALC;

            DONE: next_state = IDLE;
        endcase
    end

    // ========================================================
    // AXI4 Master Output Logic
    // ========================================================

    // Address Write (AW)
    assign m_axi_awvalid = (state == ADDR);
    assign m_axi_awaddr  = current_addr;
    assign m_axi_awlen   = current_awlen;
    assign m_axi_awsize  = 3'b010; // 4 bytes (32-bit)
    assign m_axi_awburst = 2'b01;  // INCR Type
    assign m_axi_awcache = 4'b0011; // Bufferable
    assign m_axi_awprot  = 3'b000;

    // Data Write (W)
    // [Patch 2: 握手逻辑增强]
    // 只有在 DATA 状态且 FIFO 不空时，Valid 才拉高
    assign m_axi_wvalid = (state == DATA) && !i_fifo_empty;
    assign m_axi_wdata  = i_fifo_rdata;
    assign m_axi_wstrb  = 4'hF; // 全字节有效
    assign m_axi_wlast  = (state == DATA) && (beat_count == current_awlen);

    // FIFO Read Enable
    // 当 AXI Slave 准备好接收，且我们有数据要发时，从 FIFO 读出一个数据
    assign o_fifo_ren   = (state == DATA) && m_axi_wready && !i_fifo_empty;

    // Write Response (B)
    assign m_axi_bready = (state == RESP);

    // --- Read Channel Tie-offs (Clean-up) ---
    // [Patch 3: 彻底禁用读通道]
    assign m_axi_arvalid = 1'b0;
    assign m_axi_araddr  = {ADDR_WIDTH{1'b0}};
    assign m_axi_arlen   = 8'h00;
    assign m_axi_arsize  = 3'b000;
    assign m_axi_arburst = 2'b00;
    assign m_axi_rready  = 1'b0;

endmodule
