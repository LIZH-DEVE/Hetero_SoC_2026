`timescale 1ns / 1ps

module tb_crypto_dma_subsystem();

    // =========================================================
    // 1. 时钟和复位
    // =========================================================
    logic clk = 0;
    logic rst_n = 0;
    
    initial begin clk = 0; forever #5 clk = ~clk; end
    initial begin #100 rst_n = 1; end

    // =========================================================
    // 2. AXI-Lite 接口
    // =========================================================
    logic [31:0] s_axil_awaddr = 0;
    logic        s_axil_awvalid = 0;
    logic        s_axil_awready;
    logic [31:0] s_axil_wdata = 0;
    logic [3:0]  s_axil_wstrb = 0;
    logic        s_axil_wvalid = 0;
    logic        s_axil_wready;
    logic [1:0]  s_axil_bresp;
    logic        s_axil_bvalid;
    logic        s_axil_bready = 0;
    logic [31:0] s_axil_araddr = 0;
    logic        s_axil_arvalid = 0;
    logic        s_axil_arready;
    logic [31:0] s_axil_rdata;
    logic [1:0]  s_axil_rresp;
    logic        s_axil_rvalid;
    logic        s_axil_rready = 0;

    // =========================================================
    // 3. RX/TX 接口
    // =========================================================
    logic        rx_wr_valid = 0;
    logic [31:0] rx_wr_data = 0;
    logic        rx_wr_last = 0;
    logic        rx_wr_ready;
    
    logic [31:0] tx_axis_tdata;
    logic        tx_axis_tvalid;
    logic        tx_axis_tlast;
    logic [3:0]  tx_axis_tkeep;
    logic        tx_axis_tready = 1;

    // =========================================================
    // 4. DMA AXI Master 接口 (连接到 Stub Model)
    // =========================================================
    // 主 DMA 通道
    wire  [31:0] m_axis_awaddr;
    wire  [7:0]  m_axis_awlen;
    wire  [2:0]  m_axis_awsize;
    wire  [1:0]  m_axis_awburst;
    wire  [3:0]  m_axis_awcache;
    wire  [2:0]  m_axis_awprot;
    wire         m_axis_awvalid;
    wire         m_axis_awready = 1;
    wire  [31:0] m_axis_wdata;
    wire  [3:0]  m_axis_wstrb;
    wire         m_axis_wlast;
    wire         m_axis_wvalid;
    wire         m_axis_wready = 1;
    wire  [1:0]  m_axis_bresp;
    wire         m_axis_bvalid;
    wire         m_axis_bready;

    // S2MM/MM2S 通道 (悬空)
    wire  [31:0] m_axis_s2mm_awaddr;
    wire  [7:0]  m_axis_s2mm_awlen;
    wire  [2:0]  m_axis_s2mm_awsize;
    wire  [1:0]  m_axis_s2mm_awburst;
    wire  [3:0]  m_axis_s2mm_awcache;
    wire  [2:0]  m_axis_s2mm_awprot;
    wire         m_axis_s2mm_awvalid;
    wire         m_axis_s2mm_awready = 1;
    wire  [31:0] m_axis_s2mm_wdata;
    wire  [3:0]  m_axis_s2mm_wstrb;
    wire         m_axis_s2mm_wlast;
    wire         m_axis_s2mm_wvalid;
    wire         m_axis_s2mm_wready = 1;
    wire  [1:0]  m_axis_s2mm_bresp;
    wire         m_axis_s2mm_bvalid;
    wire         m_axis_s2mm_bready;
    wire  [31:0] m_axis_s2mm_araddr;
    wire  [7:0]  m_axis_s2mm_arlen;
    wire  [2:0]  m_axis_s2mm_arsize;
    wire  [1:0]  m_axis_s2mm_arburst;
    wire         m_axis_s2mm_arvalid;
    wire         m_axis_s2mm_arready = 1;
    wire  [31:0] m_axis_s2mm_rdata = 0;
    wire  [1:0]  m_axis_s2mm_rresp = 0;
    wire         m_axis_s2mm_rlast = 0;
    wire         m_axis_s2mm_rvalid;
    wire         m_axis_s2mm_rready;

    // Fetcher 通道
    wire  [31:0] m_axis_fetcher_araddr;
    wire  [7:0]  m_axis_fetcher_arlen;
    wire  [2:0]  m_axis_fetcher_arsize;
    wire  [1:0]  m_axis_fetcher_arburst;
    wire         m_axis_fetcher_arvalid;
    wire         m_axis_fetcher_arready = 1;
    wire  [31:0] m_axis_fetcher_rdata;
    wire  [1:0]  m_axis_fetcher_rresp;
    wire         m_axis_fetcher_rlast;
    wire         m_axis_fetcher_rvalid;
    wire         m_axis_fetcher_rready;

    // =========================================================
    // 5. DUT 实例化
    // =========================================================
    crypto_dma_subsystem u_dut (
        .clk(clk), .rst_n(rst_n),
        
        // AXI-Lite Slave
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        
        // RX/TX
        .rx_wr_valid(rx_wr_valid), .rx_wr_data(rx_wr_data), .rx_wr_last(rx_wr_last), .rx_wr_ready(rx_wr_ready),
        .tx_axis_tdata(tx_axis_tdata), .tx_axis_tvalid(tx_axis_tvalid), .tx_axis_tlast(tx_axis_tlast),
        .tx_axis_tkeep(tx_axis_tkeep), .tx_axis_tready(tx_axis_tready),
        
        // DMA Master
        .m_axis_awaddr(m_axis_awaddr), .m_axis_awlen(m_axis_awlen), .m_axis_awsize(m_axis_awsize),
        .m_axis_awburst(m_axis_awburst), .m_axis_awcache(m_axis_awcache), .m_axis_awprot(m_axis_awprot),
        .m_axis_awvalid(m_axis_awvalid), .m_axis_awready(m_axis_awready),
        .m_axis_wdata(m_axis_wdata), .m_axis_wstrb(m_axis_wstrb), .m_axis_wlast(m_axis_wlast),
        .m_axis_wvalid(m_axis_wvalid), .m_axis_wready(m_axis_wready),
        .m_axis_bresp(m_axis_bresp), .m_axis_bvalid(m_axis_bvalid), .m_axis_bready(m_axis_bready),
        
        // S2MM/MM2S (不使用，悬空)
        .m_axis_s2mm_awaddr(m_axis_s2mm_awaddr), .m_axis_s2mm_awlen(m_axis_s2mm_awlen),
        .m_axis_s2mm_awsize(m_axis_s2mm_awsize), .m_axis_s2mm_awburst(m_axis_s2mm_awburst),
        .m_axis_s2mm_awcache(m_axis_s2mm_awcache), .m_axis_s2mm_awprot(m_axis_s2mm_awprot),
        .m_axis_s2mm_awvalid(m_axis_s2mm_awvalid), .m_axis_s2mm_awready(m_axis_s2mm_awready),
        .m_axis_s2mm_wdata(m_axis_s2mm_wdata), .m_axis_s2mm_wstrb(m_axis_s2mm_wstrb),
        .m_axis_s2mm_wlast(m_axis_s2mm_wlast), .m_axis_s2mm_wvalid(m_axis_s2mm_wvalid),
        .m_axis_s2mm_wready(m_axis_s2mm_wready), .m_axis_s2mm_bresp(m_axis_s2mm_bresp),
        .m_axis_s2mm_bvalid(m_axis_s2mm_bvalid), .m_axis_s2mm_bready(m_axis_s2mm_bready),
        .m_axis_s2mm_araddr(m_axis_s2mm_araddr), .m_axis_s2mm_arlen(m_axis_s2mm_arlen),
        .m_axis_s2mm_arsize(m_axis_s2mm_arsize), .m_axis_s2mm_arburst(m_axis_s2mm_arburst),
        .m_axis_s2mm_arvalid(m_axis_s2mm_arvalid), .m_axis_s2mm_arready(m_axis_s2mm_arready),
        .m_axis_s2mm_rdata(m_axis_s2mm_rdata), .m_axis_s2mm_rresp(m_axis_s2mm_rresp),
        .m_axis_s2mm_rlast(m_axis_s2mm_rlast), .m_axis_s2mm_rvalid(m_axis_s2mm_rvalid),
        .m_axis_s2mm_rready(m_axis_s2mm_rready),
        
        // Fetcher
        .m_axis_fetcher_araddr(m_axis_fetcher_araddr), .m_axis_fetcher_arlen(m_axis_fetcher_arlen),
        .m_axis_fetcher_arsize(m_axis_fetcher_arsize), .m_axis_fetcher_arburst(m_axis_fetcher_arburst),
        .m_axis_fetcher_arvalid(m_axis_fetcher_arvalid), .m_axis_fetcher_arready(m_axis_fetcher_arready),
        .m_axis_fetcher_rdata(m_axis_fetcher_rdata), .m_axis_fetcher_rresp(m_axis_fetcher_rresp),
        .m_axis_fetcher_rlast(m_axis_fetcher_rlast), .m_axis_fetcher_rvalid(m_axis_fetcher_rvalid),
        .m_axis_fetcher_rready(m_axis_fetcher_rready)
    );

    // =========================================================
    // 6. 仿真模型
    // =========================================================
    logic [31:0] mock_ddr [0:255];
    initial for(int i=0; i<256; i++) mock_ddr[i] = 32'h0000_0000;
    
    // 描述符
    initial begin
        mock_ddr[0] = 32'h2000_0000;  // Dest Addr
        mock_ddr[1] = 32'h8000_0020;  // Len=32, SM4
    end

    // DMA 写响应
    reg m_axis_bvalid_reg = 0;
    always @(posedge clk) begin
        if (m_axis_wvalid && m_axis_wready && m_axis_wlast) begin
            m_axis_bvalid_reg <= 1'b1;
        end else if (m_axis_bready) begin
            m_axis_bvalid_reg <= 1'b0;
        end
    end
    assign m_axis_bvalid = m_axis_bvalid_reg;

    // Fetcher 读响应
    reg [31:0] fetcher_rdata = 0;
    reg fetcher_rvalid = 0;
    reg fetcher_rlast = 0;
    always @(posedge clk) begin
        if (m_axis_fetcher_arvalid && m_axis_fetcher_arready) begin
            fetcher_rdata <= mock_ddr[0];
            fetcher_rvalid <= 1'b1;
            fetcher_rlast <= 1'b1;
        end else if (m_axis_fetcher_rready) begin
            fetcher_rvalid <= 1'b0;
            fetcher_rlast <= 1'b0;
        end
    end
    assign m_axis_fetcher_rdata = fetcher_rdata;
    assign m_axis_fetcher_rvalid = fetcher_rvalid;
    assign m_axis_fetcher_rlast = fetcher_rlast;
    assign m_axis_fetcher_rresp = 2'b00;

    // =========================================================
    // 7. 测试激励
    // =========================================================
    
    task axil_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axil_awaddr <= addr; s_axil_awvalid <= 1;
            s_axil_wdata <= data; s_axil_wvalid <= 1; s_axil_wstrb <= 4'hF;
            s_axil_bready <= 1;
            wait(s_axil_awready && s_axil_wready);
            @(posedge clk);
            s_axil_awvalid <= 0; s_axil_wvalid <= 0;
            wait(s_axil_bvalid);
            @(posedge clk);
            s_axil_bready <= 0;
        end
    endtask

    initial begin
        #200;
        
        $display("========================================");
        $display("Test: Configure DMA (CSR Mode)");
        $display("========================================");
        
        // 禁用 Ring 模式
        axil_write(32'h5C, 32'd0);
        
        // 配置基地址和长度
        axil_write(32'h08, 32'h2000_0000);
        axil_write(32'h0C, 32'd32);
        
        #500;
        
        $display("========================================");
        $display("Test: Inject 32 bytes data to PBM");
        $display("========================================");
        
        for(int i=1; i<=8; i++) begin
            @(posedge clk);
            rx_wr_valid <= 1;
            rx_wr_data <= i * 32'h1111_1111;
            rx_wr_last <= (i == 8);
            wait(rx_wr_ready);
            @(posedge clk);
            rx_wr_valid <= 0;
            rx_wr_last <= 0;
        end
        
        #500;
        
        $display("========================================");
        $display("Test: Start DMA");
        $display("========================================");
        
        axil_write(32'h00, 32'h01);  // Start
        
        fork
            begin
                #100000;
                $display("[TB] TIMEOUT!");
                $stop;
            end
            begin
                wait(tx_axis_tvalid);
                $display("[TB] TX VALID DETECTED!");
                $stop;
            end
        join_any
    end

endmodule
