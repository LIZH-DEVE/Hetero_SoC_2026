`timescale 1ns / 1ps

/**
 * 模块名称: crypto_engine
 * 版本: Day06_Final_Gold (双核物理适配版)
 * 描述: 
 * 集成 AES (Secworks) 和 SM4 (Raymond) 算法引擎，支持 CBC 模式。
 * [Status] 接口已根据 .v 源码进行物理级对齐，消除所有 connection error。
 */

module crypto_engine (
    input  logic           clk,
    input  logic           rst_n,
    
    // 控制接口
    input  logic           algo_sel, // 0:AES, 1:SM4
    input  logic           start,    // 启动当前 block 计算
    output logic           done,     // 当前 block 计算完成
    output logic           busy,     // 引擎忙状态
    
    // 数据接口
    input  logic [127:0]   key,      // 密钥
    input  logic [127:0]   din,      // 明文输入 (Plaintext)
    output logic [127:0]   dout      // 密文输出 (Ciphertext)
);

    // ========================================================
    // 1. CBC 模式逻辑 (Cipher Block Chaining)
    // ========================================================
    logic [127:0] r_iv;           
    logic [127:0] w_core_din;     
    logic [127:0] w_aes_dout;
    logic [127:0] w_sm4_dout;
    logic [127:0] w_result_mux;   
    
    // 内部完成信号
    logic aes_done;
    logic sm4_done;

    // CBC 异或：输入数据 ^ 上一轮密文(IV)
    assign w_core_din = din ^ r_iv; 

    // ========================================================
    // 2. 算法引擎实例化 (Algorithm Engines)
    // ========================================================
    
    // --------------------------------------------------------
    // Engine 1: AES Core (Secworks)
    // --------------------------------------------------------
    aes_core u_aes_core (
        .clk          (clk),
        .reset_n      (rst_n),
        
        // 配置信号 (固定为加密, 128位key)
        .encdec       (1'b1),        
        .keylen       (1'b0),        
        
        // 控制信号
        .init         (1'b0),        
        .next         (start),       
        .ready        (),            
        
        // 数据信号
        .key          ({128'd0, key}), // 补零至256位
        .block        (w_core_din),    
        .result       (w_aes_dout),    
        .result_valid (aes_done)       
    );

    // --------------------------------------------------------
    // Engine 2: SM4 Core (Raymond Rui Chen)
    // --------------------------------------------------------
    sm4_top u_sm4_core (
        .clk               (clk),
        .reset_n           (rst_n),
        
        // 使能控制 (全部拉高以激活核心)
        .sm4_enable_in     (1'b1),   
        .encdec_enable_in  (1'b1),   
        .enable_key_exp_in (1'b1),   // 启用密钥扩展
        
        // 模式选择 (0: Encrypt, 1: Decrypt)
        .encdec_sel_in     (1'b0),   // 固定为加密
        
        // 数据与控制
        .valid_in          (start),       // 启动脉冲
        .data_in           (w_core_din),  // 输入数据
        .user_key_in       (key),         // 密钥
        .user_key_valid_in (1'b1),        // 密钥有效指示
        
        // 输出
        .result_out        (w_sm4_dout),  
        .ready_out         (sm4_done),    // 完成/就绪信号
        .key_exp_ready_out ()             // 忽略密钥扩展完成信号
    );

    // ========================================================
    // 3. 结果输出与 IV 更新
    // ========================================================
    
    // 结果多路复用
    assign w_result_mux = (algo_sel == 1'b1) ? w_sm4_dout : w_aes_dout;
    assign done         = (algo_sel == 1'b1) ? sm4_done   : aes_done;

    // 输出驱动
    assign dout = w_result_mux;

    // IV 更新逻辑
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
                r_iv <= w_result_mux; // 锁存密文作为下一次的 IV
            end
        end
    end

endmodule