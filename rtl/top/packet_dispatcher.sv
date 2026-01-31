`timescale 1ns / 1ps

/**
 * Module: packet_dispatcher
 * Description: 基于tuser分发数据包到不同处理路径
 * Task 6.1: Dispatcher - 基于tuser分发逻辑
 * Task 6.2: Flow Control - Credit-based反压
 */
module packet_dispatcher #(
    parameter DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // --- AXI-Stream Input ---
    input  logic [DATA_WIDTH-1:0]  s_axis_tdata,
    input  logic                   s_axis_tvalid,
    input  logic                   s_axis_tlast,
    input  logic [DATA_WIDTH/8-1:0] s_axis_tkeep,
    input  logic                   s_axis_tuser, // tuser用于分发策略
    output logic                   s_axis_tready,

    // --- Output Path 0 (Normal Processing) ---
    output logic [DATA_WIDTH-1:0]  m_axis0_tdata,
    output logic                   m_axis0_tvalid,
    output logic                   m_axis0_tlast,
    output logic [DATA_WIDTH/8-1:0] m_axis0_tkeep,
    input  logic                   m_axis0_tready,

    // --- Output Path 1 (High Priority/Crypto) ---
    output logic [DATA_WIDTH-1:0]  m_axis1_tdata,
    output logic                   m_axis1_tvalid,
    output logic                   m_axis1_tlast,
    output logic [DATA_WIDTH/8-1:0] m_axis1_tkeep,
    input  logic                   m_axis1_tready,

    // --- Dispatcher Mode Control ---
    input  logic [1:0]            disp_mode  // 0: tuser-based, 1: round-robin, 2: priority
);

    // ========================================================
    // 模式定义
    // ========================================================
    typedef enum logic [1:0] {
        MODE_TUSER = 2'b00,  // 基于tuser分发
        MODE_RR   = 2'b01,  // 轮询分发
        MODE_PRIO = 2'b10   // 优先级分发（path1优先）
    } mode_t;
    mode_t current_mode;

    // ========================================================
    // 内部信号
    // ========================================================
    logic [1:0] rr_ptr;         // 轮询指针
    logic       path0_select;    // 选择path0
    logic       path1_select;    // 选择path1

    // ========================================================
    // 模式转换
    // ========================================================
    assign current_mode = mode_t'(disp_mode);

    // ========================================================
    // 分发逻辑
    // ========================================================
    always_comb begin
        path0_select = 1'b0;
        path1_select = 1'b0;

        case (current_mode)
            MODE_TUSER: begin
                // tuser=0 -> path0, tuser=1 -> path1
                path0_select = (s_axis_tuser == 1'b0);
                path1_select = (s_axis_tuser == 1'b1);
            end

            MODE_RR: begin
                // 轮询分发
                path0_select = (rr_ptr == 2'b00);
                path1_select = (rr_ptr == 2'b01);
            end

            MODE_PRIO: begin
                // 优先级分发：path1（高优先级/Crypto）优先
                path1_select = m_axis1_tready;
                path0_select = (!path1_select) && m_axis0_tready;
            end

            default: begin
                path0_select = 1'b1;
                path1_select = 1'b0;
            end
        endcase
    end

    // ========================================================
    // 轮询指针更新
    // ========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr <= 2'b00;
        end else if (s_axis_tvalid && s_axis_tlast && s_axis_tready) begin
            if (current_mode == MODE_RR) begin
                rr_ptr <= rr_ptr + 1'b1;
            end
        end
    end

    // ========================================================
    // AXI-Stream输出连接
    // ========================================================
    always_comb begin
        // 默认值
        m_axis0_tdata  = s_axis_tdata;
        m_axis0_tvalid = 1'b0;
        m_axis0_tlast  = s_axis_tlast;
        m_axis0_tkeep  = s_axis_tkeep;

        m_axis1_tdata  = s_axis_tdata;
        m_axis1_tvalid = 1'b0;
        m_axis1_tlast  = s_axis_tlast;
        m_axis1_tkeep  = s_axis_tkeep;

        // 根据选择分发数据
        if (s_axis_tvalid) begin
            if (path0_select) begin
                m_axis0_tvalid = 1'b1;
            end
            if (path1_select) begin
                m_axis1_tvalid = 1'b1;
            end
        end
    end

    // ========================================================
    // 反压逻辑 (Backpressure)
    // ========================================================
    always_comb begin
        s_axis_tready = 1'b0;

        case (current_mode)
            MODE_TUSER: begin
                // tuser模式：只有选中的路径ready才接受数据
                if (path0_select) begin
                    s_axis_tready = m_axis0_tready;
                end else if (path1_select) begin
                    s_axis_tready = m_axis1_tready;
                end
            end

            MODE_RR: begin
                // 轮询模式：任一路径ready就接受
                s_axis_tready = m_axis0_tready || m_axis1_tready;
            end

            MODE_PRIO: begin
                // 优先级模式：高优先级ready就接受，否则低优先级ready也接受
                s_axis_tready = m_axis1_tready || m_axis0_tready;
            end

            default: begin
                s_axis_tready = m_axis0_tready;
            end
        endcase
    end

endmodule
