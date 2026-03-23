`timescale 1ns / 1ps

module tb_dma_desc_fetcher_doorbell_sanity;

    logic clk;
    logic rst_n;
    logic [31:0] i_ring_base;
    logic [31:0] i_ring_size;
    logic        i_ring_doorbell;
    logic [15:0] i_sw_tail_ptr;
    logic [15:0] o_hw_head_ptr;
    logic        o_dma_start;
    logic [31:0] o_dma_addr;
    logic [31:0] o_dma_len;
    logic        o_dma_algo;
    logic        i_dma_done;
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

    dma_desc_fetcher dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_ring_base(i_ring_base),
        .i_ring_size(i_ring_size),
        .i_ring_doorbell(i_ring_doorbell),
        .i_sw_tail_ptr(i_sw_tail_ptr),
        .o_hw_head_ptr(o_hw_head_ptr),
        .o_dma_start(o_dma_start),
        .o_dma_addr(o_dma_addr),
        .o_dma_len(o_dma_len),
        .o_dma_algo(o_dma_algo),
        .i_dma_done(i_dma_done),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
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

            m_axi_rdata  <= desc_ctrl;
            m_axi_rlast  <= 1'b0;
            @(posedge clk);

            m_axi_rdata  <= 32'hDEAD_BEEF;
            m_axi_rlast  <= 1'b0;
            @(posedge clk);

            m_axi_rdata  <= 32'hCAFE_BABE;
            m_axi_rlast  <= 1'b1;
            @(posedge clk);

            m_axi_rvalid <= 1'b0;
            m_axi_rlast  <= 1'b0;
            m_axi_rdata  <= 32'd0;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        i_ring_base = 32'h1000_0000;
        i_ring_size = 32'd4;
        i_ring_doorbell = 1'b0;
        i_sw_tail_ptr = 16'd1;
        i_dma_done = 1'b0;
        m_axi_arready = 1'b0;
        m_axi_rdata = 32'd0;
        m_axi_rlast = 1'b0;
        m_axi_rvalid = 1'b0;

        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (8) @(posedge clk);

        if (m_axi_arvalid !== 1'b0) begin
            $fatal(1, "fetcher must stay silent before doorbell");
        end

        i_ring_doorbell = 1'b1;
        @(posedge clk);
        i_ring_doorbell = 1'b0;

        send_descriptor(32'h2000_0000, 32'h8000_0040);

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

        i_dma_done = 1'b1;
        @(posedge clk);
        i_dma_done = 1'b0;
        repeat (4) @(posedge clk);

        if (o_hw_head_ptr !== 16'd1) begin
            $fatal(1, "head pointer did not advance after completed fetch");
        end
        if (m_axi_arvalid !== 1'b0) begin
            $fatal(1, "fetcher should quiesce again once head catches tail");
        end

        $display("PASS: dma_desc_fetcher honors doorbell-gated fetch");
        $finish;
    end

endmodule
