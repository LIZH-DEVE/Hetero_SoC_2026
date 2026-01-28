`timescale 1ns / 1ps

/**
 * 模块名称: dma_master_engine
 * 版本: Day06_Final (FIFO 流控版)
 * 描述: 
 * AXI4-Full 主机引擎，负责将 Gearbox/FIFO 传来的 32-bit 数据写入 DDR。
 * [功能升级] 移除了内部测试数据生成器，改为通过 i_fifo_rdata 读取外部数据。
 */

module dma_master_engine #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // --- 用户控制接口 (CSR) ---
    input  logic                   i_start,      // 启动信号
    input  logic [ADDR_WIDTH-1:0]  i_base_addr,  // 目标 DDR 地址
    input  logic [31:0]            i_total_len,  // 搬运总长度 (字节)
    output logic                   o_done,       // 完成中断
    output logic                   o_error,      // 错误标志

    // --- [Day 6 Core] 数据流接口 (来自 Gearbox) ---
    // 描述: DMA 即使想发数据，也必须等这里有数据 (i_fifo_empty == 0)
    input  logic [DATA_WIDTH-1:0]  i_fifo_rdata, // 32-bit 数据输入
    input  logic                   i_fifo_empty, // 1=无数据，暂停发送
    output logic                   o_fifo_ren,   // 1=读取一个数据 (Ready)

    // --- AXI4 写地址通道 (AW) ---
    output logic [ADDR_WIDTH-1:0]  m_axi_awaddr, 
    output logic [7:0]             m_axi_awlen,  
    output logic [2:0]             m_axi_awsize, 
    output logic [1:0]             m_axi_awburst,
    output logic                   m_axi_awvalid,
    input  logic                   m_axi_awready,

    // --- AXI4 写数据通道 (W) ---
    output logic [DATA_WIDTH-1:0]  m_axi_wdata,  
    output logic [DATA_WIDTH/8-1:0] m_axi_wstrb, 
    output logic                   m_axi_wlast,  
    output logic                   m_axi_wvalid, 
    input  logic                   m_axi_wready, 

    // --- AXI4 写响应通道 (B) ---
    input  logic [1:0]             m_axi_bresp,  
    input  logic                   m_axi_bvalid, 
    output logic                   m_axi_bready, 

    // --- AXI4 读通道 (封堵) ---
    output logic [ADDR_WIDTH-1:0]  m_axi_araddr, 
    output logic [7:0]             m_axi_arlen,  
    output logic [2:0]             m_axi_arsize, 
    output logic [1:0]             m_axi_arburst,
    output logic                   m_axi_arvalid,
    input  logic                   m_axi_arready,
    input  logic [DATA_WIDTH-1:0]  m_axi_rdata,  
    input  logic                   m_axi_rlast,  
    input  logic [1:0]             m_axi_rresp,  
    input  logic                   m_axi_rvalid, 
    output logic                   m_axi_rready  
);

    // ========================================================
    // 内部寄存器与状态机定义
    // ========================================================
    typedef enum int {
        IDLE,           // 空闲
        CALC,           // 计算拆包参数
        AW_HANDSHAKE,   // 发送写地址
        W_BURST,        // 发送写数据 (流控关键点)
        B_RESP,         // 等待写响应
        DONE            // 完成
    } state_t;

    state_t current_state, next_state;

    // 任务进度寄存器
    logic [ADDR_WIDTH-1:0] addr_reg;       
    logic [31:0]           len_left_reg;   
    
    // W通道计数器
    logic [7:0]            w_beat_cnt; 

    // 拆包计算辅助信号
    logic [12:0] bytes_to_4k_boundary; 
    logic [11:0] bytes_this_burst; 
    logic [7:0]  burst_len_minus1;

    // ========================================================
    // 核心计算逻辑 (4KB Boundary & Length Split)
    // ========================================================
    
    // 1. 计算离 4KB 边界还有多远
    assign bytes_to_4k_boundary = 13'h1000 - {1'b0, addr_reg[11:0]};

    // 2. 决定本次 Burst 传多少字节 (Min-3 算法)
    always_comb begin
        // 比较逻辑：取 (剩余长度) 和 (4K距离) 的较小值
        // 然后再和 (1024字节/256拍) 比较
        if (len_left_reg < bytes_to_4k_boundary) begin
            if (len_left_reg < 32'd1024)
                bytes_this_burst = len_left_reg[11:0];
            else
                bytes_this_burst = 12'd1024;
        end 
        else begin
            if (bytes_to_4k_boundary < 13'd1024)
                bytes_this_burst = bytes_to_4k_boundary[11:0];
            else
                bytes_this_burst = 12'd1024;
        end
    end

    // 3. 字节转拍数 (bytes / 4 - 1)
    assign burst_len_minus1 = (bytes_this_burst[11:2] == 0) ? 8'd0 : (bytes_this_burst[11:2] - 8'd1);

    // ========================================================
    // 状态机时序逻辑 (Sequential Logic)
    // ========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            addr_reg      <= 0;
            len_left_reg  <= 0;
            w_beat_cnt    <= 0;
            o_error       <= 0; 
        end 
        else begin
            current_state <= next_state;

            case (current_state)
                IDLE: begin
                    // 锁存用户输入的基地址和长度
                    if (i_start) begin
                        if (i_base_addr[5:0] != 0 || i_total_len[1:0] != 0) begin
                            o_error      <= 1'b1; // 对齐检查失败
                        end
                        else begin
                            o_error      <= 1'b0; 
                            addr_reg     <= i_base_addr;
                            len_left_reg <= i_total_len;
                        end
                    end
                end

                AW_HANDSHAKE: begin
                    // 握手成功，重置 beat 计数器
                    if (m_axi_awvalid && m_axi_awready) begin
                        w_beat_cnt <= 0;
                    end
                end

                W_BURST: begin
                    // [关键修改] 只有当 Valid 和 Ready 同时有效时，才算传输了一拍
                    // Valid 由 (!fifo_empty) 决定，Ready 由 AXI 从机决定
                    if (m_axi_wvalid && m_axi_wready) begin
                        w_beat_cnt <= w_beat_cnt + 1;
                    end
                end

                B_RESP: begin
                    // 写响应成功，更新地址和剩余长度
                    if (m_axi_bvalid && m_axi_bready) begin
                        addr_reg     <= addr_reg + bytes_this_burst;
                        len_left_reg <= len_left_reg - bytes_this_burst;
                    end
                end
            endcase
        end
    end

    // ========================================================
    // 状态机组合逻辑 (Next State Logic)
    // ========================================================
    always_comb begin
        next_state = current_state;

        case (current_state)
            IDLE: begin
                if (i_start) begin
                    // 如果参数错误，卡在 IDLE
                    if (i_base_addr[5:0] != 0 || i_total_len[1:0] != 0)
                        next_state = IDLE;
                    else
                        next_state = CALC;
                end
            end

           CALC: begin
                // 计算只需一个周期，直接跳去发地址
                next_state = AW_HANDSHAKE;
            end

            AW_HANDSHAKE: begin
                if (m_axi_awvalid && m_axi_awready) 
                    next_state = W_BURST;
            end

            W_BURST: begin
                // 传完最后一拍 (wlast) 且握手成功，去等响应
                if (m_axi_wlast && m_axi_wvalid && m_axi_wready) 
                    next_state = B_RESP;
            end

            B_RESP: begin
                if (m_axi_bvalid && m_axi_bready) begin
                    // 如果剩于长度为0，说明全部搬完，Done
                    if (len_left_reg == bytes_this_burst) 
                        next_state = DONE;
                    else 
                        next_state = CALC; // 否则回去计算下一包
                end
            end

            DONE: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // ========================================================
    // [Day 6 Critical] 接口驱动逻辑 (包含 FIFO 流控)
    // ========================================================

    // --- AW (写地址) ---
    assign m_axi_awaddr  = addr_reg;
    assign m_axi_awlen   = burst_len_minus1; 
    assign m_axi_awsize  = 3'b010;           // 32-bit width
    assign m_axi_awburst = 2'b01;            // INCR
    assign m_axi_awvalid = (current_state == AW_HANDSHAKE);

    // --- W (写数据) - 核心流控 ---
    // 1. Valid 信号：处于 Burst 状态，且 FIFO 里有数据
    assign m_axi_wvalid = (current_state == W_BURST) && (!i_fifo_empty);
    
    // 2. Data 信号：直接连通 Gearbox/FIFO 输出
    assign m_axi_wdata  = i_fifo_rdata;      
    
    // 3. FIFO 读使能：AXI 总线要读 (Ready) + 我们想发 (W_BURST) + 有数据 (!Empty)
    // 这形成了一个背压链：Memory Ready -> DMA -> FIFO Read -> Gearbox -> FIFO
    assign o_fifo_ren   = (current_state == W_BURST) && m_axi_wready && (!i_fifo_empty);

    assign m_axi_wstrb  = 4'hF; // 全有效

    // 4. WLAST 信号：当前是第 N 拍 + 当前数据有效
    assign m_axi_wlast  = (w_beat_cnt == burst_len_minus1) && (current_state == W_BURST) && (!i_fifo_empty);

    // --- B (写响应) ---
    assign m_axi_bready = 1'b1; // 总是准备好接收结果

    // --- AR/R (读通道封堵) ---
    assign m_axi_araddr  = 0;
    assign m_axi_arlen   = 0;
    assign m_axi_arsize  = 0;
    assign m_axi_arburst = 0;
    assign m_axi_arvalid = 0;
    assign m_axi_rready  = 0;

    // --- 状态反馈 ---
    assign o_done = (current_state == DONE);
    
endmodule