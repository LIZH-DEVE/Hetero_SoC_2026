`timescale 1ns / 1ps

module crypto_engine (
    input  logic           clk,
    input  logic           rst_n,
    input  logic           algo_sel, // 0:AES, 1:SM4
    input  logic           start,
    output logic           done,
    output logic           busy,
    input  logic [127:0]   key,
    input  logic [127:0]   din,
    output logic [127:0]   dout
);

    // ==========================================================
    // 1. AES 部分 (保持原样，无需变动)
    // ==========================================================
    typedef enum logic [2:0] { AES_IDLE, AES_HOLD_INIT, AES_WAIT_KEY_DONE, AES_HOLD_NEXT, AES_WAIT_RESULT } aes_fsm_t;
    aes_fsm_t aes_state;
    logic aes_init_sig, aes_next_sig, aes_ready, aes_res_valid;
    logic [127:0] aes_res;

    // AES FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aes_state <= AES_IDLE; aes_init_sig <= 0; aes_next_sig <= 0;
        end else begin
            case (aes_state)
                AES_IDLE: begin aes_init_sig<=0; aes_next_sig<=0; if(start && !algo_sel) begin aes_init_sig<=1; aes_state<=AES_HOLD_INIT; end end
                AES_HOLD_INIT: begin aes_init_sig<=1; if(!aes_ready) begin aes_init_sig<=0; aes_state<=AES_WAIT_KEY_DONE; end end
                AES_WAIT_KEY_DONE: begin if(aes_ready) begin aes_next_sig<=1; aes_state<=AES_HOLD_NEXT; end end
                AES_HOLD_NEXT: begin aes_next_sig<=1; if(!aes_ready) begin aes_next_sig<=0; aes_state<=AES_WAIT_RESULT; end end
                AES_WAIT_RESULT: begin if(aes_res_valid) aes_state<=AES_IDLE; end
                default: aes_state <= AES_IDLE;
            endcase
        end
    end

    aes_core u_aes_core (
        .clk(clk), .reset_n(rst_n), .encdec(1'b1), .init(aes_init_sig), .next(aes_next_sig), .ready(aes_ready),
        .key({key, 128'b0}), .keylen(1'b0), .block(din), .result(aes_res), .result_valid(aes_res_valid)
    );

    // ==========================================================
    // 2. SM4 部分 (已修正：精确匹配 sm4_top 端口)
    // ==========================================================
    
    logic [127:0] sm4_dout_wire;
    logic         sm4_ready_out; // 对应 result_out 有效
    logic         sm4_key_exp_ready;
    
    // 信号预处理
    logic sm4_active;
    assign sm4_active = (algo_sel == 1'b0); // 选中 SM4

    sm4_top u_sm4_opensource (
        .clk                (clk),
        .reset_n            (rst_n),              // 对应 sm4_top 的 reset_n
        
        // 模块使能控制
        .sm4_enable_in      (sm4_active),         // 总使能
        .encdec_enable_in   (sm4_active),         // 加解密引擎使能
        .encdec_sel_in      (1'b0),               // 0: 加密, 1: 解密 (通常0为加密，若跑反了改这里)
        .enable_key_exp_in  (sm4_active),         // 密钥扩展使能
        
        // 数据与握手
        .valid_in           (start && sm4_active),// 数据有效脉冲
        .data_in            (din),                // 输入数据
        
        // 密钥与握手
        .user_key_valid_in  (start && sm4_active),// 密钥有效脉冲 (每次start都重新载入密钥)
        .user_key_in        (key),                // 输入密钥
        
        // 输出
        .key_exp_ready_out  (sm4_key_exp_ready),  // 密钥扩展完成标志 (可悬空或用于调试)
        .ready_out          (sm4_ready_out),      // 计算完成标志 (Result Valid)
        .result_out         (sm4_dout_wire)       // 计算结果
    );

    // Busy 信号逻辑
    // 当收到 start 且选种 SM4 时变忙，直到收到 ready_out 变闲
    reg sm4_busy_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) 
            sm4_busy_reg <= 1'b0;
        else if(start && sm4_active) 
            sm4_busy_reg <= 1'b1;
        else if(sm4_ready_out) 
            sm4_busy_reg <= 1'b0;
    end

    // ==========================================================
    // 3. 输出多路选择
    // ==========================================================
    assign done = (algo_sel == 1'b1) ? sm4_ready_out : aes_res_valid;
    assign dout = (algo_sel == 1'b1) ? sm4_dout_wire : aes_res;
    assign busy = (algo_sel == 1'b1) ? sm4_busy_reg  : (aes_state != AES_IDLE);

endmodule