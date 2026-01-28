`timescale 1ns / 1ps

module tb_dma_subsystem();

    logic clk, rst_n;

    // AXI-Lite
    logic [31:0] s_axil_awaddr; logic s_axil_awvalid, s_axil_awready;
    logic [31:0] s_axil_wdata;  logic [3:0] s_axil_wstrb; logic s_axil_wvalid, s_axil_wready;
    logic [1:0] s_axil_bresp;   logic s_axil_bvalid, s_axil_bready;
    logic [31:0] s_axil_araddr; logic s_axil_arvalid, s_axil_arready;
    logic [31:0] s_axil_rdata;  logic s_axil_rvalid, s_axil_rready;

    // AXI Master
    logic [31:0] m_axi_awaddr; logic [7:0] m_axi_awlen; logic [2:0] m_axi_awsize;
    logic [1:0] m_axi_awburst; logic [3:0] m_axi_awcache; logic [2:0] m_axi_awprot;
    logic m_axi_awvalid, m_axi_awready;
    logic [31:0] m_axi_wdata; logic [3:0] m_axi_wstrb; logic m_axi_wlast, m_axi_wvalid, m_axi_wready;
    logic [1:0] m_axi_bresp;  logic m_axi_bvalid, m_axi_bready;
    
    // Read Channel Tie-off
    logic [31:0] m_axi_araddr; logic [7:0] m_axi_arlen; logic [2:0] m_axi_arsize;
    logic [1:0] m_axi_arburst; logic m_axi_arvalid, m_axi_arready;
    logic [31:0] m_axi_rdata;  logic [1:0] m_axi_rresp; logic m_axi_rlast, m_axi_rvalid, m_axi_rready;

    dma_subsystem #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    task write_csr(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axil_awaddr <= addr; s_axil_awvalid <= 1;
            s_axil_wdata <= data; s_axil_wstrb <= 4'hF; s_axil_wvalid <= 1; s_axil_bready <= 1;
            wait(s_axil_awready && s_axil_wready);
            @(posedge clk);
            s_axil_awvalid <= 0; s_axil_wvalid <= 0;
            wait(s_axil_bvalid);
            @(posedge clk);
            s_axil_bready <= 0;
            $display("[BFM] Write CSR Addr: %h, Data: %h", addr, data);
        end
    endtask

    initial begin
        // 1. 初始化所有输入 (消灭红线 Key Step!)
        rst_n = 0;
        
        // CSR Write Channel
        s_axil_awaddr = 0; s_axil_awvalid = 0; 
        s_axil_wdata = 0; s_axil_wstrb = 0; s_axil_wvalid = 0; s_axil_bready = 0;
        
        // [Fix] CSR Read Channel (之前悬空导致红色X)
        s_axil_araddr = 0; s_axil_arvalid = 0; s_axil_rready = 0;

        // AXI Slave Response Simulation
        m_axi_awready = 1; m_axi_wready = 1; m_axi_bvalid = 1; m_axi_bresp = 0;
        m_axi_arready = 1; m_axi_rvalid = 0; m_axi_rready = 0;

        #100 rst_n = 1;
        #20;

        $display("\n=== Day 8 PBM Verification Start ===");

        // Step 1: Config DMA
        write_csr(32'h08, 32'h1000_0000); 
        write_csr(32'h0C, 32'h0000_0100); 
        write_csr(32'h00, 32'h0000_0001); 
        $display("[TB] DMA Started. Waiting for data...");
        repeat(10) @(posedge clk);

        // Step 2: Good Packet
        $display("[TB] Injecting Good Packet (AABBCCDD)...");
        force dut.gearbox_valid = 1;
        force dut.gearbox_dout  = 32'hAA_BB_CC_DD;
        force dut.gearbox_last  = 0;
        force dut.gearbox_ready = 1; 
        @(posedge clk);
        force dut.gearbox_dout  = 32'h11_22_33_44;
        @(posedge clk);
        force dut.gearbox_dout  = 32'hEE_FF_00_00;
        force dut.gearbox_last  = 1;
        @(posedge clk);
        
        release dut.gearbox_valid; release dut.gearbox_dout; release dut.gearbox_last;
        force dut.gearbox_valid = 0;
        
        $display("[TB] Good Packet injected. Observing AXI Bus...");
        repeat(30) @(posedge clk);

        // Step 3: Bad Packet (Rollback Test)
        $display("[TB] Injecting Bad Packet (DEADBEEF) with Error...");
        force dut.gearbox_valid = 1;
        force dut.gearbox_dout  = 32'hDEAD_BEEF; 
        force dut.gearbox_last  = 0;
        @(posedge clk);
        force dut.gearbox_dout  = 32'hBAD0_BAD0;
        force dut.gearbox_last  = 1;
        
        // [Fix] 使用新定义的信号进行 Force
        force dut.pbm_error_inject = 1; 
        @(posedge clk);

        release dut.gearbox_valid; release dut.gearbox_dout; release dut.gearbox_last;
        release dut.pbm_error_inject; // Release the error signal
        
        force dut.gearbox_valid = 0;
        // force dut.pbm_error_inject = 0; // Not needed if released, default is 0

        $display("[TB] Bad Packet injected. PBM should Rollback.");
        $display("[TB] Monitoring AXI WDATA. It should NOT contain DEADBEEF/BAD0BAD0.");

        repeat(50) @(posedge clk);
        $display("=== Day 8 Verification Finished ===");
        $stop;
    end
endmodule