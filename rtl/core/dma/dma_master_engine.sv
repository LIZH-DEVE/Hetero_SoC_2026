`timescale 1ns / 1ps

module dma_master_engine #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // --- 用户控制接口 (User Logic Interface) ---
    input    logic                  i_start,      // 启动指令：由 CSR 模块发出的脉冲，触发 DMA 状态机跳转。
    input    logic [ADDR_WIDTH-1:0] i_base_addr,  // 起始地址：搬运任务的物理基地址[cite: 17]。
    input    logic [31:0]           i_total_len,  // 搬运总字节数：本次 DMA 任务需要传输的数据总量（字节单位）。
    output   logic                  o_done,       // 传输完成：整个任务（包括所有 Burst）结束且收到 B 通道确认。
    output   logic                  o_error,      // 异常拦截：检测到非对齐地址或总线错误响应[cite: 21, 29]。

    // --- AXI4 写地址通道 (AW) ---
    // 负责建立写操作的“车头”，告知内存目标位置和车队规模。
    output   logic [ADDR_WIDTH-1:0] m_axi_awaddr,  // 写地址：当前 Burst 传输的起始物理地址。
    output   logic [7:0]            m_axi_awlen,   // Burst 拍数：定义单次突发传输的数据节拍数（实际拍数 = awlen + 1）[cite: 16]。
    output   logic [2:0]            m_axi_awsize,  // Burst 大小：每一拍数据的字节宽度（3'b010 = 4 字节）。
    output   logic [1:0]            m_axi_awburst, // 突发模式：2'b01 代表地址自增（INCR）模式。
    output   logic                  m_axi_awvalid, // 地址有效：Master 声明地址和控制参数已准备好。
    input    logic                  m_axi_awready, // 地址就绪：从机（Memory）确认已接收地址请求。

    // --- AXI4 写数据通道 (W) ---
    // 负责传输实际的数据载荷。
    output   logic [DATA_WIDTH-1:0] m_axi_wdata,   // 写数据：实际写入内存的总线数据位流。
    output   logic [DATA_WIDTH/8-1:0] m_axi_wstrb, // 写掩码：标记数据位中哪些字节有效（32位通常对应 4'hF）。
    output   logic                  m_axi_wlast,   // 写结束标志：指示当前 Burst 传输的最后一拍数据。
    output   logic                  m_axi_wvalid, // 数据有效：Master 声明数据线上数据有效。
    input    logic                  m_axi_wready, // 数据就绪：从机反馈已准备好接收该数据。

    // --- AXI4 写响应通道 (B) ---
    // 负责写操作后的安全握手，确保数据已到达目的地。
    input    logic [1:0]            m_axi_bresp,   // 写响应：反馈写操作结果（00: OKAY, 10: SLVERR）。
    input    logic                  m_axi_bvalid,  // 响应有效：从机发出的响应信号已就绪。
    output   logic                  m_axi_bready,  // 响应就绪：Master 确认可以接收响应结果。

    // --- AXI4 读地址通道 (AR) ---
    // 读请求逻辑，与 AW 通道对称。
    output   logic [ADDR_WIDTH-1:0] m_axi_araddr,  // 读地址：请求数据的起始物理地址。
    output   logic [7:0]            m_axi_arlen,   // 读 Burst 拍数。
    output   logic [2:0]            m_axi_arsize,  // 读数据位宽。
    output   logic [1:0]            m_axi_arburst, // 读模式（INCR）。
    output   logic                  m_axi_arvalid, // 读请求有效。
    input    logic                  m_axi_arready, // 读请求就绪。

    // --- AXI4 读数据通道 (R) ---
    // 接收从机返回的数据载荷。
    input    logic [DATA_WIDTH-1:0] m_axi_rdata,   // 读数据：从机送回的总线数据。
    input    logic                  m_axi_rlast,   // 读结束标志：指示从机送回的是最后一拍。
    input    logic [1:0]            m_axi_rresp,   // 读响应：反馈读取状态。
    input    logic                  m_axi_rvalid,  // 读数据有效。
    output   logic                  m_axi_rready   // 读数据就绪。
);
    // --- W 通道辅助计数器 ---
    logic [7:0] w_beat_cnt; // 记录当前 Burst 已经传了多少拍

// ========================================================
// 内部寄存器与连线定义 (Internal Registers and Wires)
// ========================================================

    // --- 1. 状态机定义 ---
    // 使用枚举类型定义状态，方便调试 [cite: 25]
    typedef enum  int {
        IDLE,           // 空闲：等待 i_start 信号 [cite: 18]
        CALC,           // 计算：处理 4K 边界、Burst 长度和地址自增 [cite: 27, 28]
        AW_HANDSHAKE,   // 写地址握手：发送 AW 通道信号
        W_BURST,        // 写数据传输：发送数据直到 WLAST 为高
        B_RESP,         // 等待响应：接收 B 通道反馈确认
        DONE            // 结束：拉高 o_done 脉冲
    } state_t;



    state_t current_state, next_state;

    // --- 2. 任务跟踪寄存器 ---
    logic [ADDR_WIDTH-1:0] addr_reg;       // 记录当前传输到的物理地址
    logic [31:0]           len_left_reg;   // 记录还剩下多少字节没搬运

    // --- 3. 拆包计算辅助信号 ---
    // 核心：AXI 4KB 边界限制 
    // 4096 - addr[11:0] 就是当前地址距离下一个 4K 红线的字节数
    logic [12:0] bytes_to_4k_boundary; 
    
    // 本次 Burst 计划传输的字节数（取 剩余长度、4K距离、256拍上限 的最小值） [cite: 27, 28]
    logic [11:0] bytes_this_burst; 
    
    // 最终转换成的 AXI awlen 信号 (实际拍数 = awlen + 1) [cite: 16]
    logic [7:0]  burst_len_minus1;

    // --- 4. 控制逻辑信号 ---
    logic write_active; // 标记当前是否正在执行写操作

// ========================================================
// 核心计算逻辑 (Core Calculation Logic)
// ========================================================

    // --- 1. [公式 A] 计算到 4KB 边界的物理距离 ---
    // 逻辑：4096 (13'h1000) - 当前地址的低 12 位
    // 作用：实时监控离“撞墙”还有多远
assign bytes_to_4k_boundary = 13'h1000 - {1'b0, addr_reg[11:0]};

    // --- 2. [公式 B] 三者取其小 (The Min-3 Logic) ---
    // 逻辑：本次传输量 = Min(剩余总量, 4K红线距离, 1024字节上限)
    // 作用：确保既不超载，也不撞墙，也不多干活 [cite: 16, 27]
    always_comb begin
        // 第一步：比较“剩余任务量”和“离墙的距离”，取较小值
        // 注意：len_left_reg 可能很大，所以先比较逻辑
        if (len_left_reg < bytes_to_4k_boundary) begin
            // 如果剩余量还没墙远，那瓶颈可能是 1024 上限
            if (len_left_reg < 32'd1024)
                bytes_this_burst = len_left_reg[11:0];
            else
                bytes_this_burst = 12'd1024;
        end 
        else begin
            // 如果离墙更近，那瓶颈就是墙或者 1024 上限
            if (bytes_to_4k_boundary < 13'd1024)
                bytes_this_burst = bytes_to_4k_boundary[11:0];
            else
                bytes_this_burst = 12'd1024;
        end
    end

    // --- 3. [公式 C] 协议编码翻译 ---
    // 逻辑：拍数 = 字节数 / 4; awlen = 拍数 - 1
    // 作用：将人类的字节数转换为 AXI 硬件识别的 0-255 编码 [cite: 16]
    // 技巧：[11:2] 等同于右移 2 位 (除以 4)
    assign burst_len_minus1 = (bytes_this_burst[11:2] == 0) ? 8'd0 : (bytes_this_burst[11:2] - 8'd1);

// ========================================================
// 状态机逻辑实现 (FSM Implementation)
// ========================================================

    // --- 1. 状态与任务进度更新 (时序逻辑) ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            addr_reg      <= 0;
            len_left_reg  <= 0;
            w_beat_cnt    <= 0;
            o_error       <= 0; // 复位清除错误
        end 
        else begin
            current_state <= next_state;

            case (current_state)
                IDLE: begin
                    // 严查：地址必须 64字节对齐 (Bit 5:0 = 0)
                    // 严查：长度必须 4字节对齐 (Bit 1:0 = 0) 防止下溢
                    if (i_base_addr[5:0] != 0 || i_total_len[1:0] != 0) begin
                            o_error      <= 1'b1; // 亮红灯
                            // 注意：不加载 addr_reg，保持为 0 或原值
                    end
                    else begin
                            o_error      <= 1'b0; // 灭红灯
                            addr_reg     <= i_base_addr;
                            len_left_reg <= i_total_len;
                    end
                end

                AW_HANDSHAKE: begin
                    // 每次发车前（AW握手成功），清零拍数计数器 [cite: 25]
                    if (m_axi_awvalid && m_axi_awready) begin
                        w_beat_cnt <= 0;
                    end
                end

                W_BURST: begin
                    // 搬运过程中，每成功传一拍，计数器加 1 [cite: 25]
                    if (m_axi_wvalid && m_axi_wready) begin
                        w_beat_cnt <= w_beat_cnt + 1;
                    end
                end

                B_RESP: begin
                    // 结账确认：更新进度，为下一轮 CALC 做准备 [cite: 27, 28]
                    if (m_axi_bvalid && m_axi_bready) begin
                        addr_reg     <= addr_reg + bytes_this_burst;
                        len_left_reg <= len_left_reg - bytes_this_burst;
                    end
                end
            endcase
        end
    end

    // --- 2. 状态转移判断 (组合逻辑) ---
    always_comb begin
        next_state = current_state;

        case (current_state)
            IDLE: begin
                if (i_start) begin
                    // 大脑增加判断：如果地址或长度不对齐，坚决不跳！
                    if (i_base_addr[5:0] != 0 || i_total_len[1:0] != 0)
                        next_state = IDLE; // 原地待命
                    // 收到启动脉冲，立刻进入计算状态
                    else
                        next_state = CALC;
                end
            end

           CALC: begin
                // 既然能进 CALC，说明肯定是合法的，直接去握手
                next_state = AW_HANDSHAKE;
            end

            AW_HANDSHAKE: begin
                // 当写地址通道完成握手（主从双方都 Ready）
                if (m_axi_awvalid && m_axi_awready) 
                    next_state = W_BURST;
            end

            W_BURST: begin
                // 当发出最后一拍(WLAST)且握手成功
                if (m_axi_wlast && m_axi_wvalid && m_axi_wready) 
                    next_state = B_RESP;
            end

            B_RESP: begin
                // 收到写响应回执 (BVALID && BREADY)
                if (m_axi_bvalid && m_axi_bready) begin
                    // 如果剩余量 等于 本次搬运量，说明本次扣完就归零了
                    if (len_left_reg == bytes_this_burst) 
                        next_state = DONE;
                    else 
                        next_state = CALC;
                end
            end

            DONE: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

// ========================================================
// AXI 接口物理驱动 (Interface Drivers)
// ========================================================

    // --- AXI4 写地址通道 (AW) ---
    assign m_axi_awaddr  = addr_reg;
    assign m_axi_awlen   = burst_len_minus1; // 
    assign m_axi_awsize  = 3'b010;           // 4 字节位宽
    assign m_axi_awburst = 2'b01;            // INCR 模式
    assign m_axi_awvalid = (current_state == AW_HANDSHAKE);

    // --- AXI4 写数据通道 (W) ---
    assign m_axi_wvalid = (current_state == W_BURST);
    assign m_axi_wstrb  = 4'hF;              // 全字节有效
    assign m_axi_wdata  = 32'hDEAD_BEEF;     // 暂存测试数据，Day 6 替换为 FIFO 输出 [cite: 54]
    
    // 生成 WLAST：当计数器数到最后一拍时拉高 [cite: 16, 25]
    assign m_axi_wlast  = (w_beat_cnt == burst_len_minus1) && (current_state == W_BURST);

    // --- AXI4 写响应通道 (B) ---
    assign m_axi_bready = 1'b1;              // 始终准备好接收回执

    // --- 用户控制反馈 ---
    assign o_done  = (current_state == DONE);
    
endmodule