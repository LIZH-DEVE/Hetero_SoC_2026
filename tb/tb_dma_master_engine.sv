`timescale 1ns / 1ps

module tb_dma_master_engine;

    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam TOTAL_BYTES = 2048;
    localparam TOTAL_WORDS = TOTAL_BYTES / 4;

    logic clk;
    logic rst_n;
    logic i_start;
    logic [ADDR_WIDTH-1:0] i_base_addr;
    logic [31:0] i_total_len;
    logic o_done;
    logic o_error;

    logic [DATA_WIDTH-1:0] i_fifo_rdata;
    logic                  i_fifo_empty;
    logic                  o_fifo_ren;

    logic [ADDR_WIDTH-1:0] m_axi_awaddr;
    logic [7:0]            m_axi_awlen;
    logic [2:0]            m_axi_awsize;
    logic [1:0]            m_axi_awburst;
    logic [3:0]            m_axi_awcache;
    logic [2:0]            m_axi_awprot;
    logic                  m_axi_awvalid;
    logic                  m_axi_awready;

    logic [DATA_WIDTH-1:0] m_axi_wdata;
    logic [DATA_WIDTH/8-1:0] m_axi_wstrb;
    logic                  m_axi_wlast;
    logic                  m_axi_wvalid;
    logic                  m_axi_wready;
    logic [1:0]            m_axi_wresp;
    logic                  m_axi_blast;
    logic                  m_axi_bvalid;
    logic                  m_axi_bready;

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

    logic [15:0] lfsr_aw;
    logic [15:0] lfsr_w;
    logic [15:0] lfsr_b;
    logic [7:0]  pending_b_delay;
    logic        pending_b;
    integer      words_sent;
    integer      aw_count;
    integer      b_count;
    integer      timeout_cycles;

    dma_master_engine #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MAX_OUTSTANDING_WRITES(4)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_start(i_start),
        .i_base_addr(i_base_addr),
        .i_total_len(i_total_len),
        .o_done(o_done),
        .o_error(o_error),
        .i_fifo_rdata(i_fifo_rdata),
        .i_fifo_empty(i_fifo_empty),
        .o_fifo_ren(o_fifo_ren),
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
        .m_axi_wresp(m_axi_wresp),
        .m_axi_blast(m_axi_blast),
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
        .m_axi_rready(m_axi_rready)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_aw <= 16'h1ACE;
            lfsr_w  <= 16'h2BAD;
            lfsr_b  <= 16'h3FED;
        end else begin
            lfsr_aw <= {lfsr_aw[14:0], lfsr_aw[15] ^ lfsr_aw[13] ^ lfsr_aw[12] ^ lfsr_aw[10]};
            lfsr_w  <= {lfsr_w[14:0],  lfsr_w[15]  ^ lfsr_w[14]  ^ lfsr_w[12]  ^ lfsr_w[3]};
            lfsr_b  <= {lfsr_b[14:0],  lfsr_b[15]  ^ lfsr_b[11]  ^ lfsr_b[2]   ^ lfsr_b[0]};
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            words_sent <= 0;
            i_fifo_rdata <= 32'hA000_0000;
            i_fifo_empty <= 1'b0;
        end else begin
            if (o_fifo_ren && !i_fifo_empty) begin
                words_sent <= words_sent + 1;
                i_fifo_rdata <= i_fifo_rdata + 32'd1;
                if (words_sent + 1 >= TOTAL_WORDS) begin
                    i_fifo_empty <= 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awready <= 1'b0;
            m_axi_wready <= 1'b0;
            m_axi_bvalid <= 1'b0;
            m_axi_wresp <= 2'b00;
            m_axi_blast <= 1'b0;
            pending_b <= 1'b0;
            pending_b_delay <= 8'd0;
            aw_count <= 0;
            b_count <= 0;
        end else begin
            m_axi_awready <= (lfsr_aw[3:0] < 4'd10); // ~62.5% ready
            m_axi_wready  <= (lfsr_w[3:0]  < 4'd9);  // ~56.25% ready

            if (m_axi_awvalid && m_axi_awready) begin
                aw_count <= aw_count + 1;
            end

            if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                pending_b <= 1'b1;
                pending_b_delay <= {1'b0, (lfsr_b[6:0] % 8'd101)};
            end

            if (pending_b && !m_axi_bvalid) begin
                if (pending_b_delay == 0) begin
                    m_axi_bvalid <= 1'b1;
                end else begin
                    pending_b_delay <= pending_b_delay - 8'd1;
                end
            end

            if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 1'b0;
                pending_b <= 1'b0;
                b_count <= b_count + 1;
            end

            if (dut.outstanding_writes > 4) begin
                $fatal(1, "outstanding_writes exceeded limit: %0d", dut.outstanding_writes);
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        i_start = 1'b0;
        i_base_addr = 32'd0;
        i_total_len = 32'd0;
        m_axi_arready = 1'b0;
        m_axi_rdata = '0;
        m_axi_rresp = 2'b00;
        m_axi_rlast = 1'b0;
        m_axi_rvalid = 1'b0;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        @(posedge clk);
        i_base_addr = 32'h2000_1000;
        i_total_len = TOTAL_BYTES;
        i_start = 1'b1;
        @(posedge clk);
        i_start = 1'b0;

        timeout_cycles = 0;
        while (!o_done) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
            if (timeout_cycles > 50000) begin
                $fatal(1, "DMA engine timed out under random AW/W/B backpressure");
            end
        end

        if (o_error) begin
            $fatal(1, "DMA engine asserted error during random backpressure test");
        end
        if (words_sent != TOTAL_WORDS) begin
            $fatal(1, "FIFO words mismatch: sent=%0d expected=%0d", words_sent, TOTAL_WORDS);
        end
        if (aw_count == 0 || b_count == 0) begin
            $fatal(1, "Expected non-zero AW/B activity, got aw=%0d b=%0d", aw_count, b_count);
        end

        $display("PASS: dma_master_engine survives random AW/W/B backpressure");
        $finish;
    end

endmodule
