`timescale 1ns / 1ps

/**
 * 模块名称: tb_crypto_engine
 * 版本: Day 07 稳健版
 * 描述: 模拟 CPU 行为，验证 Dispatcher 是否能正确分发 AES 和 SM4 任务
 */

module tb_crypto_engine();

    // 1. 信号定义
    logic           clk;
    logic           rst_n;
    logic           algo_sel;
    logic           start;
    logic           done;
    logic           busy;
    logic [127:0]   key;
    logic [127:0]   din;
    logic [127:0]   dout;

    // 2. 实例化被测模块 (DUT) - 显式连接
    crypto_engine u_dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .algo_sel (algo_sel),
        .start    (start),
        .done     (done),
        .busy     (busy),
        .key      (key),
        .din      (din),
        .dout     (dout)
    );

    // 3. 时钟产生 (100MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // 4. 自动化激励
    initial begin
        // 初始化
        rst_n = 0;
        start = 0;
        algo_sel = 0;
        key = 128'h2b7e151628aed2a6abf7158809cf4f3c; 
        din = 128'h6bc1bee22e409f96e93d7e117393172a;

        $display("\n[DAY 07] 开始双核分发器仿真验证...");

        // 复位
        #100 rst_n = 1;
        #20;

        // --- 场景 1: 测试 AES (algo_sel = 0) ---
        $display("[TIME: %t] -> 切换至 AES 模式", $time);
        algo_sel = 0; 
        @(posedge clk); start = 1; @(posedge clk); start = 0;
        
        wait(done); 
        $display("[TIME: %t] -> [成功] AES 输出: %h", $time, dout);
        #100;

        // --- 场景 2: 测试 SM4 (algo_sel = 1) ---
        $display("[TIME: %t] -> 切换至 SM4 模式", $time);
        algo_sel = 1; 
        @(posedge clk); start = 1; @(posedge clk); start = 0;
        
        wait(done); 
        $display("[TIME: %t] -> [成功] SM4 输出: %h", $time, dout);

        #100;
        $display("[DAY 07] 所有分发测试已完成！\n");
        $finish;
    end

endmodule