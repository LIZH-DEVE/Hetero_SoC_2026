`timescale 1ns / 1ps

module tb_gearbox_check();

    logic clk, rst_n;
    
    // 输入 (128-bit)
    logic [127:0] din;
    logic         din_valid;
    logic         din_ready; // DUT 输出

    // 输出 (32-bit)
    logic [31:0]  dout;
    logic         dout_valid; // DUT 输出
    logic         dout_ready;

    // 实例化你的模块 (使用你现在的 gearbox_128_to_32.sv)
    gearbox_128_to_32 u_dut (
        .clk(clk), .rst_n(rst_n),
        .din(din), .din_valid(din_valid), .din_ready(din_ready),
        .dout(dout), .dout_valid(dout_valid), .dout_ready(dout_ready)
    );

    // 时钟生成
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $display("\n=== Gearbox Endianness Test ===");
        
        // 1. 初始化
        rst_n = 0; din = 0; din_valid = 0; dout_ready = 1; // 下游总是准备好
        #20 rst_n = 1;
        #10;

        // 2. 构造特征数据
        // 高位是 11...11，低位是 44...44
        din = 128'h11111111_22222222_33333333_44444444; 
        
        $display("Input 128-bit: %h", din);
        $display("Expected Order (Big Endian): 11... -> 22... -> 33... -> 44...");
        $display("---------------------------------------------------------");

        // 3. 发送数据
        @(posedge clk);
        din_valid = 1;
        
        // 4. 等待 DUT 接收
        wait(din_ready); 
        @(posedge clk); // 数据进入 DUT
        din_valid = 0;  // 撤销输入

        // 5. 监测输出流 (连续观察 4 拍)
        repeat(5) @(posedge clk);
        
        $display("=== Test Finished ===\n");
        $finish;
    end

    // 自动打印输出结果
    always @(posedge clk) begin
        if (dout_valid && dout_ready) begin
            $display("[Output Monitor] Received 32-bit: %h", dout);
        end
    end

endmodule