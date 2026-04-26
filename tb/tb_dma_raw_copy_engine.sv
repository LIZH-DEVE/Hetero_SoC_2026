`timescale 1ns / 1ps

module tb_dma_raw_copy_engine;

    import dma_csr_pkg::*;

    localparam ADDR_WIDTH  = 32;
    localparam DATA_WIDTH  = 32;
    localparam FIFO_DEPTH  = DMA_RAW_COPY_FIFO_DEPTH;
    localparam MEM_WORDS   = 4096;
    localparam WORD_BYTES  = DATA_WIDTH / 8;
    localparam COPY_BYTES  = DMA_RAW_COPY_LEN_MULTIPLE * 2;
    localparam COPY_WORDS  = COPY_BYTES / WORD_BYTES;

    logic clk;
    logic rst_n;
    logic i_soft_reset;
    logic i_start;
    logic i_stream_tlast;
    logic [ADDR_WIDTH-1:0] i_src_addr;
    logic [ADDR_WIDTH-1:0] i_dst_addr;
    logic [31:0] i_total_len;
    logic [31:0] o_actual_len;
    logic o_done;
    logic o_error;
    logic o_busy;
    logic [1:0] o_bresp;

    logic [ADDR_WIDTH-1:0] m_axi_araddr;
    logic [7:0]            m_axi_arlen;
    logic [2:0]            m_axi_arsize;
    logic [1:0]            m_axi_arburst;
    logic                  m_axi_arvalid;
    logic                  m_axi_arready;
    logic [DATA_WIDTH-1:0] m_axi_rdata;
    logic [1:0]            m_axi_rresp;
    logic                  m_axi_rlast;
    logic                  m_axi_rvalid;
    logic                  m_axi_rready;

    logic [ADDR_WIDTH-1:0]   m_axi_awaddr;
    logic [7:0]              m_axi_awlen;
    logic [2:0]              m_axi_awsize;
    logic [1:0]              m_axi_awburst;
    logic [3:0]              m_axi_awcache;
    logic [2:0]              m_axi_awprot;
    logic                    m_axi_awvalid;
    logic                    m_axi_awready;
    logic [DATA_WIDTH-1:0]   m_axi_wdata;
    logic [DATA_WIDTH/8-1:0] m_axi_wstrb;
    logic                    m_axi_wlast;
    logic                    m_axi_wvalid;
    logic                    m_axi_wready;
    logic [1:0]              m_axi_bresp;
    logic                    m_axi_bvalid;
    logic                    m_axi_bready;

    logic [DATA_WIDTH-1:0]   s_axis_tdata;
    logic                    s_axis_tvalid;
    logic                    s_axis_tready;
    logic                    s_axis_tlast;

    logic [15:0] lfsr_ar;
    logic [15:0] lfsr_aw;
    logic [15:0] lfsr_w;
    logic [15:0] lfsr_b;

    logic [DATA_WIDTH-1:0] src_mem [0:MEM_WORDS-1];
    logic [DATA_WIDTH-1:0] dst_mem [0:MEM_WORDS-1];

    logic [ADDR_WIDTH-1:0] pending_r_addr;
    logic [7:0]            pending_r_delay;
    logic                  pending_r_valid;

    logic [ADDR_WIDTH-1:0] pending_awaddr;
    logic                  pending_aw_valid;
    logic [7:0]            pending_b_delay;
    logic                  pending_b_valid;

    integer idx;
    integer timeout_cycles;
    integer copied_words;
    bit     saw_fifo_tlast;
    bit     hold_write_side_low;
    bit     hold_write_resp_low;
    integer beat_idx;

    function automatic integer addr_to_word(input [31:0] addr);
        addr_to_word = addr[31:2];
    endfunction

    task automatic init_memories(input logic [31:0] seed_base);
        begin
            for (idx = 0; idx < MEM_WORDS; idx = idx + 1) begin
                src_mem[idx] = seed_base + idx;
                dst_mem[idx] = 32'hDEAD_0000 + idx;
            end
        end
    endtask

    task automatic start_copy(input [31:0] src_addr,
                              input [31:0] dst_addr,
                              input [31:0] byte_len);
        begin
            @(posedge clk);
            i_stream_tlast <= 1'b0;
            i_src_addr   <= src_addr;
            i_dst_addr   <= dst_addr;
            i_total_len  <= byte_len;
            i_start      <= 1'b1;
            @(posedge clk);
            i_start      <= 1'b0;
        end
    endtask

    task automatic start_stream(input [31:0] dst_addr,
                                input [31:0] capacity_bytes);
        begin
            @(posedge clk);
            i_stream_tlast <= 1'b1;
            i_src_addr   <= 32'd0;
            i_dst_addr   <= dst_addr;
            i_total_len  <= capacity_bytes;
            i_start      <= 1'b1;
            @(posedge clk);
            i_start      <= 1'b0;
        end
    endtask

    task automatic stream_send_beat(input [31:0] data_word,
                                    input bit last_word);
        begin
            @(posedge clk);
            s_axis_tdata  <= data_word;
            s_axis_tlast  <= last_word;
            s_axis_tvalid <= 1'b1;
            do @(posedge clk); while (!s_axis_tready);
            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
            s_axis_tdata  <= '0;
        end
    endtask

    task automatic stream_send_beat_with_timeout(input [31:0] data_word,
                                                 input bit last_word,
                                                 input integer max_cycles,
                                                 input [8*64-1:0] context_name);
        integer ready_cycles;
        begin
            @(posedge clk);
            s_axis_tdata  <= data_word;
            s_axis_tlast  <= last_word;
            s_axis_tvalid <= 1'b1;
            ready_cycles = 0;
            while (!s_axis_tready) begin
                @(posedge clk);
                ready_cycles = ready_cycles + 1;
                if (ready_cycles > max_cycles) begin
                    $fatal(1, "%0s timed out waiting for s_axis_tready", context_name);
                end
            end
            @(posedge clk);
            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
            s_axis_tdata  <= '0;
        end
    endtask

    task automatic pulse_soft_reset;
        begin
            @(posedge clk);
            i_soft_reset <= 1'b1;
            @(posedge clk);
            i_soft_reset <= 1'b0;
        end
    endtask

    task automatic wait_for_done(input integer max_cycles);
        begin
            timeout_cycles = 0;
            while (!o_done && !o_error) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
                if (timeout_cycles > max_cycles) begin
                    $fatal(1, "raw-copy engine timed out");
                end
            end
        end
    endtask

    dma_raw_copy_engine #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_soft_reset(i_soft_reset),
        .i_start(i_start),
        .i_stream_tlast(i_stream_tlast),
        .i_src_addr(i_src_addr),
        .i_dst_addr(i_dst_addr),
        .i_total_len(i_total_len),
        .o_actual_len(o_actual_len),
        .o_done(o_done),
        .o_error(o_error),
        .o_busy(o_busy),
        .o_bresp(o_bresp),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_ar <= 16'hACE1;
            lfsr_aw <= 16'h1BAD;
            lfsr_w  <= 16'h2FED;
            lfsr_b  <= 16'h39A5;
        end else begin
            lfsr_ar <= {lfsr_ar[14:0], lfsr_ar[15] ^ lfsr_ar[13] ^ lfsr_ar[12] ^ lfsr_ar[10]};
            lfsr_aw <= {lfsr_aw[14:0], lfsr_aw[15] ^ lfsr_aw[13] ^ lfsr_aw[12] ^ lfsr_aw[10]};
            lfsr_w  <= {lfsr_w[14:0],  lfsr_w[15]  ^ lfsr_w[11]  ^ lfsr_w[2]   ^ lfsr_w[0]};
            lfsr_b  <= {lfsr_b[14:0],  lfsr_b[15]  ^ lfsr_b[14]  ^ lfsr_b[12]  ^ lfsr_b[3]};
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready <= 1'b0;
            m_axi_rvalid  <= 1'b0;
            m_axi_rdata   <= '0;
            m_axi_rresp   <= 2'b00;
            m_axi_rlast   <= 1'b0;
            pending_r_valid <= 1'b0;
            pending_r_delay <= '0;
            pending_r_addr  <= '0;
        end else begin
            m_axi_arready <= (lfsr_ar[3:0] < 4'd11);

            if (m_axi_arvalid && m_axi_arready) begin
                pending_r_valid <= 1'b1;
                pending_r_delay <= {4'd0, lfsr_ar[7:4]};
                pending_r_addr  <= m_axi_araddr;
            end

            if (pending_r_valid && !m_axi_rvalid) begin
                if (pending_r_delay == 0) begin
                    m_axi_rvalid <= 1'b1;
                    m_axi_rdata  <= src_mem[addr_to_word(pending_r_addr)];
                    m_axi_rresp  <= 2'b00;
                    m_axi_rlast  <= 1'b1;
                end else begin
                    pending_r_delay <= pending_r_delay - 1'b1;
                end
            end

            if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
                m_axi_rlast  <= 1'b0;
                pending_r_valid <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awready <= 1'b0;
            m_axi_wready  <= 1'b0;
            m_axi_bvalid  <= 1'b0;
            m_axi_bresp   <= 2'b00;
            pending_aw_valid <= 1'b0;
            pending_awaddr   <= '0;
            pending_b_delay  <= '0;
            pending_b_valid  <= 1'b0;
            copied_words     <= 0;
        end else begin
            m_axi_awready <= hold_write_side_low ? 1'b0 : (lfsr_aw[3:0] < 4'd10);
            m_axi_wready  <= hold_write_side_low ? 1'b0 : (lfsr_w[3:0]  < 4'd9);

            if (m_axi_awvalid && m_axi_awready) begin
                pending_aw_valid <= 1'b1;
                pending_awaddr   <= m_axi_awaddr;
                if (m_axi_awlen !== 8'd0) begin
                    $fatal(1, "raw-copy engine write path must stay single-beat in smoke mode");
                end
            end

            if (m_axi_wvalid && m_axi_wready) begin
                if (!pending_aw_valid) begin
                    $fatal(1, "write data arrived without a captured AW address");
                end
                if (!m_axi_wlast) begin
                    $fatal(1, "single-beat raw-copy write must assert WLAST");
                end
                dst_mem[addr_to_word(pending_awaddr)] <= m_axi_wdata;
                copied_words <= copied_words + 1;
                pending_b_valid <= 1'b1;
                pending_b_delay <= {4'd0, lfsr_b[7:4]};
                pending_aw_valid <= 1'b0;
            end

            if (pending_b_valid && !m_axi_bvalid) begin
                if (!hold_write_resp_low && (pending_b_delay == 0)) begin
                    m_axi_bvalid <= 1'b1;
                    m_axi_bresp  <= 2'b00;
                end else begin
                    pending_b_delay <= pending_b_delay - 1'b1;
                end
            end

            if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid  <= 1'b0;
                pending_b_valid <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            saw_fifo_tlast <= 1'b0;
        end else begin
            if (dut.fifo_m_tvalid && dut.fifo_m_tready && dut.fifo_m_tlast) begin
                saw_fifo_tlast <= 1'b1;
            end
            if (i_soft_reset) begin
                saw_fifo_tlast <= 1'b0;
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        i_soft_reset = 1'b0;
        i_start = 1'b0;
        i_stream_tlast = 1'b0;
        i_src_addr = 32'd0;
        i_dst_addr = 32'd0;
        i_total_len = 32'd0;
        s_axis_tdata = '0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        hold_write_side_low = 1'b0;
        hold_write_resp_low = 1'b0;

        init_memories(32'h1000_0000);

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // Test 1: backpressured raw-copy must complete and propagate TLAST.
        start_copy(32'h0000_0100, 32'h0000_0800, COPY_BYTES);
        wait_for_done(40000);

        if (o_error) begin
            $fatal(1, "raw-copy engine flagged error during normal copy");
        end
        if (!saw_fifo_tlast) begin
            $fatal(1, "FIFO path never surfaced TLAST on the final beat");
        end
        if (o_actual_len !== COPY_BYTES) begin
            $fatal(1, "fixed raw-copy actual_len mismatch: got=%0d exp=%0d", o_actual_len, COPY_BYTES);
        end
        for (idx = 0; idx < COPY_WORDS; idx = idx + 1) begin
            if (dst_mem[addr_to_word(32'h0000_0800) + idx] !== src_mem[addr_to_word(32'h0000_0100) + idx]) begin
                $fatal(1, "copy mismatch at word %0d", idx);
            end
        end

        // Test 2: soft reset must flush FIFO; restarted copy must not see stale A payload.
        hold_write_side_low = 1'b1;
        for (idx = 0; idx < COPY_WORDS; idx = idx + 1) begin
            src_mem[addr_to_word(32'h0000_0200) + idx] = 32'hAAAA_0000 + idx;
            src_mem[addr_to_word(32'h0000_0300) + idx] = 32'hBBBB_0000 + idx;
            dst_mem[addr_to_word(32'h0000_0900) + idx] = 32'hCCCC_0000 + idx;
        end

        start_copy(32'h0000_0200, 32'h0000_0900, COPY_BYTES);
        repeat (50) @(posedge clk);
        pulse_soft_reset();
        repeat (10) @(posedge clk);
        if (o_actual_len !== 32'd0) begin
            $fatal(1, "soft reset must clear actual_len visibility, got=%0d", o_actual_len);
        end
        hold_write_side_low = 1'b0;

        start_copy(32'h0000_0300, 32'h0000_0900, COPY_BYTES);
        wait_for_done(40000);

        if (o_error) begin
            $fatal(1, "raw-copy engine flagged error after soft reset recovery");
        end
        if (o_actual_len !== COPY_BYTES) begin
            $fatal(1, "post-reset raw-copy actual_len mismatch: got=%0d exp=%0d", o_actual_len, COPY_BYTES);
        end
        for (idx = 0; idx < COPY_WORDS; idx = idx + 1) begin
            if (dst_mem[addr_to_word(32'h0000_0900) + idx] !== src_mem[addr_to_word(32'h0000_0300) + idx]) begin
                $fatal(1, "soft-reset recovery mismatch at word %0d", idx);
            end
            if (dst_mem[addr_to_word(32'h0000_0900) + idx] === src_mem[addr_to_word(32'h0000_0200) + idx]) begin
                $fatal(1, "stale pre-reset payload leaked into restarted copy at word %0d", idx);
            end
        end

        // Test 3: stream short frame must honor external TLAST and report actual bytes.
        for (idx = 0; idx < 4; idx = idx + 1) begin
            dst_mem[addr_to_word(32'h0000_0A00) + idx] = 32'hEE00_0000 + idx;
        end
        start_stream(32'h0000_0A00, 32'd16);
        stream_send_beat(32'hCAFE_0001, 1'b0);
        stream_send_beat(32'hCAFE_0002, 1'b1);
        wait_for_done(40000);
        if (o_error) begin
            $fatal(1, "stream short-frame path flagged error unexpectedly");
        end
        if (o_actual_len !== 32'd8) begin
            $fatal(1, "stream short-frame actual_len mismatch: got=%0d exp=8", o_actual_len);
        end
        if (dst_mem[addr_to_word(32'h0000_0A00)] !== 32'hCAFE_0001 ||
            dst_mem[addr_to_word(32'h0000_0A04)] !== 32'hCAFE_0002) begin
            $fatal(1, "stream short-frame payload mismatch");
        end
        if (dst_mem[addr_to_word(32'h0000_0A08)] !== 32'hEE00_0002) begin
            $fatal(1, "stream short-frame wrote beyond TLAST");
        end

        // Test 4: stream exact-fit must complete cleanly at capacity.
        for (idx = 0; idx < 4; idx = idx + 1) begin
            dst_mem[addr_to_word(32'h0000_0B00) + idx] = 32'hEF00_0000 + idx;
        end
        start_stream(32'h0000_0B00, 32'd12);
        stream_send_beat(32'hFACE_1001, 1'b0);
        stream_send_beat(32'hFACE_1002, 1'b0);
        stream_send_beat(32'hFACE_1003, 1'b1);
        wait_for_done(40000);
        if (o_error) begin
            $fatal(1, "stream exact-fit path flagged error unexpectedly");
        end
        if (o_actual_len !== 32'd12) begin
            $fatal(1, "stream exact-fit actual_len mismatch: got=%0d exp=12", o_actual_len);
        end
        for (idx = 0; idx < 3; idx = idx + 1) begin
            if (dst_mem[addr_to_word(32'h0000_0B00) + idx] !== (32'hFACE_1001 + idx)) begin
                $fatal(1, "stream exact-fit payload mismatch at beat %0d", idx);
            end
        end

        // Test 5: stream overflow / missing TLAST must fail after the terminal write response.
        for (idx = 0; idx < 2; idx = idx + 1) begin
            dst_mem[addr_to_word(32'h0000_0C00) + idx] = 32'hAB00_0000 + idx;
        end
        hold_write_resp_low = 1'b1;
        start_stream(32'h0000_0C00, 32'd8);
        stream_send_beat(32'hBEEF_2001, 1'b0);
        stream_send_beat(32'hBEEF_2002, 1'b0);
        repeat (8) @(posedge clk);
        if (o_done || o_error) begin
            $fatal(1, "stream completion/error must stay low until the final payload B response");
        end
        hold_write_resp_low = 1'b0;
        wait_for_done(40000);
        if (!o_error) begin
            $fatal(1, "stream overflow/missing TLAST path must assert error");
        end
        if (o_actual_len !== 32'd8) begin
            $fatal(1, "stream overflow actual_len mismatch: got=%0d exp=8", o_actual_len);
        end
        if (o_bresp !== 2'b00) begin
            $fatal(1, "stream overflow should report sanitized AXI bresp=00, got=%0b", o_bresp);
        end
        if (dst_mem[addr_to_word(32'h0000_0C00)] !== 32'hBEEF_2001 ||
            dst_mem[addr_to_word(32'h0000_0C04)] !== 32'hBEEF_2002) begin
            $fatal(1, "stream overflow payload mismatch");
        end

        // Test 6: overflow must keep draining the bad frame to TLAST so the
        // next frame does not inherit a poisoned stream boundary.
        stream_send_beat_with_timeout(32'hBEEF_2003, 1'b1, 200, "overflow tail drain");
        repeat (4) @(posedge clk);
        if (s_axis_tready !== 1'b0) begin
            $fatal(1, "stream overflow drain must release readiness after TLAST is consumed");
        end

        for (idx = 0; idx < 4; idx = idx + 1) begin
            dst_mem[addr_to_word(32'h0000_0D00) + idx] = 32'hAC00_0000 + idx;
        end
        start_stream(32'h0000_0D00, 32'd8);
        stream_send_beat_with_timeout(32'hD00D_3001, 1'b0, 200, "post-overflow frame beat0");
        stream_send_beat_with_timeout(32'hD00D_3002, 1'b1, 200, "post-overflow frame beat1");
        wait_for_done(40000);
        if (o_error) begin
            $fatal(1, "post-overflow frame must complete cleanly after tail drain");
        end
        if (o_actual_len !== 32'd8) begin
            $fatal(1, "post-overflow frame actual_len mismatch: got=%0d exp=8", o_actual_len);
        end
        if (dst_mem[addr_to_word(32'h0000_0D00)] !== 32'hD00D_3001 ||
            dst_mem[addr_to_word(32'h0000_0D04)] !== 32'hD00D_3002) begin
            $fatal(1, "post-overflow frame payload mismatch");
        end

        $display("PASS: dma_raw_copy_engine covers fixed raw-copy, external stream TLAST, overflow handling, tail-drain recovery, and final-B write barrier behavior");
        $finish;
    end

endmodule
