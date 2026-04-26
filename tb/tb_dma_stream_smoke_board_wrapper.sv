`timescale 1ns / 1ps

module tb_dma_stream_smoke_board_wrapper;

    import dma_csr_pkg::*;

    // This board-wrapper bench exercises the dedicated stream_dummy_source path
    // through dma_stream_smoke_board_wrapper and into the raw-copy subsystem.

    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 32;
    localparam int MEM_WORDS = 16384;
    localparam int BYTES_PER_WORD = DATA_WIDTH / 8;
    localparam int RING_ENTRIES = 2;

    localparam logic [31:0] DMA_CSR_BASE   = 32'h4000_0000;
    localparam logic [31:0] DUMMY_CSR_BASE = 32'h4000_1000;
    localparam logic [31:0] RING_BASE      = 32'h0000_1000;

    localparam logic [31:0] EXACT_DST_BASE    = 32'h0000_3000;
    localparam logic [31:0] SHORT_DST_BASE    = 32'h0000_3800;
    localparam logic [31:0] OVERFLOW_DST_BASE = 32'h0000_4000;

    localparam logic [31:0] EXACT_FIT_BYTES        = 32'd1024;
    localparam logic [31:0] SHORT_FRAME_BYTES      = 32'd64;
    localparam logic [31:0] OVERFLOW_CAPACITY      = 32'd64;
    localparam logic [31:0] OVERFLOW_PACKET_BYTES  = 32'd128;
    localparam logic [31:0] SENTINEL_WORD          = 32'hA5A5_A5A5;

    localparam int DESC0_IDX = 0;
    localparam int FETCH_LAST_WORD = DMA_DESC_CSW_BYTE_OFFSET / DMA_DESC_WORD_BYTES;

    logic clk;
    logic rst_n;

    logic [ADDR_WIDTH-1:0]   s_axil_dma_awaddr;
    logic                    s_axil_dma_awvalid;
    logic                    s_axil_dma_awready;
    logic [DATA_WIDTH-1:0]   s_axil_dma_wdata;
    logic [3:0]              s_axil_dma_wstrb;
    logic                    s_axil_dma_wvalid;
    logic                    s_axil_dma_wready;
    logic [1:0]              s_axil_dma_bresp;
    logic                    s_axil_dma_bvalid;
    logic                    s_axil_dma_bready;
    logic [ADDR_WIDTH-1:0]   s_axil_dma_araddr;
    logic                    s_axil_dma_arvalid;
    logic                    s_axil_dma_arready;
    logic [DATA_WIDTH-1:0]   s_axil_dma_rdata;
    logic [1:0]              s_axil_dma_rresp;
    logic                    s_axil_dma_rvalid;
    logic                    s_axil_dma_rready;

    logic [ADDR_WIDTH-1:0]   s_axil_dummy_awaddr;
    logic                    s_axil_dummy_awvalid;
    logic                    s_axil_dummy_awready;
    logic [DATA_WIDTH-1:0]   s_axil_dummy_wdata;
    logic [3:0]              s_axil_dummy_wstrb;
    logic                    s_axil_dummy_wvalid;
    logic                    s_axil_dummy_wready;
    logic [1:0]              s_axil_dummy_bresp;
    logic                    s_axil_dummy_bvalid;
    logic                    s_axil_dummy_bready;
    logic [ADDR_WIDTH-1:0]   s_axil_dummy_araddr;
    logic                    s_axil_dummy_arvalid;
    logic                    s_axil_dummy_arready;
    logic [DATA_WIDTH-1:0]   s_axil_dummy_rdata;
    logic [1:0]              s_axil_dummy_rresp;
    logic                    s_axil_dummy_rvalid;
    logic                    s_axil_dummy_rready;

    logic [ADDR_WIDTH-1:0]   m_axi_dma_wr_awaddr;
    logic [7:0]              m_axi_dma_wr_awlen;
    logic [2:0]              m_axi_dma_wr_awsize;
    logic [1:0]              m_axi_dma_wr_awburst;
    logic [3:0]              m_axi_dma_wr_awcache;
    logic [2:0]              m_axi_dma_wr_awprot;
    logic                    m_axi_dma_wr_awvalid;
    logic                    m_axi_dma_wr_awready;
    logic [DATA_WIDTH-1:0]   m_axi_dma_wr_wdata;
    logic [DATA_WIDTH/8-1:0] m_axi_dma_wr_wstrb;
    logic                    m_axi_dma_wr_wlast;
    logic                    m_axi_dma_wr_wvalid;
    logic                    m_axi_dma_wr_wready;
    logic [1:0]              m_axi_dma_wr_bresp;
    logic                    m_axi_dma_wr_bvalid;
    logic                    m_axi_dma_wr_bready;

    logic [ADDR_WIDTH-1:0]   m_axi_s2mm_awaddr;
    logic [7:0]              m_axi_s2mm_awlen;
    logic [2:0]              m_axi_s2mm_awsize;
    logic [1:0]              m_axi_s2mm_awburst;
    logic [3:0]              m_axi_s2mm_awcache;
    logic [2:0]              m_axi_s2mm_awprot;
    logic                    m_axi_s2mm_awvalid;
    logic                    m_axi_s2mm_awready;
    logic [DATA_WIDTH-1:0]   m_axi_s2mm_wdata;
    logic [DATA_WIDTH/8-1:0] m_axi_s2mm_wstrb;
    logic                    m_axi_s2mm_wlast;
    logic                    m_axi_s2mm_wvalid;
    logic                    m_axi_s2mm_wready;
    logic [1:0]              m_axi_s2mm_bresp;
    logic                    m_axi_s2mm_bvalid;
    logic                    m_axi_s2mm_bready;
    logic [ADDR_WIDTH-1:0]   m_axi_s2mm_araddr;
    logic [7:0]              m_axi_s2mm_arlen;
    logic [2:0]              m_axi_s2mm_arsize;
    logic [1:0]              m_axi_s2mm_arburst;
    logic                    m_axi_s2mm_arvalid;
    logic                    m_axi_s2mm_arready;
    logic [DATA_WIDTH-1:0]   m_axi_s2mm_rdata;
    logic [1:0]              m_axi_s2mm_rresp;
    logic                    m_axi_s2mm_rlast;
    logic                    m_axi_s2mm_rvalid;
    logic                    m_axi_s2mm_rready;

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

    logic dma_irq;

    logic [31:0] mem [0:MEM_WORDS-1];

    logic [ADDR_WIDTH-1:0] fetch_desc_addr_q;
    logic [2:0]            fetch_word_q;
    logic                  fetch_pending_q;

    logic [ADDR_WIDTH-1:0] s2mm_pending_addr_q;
    logic [DATA_WIDTH-1:0] s2mm_pending_data_q;
    logic                  s2mm_aw_seen_q;
    logic                  s2mm_write_pending_q;
    logic                  hold_payload_resp_low;

    logic [ADDR_WIDTH-1:0] wb_pending_addr_q;
    logic [DATA_WIDTH-1:0] wb_pending_data_q;
    logic                  wb_aw_seen_q;
    logic                  wb_write_pending_q;
    logic                  hold_wb_resp_low;
    logic                  saw_completion_during_payload_hold_q;
    logic                  saw_irq_during_payload_hold_q;
    logic                  saw_completion_during_wb_hold_q;
    logic                  saw_irq_during_wb_hold_q;

    integer idx;
    integer timeout_cycles;

    function automatic int addr_to_word(input logic [31:0] addr);
        addr_to_word = addr[31:2];
    endfunction

    function automatic int desc_field_to_word(input int desc_idx, input logic [31:0] byte_offset);
        desc_field_to_word = addr_to_word(RING_BASE + (desc_idx * DMA_DESC_SIZE_BYTES) + byte_offset);
    endfunction

    task automatic axil_write_dma(input logic [31:0] addr, input logic [31:0] data);
        begin
            @(posedge clk);
            s_axil_dma_awaddr  <= addr;
            s_axil_dma_awvalid <= 1'b1;
            s_axil_dma_wdata   <= data;
            s_axil_dma_wstrb   <= 4'hF;
            s_axil_dma_wvalid  <= 1'b1;
            s_axil_dma_bready  <= 1'b1;
            do @(posedge clk); while (!(s_axil_dma_awready && s_axil_dma_wready));
            s_axil_dma_awvalid <= 1'b0;
            s_axil_dma_wvalid  <= 1'b0;
            do @(posedge clk); while (!s_axil_dma_bvalid);
            @(posedge clk);
            s_axil_dma_bready <= 1'b0;
        end
    endtask

    task automatic axil_write_dummy(input logic [31:0] addr, input logic [31:0] data);
        begin
            @(posedge clk);
            s_axil_dummy_awaddr  <= addr;
            s_axil_dummy_awvalid <= 1'b1;
            s_axil_dummy_wdata   <= data;
            s_axil_dummy_wstrb   <= 4'hF;
            s_axil_dummy_wvalid  <= 1'b1;
            s_axil_dummy_bready  <= 1'b1;
            do @(posedge clk); while (!(s_axil_dummy_awready && s_axil_dummy_wready));
            s_axil_dummy_awvalid <= 1'b0;
            s_axil_dummy_wvalid  <= 1'b0;
            do @(posedge clk); while (!s_axil_dummy_bvalid);
            @(posedge clk);
            s_axil_dummy_bready <= 1'b0;
        end
    endtask

    task automatic axil_read_dma(input logic [31:0] addr, output logic [31:0] data);
        begin
            @(posedge clk);
            s_axil_dma_araddr  <= addr;
            s_axil_dma_arvalid <= 1'b1;
            s_axil_dma_rready  <= 1'b1;
            do @(posedge clk); while (!s_axil_dma_arready);
            s_axil_dma_arvalid <= 1'b0;
            do @(posedge clk); while (!s_axil_dma_rvalid);
            data = s_axil_dma_rdata;
            @(posedge clk);
            s_axil_dma_rready <= 1'b0;
        end
    endtask

    task automatic clear_region(input logic [31:0] base_addr, input logic [31:0] byte_len, input logic [31:0] fill_word);
        int word_idx;
        begin
            for (word_idx = 0; word_idx < (byte_len / BYTES_PER_WORD); word_idx = word_idx + 1) begin
                mem[addr_to_word(base_addr) + word_idx] = fill_word;
            end
        end
    endtask

    task automatic seed_stream_descriptor(
        input int desc_idx,
        input logic [31:0] dst_addr,
        input logic [31:0] capacity_bytes,
        input logic [31:0] reserved_seed
    );
        begin
            mem[desc_field_to_word(desc_idx, DMA_DESC_DST_ADDR_BYTE_OFFSET)]      = dst_addr;
            mem[desc_field_to_word(desc_idx, DMA_DESC_SRC_ADDR_BYTE_OFFSET)]      = 32'h0000_0000;
            mem[desc_field_to_word(desc_idx, DMA_DESC_CTRL_LEN_ALGO_BYTE_OFFSET)] =
                DMA_DESC_CTRL_STREAM_TLAST | (capacity_bytes & DMA_DESC_CTRL_MASK_LEN);
            mem[desc_field_to_word(desc_idx, DMA_DESC_RESERVED0_BYTE_OFFSET)]     = reserved_seed;
            mem[desc_field_to_word(desc_idx, DMA_DESC_CSW_BYTE_OFFSET)]           = DMA_DESC_CSW_OWNER;
            mem[desc_field_to_word(desc_idx, DMA_DESC_ACTUAL_LEN_BYTE_OFFSET)]    = 32'h0000_0000;
            mem[desc_field_to_word(desc_idx, DMA_DESC_RESERVED2_BYTE_OFFSET)]     = 32'h2222_0000 | desc_idx;
            mem[desc_field_to_word(desc_idx, DMA_DESC_RESERVED3_BYTE_OFFSET)]     = 32'h3333_0000 | desc_idx;
        end
    endtask

    task automatic prepare_ring;
        begin
            axil_write_dma(DMA_CSR_CTRL, DMA_CTRL_SOFT_RESET);
            repeat (8) @(posedge clk);
            axil_write_dma(DMA_CSR_RING_BASE, RING_BASE);
            axil_write_dma(DMA_CSR_RING_SIZE, RING_ENTRIES);
            axil_write_dma(DMA_CSR_RING_SW_TAIL, 32'd0);
        end
    endtask

    task automatic start_stream_descriptor(input logic [31:0] packet_len_bytes);
        begin
            axil_write_dma(DMA_CSR_RING_SW_TAIL, 32'd1);
            axil_write_dma(DMA_CSR_RING_DOORBELL, DMA_CSR_RING_DOORBELL_KICK);
            axil_write_dummy(DUMMY_CSR_BASE + 32'h04, packet_len_bytes);
            axil_write_dummy(DUMMY_CSR_BASE + 32'h00, 32'h0000_0001);
        end
    endtask

    task automatic wait_for_csw_done(input int desc_idx, input int max_cycles, input string wait_tag);
        begin
            timeout_cycles = 0;
            while ((mem[desc_field_to_word(desc_idx, DMA_DESC_CSW_BYTE_OFFSET)] & DMA_DESC_CSW_DONE) == 0) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
                if (timeout_cycles > max_cycles) begin
                    $fatal(1, "%s timed out waiting for CSW.DONE", wait_tag);
                end
            end
        end
    endtask

    task automatic expect_pattern(input logic [31:0] base_addr, input int byte_len, input string tag);
        int byte_idx;
        int word_idx;
        logic [31:0] expected_word;
        begin
            for (word_idx = 0; word_idx < (byte_len / BYTES_PER_WORD); word_idx = word_idx + 1) begin
                byte_idx = word_idx * BYTES_PER_WORD;
                expected_word = {
                    8'((byte_idx + 3) & 8'hFF),
                    8'((byte_idx + 2) & 8'hFF),
                    8'((byte_idx + 1) & 8'hFF),
                    8'(byte_idx & 8'hFF)
                };
                if (mem[addr_to_word(base_addr) + word_idx] !== expected_word) begin
                    $fatal(1, "%s payload mismatch at word %0d: got=%08h exp=%08h",
                           tag,
                           word_idx,
                           mem[addr_to_word(base_addr) + word_idx],
                           expected_word);
                end
            end
        end
    endtask

    dma_stream_smoke_board_wrapper #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .dma_irq(dma_irq),
        .s_axil_dma_awaddr(s_axil_dma_awaddr),
        .s_axil_dma_awvalid(s_axil_dma_awvalid),
        .s_axil_dma_awready(s_axil_dma_awready),
        .s_axil_dma_wdata(s_axil_dma_wdata),
        .s_axil_dma_wstrb(s_axil_dma_wstrb),
        .s_axil_dma_wvalid(s_axil_dma_wvalid),
        .s_axil_dma_wready(s_axil_dma_wready),
        .s_axil_dma_bresp(s_axil_dma_bresp),
        .s_axil_dma_bvalid(s_axil_dma_bvalid),
        .s_axil_dma_bready(s_axil_dma_bready),
        .s_axil_dma_araddr(s_axil_dma_araddr),
        .s_axil_dma_arvalid(s_axil_dma_arvalid),
        .s_axil_dma_arready(s_axil_dma_arready),
        .s_axil_dma_rdata(s_axil_dma_rdata),
        .s_axil_dma_rresp(s_axil_dma_rresp),
        .s_axil_dma_rvalid(s_axil_dma_rvalid),
        .s_axil_dma_rready(s_axil_dma_rready),
        .s_axil_dummy_awaddr(s_axil_dummy_awaddr),
        .s_axil_dummy_awvalid(s_axil_dummy_awvalid),
        .s_axil_dummy_awready(s_axil_dummy_awready),
        .s_axil_dummy_wdata(s_axil_dummy_wdata),
        .s_axil_dummy_wstrb(s_axil_dummy_wstrb),
        .s_axil_dummy_wvalid(s_axil_dummy_wvalid),
        .s_axil_dummy_wready(s_axil_dummy_wready),
        .s_axil_dummy_bresp(s_axil_dummy_bresp),
        .s_axil_dummy_bvalid(s_axil_dummy_bvalid),
        .s_axil_dummy_bready(s_axil_dummy_bready),
        .s_axil_dummy_araddr(s_axil_dummy_araddr),
        .s_axil_dummy_arvalid(s_axil_dummy_arvalid),
        .s_axil_dummy_arready(s_axil_dummy_arready),
        .s_axil_dummy_rdata(s_axil_dummy_rdata),
        .s_axil_dummy_rresp(s_axil_dummy_rresp),
        .s_axil_dummy_rvalid(s_axil_dummy_rvalid),
        .s_axil_dummy_rready(s_axil_dummy_rready),
        .m_axi_dma_wr_awaddr(m_axi_dma_wr_awaddr),
        .m_axi_dma_wr_awlen(m_axi_dma_wr_awlen),
        .m_axi_dma_wr_awsize(m_axi_dma_wr_awsize),
        .m_axi_dma_wr_awburst(m_axi_dma_wr_awburst),
        .m_axi_dma_wr_awcache(m_axi_dma_wr_awcache),
        .m_axi_dma_wr_awprot(m_axi_dma_wr_awprot),
        .m_axi_dma_wr_awvalid(m_axi_dma_wr_awvalid),
        .m_axi_dma_wr_awready(m_axi_dma_wr_awready),
        .m_axi_dma_wr_wdata(m_axi_dma_wr_wdata),
        .m_axi_dma_wr_wstrb(m_axi_dma_wr_wstrb),
        .m_axi_dma_wr_wlast(m_axi_dma_wr_wlast),
        .m_axi_dma_wr_wvalid(m_axi_dma_wr_wvalid),
        .m_axi_dma_wr_wready(m_axi_dma_wr_wready),
        .m_axi_dma_wr_bresp(m_axi_dma_wr_bresp),
        .m_axi_dma_wr_bvalid(m_axi_dma_wr_bvalid),
        .m_axi_dma_wr_bready(m_axi_dma_wr_bready),
        .m_axi_s2mm_awaddr(m_axi_s2mm_awaddr),
        .m_axi_s2mm_awlen(m_axi_s2mm_awlen),
        .m_axi_s2mm_awsize(m_axi_s2mm_awsize),
        .m_axi_s2mm_awburst(m_axi_s2mm_awburst),
        .m_axi_s2mm_awcache(m_axi_s2mm_awcache),
        .m_axi_s2mm_awprot(m_axi_s2mm_awprot),
        .m_axi_s2mm_awvalid(m_axi_s2mm_awvalid),
        .m_axi_s2mm_awready(m_axi_s2mm_awready),
        .m_axi_s2mm_wdata(m_axi_s2mm_wdata),
        .m_axi_s2mm_wstrb(m_axi_s2mm_wstrb),
        .m_axi_s2mm_wlast(m_axi_s2mm_wlast),
        .m_axi_s2mm_wvalid(m_axi_s2mm_wvalid),
        .m_axi_s2mm_wready(m_axi_s2mm_wready),
        .m_axi_s2mm_bresp(m_axi_s2mm_bresp),
        .m_axi_s2mm_bvalid(m_axi_s2mm_bvalid),
        .m_axi_s2mm_bready(m_axi_s2mm_bready),
        .m_axi_s2mm_araddr(m_axi_s2mm_araddr),
        .m_axi_s2mm_arlen(m_axi_s2mm_arlen),
        .m_axi_s2mm_arsize(m_axi_s2mm_arsize),
        .m_axi_s2mm_arburst(m_axi_s2mm_arburst),
        .m_axi_s2mm_arvalid(m_axi_s2mm_arvalid),
        .m_axi_s2mm_arready(m_axi_s2mm_arready),
        .m_axi_s2mm_rdata(m_axi_s2mm_rdata),
        .m_axi_s2mm_rresp(m_axi_s2mm_rresp),
        .m_axi_s2mm_rlast(m_axi_s2mm_rlast),
        .m_axi_s2mm_rvalid(m_axi_s2mm_rvalid),
        .m_axi_s2mm_rready(m_axi_s2mm_rready),
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
        .m_axi_fetcher_rready(m_axi_fetcher_rready)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_fetcher_arready <= 1'b1;
            m_axi_fetcher_rvalid  <= 1'b0;
            m_axi_fetcher_rresp   <= 2'b00;
            m_axi_fetcher_rlast   <= 1'b0;
            fetch_desc_addr_q     <= '0;
            fetch_word_q          <= '0;
            fetch_pending_q       <= 1'b0;
        end else begin
            if (m_axi_fetcher_arvalid && m_axi_fetcher_arready) begin
                fetch_desc_addr_q <= m_axi_fetcher_araddr;
                fetch_word_q      <= 3'd0;
                fetch_pending_q   <= 1'b1;
            end

            if (fetch_pending_q && !m_axi_fetcher_rvalid) begin
                m_axi_fetcher_rvalid <= 1'b1;
                m_axi_fetcher_rdata  <= mem[addr_to_word(fetch_desc_addr_q) + fetch_word_q];
                m_axi_fetcher_rresp  <= 2'b00;
                m_axi_fetcher_rlast  <= (fetch_word_q == FETCH_LAST_WORD[2:0]);
            end

            if (m_axi_fetcher_rvalid && m_axi_fetcher_rready) begin
                m_axi_fetcher_rvalid <= 1'b0;
                if (m_axi_fetcher_rlast) begin
                    m_axi_fetcher_rlast <= 1'b0;
                    fetch_pending_q     <= 1'b0;
                    fetch_word_q        <= '0;
                end else begin
                    fetch_word_q <= fetch_word_q + 3'd1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_s2mm_awready  <= 1'b1;
            m_axi_s2mm_wready   <= 1'b1;
            m_axi_s2mm_bvalid   <= 1'b0;
            m_axi_s2mm_bresp    <= 2'b00;
            m_axi_s2mm_arready  <= 1'b1;
            m_axi_s2mm_rvalid   <= 1'b0;
            m_axi_s2mm_rdata    <= '0;
            m_axi_s2mm_rresp    <= 2'b00;
            m_axi_s2mm_rlast    <= 1'b0;
            s2mm_pending_addr_q <= '0;
            s2mm_pending_data_q <= '0;
            s2mm_aw_seen_q      <= 1'b0;
            s2mm_write_pending_q <= 1'b0;
        end else begin
            if (m_axi_s2mm_awvalid && m_axi_s2mm_awready) begin
                s2mm_pending_addr_q <= m_axi_s2mm_awaddr;
                s2mm_aw_seen_q      <= 1'b1;
            end

            if (m_axi_s2mm_wvalid && m_axi_s2mm_wready) begin
                if (!s2mm_aw_seen_q) begin
                    $fatal(1, "stream payload write observed without prior AW");
                end
                if (!m_axi_s2mm_wlast) begin
                    $fatal(1, "stream payload path must remain single-beat");
                end
                s2mm_pending_data_q <= m_axi_s2mm_wdata;
                s2mm_aw_seen_q      <= 1'b0;
                s2mm_write_pending_q <= 1'b1;
                if (!hold_payload_resp_low) begin
                    m_axi_s2mm_bvalid <= 1'b1;
                end
            end

            if (s2mm_write_pending_q && !m_axi_s2mm_bvalid && !hold_payload_resp_low) begin
                m_axi_s2mm_bvalid <= 1'b1;
            end

            if (m_axi_s2mm_bvalid && m_axi_s2mm_bready) begin
                mem[addr_to_word(s2mm_pending_addr_q)] <= s2mm_pending_data_q;
                s2mm_write_pending_q <= 1'b0;
                m_axi_s2mm_bvalid    <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_dma_wr_awready <= 1'b1;
            m_axi_dma_wr_wready  <= 1'b1;
            m_axi_dma_wr_bvalid  <= 1'b0;
            m_axi_dma_wr_bresp   <= 2'b00;
            wb_pending_addr_q    <= '0;
            wb_pending_data_q    <= '0;
            wb_aw_seen_q         <= 1'b0;
            wb_write_pending_q   <= 1'b0;
        end else begin
            if (m_axi_dma_wr_awvalid && m_axi_dma_wr_awready) begin
                wb_pending_addr_q <= m_axi_dma_wr_awaddr;
                wb_aw_seen_q      <= 1'b1;
            end

            if (m_axi_dma_wr_wvalid && m_axi_dma_wr_wready) begin
                if (!wb_aw_seen_q) begin
                    $fatal(1, "completion writeback observed without prior AW");
                end
                if (!m_axi_dma_wr_wlast) begin
                    $fatal(1, "completion writeback must remain single-beat");
                end
                wb_pending_data_q <= m_axi_dma_wr_wdata;
                wb_aw_seen_q      <= 1'b0;
                wb_write_pending_q <= 1'b1;
                if (!hold_wb_resp_low) begin
                    m_axi_dma_wr_bvalid <= 1'b1;
                end
            end

            if (wb_write_pending_q && !m_axi_dma_wr_bvalid && !hold_wb_resp_low) begin
                m_axi_dma_wr_bvalid <= 1'b1;
            end

            if (m_axi_dma_wr_bvalid && m_axi_dma_wr_bready) begin
                mem[addr_to_word(wb_pending_addr_q)] <= wb_pending_data_q;
                wb_write_pending_q <= 1'b0;
                m_axi_dma_wr_bvalid <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            saw_completion_during_payload_hold_q <= 1'b0;
            saw_irq_during_payload_hold_q        <= 1'b0;
            saw_completion_during_wb_hold_q      <= 1'b0;
            saw_irq_during_wb_hold_q             <= 1'b0;
        end else begin
            if (!hold_payload_resp_low) begin
                saw_completion_during_payload_hold_q <= 1'b0;
                saw_irq_during_payload_hold_q        <= 1'b0;
            end else begin
                if (dut.i_stream_smoke.fetch_completion_event) begin
                    saw_completion_during_payload_hold_q <= 1'b1;
                end
                if (dma_irq) begin
                    saw_irq_during_payload_hold_q <= 1'b1;
                end
            end

            if (!hold_wb_resp_low) begin
                saw_completion_during_wb_hold_q <= 1'b0;
                saw_irq_during_wb_hold_q        <= 1'b0;
            end else begin
                if (dut.i_stream_smoke.fetch_completion_event) begin
                    saw_completion_during_wb_hold_q <= 1'b1;
                end
                if (dma_irq) begin
                    saw_irq_during_wb_hold_q <= 1'b1;
                end
            end
        end
    end

    initial begin
        rst_n               = 1'b0;
        s_axil_dma_awaddr   = '0;
        s_axil_dma_awvalid  = 1'b0;
        s_axil_dma_wdata    = '0;
        s_axil_dma_wstrb    = 4'h0;
        s_axil_dma_wvalid   = 1'b0;
        s_axil_dma_bready   = 1'b0;
        s_axil_dma_araddr   = '0;
        s_axil_dma_arvalid  = 1'b0;
        s_axil_dma_rready   = 1'b0;
        s_axil_dummy_awaddr  = '0;
        s_axil_dummy_awvalid = 1'b0;
        s_axil_dummy_wdata   = '0;
        s_axil_dummy_wstrb   = 4'h0;
        s_axil_dummy_wvalid  = 1'b0;
        s_axil_dummy_bready  = 1'b0;
        s_axil_dummy_araddr  = '0;
        s_axil_dummy_arvalid = 1'b0;
        s_axil_dummy_rready  = 1'b0;
        hold_payload_resp_low = 1'b0;
        hold_wb_resp_low      = 1'b0;

        for (idx = 0; idx < MEM_WORDS; idx = idx + 1) begin
            mem[idx] = 32'h0;
        end

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        $display("DMA stream smoke image");
        $display("  DMA CSR base      = 0x40000000");
        $display("  dummy source base = 0x40001000");
        $display("  PACKET_LEN is word-granular only in this phase");
        $display("  final CSW writeback response must gate software-visible completion");

        prepare_ring();
        clear_region(EXACT_DST_BASE, EXACT_FIT_BYTES + BYTES_PER_WORD, SENTINEL_WORD);
        seed_stream_descriptor(DESC0_IDX, EXACT_DST_BASE, EXACT_FIT_BYTES, 32'hAAAA_0000);
        hold_payload_resp_low = 1'b1;
        start_stream_descriptor(EXACT_FIT_BYTES);
        repeat (20) @(posedge clk);
        if (saw_completion_during_payload_hold_q ||
            saw_irq_during_payload_hold_q ||
            dut.i_stream_smoke.hw_head !== 16'd0 ||
            mem[desc_field_to_word(DESC0_IDX, DMA_DESC_ACTUAL_LEN_BYTE_OFFSET)] !== 32'h0000_0000 ||
            mem[desc_field_to_word(DESC0_IDX, DMA_DESC_CSW_BYTE_OFFSET)] !== DMA_DESC_CSW_OWNER) begin
            $fatal(1, "STREAM_STAGE EXACT_FIT payload write response barrier was violated before payload B completed");
        end
        hold_payload_resp_low = 1'b0;
        wait_for_csw_done(DESC0_IDX, 40000, "stream exact-fit");
        if (mem[desc_field_to_word(DESC0_IDX, DMA_DESC_ACTUAL_LEN_BYTE_OFFSET)] !== EXACT_FIT_BYTES) begin
            $fatal(1, "STREAM_STAGE EXACT_FIT actual_len mismatch: got=%08h exp=%08h",
                   mem[desc_field_to_word(DESC0_IDX, DMA_DESC_ACTUAL_LEN_BYTE_OFFSET)],
                   EXACT_FIT_BYTES);
        end
        if ((mem[desc_field_to_word(DESC0_IDX, DMA_DESC_CSW_BYTE_OFFSET)] &
             (DMA_DESC_CSW_DONE | DMA_DESC_CSW_ERR | DMA_DESC_CSW_STS_MASK)) != DMA_DESC_CSW_DONE) begin
            $fatal(1, "STREAM_STAGE EXACT_FIT CSW mismatch: got=%08h",
                   mem[desc_field_to_word(DESC0_IDX, DMA_DESC_CSW_BYTE_OFFSET)]);
        end
        expect_pattern(EXACT_DST_BASE, EXACT_FIT_BYTES, "stream exact-fit");
        if (mem[addr_to_word(EXACT_DST_BASE) + (EXACT_FIT_BYTES / BYTES_PER_WORD)] !== SENTINEL_WORD) begin
            $fatal(1, "STREAM_STAGE EXACT_FIT wrote beyond capacity");
        end
        $display("STREAM_STAGE EXACT_FIT PASS actual_len=1024");

        prepare_ring();
        clear_region(SHORT_DST_BASE, EXACT_FIT_BYTES + BYTES_PER_WORD, SENTINEL_WORD);
        seed_stream_descriptor(DESC0_IDX, SHORT_DST_BASE, EXACT_FIT_BYTES, 32'hBBBB_0000);
        start_stream_descriptor(SHORT_FRAME_BYTES);
        wait_for_csw_done(DESC0_IDX, 40000, "stream short");
        if (mem[desc_field_to_word(DESC0_IDX, DMA_DESC_ACTUAL_LEN_BYTE_OFFSET)] !== SHORT_FRAME_BYTES) begin
            $fatal(1, "STREAM_STAGE SHORT actual_len mismatch: got=%08h exp=%08h",
                   mem[desc_field_to_word(DESC0_IDX, DMA_DESC_ACTUAL_LEN_BYTE_OFFSET)],
                   SHORT_FRAME_BYTES);
        end
        if ((mem[desc_field_to_word(DESC0_IDX, DMA_DESC_CSW_BYTE_OFFSET)] &
             (DMA_DESC_CSW_DONE | DMA_DESC_CSW_ERR | DMA_DESC_CSW_STS_MASK)) != DMA_DESC_CSW_DONE) begin
            $fatal(1, "STREAM_STAGE SHORT CSW mismatch: got=%08h",
                   mem[desc_field_to_word(DESC0_IDX, DMA_DESC_CSW_BYTE_OFFSET)]);
        end
        expect_pattern(SHORT_DST_BASE, SHORT_FRAME_BYTES, "stream short");
        if (mem[addr_to_word(SHORT_DST_BASE) + (SHORT_FRAME_BYTES / BYTES_PER_WORD)] !== SENTINEL_WORD) begin
            $fatal(1, "STREAM_STAGE SHORT wrote beyond TLAST-bound payload");
        end
        $display("STREAM_STAGE SHORT PASS actual_len=64");

        prepare_ring();
        clear_region(OVERFLOW_DST_BASE, OVERFLOW_CAPACITY + BYTES_PER_WORD, SENTINEL_WORD);
        seed_stream_descriptor(DESC0_IDX, OVERFLOW_DST_BASE, OVERFLOW_CAPACITY, 32'hCCCC_0000);
        hold_wb_resp_low = 1'b1;
        start_stream_descriptor(OVERFLOW_PACKET_BYTES);
        repeat (20) @(posedge clk);
        if (saw_completion_during_wb_hold_q ||
            saw_irq_during_wb_hold_q ||
            dut.i_stream_smoke.hw_head !== 16'd0 ||
            (mem[desc_field_to_word(DESC0_IDX, DMA_DESC_CSW_BYTE_OFFSET)] & DMA_DESC_CSW_DONE) != 0) begin
            $fatal(1, "STREAM_STAGE OVERFLOW completion became software-visible before the final CSW writeback response");
        end
        hold_wb_resp_low = 1'b0;
        wait_for_csw_done(DESC0_IDX, 40000, "stream overflow");
        if (mem[desc_field_to_word(DESC0_IDX, DMA_DESC_ACTUAL_LEN_BYTE_OFFSET)] !== OVERFLOW_CAPACITY) begin
            $fatal(1, "STREAM_STAGE OVERFLOW actual_len mismatch: got=%08h exp=%08h",
                   mem[desc_field_to_word(DESC0_IDX, DMA_DESC_ACTUAL_LEN_BYTE_OFFSET)],
                   OVERFLOW_CAPACITY);
        end
        if ((mem[desc_field_to_word(DESC0_IDX, DMA_DESC_CSW_BYTE_OFFSET)] &
             (DMA_DESC_CSW_DONE | DMA_DESC_CSW_ERR | DMA_DESC_CSW_STS_MASK)) !==
            (DMA_DESC_CSW_DONE | DMA_DESC_CSW_ERR | DMA_DESC_CSW_STS_OVERFLOW_OR_MISSING_TLAST)) begin
            $fatal(1, "STREAM_STAGE OVERFLOW status mismatch: got=%08h",
                   mem[desc_field_to_word(DESC0_IDX, DMA_DESC_CSW_BYTE_OFFSET)]);
        end
        expect_pattern(OVERFLOW_DST_BASE, OVERFLOW_CAPACITY, "stream overflow");
        if (mem[addr_to_word(OVERFLOW_DST_BASE) + (OVERFLOW_CAPACITY / BYTES_PER_WORD)] !== SENTINEL_WORD) begin
            $fatal(1, "STREAM_STAGE OVERFLOW wrote beyond capacity");
        end
        $display("STREAM_STAGE OVERFLOW PASS actual_len=64");

        $display("DMA stream smoke PASS");
        $finish;
    end

endmodule
