`timescale 1ns / 1ps

module tb_dma_subsystem_crypto_encdec;
    import crypto_vectors_pkg::*;

    localparam real CLK_PERIOD_NS        = 13.333; // 75 MHz
    localparam int MAX_WORDS            = 300000;
    localparam int NUM_PARALLEL_BLOCKS  = 4;
    localparam int WORDS_PER_BLOCK      = 4;
    localparam int DEFAULT_STABILITY_OP = 10000;
    localparam int DEFAULT_REPEAT_NUM   = 3;
    localparam real TARGET_TP_MBPS      = 150.0;
    bit reset_each_transfer = 1'b0;
    int pbm_commit_words = 256; // Commit PBM packet every N words to avoid large-packet backpressure deadlock.
    // Default profile for current debug/data collection phase: SM4 throughput only.
    bit run_func_test = 1'b1;
    bit run_tp_aes_test = 1'b1;
    bit run_tp_sm4_test = 1'b1;
    bit run_backpressure_test = 1'b0;
    bit run_key_switch_test = 1'b0;
    bit run_stability_test = 1'b0;

    // CSR map
    localparam logic [31:0] CSR_CTRL      = 32'h0000_0000;
    localparam logic [31:0] CSR_STATUS    = 32'h0000_0004;
    localparam logic [31:0] CSR_BASE_ADDR = 32'h0000_0008;
    localparam logic [31:0] CSR_LEN       = 32'h0000_000C;
    localparam logic [31:0] CSR_KEY0      = 32'h0000_0028;
    localparam logic [31:0] CSR_KEY1      = 32'h0000_002C;
    localparam logic [31:0] CSR_KEY2      = 32'h0000_0030;
    localparam logic [31:0] CSR_KEY3      = 32'h0000_0034;
    localparam logic [31:0] CSR_LOOPBACK  = 32'h0000_0048;
    localparam logic [31:0] CSR_RING_SIZE = 32'h0000_005C;

    localparam logic [31:0] BASE_ADDR     = 32'h2000_0000; // 64B aligned

    localparam int BUF_IN  = 0;
    localparam int BUF_MID = 1;
    localparam int BUF_OUT = 2;
    localparam int BUF_TMP = 3;

    localparam logic [127:0] AES_KEY_ALT = 128'h0f0e0d0c0b0a09080706050403020100;
    localparam logic [127:0] SM4_KEY_ALT = 128'hfedcba98765432100123456789abcdef;

    // ------------------------------------------------------------------------
    // Clock / Reset
    // ------------------------------------------------------------------------
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;
    initial begin
        #100 rst_n = 1'b1;
    end

    longint unsigned cycle_counter;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle_counter <= 0;
        else cycle_counter <= cycle_counter + 1;
    end

    // ========================================================================
    // Precise Crypto Core Timestamp (strips fill/drain overhead)
    // ========================================================================
    // Hierarchical references into crypto_bridge_top
    wire crypto_sched_valid = u_dut.u_crypto_bridge.sched_valid;
    wire crypto_mid_wr     = u_dut.u_crypto_bridge.mid_fifo_wr_en;

    logic        crypto_ts_enable;    // arm/disarm per transfer
    logic        crypto_ts_started;
    longint      crypto_start_cycle;
    longint      crypto_end_cycle;
    int          crypto_blocks_out;
    int          crypto_expected_blocks;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crypto_ts_started   <= 0;
            crypto_start_cycle  <= 0;
            crypto_end_cycle    <= 0;
            crypto_blocks_out   <= 0;
        end else if (!crypto_ts_enable) begin
            // Hold values when disabled (reset on next enable)
        end else begin
            if (!crypto_ts_started && crypto_sched_valid) begin
                crypto_start_cycle <= cycle_counter;
                crypto_ts_started  <= 1;
            end
            if (crypto_mid_wr) begin
                crypto_blocks_out <= crypto_blocks_out + 1;
                crypto_end_cycle  <= cycle_counter;
            end
        end
    end

    // PBM read-side probe: track every rd_en and valid event with data
    integer pbm_rd_word_cnt = 0;
    always_ff @(posedge clk) begin
        // Track PBM rd_en and valid with exact data for first 40 words (10 blocks)
        if (u_dut.u_crypto_bridge.o_pbm_rd_en || u_dut.bridge_rd_valid) begin
            if (pbm_rd_word_cnt < 40)
                $display("[PBM RD] t=%0t rd_en=%b valid=%b data=%08x state=%0d cap=%0d req=%0d empty=%b",
                    $time,
                    u_dut.u_crypto_bridge.o_pbm_rd_en,
                    u_dut.bridge_rd_valid,
                    u_dut.pbm_data,
                    u_dut.u_crypto_bridge.input_state,
                    u_dut.u_crypto_bridge.cap_cnt,
                    u_dut.u_crypto_bridge.req_cnt,
                    u_dut.u_crypto_bridge.i_pbm_empty);
        end
        if (u_dut.bridge_rd_valid) pbm_rd_word_cnt <= pbm_rd_word_cnt + 1;

        // SCHED probe
/*
        if (u_dut.u_crypto_bridge.sched_valid)
            $display("[SCHED] t=%0t target=%0d plaintext_reg=%x seq=%0d",
                $time,
                u_dut.u_crypto_bridge.sched_next_inst,
                u_dut.u_crypto_bridge.plaintext_reg,
                u_dut.u_crypto_bridge.input_seq_counter);
*/
    end



    // Dedicated SM4 key expansion debug (runs every cycle for first 200 cycles after SM4 starts)
    integer sm4_dbg_cnt = 0;
    logic sm4_dbg_active = 0;
    always_ff @(posedge clk) begin
        // Trigger debug when inst_start fires for SM4
        if (u_dut.u_crypto_bridge.inst_start[0] && u_dut.u_crypto_bridge.algo_reg) begin
            sm4_dbg_active <= 1;
            sm4_dbg_cnt <= 0;
        end
        if (sm4_dbg_active) begin
            sm4_dbg_cnt <= sm4_dbg_cnt + 1;
/*
            $display("[SM4 KEY DBG] t=%0t cnt=%0d | wrapper_sm4_state=%0d | encdec_current=%0d encdec_key_exp_ready=%b | keyexp_current=%0d keyexp_count=%0d keyexp_finished=%b | enable_key_exp=%b user_key_valid=%b reg_user_key_valid=%b",
                $time, sm4_dbg_cnt,
                u_dut.u_crypto_bridge.gen_crypto_cores[0].sm4_state,
                u_dut.u_crypto_bridge.gen_crypto_cores[0].u_sm4.u_encdec.current,
                u_dut.u_crypto_bridge.gen_crypto_cores[0].u_sm4.u_encdec.key_exp_ready_in,
                u_dut.u_crypto_bridge.gen_crypto_cores[0].u_sm4.u_key.current,
                u_dut.u_crypto_bridge.gen_crypto_cores[0].u_sm4.u_key.reg_count_round,
                u_dut.u_crypto_bridge.gen_crypto_cores[0].u_sm4.u_key.key_exp_finished_out,
                u_dut.u_crypto_bridge.gen_crypto_cores[0].u_sm4.u_key.enable_key_exp_in,
                u_dut.u_crypto_bridge.gen_crypto_cores[0].u_sm4.u_key.user_key_valid_in,
                u_dut.u_crypto_bridge.gen_crypto_cores[0].u_sm4.u_key.reg_user_key_valid
            );
*/
            if (sm4_dbg_cnt > 80) sm4_dbg_active <= 0; // Stop after enough cycles
        end
    end

    // ------------------------------------------------------------------------
    // DUT interfaces
    // ------------------------------------------------------------------------
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

    logic        rx_wr_valid = 0;
    logic [31:0] rx_wr_data = 0;
    logic        rx_wr_last = 0;
    logic        rx_wr_ready;

    logic [31:0] tx_axis_tdata;
    logic        tx_axis_tvalid;
    logic        tx_axis_tlast;
    logic [3:0]  tx_axis_tkeep;
    logic        tx_axis_tready = 1;

    logic [31:0] m_axis_awaddr;
    logic [7:0]  m_axis_awlen;
    logic [2:0]  m_axis_awsize;
    logic [1:0]  m_axis_awburst;
    logic [3:0]  m_axis_awcache;
    logic [2:0]  m_axis_awprot;
    logic        m_axis_awvalid;
    logic        m_axis_awready;
    logic [31:0] m_axis_wdata;
    logic [3:0]  m_axis_wstrb;
    logic        m_axis_wlast;
    logic        m_axis_wvalid;
    logic        m_axis_wready;
    logic [1:0]  m_axis_bresp;
    logic        m_axis_bvalid;
    logic        m_axis_bready;

    logic [31:0] m_axis_s2mm_awaddr;
    logic [7:0]  m_axis_s2mm_awlen;
    logic [2:0]  m_axis_s2mm_awsize;
    logic [1:0]  m_axis_s2mm_awburst;
    logic [3:0]  m_axis_s2mm_awcache;
    logic [2:0]  m_axis_s2mm_awprot;
    logic        m_axis_s2mm_awvalid;
    logic        m_axis_s2mm_awready = 1'b1;
    logic [31:0] m_axis_s2mm_wdata;
    logic [3:0]  m_axis_s2mm_wstrb;
    logic        m_axis_s2mm_wlast;
    logic        m_axis_s2mm_wvalid;
    logic        m_axis_s2mm_wready = 1'b1;
    logic [1:0]  m_axis_s2mm_bresp = 2'b00;
    logic        m_axis_s2mm_bvalid = 1'b0;
    logic        m_axis_s2mm_bready;
    logic [31:0] m_axis_s2mm_araddr;
    logic [7:0]  m_axis_s2mm_arlen;
    logic [2:0]  m_axis_s2mm_arsize;
    logic [1:0]  m_axis_s2mm_arburst;
    logic        m_axis_s2mm_arvalid;
    logic        m_axis_s2mm_arready = 1'b1;
    logic [31:0] m_axis_s2mm_rdata = 32'h0;
    logic [1:0]  m_axis_s2mm_rresp = 2'b00;
    logic        m_axis_s2mm_rlast = 1'b0;
    logic        m_axis_s2mm_rvalid = 1'b0;
    logic        m_axis_s2mm_rready;

    logic [31:0] m_axis_fetcher_araddr;
    logic [7:0]  m_axis_fetcher_arlen;
    logic [2:0]  m_axis_fetcher_arsize;
    logic [1:0]  m_axis_fetcher_arburst;
    logic        m_axis_fetcher_arvalid;
    logic        m_axis_fetcher_arready = 1'b1;
    logic [31:0] m_axis_fetcher_rdata = 32'h0;
    logic [1:0]  m_axis_fetcher_rresp = 2'b00;
    logic        m_axis_fetcher_rlast = 1'b0;
    logic        m_axis_fetcher_rvalid = 1'b0;
    logic        m_axis_fetcher_rready;

    logic dma_irq;

    dma_subsystem u_dut (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        .rx_wr_valid(rx_wr_valid), .rx_wr_data(rx_wr_data), .rx_wr_last(rx_wr_last), .rx_wr_ready(rx_wr_ready),
        .tx_axis_tdata(tx_axis_tdata), .tx_axis_tvalid(tx_axis_tvalid), .tx_axis_tlast(tx_axis_tlast),
        .tx_axis_tkeep(tx_axis_tkeep), .tx_axis_tready(tx_axis_tready),
        .m_axis_awaddr(m_axis_awaddr), .m_axis_awlen(m_axis_awlen), .m_axis_awsize(m_axis_awsize),
        .m_axis_awburst(m_axis_awburst), .m_axis_awcache(m_axis_awcache), .m_axis_awprot(m_axis_awprot),
        .m_axis_awvalid(m_axis_awvalid), .m_axis_awready(m_axis_awready),
        .m_axis_wdata(m_axis_wdata), .m_axis_wstrb(m_axis_wstrb), .m_axis_wlast(m_axis_wlast),
        .m_axis_wvalid(m_axis_wvalid), .m_axis_wready(m_axis_wready),
        .m_axis_bresp(m_axis_bresp), .m_axis_bvalid(m_axis_bvalid), .m_axis_bready(m_axis_bready),
        .m_axis_s2mm_awaddr(m_axis_s2mm_awaddr), .m_axis_s2mm_awlen(m_axis_s2mm_awlen),
        .m_axis_s2mm_awsize(m_axis_s2mm_awsize), .m_axis_s2mm_awburst(m_axis_s2mm_awburst),
        .m_axis_s2mm_awcache(m_axis_s2mm_awcache), .m_axis_s2mm_awprot(m_axis_s2mm_awprot),
        .m_axis_s2mm_awvalid(m_axis_s2mm_awvalid), .m_axis_s2mm_awready(m_axis_s2mm_awready),
        .m_axis_s2mm_wdata(m_axis_s2mm_wdata), .m_axis_s2mm_wstrb(m_axis_s2mm_wstrb),
        .m_axis_s2mm_wlast(m_axis_s2mm_wlast), .m_axis_s2mm_wvalid(m_axis_s2mm_wvalid), .m_axis_s2mm_wready(m_axis_s2mm_wready),
        .m_axis_s2mm_bresp(m_axis_s2mm_bresp), .m_axis_s2mm_bvalid(m_axis_s2mm_bvalid), .m_axis_s2mm_bready(m_axis_s2mm_bready),
        .m_axis_s2mm_araddr(m_axis_s2mm_araddr), .m_axis_s2mm_arlen(m_axis_s2mm_arlen),
        .m_axis_s2mm_arsize(m_axis_s2mm_arsize), .m_axis_s2mm_arburst(m_axis_s2mm_arburst),
        .m_axis_s2mm_arvalid(m_axis_s2mm_arvalid), .m_axis_s2mm_arready(m_axis_s2mm_arready),
        .m_axis_s2mm_rdata(m_axis_s2mm_rdata), .m_axis_s2mm_rresp(m_axis_s2mm_rresp),
        .m_axis_s2mm_rlast(m_axis_s2mm_rlast), .m_axis_s2mm_rvalid(m_axis_s2mm_rvalid), .m_axis_s2mm_rready(m_axis_s2mm_rready),
        .m_axis_fetcher_araddr(m_axis_fetcher_araddr), .m_axis_fetcher_arlen(m_axis_fetcher_arlen),
        .m_axis_fetcher_arsize(m_axis_fetcher_arsize), .m_axis_fetcher_arburst(m_axis_fetcher_arburst),
        .m_axis_fetcher_arvalid(m_axis_fetcher_arvalid), .m_axis_fetcher_arready(m_axis_fetcher_arready),
        .m_axis_fetcher_rdata(m_axis_fetcher_rdata), .m_axis_fetcher_rresp(m_axis_fetcher_rresp),
        .m_axis_fetcher_rlast(m_axis_fetcher_rlast), .m_axis_fetcher_rvalid(m_axis_fetcher_rvalid), .m_axis_fetcher_rready(m_axis_fetcher_rready),
        .dma_irq(dma_irq)
    );

    // ------------------------------------------------------------------------
    // DDR model with configurable backpressure
    // ------------------------------------------------------------------------
    logic backpressure_enable = 1'b0;
    int bp_cycle = 0;
    logic m_axis_awready_reg = 1'b1;
    logic m_axis_wready_reg = 1'b1;
    logic m_axis_bvalid_reg = 1'b0;

    assign m_axis_awready = m_axis_awready_reg;
    assign m_axis_wready = m_axis_wready_reg;
    assign m_axis_bvalid = m_axis_bvalid_reg;
    assign m_axis_bresp = 2'b00;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bp_cycle <= 0;
            m_axis_awready_reg <= 1'b1;
            m_axis_wready_reg <= 1'b1;
        end else if (backpressure_enable) begin
            bp_cycle <= bp_cycle + 1;
            m_axis_awready_reg <= ((bp_cycle % 23) < 18);
            m_axis_wready_reg <= ((bp_cycle % 17) < 12);
        end else begin
            bp_cycle <= 0;
            m_axis_awready_reg <= 1'b1;
            m_axis_wready_reg <= 1'b1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_bvalid_reg <= 1'b0;
        end else begin
            if (m_axis_wvalid && m_axis_wready && m_axis_wlast) begin
                m_axis_bvalid_reg <= 1'b1;
            end else if (m_axis_bready) begin
                m_axis_bvalid_reg <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Buffers and monitors
    // ------------------------------------------------------------------------
    logic [31:0] cap_buf [0:MAX_WORDS-1];
    logic [31:0] buf_in  [0:MAX_WORDS-1];
    logic [31:0] buf_mid [0:MAX_WORDS-1];
    logic [31:0] buf_out [0:MAX_WORDS-1];
    logic [31:0] buf_tmp [0:MAX_WORDS-1];
    int cap_count = 0;
    logic capture_enable = 1'b0;
    logic monitor_enable = 1'b0;

    longint run_cycles = 0;
    longint run_busy_sum = 0;
    int run_max_busy = 0;
    int run_max_pbm = 0;
    int run_max_mid = 0;
    int run_max_out = 0;
    longint run_sched_count = 0;
    longint run_mid_count = 0;
    longint run_sched_gap_sum = 0;
    longint run_mid_gap_sum = 0;
    longint run_last_sched_cycle = 0;
    longint run_last_mid_cycle = 0;
    logic run_have_sched = 1'b0;
    logic run_have_mid = 1'b0;
    longint run_collect_wait_cycles = 0;
    longint run_dispatch_noinst_cycles = 0;
    longint run_mid_full_cycles = 0;
    longint run_out_full_cycles = 0;
    longint run_gb_blocked_cycles = 0;
    longint run_tx_wait_cycles = 0;
    longint inst_busy_cycles [0:NUM_PARALLEL_BLOCKS-1];
    integer inst_start_count [0:NUM_PARALLEL_BLOCKS-1];
    integer inst_done_count [0:NUM_PARALLEL_BLOCKS-1];
    longint inst_service_sum [0:NUM_PARALLEL_BLOCKS-1];
    longint inst_service_min [0:NUM_PARALLEL_BLOCKS-1];
    longint inst_service_max [0:NUM_PARALLEL_BLOCKS-1];
    longint inst_active_start [0:NUM_PARALLEL_BLOCKS-1];

    always_ff @(posedge clk) begin
        if (capture_enable && m_axis_wvalid && m_axis_wready) begin
            if (cap_count < MAX_WORDS) begin
                cap_buf[cap_count] <= m_axis_wdata;
                cap_count <= cap_count + 1;
            end
        end
    end

    always_ff @(posedge clk) begin
        integer i_mon;
        int busy_now;
        int pbm_now;
        int mid_now;
        int out_now;
        if (monitor_enable) begin
            busy_now = $countones(u_dut.u_crypto_bridge.inst_busy);
            pbm_now  = int'(u_dut.u_pbm.o_buffer_usage);
            mid_now  = int'(u_dut.u_crypto_bridge.u_mid_fifo.cnt);
            out_now  = int'(u_dut.u_crypto_bridge.u_out_fifo.cnt);

            run_cycles   <= run_cycles + 1;
            run_busy_sum <= run_busy_sum + busy_now;
            if (busy_now > run_max_busy) run_max_busy <= busy_now;
            if (pbm_now  > run_max_pbm)  run_max_pbm  <= pbm_now;
            if (mid_now  > run_max_mid)  run_max_mid  <= mid_now;
            if (out_now  > run_max_out)  run_max_out  <= out_now;

            if (crypto_sched_valid) begin
                run_sched_count <= run_sched_count + 1;
                if (run_have_sched) begin
                    run_sched_gap_sum <= run_sched_gap_sum + (cycle_counter - run_last_sched_cycle);
                end
                run_last_sched_cycle <= cycle_counter;
                run_have_sched <= 1'b1;
            end

            if (crypto_mid_wr) begin
                run_mid_count <= run_mid_count + 1;
                if (run_have_mid) begin
                    run_mid_gap_sum <= run_mid_gap_sum + (cycle_counter - run_last_mid_cycle);
                end
                run_last_mid_cycle <= cycle_counter;
                run_have_mid <= 1'b1;
            end

            if ((u_dut.u_crypto_bridge.input_state == 3'd1) && u_dut.pbm_empty) begin
                run_collect_wait_cycles <= run_collect_wait_cycles + 1;
            end
            if ((u_dut.u_crypto_bridge.input_state == 3'd2) && ($countones(u_dut.u_crypto_bridge.inst_available) == 0)) begin
                run_dispatch_noinst_cycles <= run_dispatch_noinst_cycles + 1;
            end
            if (u_dut.u_crypto_bridge.mid_fifo_full) begin
                run_mid_full_cycles <= run_mid_full_cycles + 1;
            end
            if (u_dut.u_crypto_bridge.out_fifo_full) begin
                run_out_full_cycles <= run_out_full_cycles + 1;
            end
            if (u_dut.u_crypto_bridge.gb_dout_valid && !u_dut.u_crypto_bridge.gb_dout_ready) begin
                run_gb_blocked_cycles <= run_gb_blocked_cycles + 1;
            end
            if (!u_dut.u_crypto_bridge.o_tx_empty && !u_dut.bridge_tx_rd_en) begin
                run_tx_wait_cycles <= run_tx_wait_cycles + 1;
            end

            for (i_mon = 0; i_mon < NUM_PARALLEL_BLOCKS; i_mon++) begin
                if (u_dut.u_crypto_bridge.inst_busy[i_mon]) begin
                    inst_busy_cycles[i_mon] <= inst_busy_cycles[i_mon] + 1;
                end
                if (u_dut.u_crypto_bridge.inst_start[i_mon]) begin
                    inst_start_count[i_mon] <= inst_start_count[i_mon] + 1;
                    inst_active_start[i_mon] <= cycle_counter;
                end
                if (u_dut.u_crypto_bridge.inst_result_valid[i_mon] && u_dut.u_crypto_bridge.inst_busy[i_mon]) begin
                    longint service_cycles;
                    service_cycles = cycle_counter - inst_active_start[i_mon];
                    inst_done_count[i_mon] <= inst_done_count[i_mon] + 1;
                    inst_service_sum[i_mon] <= inst_service_sum[i_mon] + service_cycles;
                    if ((inst_service_min[i_mon] < 0) || (service_cycles < inst_service_min[i_mon])) begin
                        inst_service_min[i_mon] <= service_cycles;
                    end
                    if (service_cycles > inst_service_max[i_mon]) begin
                        inst_service_max[i_mon] <= service_cycles;
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // Reporting
    // ------------------------------------------------------------------------
    integer report_fd;
    int test_total = 0;
    int test_pass = 0;
    int test_fail = 0;
    int checks_total = 0;
    int checks_pass = 0;
    int checks_fail = 0;

    task automatic log_line(input string line);
        begin
            $display("%s", line);
            if (report_fd != 0) $fdisplay(report_fd, "%s", line);
        end
    endtask

    task automatic record_check(input string check_name, input bit pass_cond);
        begin
            checks_total++;
            if (pass_cond) begin
                checks_pass++;
                log_line($sformatf("  [CHECK PASS] %s", check_name));
            end else begin
                checks_fail++;
                log_line($sformatf("  [CHECK FAIL] %s", check_name));
            end
        end
    endtask

    task automatic finish_test(input string test_name, input bit pass_cond);
        begin
            test_total++;
            if (pass_cond) begin
                test_pass++;
                log_line($sformatf("[TEST PASS] %s", test_name));
            end else begin
                test_fail++;
                log_line($sformatf("[TEST FAIL] %s", test_name));
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------
    function automatic [31:0] pattern_word(input int seed, input int idx);
        logic [31:0] x;
        begin
            x = 32'h1f12_3bb5 ^ (seed * 32'h9e37_79b9) ^ (idx * 32'h85eb_ca6b);
            x = {x[15:0], x[31:16]} ^ {idx[15:0], seed[15:0]};
            pattern_word = x;
        end
    endfunction

    function automatic [31:0] get_buf_word(input int buf_id, input int idx);
        begin
            case (buf_id)
                BUF_IN:  get_buf_word = buf_in[idx];
                BUF_MID: get_buf_word = buf_mid[idx];
                BUF_OUT: get_buf_word = buf_out[idx];
                BUF_TMP: get_buf_word = buf_tmp[idx];
                default: get_buf_word = 32'h0;
            endcase
        end
    endfunction

    task automatic set_buf_word(input int buf_id, input int idx, input logic [31:0] val);
        begin
            case (buf_id)
                BUF_IN:  buf_in[idx]  = val;
                BUF_MID: buf_mid[idx] = val;
                BUF_OUT: buf_out[idx] = val;
                BUF_TMP: buf_tmp[idx] = val;
                default: ;
            endcase
        end
    endtask

    function automatic [31:0] crc32_byte(input [31:0] crc_in, input [7:0] data_byte);
        integer bi;
        reg [31:0] crc;
        begin
            crc = crc_in ^ data_byte;
            for (bi = 0; bi < 8; bi++) begin
                if (crc[0]) crc = (crc >> 1) ^ 32'hEDB8_8320;
                else crc = crc >> 1;
            end
            crc32_byte = crc;
        end
    endfunction

    task automatic calc_crc_buffer(input int buf_id, input int words, output logic [31:0] crc_out);
        integer i;
        logic [31:0] crc;
        logic [31:0] w;
        begin
            crc = 32'hFFFF_FFFF;
            for (i = 0; i < words; i++) begin
                w = get_buf_word(buf_id, i);
                crc = crc32_byte(crc, w[7:0]);
                crc = crc32_byte(crc, w[15:8]);
                crc = crc32_byte(crc, w[23:16]);
                crc = crc32_byte(crc, w[31:24]);
            end
            crc_out = ~crc;
        end
    endtask

    task automatic fill_pattern(input int buf_id, input int words, input int seed);
        integer i;
        begin
            for (i = 0; i < words; i++) begin
                set_buf_word(buf_id, i, pattern_word(seed, i));
            end
        end
    endtask

    task automatic clear_capture;
        begin
            cap_count = 0;
            @(posedge clk);
        end
    endtask

    task automatic copy_capture_to_buffer(input int dst_buf, input int words);
        integer i;
        begin
            for (i = 0; i < words; i++) begin
                if (i < cap_count) set_buf_word(dst_buf, i, cap_buf[i]);
                else set_buf_word(dst_buf, i, 32'hDEAD_DEAD);
            end
        end
    endtask

    task automatic compare_buffers(
        input int buf_a,
        input int buf_b,
        input int words,
        output bit match
    );
        integer i;
        begin
            match = 1'b1;
            for (i = 0; i < words; i++) begin
                if (get_buf_word(buf_a, i) !== get_buf_word(buf_b, i)) begin
                    match = 1'b0;
                    if (i < 16) begin
                        log_line($sformatf(
                            "    mismatch[%0d] exp=%08h got=%08h",
                            i, get_buf_word(buf_a, i), get_buf_word(buf_b, i)
                        ));
                    end
                end
            end
        end
    endtask

    task automatic buffers_different(
        input int buf_a,
        input int buf_b,
        input int words,
        output bit different
    );
        integer i;
        begin
            different = 1'b0;
            for (i = 0; i < words; i++) begin
                if (get_buf_word(buf_a, i) !== get_buf_word(buf_b, i)) begin
                    different = 1'b1;
                end
            end
        end
    endtask

    task automatic reset_run_monitor;
        integer i;
        begin
            run_cycles = 0;
            run_busy_sum = 0;
            run_max_busy = 0;
            run_max_pbm = 0;
            run_max_mid = 0;
            run_max_out = 0;
            run_sched_count = 0;
            run_mid_count = 0;
            run_sched_gap_sum = 0;
            run_mid_gap_sum = 0;
            run_last_sched_cycle = 0;
            run_last_mid_cycle = 0;
            run_have_sched = 1'b0;
            run_have_mid = 1'b0;
            run_collect_wait_cycles = 0;
            run_dispatch_noinst_cycles = 0;
            run_mid_full_cycles = 0;
            run_out_full_cycles = 0;
            run_gb_blocked_cycles = 0;
            run_tx_wait_cycles = 0;
            for (i = 0; i < NUM_PARALLEL_BLOCKS; i++) begin
                inst_busy_cycles[i] = 0;
                inst_start_count[i] = 0;
                inst_done_count[i] = 0;
                inst_service_sum[i] = 0;
                inst_service_min[i] = -1;
                inst_service_max[i] = 0;
                inst_active_start[i] = 0;
            end
            @(posedge clk);
        end
    endtask

    task automatic dut_clean_reset;
        begin
            // Clear TB-driven handshakes before reset
            s_axil_awaddr  <= 32'h0;
            s_axil_awvalid <= 1'b0;
            s_axil_wdata   <= 32'h0;
            s_axil_wstrb   <= 4'h0;
            s_axil_wvalid  <= 1'b0;
            s_axil_bready  <= 1'b0;
            s_axil_araddr  <= 32'h0;
            s_axil_arvalid <= 1'b0;
            s_axil_rready  <= 1'b0;
            rx_wr_valid    <= 1'b0;
            rx_wr_data     <= 32'h0;
            rx_wr_last     <= 1'b0;
            capture_enable <= 1'b0;
            monitor_enable <= 1'b0;
            backpressure_enable <= 1'b0;
            cap_count <= 0;

            @(posedge clk);
            rst_n <= 1'b0;
            repeat (8) @(posedge clk);
            rst_n <= 1'b1;
            repeat (12) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------------
    // AXI-Lite transactions
    // ------------------------------------------------------------------------
    task automatic axil_write(input logic [31:0] addr, input logic [31:0] data);
        begin
            @(posedge clk);
            s_axil_awaddr  <= addr;
            s_axil_awvalid <= 1'b1;
            s_axil_wdata   <= data;
            s_axil_wstrb   <= 4'hF;
            s_axil_wvalid  <= 1'b1;
            s_axil_bready  <= 1'b1;

            wait (s_axil_awready && s_axil_wready);
            @(posedge clk);
            s_axil_awvalid <= 1'b0;
            s_axil_wvalid  <= 1'b0;

            wait (s_axil_bvalid);
            @(posedge clk);
            s_axil_bready  <= 1'b0;
        end
    endtask

    task automatic axil_read(input logic [31:0] addr, output logic [31:0] data);
        begin
            @(posedge clk);
            s_axil_araddr  <= addr;
            s_axil_arvalid <= 1'b1;
            s_axil_rready  <= 1'b1;

            wait (s_axil_arready);
            @(posedge clk);
            s_axil_arvalid <= 1'b0;

            wait (s_axil_rvalid);
            data = s_axil_rdata;
            @(posedge clk);
            s_axil_rready <= 1'b0;
        end
    endtask

    task automatic program_key(input logic [127:0] key_val);
        begin
            axil_write(CSR_KEY0, key_val[31:0]);
            axil_write(CSR_KEY1, key_val[63:32]);
            axil_write(CSR_KEY2, key_val[95:64]);
            axil_write(CSR_KEY3, key_val[127:96]);
        end
    endtask

    task automatic send_buffer_words(
        input int src_buf,
        input int words,
        output bit push_ok
    );
        integer i;
        int stall_cycles;
        int commit_words;
        bit commit_last;
        begin
            push_ok = 1'b1;
            commit_words = (pbm_commit_words > 0) ? pbm_commit_words : words;
            for (i = 0; i < words; i++) begin
                commit_last = (i == words - 1);
                if (!commit_last && commit_words > 0) begin
                    commit_last = (((i + 1) % commit_words) == 0);
                end
                
                // Assert payload and wait for handshake
                rx_wr_valid <= 1'b1;
                rx_wr_data  <= get_buf_word(src_buf, i);
                rx_wr_last  <= commit_last;
                
                stall_cycles = 0;
                do begin
                    @(posedge clk);
                    if (!rx_wr_ready) begin
                        stall_cycles++;
                        if ((stall_cycles % 1_000_000) == 0) begin
                            log_line($sformatf(
                                "[TX STALL] word=%0d/%0d stalled=%0d cycles pbm_usage=%0d pbm_state=%0d bridge_state=%0d mid=%0d out=%0d dma_state=%0d beat=%0d/%0d",
                                i, words, stall_cycles,
                                int'(u_dut.u_pbm.o_buffer_usage),
                                int'(u_dut.u_pbm.state),
                                int'(u_dut.u_crypto_bridge.input_state),
                                int'(u_dut.u_crypto_bridge.u_mid_fifo.cnt),
                                int'(u_dut.u_crypto_bridge.u_out_fifo.cnt),
                                int'(u_dut.u_dma_engine.state),
                                int'(u_dut.u_dma_engine.beat_count),
                                int'(u_dut.u_dma_engine.current_awlen)
                            ));
                        end
                        if (stall_cycles >= 5_000_000) begin
                            push_ok = 1'b0;
                            log_line($sformatf(
                                "[TX STALL TIMEOUT] word=%0d/%0d, abort send", i, words
                            ));
                            rx_wr_valid <= 1'b0;
                            rx_wr_data  <= 32'h0;
                            rx_wr_last  <= 1'b0;
                            return;
                        end
                    end
                end while (!rx_wr_ready);
                
                // Handshake completed on this clock edge, drop valid next cycle or setup next data (the non-blocking assignment handles it)
            end
            
            // Clear valid after the last word is accepted
            rx_wr_valid <= 1'b0;
            rx_wr_data  <= 32'h0;
            rx_wr_last  <= 1'b0;
        end
    endtask

    task automatic wait_transfer_done(
        input int expected_words,
        input int timeout_cycles,
        output bit timeout_hit,
        output longint data_done_cycle
    );
        int i;
        bit irq_seen;
        bit data_seen;
        begin
            timeout_hit = 1'b1;
            irq_seen = 1'b0;
            data_seen = 1'b0;
            data_done_cycle = 0;
            for (i = 0; i < timeout_cycles; i++) begin
                @(posedge clk);
                if (dma_irq) irq_seen = 1'b1;
                if (!data_seen && (cap_count >= expected_words)) begin
                    data_seen = 1'b1;
                    data_done_cycle = cycle_counter;
                end
                if (irq_seen && data_seen) begin
                    timeout_hit = 1'b0;
                    break;
                end
            end
            if (!data_seen) data_done_cycle = cycle_counter;
        end
    endtask

    task automatic run_transfer(
        input  string test_tag,
        input  bit algo_sel,         // 0=AES, 1=SM4
        input  bit enc_mode,         // 1=ENC, 0=DEC
        input  logic [127:0] key_val,
        input  int num_bytes,
        input  int src_buf,
        input  int dst_buf,
        input  bit enable_bp,
        input  bit verbose,
        output bit pass_flag,
        output longint latency_cycles,
        output real throughput_mbps,
        output real parallel_eff_pct,
        output real fifo_util_pct,
        output logic [31:0] crc_in,
        output logic [31:0] crc_out
    );
        int words;
        int ctrl_val;
        int timeout_cycles;
        bit timeout_hit;
        bit push_ok;
        longint start_cycle;
        longint end_cycle;
        longint data_done_cycle;
        real elapsed_s;
        longint sys_latency;
        real sys_tp;
        real avg_sched_gap;
        real avg_mid_gap;
        real avg_block_service;
        real collect_wait_pct;
        real dispatch_noinst_pct;
        real mid_full_pct;
        real out_full_pct;
        real gb_blocked_pct;
        real tx_wait_pct;
        integer inst_i;
        integer total_done_blocks;
        longint total_service_cycles;
        real inst_avg_service;
        real inst_busy_pct;
        begin
            words = num_bytes / 4;
            pass_flag = 1'b0;
            latency_cycles = 0;
            throughput_mbps = 0.0;
            parallel_eff_pct = 0.0;
            fifo_util_pct = 0.0;
            crc_in = 32'h0;
            crc_out = 32'h0;

            // Reset precise crypto timestamp for this transfer
            crypto_ts_enable = 1'b0;
            @(posedge clk);
            crypto_ts_started  = 1'b0;
            crypto_start_cycle = 0;
            crypto_end_cycle   = 0;
            crypto_blocks_out  = 0;
            crypto_expected_blocks = num_bytes / 16;
            crypto_ts_enable = 1'b1;

            if (num_bytes <= 0 || (num_bytes % 16) != 0) begin
                if (verbose) log_line($sformatf("[%s] invalid transfer size: %0d", test_tag, num_bytes));
                return;
            end

            if (reset_each_transfer) begin
                // Optional isolation mode for debug; disabled for throughput tests.
                dut_clean_reset();
            end

            timeout_cycles = 10000 + (words * 40);
            backpressure_enable = enable_bp;

            clear_capture();
            reset_run_monitor();
            capture_enable = 1'b1;
            monitor_enable = 1'b1;

            axil_write(CSR_RING_SIZE, 32'd0);
            axil_write(CSR_LOOPBACK,  32'd0);
            program_key(key_val);
            axil_write(CSR_BASE_ADDR, BASE_ADDR);
            axil_write(CSR_LEN, num_bytes[31:0]);

            ctrl_val = (algo_sel ? 32'h4 : 32'h0) | (enc_mode ? 32'h8 : 32'h0);
            start_cycle = cycle_counter;
            axil_write(CSR_CTRL, ctrl_val | 32'h1); // start pulse

            send_buffer_words(src_buf, words, push_ok);
            if (!push_ok) begin
                capture_enable = 1'b0;
                monitor_enable = 1'b0;
                backpressure_enable = 1'b0;
                if (verbose) begin
                    log_line($sformatf("[%s] TX push timeout, transfer aborted", test_tag));
                end
                return;
            end
            wait_transfer_done(words, timeout_cycles, timeout_hit, data_done_cycle);
            end_cycle = data_done_cycle;

            capture_enable = 1'b0;
            monitor_enable = 1'b0;
            crypto_ts_enable = 1'b0;
            backpressure_enable = 1'b0;
            copy_capture_to_buffer(dst_buf, words);

            calc_crc_buffer(src_buf, words, crc_in);
            calc_crc_buffer(dst_buf, words, crc_out);

            // Compute System-level throughput (includes AXI & DMA overhead)
            sys_latency = end_cycle - start_cycle;
            sys_tp = 0.0;
            if (sys_latency > 0) sys_tp = (num_bytes / (sys_latency * (CLK_PERIOD_NS * 1e-9))) / 1e6;

            // Use PRECISE crypto timestamp if available, else fall back to coarse
            if (crypto_ts_started && crypto_blocks_out >= crypto_expected_blocks) begin
                latency_cycles = crypto_end_cycle - crypto_start_cycle;
            end else begin
                latency_cycles = sys_latency;
            end
            elapsed_s = latency_cycles * (CLK_PERIOD_NS * 1e-9);
            if (elapsed_s > 0.0) throughput_mbps = (num_bytes / elapsed_s) / 1e6;
            if (run_cycles > 0) parallel_eff_pct = (run_busy_sum * 100.0) / (run_cycles * NUM_PARALLEL_BLOCKS);
            fifo_util_pct = (run_max_out * 100.0) / 128.0;
            avg_sched_gap = 0.0;
            avg_mid_gap = 0.0;
            avg_block_service = 0.0;
            collect_wait_pct = 0.0;
            dispatch_noinst_pct = 0.0;
            mid_full_pct = 0.0;
            out_full_pct = 0.0;
            gb_blocked_pct = 0.0;
            tx_wait_pct = 0.0;
            total_done_blocks = 0;
            total_service_cycles = 0;
            if (run_sched_count > 1) avg_sched_gap = real'(run_sched_gap_sum) / real'(run_sched_count - 1);
            if (run_mid_count > 1) avg_mid_gap = real'(run_mid_gap_sum) / real'(run_mid_count - 1);
            if (run_cycles > 0) begin
                collect_wait_pct = real'(run_collect_wait_cycles) * 100.0 / real'(run_cycles);
                dispatch_noinst_pct = real'(run_dispatch_noinst_cycles) * 100.0 / real'(run_cycles);
                mid_full_pct = real'(run_mid_full_cycles) * 100.0 / real'(run_cycles);
                out_full_pct = real'(run_out_full_cycles) * 100.0 / real'(run_cycles);
                gb_blocked_pct = real'(run_gb_blocked_cycles) * 100.0 / real'(run_cycles);
                tx_wait_pct = real'(run_tx_wait_cycles) * 100.0 / real'(run_cycles);
            end
            for (inst_i = 0; inst_i < NUM_PARALLEL_BLOCKS; inst_i++) begin
                total_done_blocks += inst_done_count[inst_i];
                total_service_cycles += inst_service_sum[inst_i];
            end
            if (total_done_blocks > 0) avg_block_service = real'(total_service_cycles) / real'(total_done_blocks);

            log_line($sformatf("[%s] SYSTEM-LEVEL (with AXI/DMA): latency=%0d cyc, throughput=%0.2f MB/s", test_tag, sys_latency, sys_tp));
            log_line($sformatf("[%s] DIAG blocks sched=%0d out=%0d avg_sched_gap=%0.2f cyc avg_done_gap=%0.2f cyc avg_block_service=%0.2f cyc",
                               test_tag, run_sched_count, run_mid_count, avg_sched_gap, avg_mid_gap, avg_block_service));
            log_line($sformatf("[%s] DIAG pressure parallel_eff=%0.2f%% pbm_max=%0d mid_max=%0d out_max=%0d",
                               test_tag, parallel_eff_pct, run_max_pbm, run_max_mid, run_max_out));
            log_line($sformatf("[%s] DIAG stall_pct collect_wait=%0.2f%% dispatch_noinst=%0.2f%% mid_full=%0.2f%% out_full=%0.2f%% gb_blocked=%0.2f%% tx_wait=%0.2f%%",
                               test_tag, collect_wait_pct, dispatch_noinst_pct, mid_full_pct, out_full_pct, gb_blocked_pct, tx_wait_pct));
            for (inst_i = 0; inst_i < NUM_PARALLEL_BLOCKS; inst_i++) begin
                inst_avg_service = 0.0;
                inst_busy_pct = 0.0;
                if (inst_done_count[inst_i] > 0) begin
                    inst_avg_service = real'(inst_service_sum[inst_i]) / real'(inst_done_count[inst_i]);
                end
                if (run_cycles > 0) begin
                    inst_busy_pct = real'(inst_busy_cycles[inst_i]) * 100.0 / real'(run_cycles);
                end
                log_line($sformatf("[%s] DIAG inst%0d starts=%0d dones=%0d avg_service=%0.2f cyc min=%0d max=%0d busy_pct=%0.2f%%",
                                   test_tag, inst_i, inst_start_count[inst_i], inst_done_count[inst_i],
                                   inst_avg_service, inst_service_min[inst_i], inst_service_max[inst_i], inst_busy_pct));
            end

            pass_flag = (!timeout_hit) && (cap_count >= words);
            if (!pass_flag) begin
                log_line($sformatf("[%s] bytes=%0d words=%0d captured=%0d timeout=%0b", test_tag, num_bytes, words, cap_count, timeout_hit));
                if (crypto_ts_started && crypto_blocks_out >= crypto_expected_blocks) begin
                    log_line($sformatf("[%s] PRECISE: crypto_start=%0d crypto_end=%0d blocks=%0d/%0d",
                                       test_tag, crypto_start_cycle, crypto_end_cycle,
                                       crypto_blocks_out, crypto_expected_blocks));
                end
                log_line($sformatf("[%s] latency=%0d cyc, throughput=%0.2f MB/s, parallel_eff=%0.2f%%, out_fifo_max=%0d (util=%0.2f%%)",
                                   test_tag, latency_cycles, throughput_mbps, parallel_eff_pct, run_max_out, fifo_util_pct));
                log_line($sformatf("[%s] crc_in=%08h crc_out=%08h", test_tag, crc_in, crc_out));
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Test cases requested by user
    // ------------------------------------------------------------------------
    task automatic test_N_parallel_blocks;
        bit pass_aes_enc, pass_aes_dec, pass_sm4_enc, pass_sm4_dec;
        bit match_aes, match_sm4;
        longint lat;
        real tp, pe, fu;
        logic [31:0] crc0, crc1;
        int bytes;
        begin
            bytes = NUM_PARALLEL_BLOCKS * 16 * 16;
            log_line("==================================================");
            log_line($sformatf("test_%0d_parallel_blocks", NUM_PARALLEL_BLOCKS));
            log_line("==================================================");

            fill_pattern(BUF_IN, bytes/4, 32'h101);

            // --- AES Roundtrip (clean pipeline between enc/dec) ---
            dut_clean_reset();
            axil_write(CSR_RING_SIZE, 32'd0);
            axil_write(CSR_LOOPBACK,  32'd0);

            run_transfer($sformatf("%0dblk_aes_enc", NUM_PARALLEL_BLOCKS), 1'b0, 1'b1, AES128_KEY, bytes, BUF_IN, BUF_MID, 1'b0, 1'b1,
                         pass_aes_enc, lat, tp, pe, fu, crc0, crc1);

            dut_clean_reset();
            axil_write(CSR_RING_SIZE, 32'd0);
            axil_write(CSR_LOOPBACK,  32'd0);
            run_transfer($sformatf("%0dblk_aes_dec", NUM_PARALLEL_BLOCKS), 1'b0, 1'b0, AES128_KEY, bytes, BUF_MID, BUF_OUT, 1'b0, 1'b1,
                         pass_aes_dec, lat, tp, pe, fu, crc0, crc1);

            compare_buffers(BUF_IN, BUF_OUT, bytes/4, match_aes);
            record_check("AES N-block roundtrip", pass_aes_enc && pass_aes_dec && match_aes);

            // --- SM4 Roundtrip (clean pipeline between enc/dec) ---
            dut_clean_reset();
            axil_write(CSR_RING_SIZE, 32'd0);
            axil_write(CSR_LOOPBACK,  32'd0);

            run_transfer($sformatf("%0dblk_sm4_enc", NUM_PARALLEL_BLOCKS), 1'b1, 1'b1, SM4_KEY, bytes, BUF_IN, BUF_MID, 1'b0, 1'b1,
                         pass_sm4_enc, lat, tp, pe, fu, crc0, crc1);

            dut_clean_reset();
            axil_write(CSR_RING_SIZE, 32'd0);
            axil_write(CSR_LOOPBACK,  32'd0);
            run_transfer($sformatf("%0dblk_sm4_dec", NUM_PARALLEL_BLOCKS), 1'b1, 1'b0, SM4_KEY, bytes, BUF_MID, BUF_OUT, 1'b0, 1'b1,
                         pass_sm4_dec, lat, tp, pe, fu, crc0, crc1);

            compare_buffers(BUF_IN, BUF_OUT, bytes/4, match_sm4);
            record_check("SM4 N-block roundtrip", pass_sm4_enc && pass_sm4_dec && match_sm4);

            finish_test("test_N_parallel_blocks", (pass_aes_enc && pass_aes_dec && match_aes && pass_sm4_enc && pass_sm4_dec && match_sm4));
        end
    endtask

    task automatic test_throughput_aes;
        int size_list [0:3];
        int size_count;
        int repeat_num;
        int warmup_num;
        int si, ri, wi;
        bit pass_run;
        longint lat;
        real tp, pe, fu;
        real tp_sum, lat_sum, pe_sum, fu_sum;
        int ok_runs;
        logic [31:0] crc0, crc1;
        bit task_pass;
        int plusarg_ok;
        begin
            // Isolate throughput test from previous task side effects.
            dut_clean_reset();
            axil_write(CSR_RING_SIZE, 32'd0);
            axil_write(CSR_LOOPBACK,  32'd0);

            size_list[0] = 1024 * 1024; // 1MB (Large)
            size_list[1] = 65536;       // 64KB (Medium)
            size_list[2] = 1024;        // 1KB (Small)
            size_list[3] = 1024 * 1024;
            size_count = 3;
            repeat_num = DEFAULT_REPEAT_NUM;
            warmup_num = 1;
            plusarg_ok = $value$plusargs("THROUGHPUT_SIZE_COUNT=%d", size_count);
            plusarg_ok = $value$plusargs("THROUGHPUT_REPEAT=%d", repeat_num);
            plusarg_ok = $value$plusargs("THROUGHPUT_WARMUP=%d", warmup_num);
            if (size_count < 1) size_count = 1;
            if (size_count > 4) size_count = 4;

            log_line("==================================================");
            log_line("test_throughput_aes");
            log_line("==================================================");
            task_pass = 1'b1;

            for (si = 0; si < size_count; si++) begin
                tp_sum = 0.0;
                lat_sum = 0.0;
                pe_sum = 0.0;
                fu_sum = 0.0;
                ok_runs = 0;
                log_line($sformatf("  AES size=%0dB warmup=%0d repeat=%0d", size_list[si], warmup_num, repeat_num));

                // Warmup runs are not counted in average throughput.
                for (wi = 0; wi < warmup_num; wi++) begin
                    fill_pattern(BUF_IN, size_list[si]/4, (32'h2A00 + si*29 + wi));
                    run_transfer($sformatf("aes_tp_%0dB_warmup%0d", size_list[si], wi+1),
                                 1'b0, 1'b1, AES128_KEY, size_list[si],
                                 BUF_IN, BUF_MID, 1'b0, 1'b0,
                                 pass_run, lat, tp, pe, fu, crc0, crc1);
                end

                for (ri = 0; ri < repeat_num; ri++) begin
                    fill_pattern(BUF_IN, size_list[si]/4, (32'h2000 + si*17 + ri));
                    run_transfer($sformatf("aes_tp_%0dB_run%0d", size_list[si], ri+1),
                                 1'b0, 1'b1, AES128_KEY, size_list[si],
                                 BUF_IN, BUF_MID, 1'b0, 1'b1,
                                 pass_run, lat, tp, pe, fu, crc0, crc1);
                    if (pass_run) begin
                        ok_runs++;
                        tp_sum += tp;
                        lat_sum += lat;
                        pe_sum += pe;
                        fu_sum += fu;
                    end
                end

                if (ok_runs > 0) begin
                    tp_sum = tp_sum / ok_runs;
                    lat_sum = lat_sum / ok_runs;
                    pe_sum = pe_sum / ok_runs;
                    fu_sum = fu_sum / ok_runs;
                    log_line($sformatf("  AES size=%0dB avg_tp=%0.2f MB/s avg_lat=%0.1f cyc avg_eff=%0.2f%% avg_fifo_util=%0.2f%%",
                                       size_list[si], tp_sum, lat_sum, pe_sum, fu_sum));
                    record_check($sformatf("AES throughput >=150MB/s @%0dB", size_list[si]), (tp_sum >= TARGET_TP_MBPS));
                    if (tp_sum < TARGET_TP_MBPS) task_pass = 1'b0;
                end else begin
                    log_line($sformatf("  AES size=%0dB no valid run", size_list[si]));
                    task_pass = 1'b0;
                end
            end

            finish_test("test_throughput_aes", task_pass);
        end
    endtask

    task automatic test_throughput_sm4;
        int size_list [0:3];
        int size_count;
        int repeat_num;
        int warmup_num;
        int si, ri, wi;
        bit pass_run;
        longint lat;
        real tp, pe, fu;
        real tp_sum, lat_sum, pe_sum, fu_sum;
        int ok_runs;
        logic [31:0] crc0, crc1;
        bit task_pass;
        int plusarg_ok;
        begin
            // Isolate algorithm switch (AES->SM4) to avoid stale pipeline state.
            dut_clean_reset();
            axil_write(CSR_RING_SIZE, 32'd0);
            axil_write(CSR_LOOPBACK,  32'd0);

            size_list[0] = 1024 * 1024; // 1MB (Large)
            size_list[1] = 65536;       // 64KB (Medium)
            size_list[2] = 1024;        // 1KB (Small)
            size_list[3] = 1024 * 1024;
            size_count = 3;
            repeat_num = DEFAULT_REPEAT_NUM;
            warmup_num = 1;
            plusarg_ok = $value$plusargs("THROUGHPUT_SIZE_COUNT=%d", size_count);
            plusarg_ok = $value$plusargs("THROUGHPUT_REPEAT=%d", repeat_num);
            plusarg_ok = $value$plusargs("THROUGHPUT_WARMUP=%d", warmup_num);
            if (size_count < 1) size_count = 1;
            if (size_count > 4) size_count = 4;

            log_line("==================================================");
            log_line("test_throughput_sm4");
            log_line("==================================================");
            task_pass = 1'b1;

            for (si = 0; si < size_count; si++) begin
                tp_sum = 0.0;
                lat_sum = 0.0;
                pe_sum = 0.0;
                fu_sum = 0.0;
                ok_runs = 0;
                log_line($sformatf("  SM4 size=%0dB warmup=%0d repeat=%0d", size_list[si], warmup_num, repeat_num));

                // Warmup runs are not counted in average throughput.
                for (wi = 0; wi < warmup_num; wi++) begin
                    fill_pattern(BUF_IN, size_list[si]/4, (32'h3A00 + si*31 + wi));
                    run_transfer($sformatf("sm4_tp_%0dB_warmup%0d", size_list[si], wi+1),
                                 1'b1, 1'b1, SM4_KEY, size_list[si],
                                 BUF_IN, BUF_MID, 1'b0, 1'b0,
                                 pass_run, lat, tp, pe, fu, crc0, crc1);
                end

                for (ri = 0; ri < repeat_num; ri++) begin
                    fill_pattern(BUF_IN, size_list[si]/4, (32'h3000 + si*19 + ri));
                    run_transfer($sformatf("sm4_tp_%0dB_run%0d", size_list[si], ri+1),
                                 1'b1, 1'b1, SM4_KEY, size_list[si],
                                 BUF_IN, BUF_MID, 1'b0, 1'b1,
                                 pass_run, lat, tp, pe, fu, crc0, crc1);
                    if (pass_run) begin
                        ok_runs++;
                        tp_sum += tp;
                        lat_sum += lat;
                        pe_sum += pe;
                        fu_sum += fu;
                    end
                end

                if (ok_runs > 0) begin
                    tp_sum = tp_sum / ok_runs;
                    lat_sum = lat_sum / ok_runs;
                    pe_sum = pe_sum / ok_runs;
                    fu_sum = fu_sum / ok_runs;
                    log_line($sformatf("  SM4 size=%0dB avg_tp=%0.2f MB/s avg_lat=%0.1f cyc avg_eff=%0.2f%% avg_fifo_util=%0.2f%%",
                                       size_list[si], tp_sum, lat_sum, pe_sum, fu_sum));
                    record_check($sformatf("SM4 throughput >=150MB/s @%0dB", size_list[si]), (tp_sum >= TARGET_TP_MBPS));
                    if (tp_sum < TARGET_TP_MBPS) task_pass = 1'b0;
                end else begin
                    log_line($sformatf("  SM4 size=%0dB no valid run", size_list[si]));
                    task_pass = 1'b0;
                end
            end

            finish_test("test_throughput_sm4", task_pass);
        end
    endtask

    task automatic test_backpressure;
        bit pass_enc, pass_dec, pass_recover;
        bit data_match;
        longint lat;
        real tp, pe, fu;
        logic [31:0] crc0, crc1;
        logic [31:0] status_val;
        bit reject_seen;
        int bytes;
        begin
            log_line("==================================================");
            log_line("test_backpressure");
            log_line("==================================================");
            bytes = 100 * 1024;

            // Non-aligned length rejection
            program_key(AES128_KEY);
            axil_write(CSR_BASE_ADDR, BASE_ADDR);
            axil_write(CSR_LEN, 32'd20); // not multiple of 16
            axil_write(CSR_CTRL, 32'h0000_0009); // AES ENC + START
            repeat (20) @(posedge clk);
            axil_read(CSR_STATUS, status_val);
            reject_seen = status_val[3] || status_val[4] || status_val[1];
            record_check("Non-aligned data block reject", reject_seen);

            // Recovery with valid short transfer
            fill_pattern(BUF_IN, 4, 32'h4040);
            run_transfer("recover_after_error", 1'b0, 1'b1, AES128_KEY, 16,
                         BUF_IN, BUF_MID, 1'b0, 1'b1,
                         pass_recover, lat, tp, pe, fu, crc0, crc1);
            record_check("Error recovery transfer works", pass_recover);

            // Backpressure roundtrip
            fill_pattern(BUF_IN, bytes/4, 32'h4050);
            run_transfer("bp_aes_enc", 1'b0, 1'b1, AES128_KEY, bytes,
                         BUF_IN, BUF_MID, 1'b1, 1'b1,
                         pass_enc, lat, tp, pe, fu, crc0, crc1);
            run_transfer("bp_aes_dec", 1'b0, 1'b0, AES128_KEY, bytes,
                         BUF_MID, BUF_OUT, 1'b1, 1'b1,
                         pass_dec, lat, tp, pe, fu, crc0, crc1);
            compare_buffers(BUF_IN, BUF_OUT, bytes/4, data_match);

            record_check("Backpressure roundtrip data integrity", pass_enc && pass_dec && data_match);
            finish_test("test_backpressure", reject_seen && pass_recover && pass_enc && pass_dec && data_match);
        end
    endtask

    task automatic test_key_switch;
        bit pass_a_enc, pass_b_enc, pass_a_dec, pass_b_dec;
        bit ct_different, rt_a_match, rt_b_match;
        longint lat;
        real tp, pe, fu;
        logic [31:0] crc0, crc1;
        int bytes;
        begin
            log_line("==================================================");
            log_line("test_key_switch");
            log_line("==================================================");
            bytes = 16 * 16;

            fill_pattern(BUF_IN, bytes/4, 32'h5050);

            run_transfer("keyA_enc", 1'b0, 1'b1, AES128_KEY, bytes,
                         BUF_IN, BUF_MID, 1'b0, 1'b1,
                         pass_a_enc, lat, tp, pe, fu, crc0, crc1);
            run_transfer("keyB_enc", 1'b0, 1'b1, AES_KEY_ALT, bytes,
                         BUF_IN, BUF_OUT, 1'b0, 1'b1,
                         pass_b_enc, lat, tp, pe, fu, crc0, crc1);
            buffers_different(BUF_MID, BUF_OUT, bytes/4, ct_different);
            record_check("Ciphertext changes after key switch", pass_a_enc && pass_b_enc && ct_different);

            run_transfer("keyA_dec", 1'b0, 1'b0, AES128_KEY, bytes,
                         BUF_MID, BUF_TMP, 1'b0, 1'b1,
                         pass_a_dec, lat, tp, pe, fu, crc0, crc1);
            compare_buffers(BUF_IN, BUF_TMP, bytes/4, rt_a_match);
            record_check("Roundtrip with keyA", pass_a_dec && rt_a_match);

            run_transfer("keyB_dec", 1'b0, 1'b0, AES_KEY_ALT, bytes,
                         BUF_OUT, BUF_TMP, 1'b0, 1'b1,
                         pass_b_dec, lat, tp, pe, fu, crc0, crc1);
            compare_buffers(BUF_IN, BUF_TMP, bytes/4, rt_b_match);
            record_check("Roundtrip with keyB", pass_b_dec && rt_b_match);

            finish_test("test_key_switch", pass_a_enc && pass_b_enc && ct_different && pass_a_dec && pass_b_dec && rt_a_match && rt_b_match);
        end
    endtask

    task automatic test_stability;
        int stability_ops;
        int i;
        int op_pass;
        int op_fail;
        bit pass_run;
        longint lat;
        real tp, pe, fu;
        logic [31:0] crc0, crc1;
        bit algo;
        logic [127:0] key_sel;
        int plusarg_ok;
        begin
            stability_ops = DEFAULT_STABILITY_OP;
            plusarg_ok = $value$plusargs("STABILITY_OPS=%d", stability_ops);

            log_line("==================================================");
            log_line($sformatf("test_stability (%0d ops)", stability_ops));
            log_line("==================================================");

            op_pass = 0;
            op_fail = 0;

            for (i = 0; i < stability_ops; i++) begin
                algo = i[0];
                if (algo) begin
                    key_sel = (i[4]) ? SM4_KEY_ALT : SM4_KEY;
                end else begin
                    key_sel = (i[4]) ? AES_KEY_ALT : AES128_KEY;
                end

                fill_pattern(BUF_IN, 4, (32'h6000 + i));
                run_transfer($sformatf("stability_op_%0d", i), algo, 1'b1, key_sel, 16,
                             BUF_IN, BUF_MID, ((i % 19) == 0), 1'b0,
                             pass_run, lat, tp, pe, fu, crc0, crc1);
                if (pass_run) op_pass++;
                else op_fail++;

                if ((i % 1000) == 0) begin
                    log_line($sformatf("  progress: %0d/%0d pass=%0d fail=%0d", i, stability_ops, op_pass, op_fail));
                end
            end

            record_check("Stability 10000 operations no crash", (op_fail == 0));
            record_check("Stability success rate 100%", (op_pass == stability_ops));
            finish_test("test_stability", (op_fail == 0));
        end
    endtask

    // ------------------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------------------
    initial begin : main_test
        real success_rate;
        int reset_each_transfer_arg;
        int pbm_commit_words_arg;
        int run_func_arg;
        int run_tp_aes_arg;
        int run_tp_sm4_arg;
        int run_bp_arg;
        int run_key_arg;
        int run_stability_arg;
        int sm4_only_arg;
        bit sm4_only_mode;
        report_fd = $fopen("tb_dma_subsystem_crypto_encdec_report.log", "w");

        wait (rst_n === 1'b1);
        repeat (10) @(posedge clk);

        reset_each_transfer_arg = 1;
        if ($value$plusargs("RESET_EACH_TRANSFER=%d", reset_each_transfer_arg)) begin
            reset_each_transfer = (reset_each_transfer_arg != 0);
        end
        pbm_commit_words_arg = pbm_commit_words;
        if ($value$plusargs("PBM_COMMIT_WORDS=%d", pbm_commit_words_arg)) begin
            pbm_commit_words = pbm_commit_words_arg;
        end
        if (pbm_commit_words < 1) pbm_commit_words = 1;
        run_func_arg = run_func_test;
        run_tp_aes_arg = run_tp_aes_test;
        run_tp_sm4_arg = run_tp_sm4_test;
        run_bp_arg = run_backpressure_test;
        run_key_arg = run_key_switch_test;
        run_stability_arg = run_stability_test;
        if ($value$plusargs("RUN_FUNC=%d", run_func_arg)) run_func_test = (run_func_arg != 0);
        if ($value$plusargs("RUN_TP_AES=%d", run_tp_aes_arg)) run_tp_aes_test = (run_tp_aes_arg != 0);
        if ($value$plusargs("RUN_TP_SM4=%d", run_tp_sm4_arg)) run_tp_sm4_test = (run_tp_sm4_arg != 0);
        if ($value$plusargs("RUN_BACKPRESSURE=%d", run_bp_arg)) run_backpressure_test = (run_bp_arg != 0);
        if ($value$plusargs("RUN_KEY_SWITCH=%d", run_key_arg)) run_key_switch_test = (run_key_arg != 0);
        if ($value$plusargs("RUN_STABILITY=%d", run_stability_arg)) run_stability_test = (run_stability_arg != 0);
        sm4_only_arg = 0;
        sm4_only_mode = 1'b0;
        if ($value$plusargs("SM4_ONLY=%d", sm4_only_arg)) begin
            sm4_only_mode = (sm4_only_arg != 0);
        end
        if (sm4_only_mode) begin
            run_func_test = 1'b0;
            run_tp_aes_test = 1'b0;
            run_tp_sm4_test = 1'b1;
            run_backpressure_test = 1'b0;
            run_key_switch_test = 1'b0;
            run_stability_test = 1'b0;
        end

        log_line("##################################################");
        log_line("DMA Subsystem Crypto ENC/DEC Comprehensive Test");
        log_line("Includes: functional, throughput, backpressure, key switch, stability");
        log_line($sformatf("RESET_EACH_TRANSFER=%0d", reset_each_transfer));
        log_line($sformatf("PBM_COMMIT_WORDS=%0d", pbm_commit_words));
        log_line($sformatf("SM4_ONLY=%0d", sm4_only_mode));
        log_line($sformatf("RUN_FUNC=%0d RUN_TP_AES=%0d RUN_TP_SM4=%0d RUN_BACKPRESSURE=%0d RUN_KEY_SWITCH=%0d RUN_STABILITY=%0d",
                           run_func_test, run_tp_aes_test, run_tp_sm4_test,
                           run_backpressure_test, run_key_switch_test, run_stability_test));
        log_line("##################################################");

        // Global setup
        axil_write(CSR_RING_SIZE, 32'd0);
        axil_write(CSR_LOOPBACK,  32'd0);

        if (run_func_test) test_N_parallel_blocks();
        if (run_tp_aes_test) test_throughput_aes();
        if (run_tp_sm4_test) test_throughput_sm4();
        if (run_backpressure_test) test_backpressure();
        if (run_key_switch_test) test_key_switch();
        if (run_stability_test) test_stability();

        success_rate = (checks_total > 0) ? (checks_pass * 100.0 / checks_total) : 0.0;

        log_line("##################################################");
        log_line("FINAL SUMMARY");
        log_line("##################################################");
        log_line($sformatf("Tests       : total=%0d pass=%0d fail=%0d", test_total, test_pass, test_fail));
        log_line($sformatf("Checks      : total=%0d pass=%0d fail=%0d", checks_total, checks_pass, checks_fail));
        log_line($sformatf("SuccessRate : %0.2f%%", success_rate));
        log_line("Targets:");
        log_line("  Data integrity = 100%");
        log_line("  AES throughput >= 150 MB/s");
        log_line("  SM4 throughput >= 150 MB/s");
        log_line("  Stability = 10000 ops without crash");
        log_line("  Roundtrip consistency = 100%");

        if ((test_fail == 0) && (checks_fail == 0)) begin
            log_line("OVERALL RESULT: PASS");
        end else begin
            log_line("OVERALL RESULT: FAIL");
        end

        if (report_fd != 0) $fclose(report_fd);
        #1000;
        $finish;
    end

    initial begin : watchdog
        #2_000_000_000;
        $display("[TB TIMEOUT] simulation watchdog fired");
        if (report_fd != 0) $fclose(report_fd);
        $finish;
    end
endmodule
