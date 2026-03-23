`timescale 1ns / 1ps

module tb_dma_system;

    // =========================================================
    // Parameters
    // =========================================================
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter PERIOD = 13.333; // 75MHz (1/75MHz = 13.333ns)
    parameter TEST_LEN = 1024; // Medium Packet Test, 1KB

    // Backpressure control: threshold out of 32 (6/32 ≈ 18.75% backpressure)
    parameter BP_THRESHOLD = 6;

    // =========================================================
    // Signals
    // =========================================================
    logic clk;
    logic rst_n;

    // AXI-Lite (CPU)
    logic [ADDR_WIDTH-1:0]  s_axil_awaddr;
    logic                   s_axil_awvalid;
    logic                   s_axil_awready;
    logic [DATA_WIDTH-1:0]  s_axil_wdata;
    logic [3:0]             s_axil_wstrb;
    logic                   s_axil_wvalid;
    logic                   s_axil_wready;
    logic [1:0]             s_axil_bresp;
    logic                   s_axil_bvalid;
    logic                   s_axil_bready;
    logic [ADDR_WIDTH-1:0]  s_axil_araddr;
    logic                   s_axil_arvalid;
    logic                   s_axil_arready;
    logic [DATA_WIDTH-1:0]  s_axil_rdata;
    logic [1:0]             s_axil_rresp;
    logic                   s_axil_rvalid;
    logic                   s_axil_rready;

    // RX Input (Stimulus)
    logic                   rx_wr_valid;
    logic [31:0]            rx_wr_data;
    logic                   rx_wr_last;
    logic                   rx_wr_ready;

    // TX Output (Ignore)
    logic [31:0]            tx_axis_tdata;
    logic                   tx_axis_tvalid;
    logic                   tx_axis_tlast;
    logic [3:0]             tx_axis_tkeep;
    logic                   tx_axis_tready;

    // AXI4 Master (DDR) - S2MM (Master Engine)
    logic [ADDR_WIDTH-1:0]  m_axis_awaddr;
    logic [7:0]             m_axis_awlen;
    logic [2:0]             m_axis_awsize;
    logic [1:0]             m_axis_awburst;
    logic [3:0]             m_axis_awcache;
    logic [2:0]             m_axis_awprot;
    logic                   m_axis_awvalid;
    logic                   m_axis_awready;
    logic [DATA_WIDTH-1:0]  m_axis_wdata;
    logic [DATA_WIDTH/8-1:0] m_axis_wstrb;
    logic                   m_axis_wlast;
    logic                   m_axis_wvalid;
    logic                   m_axis_wready;
    logic [1:0]             m_axis_bresp;
    logic                   m_axis_bvalid;
    logic                   m_axis_bready;

    // Interrupt
    logic                   dma_irq;

    // Legacy Performance Counters (coarse)
    real start_time;
    real end_time;
    real elapsed_time;

    // =========================================================
    // Precise Crypto Timestamp
    // =========================================================
    real   crypto_start_time;
    real   crypto_end_time;
    logic  crypto_started;
    int    crypto_blocks_out;
    localparam int EXPECTED_BLOCKS = TEST_LEN / 16;  // each block = 128-bit = 16 bytes

    // Hierarchical references into crypto_bridge_top
    wire crypto_sched_valid = dut.u_crypto_bridge.sched_valid;
    wire crypto_mid_wr     = dut.u_crypto_bridge.mid_fifo_wr_en;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crypto_started    <= 0;
            crypto_blocks_out <= 0;
        end else begin
            // Capture START: first block dispatched into a crypto instance
            if (!crypto_started && crypto_sched_valid) begin
                crypto_start_time <= $realtime;
                crypto_started    <= 1;
                $display("[TIMESTAMP] Crypto START @ %0t", $time);
            end
            // Capture END: each block written out of reorder buffer
            if (crypto_mid_wr) begin
                crypto_blocks_out <= crypto_blocks_out + 1;
                crypto_end_time   <= $realtime;
                if (crypto_blocks_out + 1 == EXPECTED_BLOCKS)
                    $display("[TIMESTAMP] Crypto END   @ %0t (block %0d/%0d)",
                             $time, crypto_blocks_out + 1, EXPECTED_BLOCKS);
            end
        end
    end
    
    // =========================================================
    // DUT Instantiation
    // =========================================================
    dma_subsystem #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        // AXI-Lite
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),

        // RX Stimulus
        .rx_wr_valid(rx_wr_valid), .rx_wr_data(rx_wr_data), .rx_wr_last(rx_wr_last), .rx_wr_ready(rx_wr_ready),

        // TX Output
        .tx_axis_tdata(tx_axis_tdata), .tx_axis_tvalid(tx_axis_tvalid), .tx_axis_tlast(tx_axis_tlast),
        .tx_axis_tkeep(tx_axis_tkeep), .tx_axis_tready(tx_axis_tready),

        // AXI4 Master (S2MM) - We only check this one for throughput
        .m_axis_awaddr(m_axis_awaddr), .m_axis_awlen(m_axis_awlen), .m_axis_awsize(m_axis_awsize),
        .m_axis_awburst(m_axis_awburst), .m_axis_awcache(m_axis_awcache), .m_axis_awprot(m_axis_awprot),
        .m_axis_awvalid(m_axis_awvalid), .m_axis_awready(m_axis_awready),
        .m_axis_wdata(m_axis_wdata), .m_axis_wstrb(m_axis_wstrb), .m_axis_wlast(m_axis_wlast),
        .m_axis_wvalid(m_axis_wvalid), .m_axis_wready(m_axis_wready),
        .m_axis_bresp(m_axis_bresp), .m_axis_bvalid(m_axis_bvalid), .m_axis_bready(m_axis_bready),

        // Tie-off unused or secondary ports
        .m_axis_s2mm_awready(1'b1), .m_axis_s2mm_wready(1'b1), .m_axis_s2mm_bvalid(1'b0), .m_axis_s2mm_bresp(2'b0),
        .m_axis_s2mm_arready(1'b1), .m_axis_s2mm_rdata(32'b0), .m_axis_s2mm_rlast(1'b0), .m_axis_s2mm_rvalid(1'b0), .m_axis_s2mm_rresp(2'b0),

        .m_axis_fetcher_arready(1'b1), .m_axis_fetcher_rdata(32'b0), .m_axis_fetcher_rlast(1'b0), .m_axis_fetcher_rvalid(1'b0), .m_axis_fetcher_rresp(2'b0),

        .dma_irq(dma_irq)
    );

    // =========================================================
    // Clock & Reset
    // =========================================================
    initial begin
        clk = 0;
        forever #(PERIOD/2) clk = ~clk;
    end

    initial begin
        rst_n = 0;
        #100;
        @(posedge clk) rst_n = 1;
    end

    // =========================================================
    // Pseudo-Random Backpressure Generator (LFSR-based)
    // =========================================================
    // Replaces the old `assign m_axis_wready = 1'b1`
    // LFSR generates deterministic pseudo-random sequence.
    // When low 5 bits < BP_THRESHOLD, wready deasserts (~18.75% backpressure).
    logic [31:0] bp_lfsr;
    logic        bp_wready_random;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bp_lfsr <= 32'hACE1_CAFE;  // deterministic seed
        else
            bp_lfsr <= {bp_lfsr[30:0], bp_lfsr[31] ^ bp_lfsr[21] ^ bp_lfsr[1] ^ bp_lfsr[0]};
    end

    // ~18.75% backpressure: deassert when low 5 bits < threshold
    assign bp_wready_random = (bp_lfsr[4:0] >= BP_THRESHOLD[4:0]);

    assign m_axis_awready = bp_wready_random;
    assign m_axis_wready  = bp_wready_random;

    // =========================================================
    // Robust DDR Slave Model (Counter Based)
    // =========================================================
    logic [7:0] sim_burst_cnt;
    logic [7:0] sim_beat_cnt;
    logic       sim_in_burst;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            m_axis_bvalid <= 0;
            sim_burst_cnt <= 0;
            sim_beat_cnt <= 0;
            sim_in_burst <= 0;
        end else begin
            // Detect Burst Start
            if (m_axis_awvalid && m_axis_awready) begin
                sim_burst_cnt <= m_axis_awlen;
                sim_beat_cnt <= 0;
                sim_in_burst <= 1;
            end

            // Count Data Beats
            if (sim_in_burst && m_axis_wvalid && m_axis_wready) begin
                if (sim_beat_cnt == sim_burst_cnt) begin
                    // Burst End
                    m_axis_bvalid <= 1;
                    sim_in_burst <= 0;
                end else begin
                    sim_beat_cnt <= sim_beat_cnt + 1;
                end
            end else if (m_axis_bready && m_axis_bvalid) begin
                m_axis_bvalid <= 0;
            end
        end
    end
    assign m_axis_bresp = 2'b00;

    assign tx_axis_tready = 1'b1; // Drain TX

    // =========================================================
    // Main Test Sequence
    // =========================================================
    initial begin
        // Init
        s_axil_awaddr  = 0;
        s_axil_awvalid = 0;
        s_axil_wdata   = 0;
        s_axil_wstrb   = 0;
        s_axil_wvalid  = 0;
        s_axil_bready  = 0;
        s_axil_araddr  = 0;
        s_axil_arvalid = 0;
        s_axil_rready  = 0;
        rx_wr_valid    = 0;
        rx_wr_data     = 0;
        rx_wr_last     = 0;

        #500;
        wait(rst_n);

        $display("================================================================");
        $display("  DMA Simulation @ 75MHz");
        $display("  Backpressure : ~%0d%% (threshold=%0d/32)",
                 (BP_THRESHOLD * 100) / 32, BP_THRESHOLD);
        $display("  Data Size    : %0d Bytes (%0d crypto blocks)",
                 TEST_LEN, EXPECTED_BLOCKS);
        $display("================================================================");

        // 1. Configure DMA
        $display("[TB] Configuring DMA registers...");
        axi_write(52'h08, 32'h1000_0000);    // Dest Address (S2MM)
        axi_write(52'h0C, TEST_LEN + 8);      // Length (+8 for alignment compensation)
        axi_write(52'h10, 32'h2000_0000);     // Source Address (MM2S)

        // 2. Drive Data (continuous burst, non-blocking fork)
        fork
            drive_data();
        join_none

        // 3. Start DMA (S2MM Only)
        $display("[TB] Starting DMA transfer...");
        start_time = $realtime;
        // Control: Run | Init | SM4_MODE => 0x0000_0017
        axi_write(52'h00, 32'h0000_0017);

        // 4. Wait for Interrupt
        $display("[CPU] Waiting for Interrupt...");
        @(posedge dma_irq);
        $display("[TB] Interrupt Received at %0t", $time);
        
        end_time = $realtime;
        elapsed_time = end_time - start_time;

        // =========================================================
        // Performance Report
        // =========================================================
        $display("");
        $display("================================================================");
        $display("  COARSE TIMING (includes pipeline fill/drain)");
        $display("================================================================");
        $display("  Data Size    : %0d Bytes", TEST_LEN);
        $display("  Elapsed Time : %0.2f ns", elapsed_time);
        $display("  Throughput   : %0.2f MB/s", (TEST_LEN / (elapsed_time * 1e-9)) / 1e6);
        $display("  Sim Cycles   : %0d cycles", $rtoi(elapsed_time / PERIOD));

        // Precise crypto-core-only measurement
        if (crypto_blocks_out >= EXPECTED_BLOCKS) begin
            automatic real crypto_elapsed = crypto_end_time - crypto_start_time;
            $display("");
            $display("================================================================");
            $display("  PRECISE CRYPTO CORE TIMING (sched_valid -> mid_fifo_wr_en)");
            $display("================================================================");
            $display("  Crypto Blocks: %0d", crypto_blocks_out);
            $display("  Crypto Time  : %0.2f ns", crypto_elapsed);
            $display("  Throughput   : %0.2f MB/s",
                     (TEST_LEN / (crypto_elapsed * 1e-9)) / 1e6);
            $display("  Eff Cycles   : %0d cycles", $rtoi(crypto_elapsed / PERIOD));
        end else begin
            $display("[WARN] Only %0d/%0d crypto blocks received, timing incomplete",
                     crypto_blocks_out, EXPECTED_BLOCKS);
        end
        $display("================================================================");
        
        $finish;
    end
    
    // Watchdog
    initial begin
        #20_000_000; // 20ms
        $display("TIMEOUT: Simulation took too long!");
        $finish;
    end


    // =========================================================
    // Tasks
    // =========================================================

    // --- AXI-Lite Write ------------------------------------------
    task axi_write(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        begin
            @(posedge clk);
            s_axil_awaddr <= addr;
            s_axil_awvalid <= 1;
            s_axil_wdata <= data;
            s_axil_wvalid <= 1;
            s_axil_wstrb <= 4'hF;
            s_axil_bready <= 1;

            do begin
                @(posedge clk);
            end while ((!s_axil_awready) || (!s_axil_wready));
            
            s_axil_awvalid <= 0;
            s_axil_wvalid <= 0;
            s_axil_wstrb <= 0;
            
            while (!s_axil_bvalid) begin
                @(posedge clk);
            end
            
            s_axil_bready <= 0;
        end
    endtask

    // --- Continuous Burst Data Driver ----------------------------
    // Replaces the old blocking for-loop style.
    // Uses standard AXI-Stream pipeline handshake:
    //   - valid stays HIGH, data updates every beat
    //   - on ready deassert, valid & data HOLD (AXI spec compliance)
    //   - pointer advances only on (valid && ready) handshake
    task drive_data();
        int beat_idx;
        int total_beats;
        begin
            // total = head_dummy(2) + payload(TEST_LEN/4) + tail_dummy(8)
            total_beats = 2 + TEST_LEN/4 + 8;

            // Wait for DMA to be configured (approx)
            #1000;

            beat_idx = 0;
            rx_wr_valid = 1;

            while (beat_idx < total_beats) begin
                // Select data based on beat_idx
                if (beat_idx < 2)
                    rx_wr_data = 32'hDEAD_BEEF;                     // Head dummy
                else if (beat_idx < 2 + TEST_LEN/4)
                    rx_wr_data = (beat_idx - 2) + 32'hA0A0_0000;   // Payload pattern
                else
                    rx_wr_data = 32'hDEAD_F00D;                    // Tail dummy

                rx_wr_last = (beat_idx == total_beats - 1) ? 1'b1 : 1'b0;

                @(posedge clk);
                if (rx_wr_ready) begin
                    beat_idx++;  // Handshake OK, advance
                end
                // If ready is LOW, valid & data hold — pipeline stall
            end

            @(posedge clk);
            rx_wr_valid = 0;
            rx_wr_last  = 0;
        end
    endtask

endmodule
