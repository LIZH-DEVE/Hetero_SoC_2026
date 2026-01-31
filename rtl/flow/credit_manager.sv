`timescale 1ns / 1ps

/**
 * Module: credit_manager
 * Description: Credit-based流控管理器
 * Task 6.2: Credit-based Flow Control
 */
module credit_manager #(
    parameter DATA_WIDTH = 32,
    parameter CREDIT_WIDTH = 8,
    parameter MAX_CREDITS = 8'h10  // 默认16个credits
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // --- 上游AXI-Stream接口（输入） ---
    input  logic [DATA_WIDTH-1:0]  s_axis_tdata,
    input  logic                   s_axis_tvalid,
    input  logic                   s_axis_tlast,
    output logic                   s_axis_tready,

    // --- 下游AXI-Stream接口（输出） ---
    output logic [DATA_WIDTH-1:0]  m_axis_tdata,
    output logic                   m_axis_tvalid,
    output logic                   m_axis_tlast,
    input  logic                   m_axis_tready,

    // --- 控制接口---
    input  logic                   i_credit_init,      // 初始化credits
    input  logic [CREDIT_WIDTH-1:0] i_credit_add,       // 增加credits
    input  logic [CREDIT_WIDTH-1:0] i_credit_set,       // 直接设置credits
    input  logic                   i_credit_update,    // 更新信号
    output logic [CREDIT_WIDTH-1:0]  o_credit_avail,     // 可用credits
    output logic                   o_credit_full,      // credit满
    output logic                   o_credit_empty     // credit空
);

    // =========================================================
    // 内部信号
    // =========================================================
    logic [CREDIT_WIDTH-1:0] credits;
    logic data_staged;
    logic [DATA_WIDTH-1:0] staged_data;
    logic staged_last;

    // =========================================================
    // Credit管理
    // =========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            credits <= MAX_CREDITS;
            data_staged <= 1'b0;
            staged_data <= 0;
            staged_last <= 1'b0;
        end else begin
            // Credit初始化
            if (i_credit_init) begin
                credits <= MAX_CREDITS;
            end
            // Credit更新
            else if (i_credit_update) begin
                credits <= i_credit_set;
            end
            // 消耗credit（数据传输给下游）
            else if (m_axis_tvalid && m_axis_tready) begin
                if (credits > 0) begin
                    credits <= credits - 1'b1;
                end
            end
            // 回收credit（接收到下游的反馈）
            else if (i_credit_add > 0) begin
                if (credits < MAX_CREDITS) begin
                    credits <= credits + i_credit_add;
                end
            end
        end
    end

    // =========================================================
    // 数据暂存（当credit为0时）
    // =========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_staged <= 1'b0;
            staged_data <= 0;
            staged_last <= 1'b0;
        end else begin
            // 暂存数据
            if (s_axis_tvalid && s_axis_tready && !m_axis_tvalid && credits > 0) begin
                data_staged <= 1'b1;
                staged_data <= s_axis_tdata;
                staged_last <= s_axis_tlast;
            end
            // 传输数据
            else if (data_staged && m_axis_tready) begin
                data_staged <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 流控逻辑
    // =========================================================================
    always_comb begin
        o_credit_avail = credits;
        o_credit_full = (credits >= MAX_CREDITS);
        o_credit_empty = (credits == 0);
    end

    // 上游反压：没有credit时不接受新数据
    assign s_axis_tready = (credits > 0) ? (m_axis_tready || data_staged) : 1'b0;

    // 下游数据源
    assign m_axis_tdata = data_staged ? staged_data : s_axis_tdata;
    assign m_axis_tvalid = data_staged ? 1'b1 : s_axis_tvalid;
    assign m_axis_tlast = data_staged ? staged_last : s_axis_tlast;

endmodule
