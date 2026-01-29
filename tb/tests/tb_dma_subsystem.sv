`timescale 1ns / 1ps

module tb_dma_subsystem();

    // 信号定义 (与之前一致)
    logic clk, rst_n;
    // ... AXI-Lite 信号 ...
    // ... AXI Master 信号 ...

    // [Day 9] MAC 模拟信号
    logic [31:0] rx_tdata;
    logic        rx_tvalid, rx_tlast, rx_tuser, rx_tready;

    // 实例化 DUT
    dma_subsystem dut (
        .clk(clk), .rst_n(rst_n),
        // ... AXI 接口连线 ...
        .rx_axis_tdata(rx_tdata),
        .rx_axis_tvalid(rx_tvalid),
        .rx_axis_tlast(rx_tlast),
        .rx_axis_tuser(rx_tuser),
        .rx_axis_tready(rx_tready)
    );

    // 时钟生成
    initial clk = 0;
    always #5 clk = ~clk;

    // ==========================================================
    // Task: 模拟 MAC 发送一个标准的 UDP 包 (14B Eth + 20B IP + 8B UDP + Data)
    // ==========================================================
    task send_udp_packet(input logic [15:0] ip_len, input logic [15:0] udp_len, input logic trigger_error);
        begin
            @(posedge clk);
            // --- [Word 0-2] Ethernet Header (Destination/Source MAC) ---
            rx_tvalid = 1; rx_tdata = 32'h11223344; rx_tlast = 0; @(posedge clk);
            rx_tdata = 32'h55667788; @(posedge clk);
            rx_tdata = 32'h99AA0800; // Type = 0x0800 (IPv4)
            @(posedge clk);

            // --- [Word 3-7] IP Header ---
            rx_tdata = {16'h4500, ip_len}; // Version, IHL, TOS, Total Len
            @(posedge clk);
            rx_tdata = 32'h00010000; // ID, Flags, Frag
            @(posedge clk);
            rx_tdata = 32'h40110000; // TTL, Protocol(UDP=0x11), Checksum
            @(posedge clk);
            rx_tdata = 32'hC0A80101; // Source IP
            @(posedge clk);
            rx_tdata = 32'hC0A80102; // Dest IP
            @(posedge clk);

            // --- [Word 8-9] UDP Header ---
            rx_tdata = 32'h1F401F40; // Src Port, Dest Port
            @(posedge clk);
            rx_tdata = {udp_len, 16'h0000}; // UDP Len, Checksum
            @(posedge clk);

            // --- [Word 10+] Payload ---
            rx_tdata = 32'hDEADBEEF;
            rx_tlast = 1;
            rx_tuser = trigger_error; // 如果 trigger_error=1，模拟 MAC 校验错
            @(posedge clk);
            
            rx_tvalid = 0; rx_tlast = 0; rx_tuser = 0;
            $display("[MAC] Packet sent: IP_Len=%d, UDP_Len=%d, Error=%b", ip_len, udp_len, trigger_error);
        end
    endtask

    initial begin
        // 初始化信号
        rst_n = 0; rx_tdata = 0; rx_tvalid = 0; rx_tlast = 0; rx_tuser = 0;
        // ... 初始化 AXI 读写通道 ...

        #100 rst_n = 1;
        #50;

        $display("\n=== Day 9 Protocol Parsing Test Start ===");

        // --- TEST 1: 发送一个标准的【好包】 ---
        // IP Total Len = 48 (20 IP + 8 UDP + 20 Data), UDP Len = 28 (8 UDP + 20 Data)
        // 注意：我们的代码里 ip_total_len 应该比 udp_len 大 20
        send_udp_packet(16'd48, 16'd28, 0);
        
        repeat(50) @(posedge clk);

        // --- TEST 2: 发送一个【长度不匹配的坏包】 ---
        // IP 报 48，UDP 报 100 -> 触发 Task 8.2 的逻辑回滚
        send_udp_packet(16'd48, 16'd100, 0);

        repeat(50) @(posedge clk);
        $display("=== Day 9 Test Finished ===");
        $stop;
    end
endmodule