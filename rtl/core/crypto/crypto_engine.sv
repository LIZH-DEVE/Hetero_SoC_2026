`timescale 1ns / 1ps

/**
 * Module: crypto_engine
 * Version: Day 07 - Optimized V2 (Low Power & Robust)
 * 描述: 集成 ACL 计数器与硬件拦截，增加操作数隔离与边沿启动检测。
 */

module crypto_engine (
    input  logic           clk,
    input  logic           rst_n,
    
    // --- 控制接口 ---
    input  logic           algo_sel,    // 0:AES, 1:SM4
    input  logic           start,       // 外部启动信号
    input  logic [31:0]    i_total_len, // 输入包总长度
    output logic           done,        // 统一完成信号 (Pulse)
    output logic           busy,        // 引擎忙状态
    
    // --- CSR 接口 (AXI-Lite) ---
    input  logic [7:0]     s_axil_araddr, 
    output logic [31:0]    s_axil_rdata,

    // --- 数据接口 ---
    input  logic [127:0]   key,      
    input  logic [127:0]   din,      
    output logic [127:0]   dout      
);

    // ========================================================
    // 1. 信号预处理与安全检查
    // ========================================================
    
    // [优化] Start 边沿检测：防止 Level 信号导致误触发
    logic start_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) start_r <= 1'b0;
        else        start_r <= start;
    end
    wire start_pulse = start && !start_r; // 上升沿有效

    // 对齐检查 (128-bit alignment)
    wire is_aligned = (i_total_len[3:0] == 4'd0);

    // 启动判定：(上升沿) && (对齐) && (不忙)
    wire valid_trigger = start_pulse && is_aligned && !busy;

    // ========================================================
    // 2. ACL 错误计数器 (CSR)
    // ========================================================
    reg [31:0] acl_err_cnt; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acl_err_cnt <= 32'd0;
        end else begin
            // 只要有启动意图但不对齐，即视为非法，计入 log
            if (start_pulse && !is_aligned) begin
                acl_err_cnt <= acl_err_cnt + 1;
            end
        end
    end

    // CSR 读取逻辑
    always_comb begin
        case (s_axil_araddr)
            8'h10:   s_axil_rdata = {31'd0, algo_sel}; // 状态/配置回读
            8'h44:   s_axil_rdata = acl_err_cnt;       // 错误计数
            default: s_axil_rdata = 32'd0;
        endcase
    end

    // ========================================================
    // 3. 数据通路与操作数隔离 (Low Power Technique)
    // ========================================================
    logic [127:0] r_iv;
    logic [127:0] w_core_din;
    
    // CBC 模式异或
    assign w_core_din = din ^ r_iv;

    // [优化] 操作数隔离：未被选中的核输入强制为 0
    // 防止未选中的 IP 内部逻辑无效翻转，降低动态功耗
    logic [127:0] aes_din_gated, sm4_din_gated;
    logic         aes_start_gated, sm4_start_gated;

    assign aes_din_gated   = (algo_sel == 1'b0) ? w_core_din : 128'd0;
    assign sm4_din_gated   = (algo_sel == 1'b1) ? w_core_din : 128'd0;
    
    // 只有选中的算法且满足触发条件时，才拉高对应的 start
    assign aes_start_gated = (algo_sel == 1'b0) ? valid_trigger : 1'b0;
    assign sm4_start_gated = (algo_sel == 1'b1) ? valid_trigger : 1'b0;

    // ========================================================
    // 4. 加密核实例化
    // ========================================================
    logic [127:0] w_aes_dout, w_sm4_dout;
    logic         aes_done, sm4_done;

    // AES Core
    aes_core u_aes_core (
        .clk        (clk), 
        .reset_n    (rst_n),
        .encdec     (1'b1),        // 固定为加密
        .keylen     (1'b0),        // 128-bit key
        .init       (1'b0),        // 假设不需要每次重置 key expansion
        .next       (aes_start_gated), 
        .ready      (),            // 不使用 ready，统一用 done
        .key        ({128'd0, key}), 
        .block      (aes_din_gated), // 使用隔离后的数据
        .result     (w_aes_dout), 
        .result_valid(aes_done)
    );

    // SM4 Core
    sm4_top u_sm4_core (
        .clk               (clk), 
        .reset_n           (rst_n),
        .sm4_enable_in     (1'b1), 
        .encdec_enable_in  (1'b1), 
        .enable_key_exp_in (1'b1),
        .encdec_sel_in     (1'b0), // 0: Encrypt
        .valid_in          (sm4_start_gated), 
        .data_in           (sm4_din_gated), // 使用隔离后的数据
        .user_key_in       (key), 
        .user_key_valid_in (1'b1), // Key 始终有效
        .result_out        (w_sm4_dout), 
        .ready_out         (sm4_done), 
        .key_exp_ready_out ()
    );

    // ========================================================
    // 5. 状态维护与输出逻辑
    // ========================================================
    
    // 汇总 Done 信号 (Pulse)
    // 这是一个关键路径，如果时序紧张，可以在此处打拍，但需注意握手延迟
    assign done = (algo_sel == 1'b1) ? sm4_done : aes_done;
    
    // 数据输出选择
    assign dout = (algo_sel == 1'b1) ? w_sm4_dout : w_aes_dout;

    // 忙状态与 IV 更新状态机
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_iv <= 128'd0;
            busy <= 1'b0;
        end else begin
            if (valid_trigger) begin
                busy <= 1'b1;  // 进入计算状态
            end else if (done) begin
                busy <= 1'b0;  // 计算完成
                
                // CBC IV 更新：当前密文即为下一块的 IV
                // 注意：这里利用 done 脉冲同步更新，确保 IV 在下一块数据到来前准备好
                r_iv <= (algo_sel == 1'b1) ? w_sm4_dout : w_aes_dout;
            end
        end
    end

endmodule