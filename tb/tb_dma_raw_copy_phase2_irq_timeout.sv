`timescale 1ns / 1ps

module tb_dma_raw_copy_phase2_irq_timeout;

    import dma_csr_pkg::*;

    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam MEM_WORDS  = 4096;
    localparam RING_BASE  = 32'h0000_1000;
    localparam SRC_BASE   = 32'h0000_2000;
    localparam DST_BASE   = 32'h0000_3000;
    localparam BYTE_LEN   = DMA_RAW_COPY_LEN_MULTIPLE * 2;
    localparam WORD_LEN   = BYTE_LEN / (DATA_WIDTH / 8);
    localparam FETCH_LAST_WORD = DMA_DESC_CSW_BYTE_OFFSET / DMA_DESC_WORD_BYTES;

    logic clk;
    logic rst_n;

    logic [ADDR_WIDTH-1:0]   s_axil_awaddr;
    logic                    s_axil_awvalid;
    logic                    s_axil_awready;
    logic [DATA_WIDTH-1:0]   s_axil_wdata;
    logic [3:0]              s_axil_wstrb;
    logic                    s_axil_wvalid;
    logic                    s_axil_wready;
    logic [1:0]              s_axil_bresp;
    logic                    s_axil_bvalid;
    logic                    s_axil_bready;
    logic [ADDR_WIDTH-1:0]   s_axil_araddr;
    logic                    s_axil_arvalid;
    logic                    s_axil_arready;
    logic [DATA_WIDTH-1:0]   s_axil_rdata;
    logic [1:0]              s_axil_rresp;
    logic                    s_axil_rvalid;
    logic                    s_axil_rready;
    logic [DATA_WIDTH-1:0]   s_axis_tdata;
    logic                    s_axis_tvalid;
    logic                    s_axis_tready;
    logic                    s_axis_tlast;

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

    logic [ADDR_WIDTH-1:0]   m_axi_araddr;
    logic [7:0]              m_axi_arlen;
    logic [2:0]              m_axi_arsize;
    logic [1:0]              m_axi_arburst;
    logic                    m_axi_arvalid;
    logic                    m_axi_arready;
    logic [DATA_WIDTH-1:0]   m_axi_rdata;
    logic [1:0]              m_axi_rresp;
    logic                    m_axi_rlast;
    logic                    m_axi_rvalid;
    logic                    m_axi_rready;

    logic [ADDR_WIDTH-1:0]   m_axi_fetcher_araddr;
    logic [7:0]              m_axi_fetcher_arlen;
    logic [2:0]              m_axi_fetcher_arsize;
    logic [1:0]              m_axi_fetcher_arburst;
    logic                    m_axi_fetcher_arvalid;
    logic                    m_axi_fetcher_arready;
    logic [DATA_WIDTH-1:0]   m_axi_fetcher_rdata;
    logic [1:0]              m_axi_fetcher_rresp;
    logic                    m_axi_fetcher_rlast;
    logic                    m_axi_fetcher_rvalid;
    logic                    m_axi_fetcher_rready;

    logic [ADDR_WIDTH-1:0]   m_axi_wb_awaddr;
    logic [7:0]              m_axi_wb_awlen;
    logic [2:0]              m_axi_wb_awsize;
    logic [1:0]              m_axi_wb_awburst;
    logic [3:0]              m_axi_wb_awcache;
    logic [2:0]              m_axi_wb_awprot;
    logic                    m_axi_wb_awvalid;
    logic                    m_axi_wb_awready;
    logic [DATA_WIDTH-1:0]   m_axi_wb_wdata;
    logic [3:0]              m_axi_wb_wstrb;
    logic                    m_axi_wb_wlast;
    logic                    m_axi_wb_wvalid;
    logic                    m_axi_wb_wready;
    logic [1:0]              m_axi_wb_bresp;
    logic                    m_axi_wb_bvalid;
    logic                    m_axi_wb_bready;

    logic dma_irq;

    logic [31:0] mem [0:MEM_WORDS-1];

    logic [ADDR_WIDTH-1:0]   data_read_addr_q;
    logic                    data_read_pending_q;
    logic [ADDR_WIDTH-1:0]   fetch_desc_addr_q;
    logic [2:0]              fetch_word_q;
    logic                    fetch_read_pending_q;
    logic [ADDR_WIDTH-1:0]   data_write_addr_q;
    logic                    data_write_aw_seen_q;
    logic [ADDR_WIDTH-1:0]   wb_write_addr_q;
    logic                    wb_write_aw_seen_q;

    integer idx;
    integer timeout_cycles;
    reg [31:0] axil_read_data;

    function automatic integer addr_to_word(input [31:0] addr);
        addr_to_word = addr[31:2];
    endfunction

    task automatic axil_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axil_awaddr  <= addr;
            s_axil_awvalid <= 1'b1;
            s_axil_wdata   <= data;
            s_axil_wstrb   <= 4'hF;
            s_axil_wvalid  <= 1'b1;
            s_axil_bready  <= 1'b1;
            do @(posedge clk); while (!(s_axil_awready && s_axil_wready));
            s_axil_awvalid <= 1'b0;
            s_axil_wvalid  <= 1'b0;
            do @(posedge clk); while (!s_axil_bvalid);
            @(posedge clk);
            s_axil_bready  <= 1'b0;
        end
    endtask

    task automatic axil_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            s_axil_araddr  <= addr;
            s_axil_arvalid <= 1'b1;
            s_axil_rready  <= 1'b1;
            do @(posedge clk); while (!(s_axil_arready && s_axil_arvalid));
            s_axil_arvalid <= 1'b0;
            do @(posedge clk); while (!s_axil_rvalid);
            data = s_axil_rdata;
            @(posedge clk);
            s_axil_rready <= 1'b0;
        end
    endtask

    task automatic init_copy_region(input logic [31:0] src_seed, input logic [31:0] dst_seed);
        begin
            for (idx = 0; idx < WORD_LEN; idx = idx + 1) begin
                mem[addr_to_word(SRC_BASE) + idx] = src_seed + idx;
                mem[addr_to_word(DST_BASE) + idx] = dst_seed + idx;
            end
        end
    endtask

    task automatic init_descriptor(input logic [31:0] reserved0_seed);
        begin
            mem[addr_to_word(RING_BASE) + (DMA_DESC_DST_ADDR_BYTE_OFFSET >> 2)]      = DST_BASE;
            mem[addr_to_word(RING_BASE) + (DMA_DESC_SRC_ADDR_BYTE_OFFSET >> 2)]      = SRC_BASE;
            mem[addr_to_word(RING_BASE) + (DMA_DESC_CTRL_LEN_ALGO_BYTE_OFFSET >> 2)] = BYTE_LEN;
            mem[addr_to_word(RING_BASE) + (DMA_DESC_RESERVED0_BYTE_OFFSET >> 2)]     = reserved0_seed;
            mem[addr_to_word(RING_BASE) + (DMA_DESC_CSW_BYTE_OFFSET >> 2)]           = DMA_DESC_CSW_OWNER;
            mem[addr_to_word(RING_BASE) + (DMA_DESC_ACTUAL_LEN_BYTE_OFFSET >> 2)]    = 32'h0000_0000;
            mem[addr_to_word(RING_BASE) + (DMA_DESC_RESERVED2_BYTE_OFFSET >> 2)]     = 32'h2222_0002;
            mem[addr_to_word(RING_BASE) + (DMA_DESC_RESERVED3_BYTE_OFFSET >> 2)]     = 32'h3333_0003;
        end
    endtask

    task automatic wait_for_csw_done(input integer max_cycles, input string wait_tag);
        begin
            timeout_cycles = 0;
            while ((mem[addr_to_word(RING_BASE) + (DMA_DESC_CSW_BYTE_OFFSET >> 2)] & DMA_DESC_CSW_DONE) == 0) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
                if (timeout_cycles > max_cycles) begin
                    $fatal(1, "%s timed out waiting for CSW.DONE", wait_tag);
                end
            end
        end
    endtask

    task automatic wait_for_irq_level(input logic expected_level, input integer max_cycles, input string wait_tag);
        begin
            timeout_cycles = 0;
            while (dma_irq !== expected_level) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
                if (timeout_cycles > max_cycles) begin
                    $fatal(1, "%s timed out waiting for dma_irq=%0d", wait_tag, expected_level);
                end
            end
        end
    endtask

    dma_raw_copy_subsystem #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(DMA_RAW_COPY_FIFO_DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr),
        .s_axil_awvalid(s_axil_awvalid),
        .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata),
        .s_axil_wstrb(s_axil_wstrb),
        .s_axil_wvalid(s_axil_wvalid),
        .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp),
        .s_axil_bvalid(s_axil_bvalid),
        .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr),
        .s_axil_arvalid(s_axil_arvalid),
        .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata),
        .s_axil_rresp(s_axil_rresp),
        .s_axil_rvalid(s_axil_rvalid),
        .s_axil_rready(s_axil_rready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
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
        .m_axi_fetcher_araddr(m_axi_fetcher_araddr),
        .m_axi_fetcher_arlen(m_axi_fetcher_arlen),
        .m_axi_fetcher_arsize(m_axi_fetcher_arsize),
        .m_axi_fetcher_arburst(m_axi_fetcher_arburst),
        .m_axi_fetcher_arvalid(m_axi_fetcher_arvalid),
        .m_axi_fetcher_arready(m_axi_fetcher_arready),
        .m_axi_fetcher_rdata(m_axi_fetcher_rdata),
        .m_axi_fetcher_rresp(m_axi_fetcher_rresp),
        .m_axi_fetcher_rlast(m_axi_fetcher_rlast),
        .m_axi_fetcher_rvalid(m_axi_fetcher_rvalid),
        .m_axi_fetcher_rready(m_axi_fetcher_rready),
        .m_axi_wb_awaddr(m_axi_wb_awaddr),
        .m_axi_wb_awlen(m_axi_wb_awlen),
        .m_axi_wb_awsize(m_axi_wb_awsize),
        .m_axi_wb_awburst(m_axi_wb_awburst),
        .m_axi_wb_awcache(m_axi_wb_awcache),
        .m_axi_wb_awprot(m_axi_wb_awprot),
        .m_axi_wb_awvalid(m_axi_wb_awvalid),
        .m_axi_wb_awready(m_axi_wb_awready),
        .m_axi_wb_wdata(m_axi_wb_wdata),
        .m_axi_wb_wstrb(m_axi_wb_wstrb),
        .m_axi_wb_wlast(m_axi_wb_wlast),
        .m_axi_wb_wvalid(m_axi_wb_wvalid),
        .m_axi_wb_wready(m_axi_wb_wready),
        .m_axi_wb_bresp(m_axi_wb_bresp),
        .m_axi_wb_bvalid(m_axi_wb_bvalid),
        .m_axi_wb_bready(m_axi_wb_bready),
        .dma_irq(dma_irq)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready        <= 1'b1;
            m_axi_rvalid         <= 1'b0;
            m_axi_rdata          <= '0;
            m_axi_rresp          <= 2'b00;
            m_axi_rlast          <= 1'b0;
            data_read_addr_q     <= '0;
            data_read_pending_q  <= 1'b0;
        end else begin
            if (m_axi_arvalid && m_axi_arready) begin
                data_read_addr_q    <= m_axi_araddr;
                data_read_pending_q <= 1'b1;
            end

            if (data_read_pending_q && !m_axi_rvalid) begin
                m_axi_rvalid <= 1'b1;
                m_axi_rdata  <= mem[addr_to_word(data_read_addr_q)];
                m_axi_rresp  <= 2'b00;
                m_axi_rlast  <= 1'b1;
            end

            if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid        <= 1'b0;
                m_axi_rlast         <= 1'b0;
                data_read_pending_q <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_fetcher_arready <= 1'b1;
            m_axi_fetcher_rvalid  <= 1'b0;
            m_axi_fetcher_rdata   <= '0;
            m_axi_fetcher_rresp   <= 2'b00;
            m_axi_fetcher_rlast   <= 1'b0;
            fetch_desc_addr_q     <= '0;
            fetch_word_q          <= '0;
            fetch_read_pending_q  <= 1'b0;
        end else begin
            if (m_axi_fetcher_arvalid && m_axi_fetcher_arready) begin
                fetch_desc_addr_q    <= m_axi_fetcher_araddr;
                fetch_word_q         <= 3'd0;
                fetch_read_pending_q <= 1'b1;
            end

            if (fetch_read_pending_q && !m_axi_fetcher_rvalid) begin
                m_axi_fetcher_rvalid <= 1'b1;
                m_axi_fetcher_rdata  <= mem[addr_to_word(fetch_desc_addr_q) + fetch_word_q];
                m_axi_fetcher_rresp  <= 2'b00;
                m_axi_fetcher_rlast  <= (fetch_word_q == FETCH_LAST_WORD[2:0]);
            end

            if (m_axi_fetcher_rvalid && m_axi_fetcher_rready) begin
                m_axi_fetcher_rvalid <= 1'b0;
                if (m_axi_fetcher_rlast) begin
                    m_axi_fetcher_rlast  <= 1'b0;
                    fetch_read_pending_q <= 1'b0;
                    fetch_word_q         <= '0;
                end else begin
                    fetch_word_q <= fetch_word_q + 3'd1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awready        <= 1'b1;
            m_axi_wready         <= 1'b1;
            m_axi_bvalid         <= 1'b0;
            m_axi_bresp          <= 2'b00;
            data_write_addr_q    <= '0;
            data_write_aw_seen_q <= 1'b0;
        end else begin
            if (m_axi_awvalid && m_axi_awready) begin
                data_write_addr_q    <= m_axi_awaddr;
                data_write_aw_seen_q <= 1'b1;
            end

            if (m_axi_wvalid && m_axi_wready) begin
                if (!data_write_aw_seen_q) begin
                    $fatal(1, "raw-copy data write observed without prior AW");
                end
                if (!m_axi_wlast) begin
                    $fatal(1, "raw-copy data write must remain single-beat");
                end
                mem[addr_to_word(data_write_addr_q)] <= m_axi_wdata;
                data_write_aw_seen_q <= 1'b0;
                m_axi_bvalid         <= 1'b1;
                m_axi_bresp          <= 2'b00;
            end

            if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_wb_awready     <= 1'b1;
            m_axi_wb_wready      <= 1'b1;
            m_axi_wb_bvalid      <= 1'b0;
            m_axi_wb_bresp       <= 2'b00;
            wb_write_addr_q      <= '0;
            wb_write_aw_seen_q   <= 1'b0;
        end else begin
            if (m_axi_wb_awvalid && m_axi_wb_awready) begin
                wb_write_addr_q    <= m_axi_wb_awaddr;
                wb_write_aw_seen_q <= 1'b1;
            end

            if (m_axi_wb_wvalid && m_axi_wb_wready) begin
                if (!wb_write_aw_seen_q) begin
                    $fatal(1, "CSW write-back observed without prior AW");
                end
                if (!m_axi_wb_wlast) begin
                    $fatal(1, "CSW write-back must remain single-beat");
                end
                mem[addr_to_word(wb_write_addr_q)] <= m_axi_wb_wdata;
                wb_write_aw_seen_q <= 1'b0;
                m_axi_wb_bvalid    <= 1'b1;
                m_axi_wb_bresp     <= 2'b00;
            end

            if (m_axi_wb_bvalid && m_axi_wb_bready) begin
                m_axi_wb_bvalid <= 1'b0;
            end
        end
    end

    initial begin
        rst_n           = 1'b0;
        s_axil_awaddr   = '0;
        s_axil_awvalid  = 1'b0;
        s_axil_wdata    = '0;
        s_axil_wstrb    = 4'h0;
        s_axil_wvalid   = 1'b0;
        s_axil_bready   = 1'b0;
        s_axil_araddr   = '0;
        s_axil_arvalid  = 1'b0;
        s_axil_rready   = 1'b0;
        s_axis_tdata    = '0;
        s_axis_tvalid   = 1'b0;
        s_axis_tlast    = 1'b0;

        for (idx = 0; idx < MEM_WORDS; idx = idx + 1) begin
            mem[idx] = 32'h0;
        end

        init_copy_region(32'h5000_0000, 32'h9000_0000);
        init_descriptor(32'h1357_2468);

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        axil_write(DMA_CSR_RING_BASE, RING_BASE);
        axil_write(DMA_CSR_RING_SIZE, 32'd4);
        axil_write(DMA_CSR_IRQ_COALESCE_COUNT, 32'd8);
        axil_write(DMA_CSR_IRQ_COALESCE_TIMEOUT, 32'd12);
        axil_write(DMA_CSR_IRQ_ENABLE, DMA_IRQ_ENABLE_DONE);
        axil_write(DMA_CSR_RING_SW_TAIL, 32'd1);
        axil_write(DMA_CSR_RING_DOORBELL, 32'd1);

        wait_for_csw_done(40000, "timeout raw-copy");
        repeat (8) @(posedge clk);
        if (dma_irq !== 1'b0) begin
            $fatal(1, "dma_irq asserted before timeout threshold");
        end

        wait_for_irq_level(1'b1, 64, "irq timeout");
        axil_read(DMA_CSR_IRQ_STATUS, axil_read_data);
        if ((axil_read_data & DMA_IRQ_STATUS_DONE_PENDING) == 0) begin
            $fatal(1, "IRQ status did not assert after timeout");
        end

        axil_write(DMA_CSR_IRQ_ACK, DMA_IRQ_ACK_DONE_ACK);
        if (dma_irq !== 1'b0) begin
            $fatal(1, "dma_irq should clear after timeout ACK");
        end

        $display("PASS: raw-copy Phase 2 timeout coalescing raises IRQ after completion aging");
        $finish;
    end

endmodule
