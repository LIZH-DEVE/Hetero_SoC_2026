`timescale 1ns / 1ps

module tb_dma_desc_fetcher_doorbell_sanity;

    import dma_csr_pkg::*;

    logic clk;
    logic rst_n;
    logic i_soft_reset;
    logic [31:0] i_ring_base;
    logic [31:0] i_ring_size;
    logic        i_ring_doorbell;
    logic [15:0] i_sw_tail_ptr;
    logic [15:0] o_hw_head_ptr;
    logic        o_dma_start;
    logic [31:0] o_dma_addr;
    logic [31:0] o_dma_src_addr;
    logic [31:0] o_dma_len;
    logic        o_dma_algo;
    logic        o_dma_stream_tlast;
    logic [31:0] i_dma_actual_len;
    logic        i_dma_done;
    logic        i_dma_error;
    logic [1:0]  i_dma_bresp;
    logic        o_completion_event;
    logic [31:0] m_axi_araddr;
    logic [7:0]  m_axi_arlen;
    logic [2:0]  m_axi_arsize;
    logic [1:0]  m_axi_arburst;
    logic        m_axi_arvalid;
    logic        m_axi_arready;
    logic [31:0] m_axi_rdata;
    logic        m_axi_rlast;
    logic        m_axi_rvalid;
    logic        m_axi_rready;
    logic [31:0] m_axi_awaddr;
    logic [7:0]  m_axi_awlen;
    logic [2:0]  m_axi_awsize;
    logic [1:0]  m_axi_awburst;
    logic [3:0]  m_axi_awcache;
    logic [2:0]  m_axi_awprot;
    logic        m_axi_awvalid;
    logic        m_axi_awready;
    logic [31:0] m_axi_wdata;
    logic [3:0]  m_axi_wstrb;
    logic        m_axi_wlast;
    logic        m_axi_wvalid;
    logic        m_axi_wready;
    logic [1:0]  m_axi_bresp;
    logic        m_axi_bvalid;
    logic        m_axi_bready;
    logic        o_wb_active;

    dma_desc_fetcher dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_soft_reset(i_soft_reset),
        .i_ring_base(i_ring_base),
        .i_ring_size(i_ring_size),
        .i_ring_doorbell(i_ring_doorbell),
        .i_sw_tail_ptr(i_sw_tail_ptr),
        .o_hw_head_ptr(o_hw_head_ptr),
        .o_dma_start(o_dma_start),
        .o_dma_addr(o_dma_addr),
        .o_dma_src_addr(o_dma_src_addr),
        .o_dma_len(o_dma_len),
        .o_dma_algo(o_dma_algo),
        .o_dma_stream_tlast(o_dma_stream_tlast),
        .i_dma_done(i_dma_done),
        .i_dma_error(i_dma_error),
        .i_dma_bresp(i_dma_bresp),
        .i_dma_actual_len(i_dma_actual_len),
        .o_completion_event(o_completion_event),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
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
        .o_wb_active(o_wb_active)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic send_descriptor(
        input [31:0] desc_addr,
        input [31:0] desc_ctrl
    );
        begin
            m_axi_arready <= 1'b1;
            do @(posedge clk); while (!m_axi_arvalid);
            @(posedge clk);
            m_axi_arready <= 1'b0;

            m_axi_rvalid <= 1'b1;
            m_axi_rdata  <= desc_addr;
            m_axi_rlast  <= 1'b0;
            do @(posedge clk); while (!m_axi_rready);

            m_axi_rdata  <= 32'hABCD_0001;
            m_axi_rlast  <= 1'b0;
            @(posedge clk);

            m_axi_rdata  <= desc_ctrl;
            m_axi_rlast  <= 1'b0;
            @(posedge clk);

            m_axi_rdata  <= 32'hDEAD_BEEF;
            m_axi_rlast  <= 1'b0;
            @(posedge clk);

            m_axi_rdata  <= DMA_DESC_CSW_OWNER;
            m_axi_rlast  <= 1'b1;
            @(posedge clk);

            m_axi_rvalid <= 1'b0;
            m_axi_rlast  <= 1'b0;
            m_axi_rdata  <= 32'd0;
        end
    endtask

    task automatic respond_writeback(
        input [31:0] expected_addr,
        input [31:0] expected_data
    );
        begin
            m_axi_awready <= 1'b1;
            do @(posedge clk); while (!m_axi_awvalid);
            if (m_axi_awlen !== 8'd0) begin
                $fatal(1, "write-back must be single word");
            end
            if (m_axi_awaddr !== expected_addr) begin
                $fatal(1, "write-back address mismatch: got=%08h", m_axi_awaddr);
            end
            @(posedge clk);
            m_axi_awready <= 1'b0;

            m_axi_wready <= 1'b1;
            do @(posedge clk); while (!m_axi_wvalid);
            if (m_axi_wstrb !== 4'hF) begin
                $fatal(1, "write-back WSTRB mismatch");
            end
            if (!m_axi_wlast) begin
                $fatal(1, "write-back must assert WLAST");
            end
            if (m_axi_wdata !== expected_data) begin
                $fatal(1,
                       "write-back data mismatch: got=%08h exp=%08h desc_ctrl=%08h dma_status=%08h stream=%0b",
                       m_axi_wdata,
                       expected_data,
                       dut.desc_word2_ctrl,
                       dut.dma_status_word,
                       o_dma_stream_tlast);
            end
            @(posedge clk);
            m_axi_wready <= 1'b0;

            m_axi_bresp  <= 2'b00;
            m_axi_bvalid <= 1'b1;
            do @(posedge clk); while (!m_axi_bready);
            @(posedge clk);
            m_axi_bvalid <= 1'b0;
            m_axi_bresp  <= 2'b00;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        i_soft_reset = 1'b0;
        i_ring_base = 32'h1000_0000;
        i_ring_size = 32'd4;
        i_ring_doorbell = 1'b0;
        i_sw_tail_ptr = 16'd1;
        i_dma_actual_len = 32'h0000_0040;
        i_dma_done = 1'b0;
        i_dma_error = 1'b0;
        i_dma_bresp = 2'b00;
        m_axi_arready = 1'b0;
        m_axi_rdata = 32'd0;
        m_axi_rlast = 1'b0;
        m_axi_rvalid = 1'b0;
        m_axi_awready = 1'b0;
        m_axi_wready = 1'b0;
        m_axi_bresp = 2'b00;
        m_axi_bvalid = 1'b0;

        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (8) @(posedge clk);

        if (m_axi_arvalid !== 1'b0) begin
            $fatal(1, "fetcher must stay silent before doorbell");
        end

        i_ring_doorbell = 1'b1;
        @(posedge clk);
        i_ring_doorbell = 1'b0;

        send_descriptor(32'h2000_0000, DMA_DESC_CTRL_ALGO | 32'h0000_0040);

        do @(posedge clk); while (!o_dma_start);
        if (o_dma_addr !== 32'h2000_0000) begin
            $fatal(1, "decoded addr mismatch: got=%08h", o_dma_addr);
        end
        if (o_dma_len !== 32'h0000_0040) begin
            $fatal(1, "decoded len mismatch: got=%08h", o_dma_len);
        end
        if (o_dma_algo !== 1'b1) begin
            $fatal(1, "decoded algo mismatch");
        end
        if (o_dma_stream_tlast !== 1'b0) begin
            $fatal(1, "fixed-length descriptor must not raise stream_tlast");
        end

        i_dma_done = 1'b1;
        @(posedge clk);
        i_dma_done = 1'b0;

        respond_writeback(i_ring_base + DMA_DESC_ACTUAL_LEN_BYTE_OFFSET, i_dma_actual_len);
        repeat (2) @(posedge clk);
        if (o_completion_event !== 1'b0) begin
            $fatal(1, "completion event must wait for the final CSW write-back response");
        end
        if (o_hw_head_ptr !== 16'd0) begin
            $fatal(1, "head pointer must not advance until the final CSW write-back response");
        end
        if (o_wb_active !== 1'b1) begin
            $fatal(1, "write-back path should remain active between actual_len and CSW write-back");
        end
        respond_writeback(i_ring_base + DMA_DESC_CSW_BYTE_OFFSET, DMA_DESC_CSW_DONE);
        repeat (4) @(posedge clk);
        if (o_completion_event !== 1'b0) begin
            $fatal(1, "completion event should be a pulse");
        end

        if (o_hw_head_ptr !== 16'd1) begin
            $fatal(1, "head pointer did not advance after completed fetch");
        end
        if (o_wb_active !== 1'b0) begin
            $fatal(1, "write-back should quiesce after response");
        end
        if (m_axi_arvalid !== 1'b0) begin
            $fatal(1, "fetcher should quiesce again once head catches tail");
        end

        i_soft_reset = 1'b1;
        @(posedge clk);
        i_soft_reset = 1'b0;
        repeat (4) @(posedge clk);
        if (o_wb_active !== 1'b0) begin
            $fatal(1, "write-back state should clear on soft reset");
        end
        if (o_hw_head_ptr !== 16'd0) begin
            $fatal(1, "soft reset should clear the fetcher head pointer");
        end

        i_ring_doorbell = 1'b1;
        @(posedge clk);
        i_ring_doorbell = 1'b0;

        send_descriptor(32'h2000_0000, DMA_DESC_CTRL_ALGO | DMA_DESC_CTRL_STREAM_TLAST | 32'h0000_0040);
        do @(posedge clk); while (!o_dma_start);
        if (o_dma_stream_tlast !== 1'b1) begin
            $fatal(1, "stream_tlast hook must decode descriptor bit 30");
        end
        wait (dut.state == dut.EXEC_WAIT);
        i_dma_actual_len = 32'h0000_0020;
        i_dma_error = 1'b1;
        i_dma_bresp = 2'b00;
        respond_writeback(i_ring_base + DMA_DESC_ACTUAL_LEN_BYTE_OFFSET, i_dma_actual_len);
        i_dma_error = 1'b0;
        i_dma_bresp = 2'b00;
        repeat (2) @(posedge clk);
        if (o_completion_event !== 1'b0) begin
            $fatal(1, "stream error completion must still wait for the final CSW write-back response");
        end
        if (o_hw_head_ptr !== 16'd0) begin
            $fatal(1, "stream error path must not advance the head pointer before the final CSW write-back");
        end
        respond_writeback(
            i_ring_base + DMA_DESC_CSW_BYTE_OFFSET,
            DMA_DESC_CSW_DONE | DMA_DESC_CSW_ERR | DMA_DESC_CSW_STS_OVERFLOW_OR_MISSING_TLAST
        );
        repeat (4) @(posedge clk);
        if (o_hw_head_ptr !== 16'd1) begin
            $fatal(1, "stream error path must advance the head pointer after the final CSW write-back");
        end

        $display("PASS: dma_desc_fetcher honors doorbell-gated fetch");
        $finish;
    end

endmodule
