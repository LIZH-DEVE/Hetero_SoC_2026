`timescale 1ns / 1ps

module crypto_bridge_top (
    input  logic        clk,
    input  logic        rst_n,

    // --- Control Interface ---
    input  logic        i_algo_sel,   // 0: AES, 1: SM4
    input  logic [127:0] i_key,        // 128-bit Root Key
    output logic        o_system_ready, // 系统初始化完成指示

    // --- PBM Interface (Slave: Pull Mode) ---
    input  logic [31:0] i_pbm_data,
    input  logic        i_pbm_empty,
    output logic        o_pbm_rd_en,

    // --- TX Interface (Master: Pull Mode) ---
    output logic [31:0] o_tx_data,
    output logic        o_tx_empty,
    input  logic        i_tx_rd_en
);

    // =========================================================
    // 1. 内部信号定义
    // =========================================================
    
    // 输入拼包逻辑
    logic [127:0] plaintext_reg;
    logic [1:0]   word_cnt;
    
    // 核心输出
    logic [127:0] ciphertext_selected;
    logic         ciphertext_valid;

    // --- AES Signals ---
    logic         aes_init;
    logic         aes_next;
    logic         aes_ready;
    logic         aes_result_valid;
    logic [127:0] aes_result;

    // --- SM4 Signals ---
    logic         sm4_key_exp_en;
    logic         sm4_valid_in;
    logic         sm4_ready_out;
    logic         sm4_key_ready;
    logic [127:0] sm4_result;
    
    // --- Intermediate FIFO (128-bit) Signals ---
    logic         mid_fifo_wr_en;
    logic [127:0] mid_fifo_din;
    logic         mid_fifo_full;
    logic         mid_fifo_empty;
    logic         mid_fifo_rd_en;
    logic [127:0] mid_fifo_dout;

    // --- Gearbox Interface ---
    logic         gb_din_valid;
    logic         gb_din_ready;
    logic [31:0]  gb_dout;
    logic         gb_dout_valid;
    logic         gb_dout_last;
    logic         gb_dout_ready;

    // --- Output FIFO (32-bit) Signals ---
    logic         out_fifo_full;

    // =========================================================
    // 2. 状态机：输入拼包与核心调度
    // =========================================================
    typedef enum logic [3:0] {
        RESET,
        INIT_KEYS,      // 触发密钥扩展
        WAIT_KEYS,      // 等待扩展完成
        IDLE,           // 等待 PBM 数据
        LOAD_PBM,       // 读取 4 个字
        START_ENC,      // 启动加密核
        WAIT_CORE,      // 等待计算完成
        PUSH_MID_FIFO   // 写入中间 FIFO
    } state_t;

    state_t state, next_state;

    // 状态机时序逻辑
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= RESET;
        else state <= next_state;
    end

    // 移位寄存器 (32 -> 128 Big Endian)
    always_ff @(posedge clk) begin
        if (state == LOAD_PBM && !i_pbm_empty) begin
            // 新数据进低位 (符合网络字节序)
            plaintext_reg <= {plaintext_reg[95:0], i_pbm_data};
        end
    end

    // 计数器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) word_cnt <= 0;
        else if (state == LOAD_PBM && !i_pbm_empty) word_cnt <= word_cnt + 1;
        else if (state == IDLE) word_cnt <= 0;
    end

    // 组合逻辑状态转移
    always_comb begin
        next_state = state;
        o_pbm_rd_en = 0;
        aes_init = 0;
        aes_next = 0;
        sm4_key_exp_en = 0;
        sm4_valid_in = 0;
        mid_fifo_wr_en = 0;

        case (state)
            RESET: next_state = INIT_KEYS;

            INIT_KEYS: begin
                aes_init = 1;       // 触发 AES Init
                sm4_key_exp_en = 1; // 触发 SM4 Init
                next_state = WAIT_KEYS;
            end

            WAIT_KEYS: begin
                // 只等待当前选择的算法完成初始化
                if (i_algo_sel == 0) begin
                    // AES 模式：只等待 AES 就绪
                    if (aes_ready) next_state = IDLE;
                end else begin
                    // SM4 模式：等待密钥扩展完成 + ready_out 拉高
                    if (sm4_key_ready && sm4_ready_out) next_state = IDLE;
                end
            end

            IDLE: begin
                // 只有当中简 FIFO 不满，且 PBM 有数据时才开始工作
                if (!i_pbm_empty && !mid_fifo_full)
                    next_state = LOAD_PBM;
            end

            LOAD_PBM: begin
                if (!i_pbm_empty) begin
                    o_pbm_rd_en = 1;
                    if (word_cnt == 3) // 读够 4 个字
                        next_state = START_ENC;
                end
            end

            START_ENC: begin
                if (i_algo_sel == 0) begin
                    // AES 路径
                    if (aes_ready) begin
                        aes_next = 1;
                        next_state = WAIT_CORE;
                    end
                end else begin
                    // SM4 路径
                    if (sm4_ready_out) begin
                        sm4_valid_in = 1;
                        next_state = WAIT_CORE;
                    end
                end
            end

            WAIT_CORE: begin
                if (i_algo_sel == 0) begin
                    if (aes_result_valid) next_state = PUSH_MID_FIFO;
                end else begin
                    // SM4 的时序：需要保持 valid_in = 1 直到 ready_out = 1
                    sm4_valid_in = 1;
                    if (sm4_ready_out) next_state = PUSH_MID_FIFO;
                end
            end

            PUSH_MID_FIFO: begin
                if (!mid_fifo_full) begin
                    mid_fifo_wr_en = 1;
                    next_state = IDLE;
                end
            end
        endcase
    end

    // 核心输出选择
    assign mid_fifo_din = (i_algo_sel == 0) ? aes_result : sm4_result;
    
    // 系统就绪信号
    assign o_system_ready = (state != RESET && state != INIT_KEYS && state != WAIT_KEYS);


    // =========================================================
    // 3. 核心实例化 (Real Cores)
    // =========================================================

    // --- AES Core ---
    aes_core u_aes (
        .clk(clk),
        .reset_n(rst_n),
        .encdec(1'b1),        // 1: Encrypt
        .init(aes_init),
        .next(aes_next),
        .ready(aes_ready),
        .key({128'b0, i_key}), // Pad to 256 bits
        .keylen(1'b0),        // 128-bit key
        .block(plaintext_reg),
        .result(aes_result),
        .result_valid(aes_result_valid)
    );

    // --- SM4 Core ---
    sm4_top u_sm4 (
        .clk(clk),
        .reset_n(rst_n),
        .sm4_enable_in(1'b1),
        .encdec_enable_in(1'b1), // Encrypt
        .encdec_sel_in(1'b0),    // SM4
        .valid_in(sm4_valid_in),
        .data_in(plaintext_reg),
        .enable_key_exp_in(sm4_key_exp_en),
        .user_key_valid_in(sm4_key_exp_en),
        .user_key_in(i_key),
        .key_exp_ready_out(sm4_key_ready),
        .ready_out(sm4_ready_out),
        .result_out(sm4_result)
    );

    // =========================================================
    // 4. 中间缓冲与位宽转换 (Wait -> Gearbox)
    // =========================================================

    // A. 中间 FIFO (128-bit 宽)
    // 作用：缓存加密好的 128-bit 块，适配 Gearbox 的 ready/valid 接口
    sync_fifo #(.WIDTH(128), .DEPTH(4)) u_mid_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(mid_fifo_wr_en),
        .din(mid_fifo_din),
        .full(mid_fifo_full),
        
        .rd_en(mid_fifo_rd_en),
        .dout(mid_fifo_dout),
        .empty(mid_fifo_empty)
    );

    // 适配逻辑：FIFO Read -> Gearbox Valid
    // 只有当 Gearbox 准备好接收 (gb_din_ready) 且 FIFO 不空时，才读 FIFO
    assign mid_fifo_rd_en = !mid_fifo_empty && gb_din_ready;
    assign gb_din_valid   = !mid_fifo_empty; // FIFO 有数据，Valid 就拉高

    // B. 用户提供的 Gearbox (128 -> 32)
    gearbox_128_to_32 u_user_gearbox (
        .clk(clk),
        .rst_n(rst_n),
        
        // Input from Mid-FIFO
        .din(mid_fifo_dout),
        .din_valid(gb_din_valid), // 实际上使用 FIFO empty 取反
        .din_ready(gb_din_ready),
        
        // Output to Out-FIFO
        .dout(gb_dout),
        .dout_valid(gb_dout_valid),
        .dout_last(gb_dout_last),
        .dout_ready(gb_dout_ready)
    );

    // =========================================================
    // 5. 输出缓冲 (Gearbox -> TX Stack)
    // =========================================================

    // C. 输出 FIFO (32-bit 宽)
    // 作用：Gearbox 是 Push 模式 (Valid)，TX Stack 是 Pull 模式 (Rd_en)
    // FIFO 完美解决了这个接口转换
    sync_fifo #(.WIDTH(32), .DEPTH(16)) u_out_fifo (
        .clk(clk),
        .rst_n(rst_n),
        
        // Write Side (from Gearbox)
        .wr_en(gb_dout_valid),
        .din(gb_dout),
        .full(out_fifo_full),
        
        // Read Side (to TX Stack)
        .rd_en(i_tx_rd_en),
        .dout(o_tx_data),
        .empty(o_tx_empty)
    );

    // 反压 Gearbox：如果输出 FIFO 满了，就不让 Gearbox 发数据
    assign gb_dout_ready = !out_fifo_full;

endmodule
