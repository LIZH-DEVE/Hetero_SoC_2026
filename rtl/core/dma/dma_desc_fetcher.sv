`timescale 1ns / 1ps

module dma_desc_fetcher #(
    parameter ADDR_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // --- CSR 接口 (来自 axil_csr) ---
    input  logic [31:0]            i_ring_base,   // 环基地址
    input  logic [31:0]            i_ring_size,   // 环大小
    input  logic [15:0]            i_sw_tail_ptr, // 软件写的尾指针
    output logic [15:0]            o_hw_head_ptr, // 硬件维护的头指针

    // --- 控制 DMA 引擎接口 ---
    output logic                   o_dma_start,   // 启动信号
    output logic [31:0]            o_dma_addr,    // 解析出的源地址
    output logic [31:0]            o_dma_len,     // 解析出的长度
    output logic                   o_dma_algo,    // 解析出的算法位
    input  logic                   i_dma_done,    // DMA 完成标志

    // --- AXI4 Read Interface (去 DDR 读描述符) ---
    output logic [ADDR_WIDTH-1:0]  m_axi_araddr,
    output logic [7:0]             m_axi_arlen,
    output logic [2:0]             m_axi_arsize,
    output logic [1:0]             m_axi_arburst,
    output logic                   m_axi_arvalid,
    input  logic                   m_axi_arready,
    input  logic [31:0]            m_axi_rdata,
    input  logic                   m_axi_rlast,
    input  logic                   m_axi_rvalid,
    output logic                   m_axi_rready
);

    // 状态机定义
    typedef enum logic [2:0] {
        IDLE,       // 等待指针更新
        FETCH_REQ,  // 发起读请求
        FETCH_DAT,  // 接收描述符数据
        DECODE,     // 解析数据
        EXEC_WAIT,  // 等待 DMA 搬运完毕
        UPDATE_HEAD // 更新 Head 指针
    } state_t;

    state_t state, next_state;

    // 内部寄存器
    logic [15:0] head_ptr;
    logic [31:0] desc_word0_addr;
    logic [31:0] desc_word1_ctrl;
    logic [1:0]  fetch_cnt; // 计数器：描述符有 4 个字 (16 Bytes)

    // =========================================================
    // 状态机逻辑
    // =========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            head_ptr <= 0;
            fetch_cnt <= 0;
            o_dma_start <= 0;
            desc_word0_addr <= 0;
            desc_word1_ctrl <= 0;
        end else begin
            case (state)
                IDLE: begin
                    // 只要 Head 不等于 Tail，且 Ring Size 不为 0，说明有任务
                    if ((head_ptr != i_sw_tail_ptr) && (i_ring_size != 0)) begin
                        state <= FETCH_REQ;
                    end
                end

                FETCH_REQ: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        state <= FETCH_DAT;
                        fetch_cnt <= 0;
                    end
                end

                FETCH_DAT: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        fetch_cnt <= fetch_cnt + 1;
                        // 抓取第0个字：源地址
                        if (fetch_cnt == 0) desc_word0_addr <= m_axi_rdata;
                        // 抓取第1个字：长度 + 算法控制位
                        if (fetch_cnt == 1) desc_word1_ctrl <= m_axi_rdata;
                        
                        if (m_axi_rlast) state <= DECODE;
                    end
                end

                DECODE: begin
                    o_dma_start <= 1; // 触发 DMA
                    state <= EXEC_WAIT;
                end

                EXEC_WAIT: begin
                    o_dma_start <= 0; // 脉冲结束
                    if (i_dma_done) state <= UPDATE_HEAD;
                end

                UPDATE_HEAD: begin
                    // 环形回绕逻辑
                    if (head_ptr == i_ring_size[15:0] - 1) 
                        head_ptr <= 0;
                    else 
                        head_ptr <= head_ptr + 1;
                    
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

    // =========================================================
    // 输出逻辑
    // =========================================================
    assign o_hw_head_ptr = head_ptr;

    // 解析描述符内容给 DMA Engine
    assign o_dma_addr = desc_word0_addr;
    assign o_dma_len  = {8'b0, desc_word1_ctrl[23:0]}; // 低24位是长度
    assign o_dma_algo = desc_word1_ctrl[31];           // 最高位是算法选择

    // AXI Read Channel 逻辑
    // 目标地址 = 环基地址 + (Head指针 * 16字节)
    assign m_axi_araddr  = i_ring_base + ({16'b0, head_ptr} << 4); 
    assign m_axi_arlen   = 8'd3;   // 读取 4 个 32-bit (即 16 字节)
    assign m_axi_arsize  = 3'b010; // 4 Bytes width
    assign m_axi_arburst = 2'b01;  // INCR
    assign m_axi_arvalid = (state == FETCH_REQ);
    assign m_axi_rready  = (state == FETCH_DAT);

endmodule