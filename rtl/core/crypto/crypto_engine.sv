`timescale 1ns / 1ps

/**
 * 模块名称: crypto_engine
 * 版本: Day 07 - Dispatcher Architecture
 * 描述: [Task 6.1] 实现基于 algo_sel 的双核硬件分发。
 */

module crypto_engine (
    input  logic           clk,
    input  logic           rst_n,
    
    // 控制接口
    input  logic           algo_sel, // 0:AES, 1:SM4
    input  logic           start,    // 外部启动脉冲
    output logic           done,     // 统一完成信号
    output logic           busy,     // 引擎忙状态
    
    // 数据接口
    input  logic [127:0]   key,      
    input  logic [127:0]   din,      
    output logic [127:0]   dout      
);

    // 内部连接信号
    logic [127:0] w_core_din;     
    logic [127:0] w_aes_dout;
    logic [127:0] w_sm4_dout;
    logic         aes_done, sm4_done;
    logic [127:0] r_iv;

    // CBC 异或逻辑 [cite: 52, 53]
    assign w_core_din = din ^ r_iv; 

    // ========================================================
    // [Task 6.1] Dispatcher 逻辑：控制信号分发
    // ========================================================
    logic aes_start, sm4_start;
    assign aes_start = (algo_sel == 1'b0) ? start : 1'b0;
    assign sm4_start = (algo_sel == 1'b1) ? start : 1'b0;

    // --------------------------------------------------------
    // Engine 1: AES Core (Secworks)
    // --------------------------------------------------------
    aes_core u_aes_core (
        .clk(clk), .reset_n(rst_n),
        .encdec(1'b1), .keylen(1'b0), .init(1'b0),
        .next(aes_start), // 仅接收分发后的信号
        .ready(),
        .key({128'd0, key}), .block(w_core_din),
        .result(w_aes_dout), .result_valid(aes_done)
    );

    // --------------------------------------------------------
    // Engine 2: SM4 Core (Raymond)
    // --------------------------------------------------------
    sm4_top u_sm4_core (
        .clk(clk), .reset_n(rst_n),
        .sm4_enable_in(1'b1), .encdec_enable_in(1'b1), .enable_key_exp_in(1'b1),
        .encdec_sel_in(1'b0),
        .valid_in(sm4_start), // 仅接收分发后的信号
        .data_in(w_core_din), .user_key_in(key), .user_key_valid_in(1'b1),
        .result_out(w_sm4_dout), .ready_out(sm4_done), .key_exp_ready_out()
    );

    // ========================================================
    // [Task 6.2] Result Mux & Flow Control
    // ========================================================
    // 根据选择输出对应的数据和完成脉冲
    assign dout = (algo_sel == 1'b1) ? w_sm4_dout : w_aes_dout;
    assign done = (algo_sel == 1'b1) ? sm4_done   : aes_done;

    // 状态监测
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_iv <= 128'd0;
            busy <= 1'b0;
        end else begin
            if (start) 
                busy <= 1'b1;
            else if (done) 
                busy <= 1'b0;

            if (done) begin
                r_iv <= (algo_sel == 1'b1) ? w_sm4_dout : w_aes_dout;
            end
        end
    end

endmodule