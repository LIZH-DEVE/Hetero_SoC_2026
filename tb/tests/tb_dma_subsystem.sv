`timescale 1ns / 1ps

module tb_dma_subsystem();

    // =========================================================
    // 0. 参数定义
    // =========================================================
    parameter CLK_PERIOD = 10;
    parameter TIMEOUT_CYCLES = 10000;

    // =========================================================
    // 1. 信号定义
    // =========================================================
    bit clk; // 使用 bit 避免 x 态
    bit rst_n;

    // --- AXI-Lite CSR Interface ---
    logic [31:0] s_axil_awaddr;
    logic        s_axil_awvalid;
    logic        s_axil_awready;
    logic [31:0] s_axil_wdata;
    logic [3:0]  s_axil_wstrb;
    logic        s_axil_wvalid;
    logic        s_axil_wready;
    logic [1:0]  s_axil_bresp;
    logic        s_axil_bvalid;
    logic        s_axil_bready;
    logic [31:0] s_axil_araddr;
    logic        s_axil_arvalid;
    logic        s_axil_arready;
    logic [31:0] s_axil_rdata;
    logic        s_axil_rvalid;
    logic        s_axil_rready;

    // --- DMA AXI Master Interface (Tie-off) ---
    // 为了代码整洁，未使用的输出可以不声明 wire，直接在实例化时 .port() 留空
    // 这里仅声明需要驱动的输入
    logic        m_axi_awready;
    logic        m_axi_wready;
    logic        m_axi_bvalid;
    logic        m_axi_arready;
    logic        m_axi_rlast;
    logic        m_axi_rvalid;

    // --- RX / TX Interface ---
    logic [31:0] rx_axis_tdata;
    logic        rx_axis_tvalid;
    logic        rx_axis_tlast;
    logic        rx_axis_tuser;
    logic        rx_axis_tready;

    logic [31:0] tx_axis_tdata;
    logic        tx_axis_tvalid;
    logic        tx_axis_tlast;
    logic [3:0]  tx_axis_tkeep;
    logic        tx_axis_tready;

    // --- Display ---
    logic [3:0]  o_seven_seg_an;
    logic [7:0]  o_seven_seg_seg;

    // =========================================================
    // 2. DUT 实例化
    // =========================================================
    dma_subsystem dut (
        .clk(clk),
        .rst_n(rst_n),
        
        // CSR
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        
        // DMA Master (Dummy Slave)
        .m_axi_awaddr(), .m_axi_awlen(), .m_axi_awsize(), .m_axi_awburst(),
        .m_axi_awvalid(), .m_axi_awready(1'b1), // Always Ready
        .m_axi_wdata(), .m_axi_wlast(), .m_axi_wvalid(), .m_axi_wready(1'b1), // Always Ready
        .m_axi_bvalid(1'b1), .m_axi_bready(), .m_axi_bresp(2'b00), // OKAY Response
        .m_axi_araddr(), .m_axi_arlen(), .m_axi_arsize(), .m_axi_arburst(), .m_axi_arvalid(), .m_axi_arready(1'b1),
        .m_axi_rdata(32'd0), .m_axi_rresp(2'b00), .m_axi_rlast(1'b1), .m_axi_rvalid(1'b0), .m_axi_rready(),

        // RX
        .rx_axis_tdata(rx_axis_tdata), .rx_axis_tvalid(rx_axis_tvalid), 
        .rx_axis_tlast(rx_axis_tlast), .rx_axis_tuser(rx_axis_tuser), .rx_axis_tready(rx_axis_tready),

        // TX
        .tx_axis_tdata(tx_axis_tdata), .tx_axis_tvalid(tx_axis_tvalid),
        .tx_axis_tlast(tx_axis_tlast), .tx_axis_tkeep(tx_axis_tkeep), .tx_axis_tready(tx_axis_tready),

        // Display
        .o_seven_seg_an(o_seven_seg_an), .o_seven_seg_seg(o_seven_seg_seg)
    );

    // =========================================================
    // 3. 基础驱动 (Tasks & Clocks)
    // =========================================================
    
    // 时钟生成
    always #(CLK_PERIOD/2) clk = ~clk;

    // CSR 写任务 (带超时保护)
    task write_csr(input [31:0] addr, input [31:0] data);
        int timeout;
        begin
            @(posedge clk);
            s_axil_awaddr = addr;
            s_axil_awvalid = 1;
            s_axil_wdata = data;
            s_axil_wvalid = 1;
            s_axil_wstrb = 4'hF;
            s_axil_bready = 1;
            
            // 等待握手 (带超时)
            timeout = 0;
            while((!s_axil_awready || !s_axil_wready) && timeout < 100) begin
                @(posedge clk);
                timeout++;
            end
            if (timeout == 100) begin
                $error("[TB Error] CSR Write Timeout (AW/W Handshake)!");
                $stop;
            end

            @(posedge clk);
            s_axil_awvalid = 0;
            s_axil_wvalid = 0;
            
            // 等待响应 (带超时)
            timeout = 0;
            while(!s_axil_bvalid && timeout < 100) begin
                @(posedge clk);
                timeout++;
            end
            
            @(posedge clk);
            s_axil_bready = 0;
            $display("[TB] CSR Write OK: Addr=0x%h, Data=0x%h", addr, data);
        end
    endtask

    // 优化后的包发送任务 (使用 Queue)
    task send_udp_packet();
        logic [31:0] pkt_queue [$]; // 动态队列
        int i;
        begin
            $display("[TB] Preparing RX Packet...");
            // 构造包内容 (严格对齐协议)
            pkt_queue.push_back(32'hFFFF_FFFF); // Dst MAC Hi
            pkt_queue.push_back(32'hFFFF_000A); // Dst Lo, Src Hi
            pkt_queue.push_back(32'h3500_0102); // Src Lo
            pkt_queue.push_back(32'h0800_4500); // Type=0800 (IPv4), Ver=45
            pkt_queue.push_back(32'h0020_1234); // Len=32
            pkt_queue.push_back(32'h4000_4011); // Proto=UDP
            pkt_queue.push_back(32'h0000_C0A8); // Checksum, SrcIP Hi (192.168...)
            pkt_queue.push_back(32'h0101_C0A8); // SrcIP Lo (.1.1), DstIP Hi
            pkt_queue.push_back(32'h0164_1234); // DstIP Lo, SrcPort
            pkt_queue.push_back(32'h5678_000C); // DstPort, UDPLen
            pkt_queue.push_back(32'hAAAA_BBBB); // Payload

            @(posedge clk);
            rx_axis_tvalid = 1;
            rx_axis_tuser = 0;

            foreach(pkt_queue[i]) begin
                rx_axis_tdata = pkt_queue[i];
                if (i == pkt_queue.size() - 1) rx_axis_tlast = 1;
                else rx_axis_tlast = 0;
                @(posedge clk);
            end

            rx_axis_tvalid = 0;
            rx_axis_tlast = 0;
            $display("[TB] RX Packet Injected (%0d beats).", pkt_queue.size());
        end
    endtask

    // =========================================================
    // 4. 自动化监测器 (Self-Checking Monitor)
    // =========================================================
    // 这个进程会一直盯着 TX 接口，一旦有数据发出就进行检查
    initial begin
        logic [31:0] captured_dst_ip;
        logic [31:0] tx_beat;
        int beat_cnt;
        
        forever begin
            beat_cnt = 0;
            // 等待 TX 启动
            wait(tx_axis_tvalid);
            $display("[TB Monitor] TX Transmission Detected!");

            while(tx_axis_tvalid) begin
                tx_beat = tx_axis_tdata;
                beat_cnt++;
                
                // 检查第 7 和 第 8 个字 (IP Header 部分)
                // TX Output Format:
                // Beat 0,1,2: ETH
                // Beat 3,4,5,6: IP Header Start
                // Beat 7: ... DstIP_Hi
                // Beat 8: DstIP_Lo ...
                
                // 简化的检查逻辑：寻找 Info Swap 结果 (C0A80101)
                // 在 TX Stack 的组包逻辑中，IP 目的地址位于 Beat 7 (低16位) 和 Beat 8 (高16位) 之间
                // 或者更简单：直接在数据流里找特征值
                
                if (tx_beat[15:0] == 16'hC0A8 && beat_cnt == 7) 
                    $display("[TB Check] Found Dst IP Part 1: C0A8 (PASS)");
                
                if (tx_beat[31:16] == 16'h0101 && beat_cnt == 8) 
                    $display("[TB Check] Found Dst IP Part 2: 0101 (PASS) -> Swap Success!");

                @(posedge clk);
            end
            $display("[TB Monitor] TX Packet Finished. Total Length: %0d bytes (padded)", beat_cnt*4);
        end
    end

    // =========================================================
    // 5. 主测试脚本
    // =========================================================
    initial begin
        // 初始化
        rst_n = 0;
        s_axil_awvalid = 0; s_axil_wvalid = 0; s_axil_bready = 0;
        s_axil_arvalid = 0; s_axil_rready = 0;
        rx_axis_tvalid = 0; rx_axis_tlast = 0; rx_axis_tuser = 0;
        tx_axis_tready = 1;
        
        #100 rst_n = 1;
        #100;

        // Step 1: 注入 RX
        send_udp_packet();
        
        #500; 

        // Step 2: CSR 配置
        write_csr(32'h0000_0008, 32'd4); // Len=4
        write_csr(32'h0000_0000, 32'h0000_0001); // Start

        // Step 3: 等待并结束
        // 这里的延时是为了让 Monitor 捕获数据
        #2000;
        $display("[TB] Simulation Completed.");
        $stop;
    end

endmodule