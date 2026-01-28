`timescale 1ns / 1ps

module dma_master_engine (
    input  logic        clk,
    input  logic        rst_n,

    // 控制接口
    input  logic        i_start,
    input  logic [31:0] i_base_addr,
    input  logic [31:0] i_total_len,
    output logic        o_done,

    // AXI4 Master Write Interface
    output logic [31:0] m_axi_awaddr,
    output logic [7:0]  m_axi_awlen,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    
    output logic [31:0] m_axi_wdata,
    output logic        m_axi_wlast,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,
    input  logic [1:0]  m_axi_bresp,

    // FIFO Interface
    input  logic        i_fifo_empty,
    input  logic [31:0] i_fifo_rdata,
    output logic        o_fifo_ren
);

    // =================================================
    // 参数与内部信号
    // =================================================
    // AXI 最大 Burst 限制 (bytes)
    localparam int MAX_BURST_BYTES = 1024; // 256 beats * 4 bytes

    typedef enum logic [2:0] {
        IDLE,
        CALC_BURST, // 计算拆包参数
        ADDR_PHASE, // 发送地址
        DATA_PHASE, // 发送数据
        RESP_PHASE, // 等待写响应
        DONE
    } state_t;

    state_t state, next_state;

    // 内部寄存器
    logic [31:0] current_addr;
    logic [31:0] bytes_remaining;
    logic [31:0] burst_bytes;     // 当前 Burst 实际传输字节
    
    // [优化] 计数器位宽扩展：防止 256 beats 时溢出 (虽然 awlen 是 8 位，但比较时安全起见用 9 位)
    logic [8:0]  beat_count;      

    // [Patch 1] 4K 边界计算辅助信号
    logic [12:0] dist_to_4k;
    logic [31:0] calc_burst_bytes; // 组合逻辑计算出的下一跳长度

    // =================================================
    // 组合逻辑：Burst 长度裁决 (Timing Critical)
    // =================================================
    always_comb begin
        // 1. 计算距离下一个 4K 边界的字节数 (0x1000 - 低12位)
        dist_to_4k = 13'h1000 - {1'b0, current_addr[11:0]};

        // 2. 三方比对取最小值：(剩余长度) vs (4K距离) vs (AXI最大限制)
        // 优先级：4K边界最优先 (防止协议违规)，其次是剩余长度
        if (bytes_remaining < MAX_BURST_BYTES) begin
            if (bytes_remaining < dist_to_4k)
                calc_burst_bytes = bytes_remaining;
            else
                calc_burst_bytes = {19'd0, dist_to_4k};
        end else begin
            if (dist_to_4k < MAX_BURST_BYTES)
                calc_burst_bytes = {19'd0, dist_to_4k};
            else
                calc_burst_bytes = MAX_BURST_BYTES;
        end
    end

    // =================================================
    // 状态机逻辑 (Sequential)
    // =================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= IDLE;
            current_addr    <= '0;
            bytes_remaining <= '0;
            burst_bytes     <= '0;
            beat_count      <= '0;
            o_done          <= 1'b0;
        end else begin
            state  <= next_state;
            o_done <= (state == DONE);

            case (state)
                IDLE: begin
                    if (i_start && i_total_len != 0) begin // [优化] 零长度保护
                        current_addr    <= i_base_addr;
                        bytes_remaining <= i_total_len;
                    end
                end

                CALC_BURST: begin
                    beat_count  <= '0;
                    burst_bytes <= calc_burst_bytes; // 锁存计算结果
                end

                DATA_PHASE: begin
                    // 仅当握手成功时计数
                    if (m_axi_wvalid && m_axi_wready) begin
                        beat_count <= beat_count + 1;
                    end
                end

                RESP_PHASE: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        // 响应成功，更新指针
                        current_addr    <= current_addr + burst_bytes;
                        bytes_remaining <= bytes_remaining - burst_bytes;
                    end
                end
            endcase
        end
    end

    // =================================================
    // 下一状态逻辑 (Combinational)
    // =================================================
    always_comb begin
        next_state = state;
        case (state)
            IDLE: 
                // [优化] 增加非零检查
                if (i_start && i_total_len != 0) next_state = CALC_BURST;

            CALC_BURST: 
                next_state = ADDR_PHASE;

            ADDR_PHASE: 
                if (m_axi_awvalid && m_axi_awready) next_state = DATA_PHASE;

            DATA_PHASE: 
                // 数据发完 (wlast) 且 握手成功
                if (m_axi_wlast && m_axi_wvalid && m_axi_wready) next_state = RESP_PHASE;

            RESP_PHASE: 
                if (m_axi_bvalid && m_axi_bready) begin
                    // 检查是否全部传完
                    if (bytes_remaining == burst_bytes) 
                        next_state = DONE;
                    else 
                        next_state = CALC_BURST; // 继续拆包
                end

            DONE: 
                next_state = IDLE;
                
            default: next_state = IDLE;
        endcase
    end

    // =================================================
    // AXI 输出逻辑
    // =================================================
    
    // Write Address
    assign m_axi_awvalid = (state == ADDR_PHASE);
    assign m_axi_awaddr  = current_addr;
    // awlen = beats - 1. (bytes >> 2) - 1. 
    // 假设地址是 4 字节对齐的。
    assign m_axi_awlen   = (burst_bytes[31:2]) - 1; 

    // Write Data
    assign m_axi_wvalid = (state == DATA_PHASE) && !i_fifo_empty;
    assign m_axi_wdata  = i_fifo_rdata;
    
    // WLAST 生成: 当拍数 == awlen 时拉高
    // 注意: m_axi_awlen 是 8 位，这里隐式扩展比较
    assign m_axi_wlast  = (state == DATA_PHASE) && (beat_count == m_axi_awlen);

    // Write Response
    assign m_axi_bready = (state == RESP_PHASE);
    
    // FIFO Read Enable: 仅在 AXI 数据握手时读 FIFO
    assign o_fifo_ren   = (state == DATA_PHASE) && m_axi_wvalid && m_axi_wready;

    // =================================================
    // [验证] 断言检查 (Assertions)
    // =================================================
    // synthesis translate_off
    
    // 检查 1: 输入地址必须 4 字节对齐，否则移位计算 awlen 会出错
    initial begin
        wait(rst_n);
        forever begin
            @(posedge clk);
            if (i_start) begin
                assert(i_base_addr[1:0] == 2'b00) 
                else $error("DMA Error: Base address must be 4-byte aligned!");
            end
        end
    end

    // 检查 2: 4K 边界保护
    always @(posedge clk) begin
        if (m_axi_awvalid && m_axi_awready) begin
            // 检查当前 Burst 结束地址是否跨越 4K
            assert ( (m_axi_awaddr[11:0] + (m_axi_awlen + 1)*4) <= 13'h1000 )
            else $error("DMA Error: AXI Burst crossed 4K boundary!");
        end
    end
    // synthesis translate_on

endmodule