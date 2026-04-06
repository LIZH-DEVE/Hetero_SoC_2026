`timescale 1ns / 1ps

module tb_dma_tx_output_sanity;

    logic clk;
    logic rst_n;

    logic [31:0] s_axil_awaddr;
    logic        s_axil_awvalid;
    logic        s_axil_awready;
    logic [31:0] s_axil_wdata;
    logic [3:0]  s_axil_wstrb;
    logic        s_axil_wvalid;
    logic        s_axil_wready;
    logic [1:0]  s_axil_bresp;
    logic        s_axil_bvalid;
    logic        s_axil_bready;
    logic [31:0] s_axil_araddr;
    logic        s_axil_arvalid;
    logic        s_axil_arready;
    logic [31:0] s_axil_rdata;
    logic [1:0]  s_axil_rresp;
    logic        s_axil_rvalid;
    logic        s_axil_rready;

    logic        rx_wr_valid;
    logic [31:0] rx_wr_data;
    logic        rx_wr_last;
    logic        rx_wr_ready;

    logic [31:0] tx_axis_tdata;
    logic        tx_axis_tvalid;
    logic        tx_axis_tlast;
    logic [3:0]  tx_axis_tkeep;
    logic        tx_axis_tready;

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
    logic        m_axis_s2mm_awready;
    logic [31:0] m_axis_s2mm_wdata;
    logic [3:0]  m_axis_s2mm_wstrb;
    logic        m_axis_s2mm_wlast;
    logic        m_axis_s2mm_wvalid;
    logic        m_axis_s2mm_wready;
    logic [1:0]  m_axis_s2mm_bresp;
    logic        m_axis_s2mm_bvalid;
    logic        m_axis_s2mm_bready;
    logic [31:0] m_axis_s2mm_araddr;
    logic [7:0]  m_axis_s2mm_arlen;
    logic [2:0]  m_axis_s2mm_arsize;
    logic [1:0]  m_axis_s2mm_arburst;
    logic        m_axis_s2mm_arvalid;
    logic        m_axis_s2mm_arready;
    logic [31:0] m_axis_s2mm_rdata;
    logic [1:0]  m_axis_s2mm_rresp;
    logic        m_axis_s2mm_rlast;
    logic        m_axis_s2mm_rvalid;
    logic        m_axis_s2mm_rready;

    logic [31:0] m_axis_fetcher_araddr;
    logic [7:0]  m_axis_fetcher_arlen;
    logic [2:0]  m_axis_fetcher_arsize;
    logic [1:0]  m_axis_fetcher_arburst;
    logic        m_axis_fetcher_arvalid;
    logic        m_axis_fetcher_arready;
    logic [31:0] m_axis_fetcher_rdata;
    logic [1:0]  m_axis_fetcher_rresp;
    logic        m_axis_fetcher_rlast;
    logic        m_axis_fetcher_rvalid;
    logic        m_axis_fetcher_rready;

    logic        dma_irq;

    integer      tx_count;
    logic [31:0] tx_words [0:15];
    logic        tx_lasts [0:15];
    logic [3:0]  tx_keeps [0:15];

    dma_subsystem dut (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        .rx_wr_valid(rx_wr_valid), .rx_wr_data(rx_wr_data), .rx_wr_last(rx_wr_last), .rx_wr_ready(rx_wr_ready),
        .tx_axis_tdata(tx_axis_tdata), .tx_axis_tvalid(tx_axis_tvalid), .tx_axis_tlast(tx_axis_tlast), .tx_axis_tkeep(tx_axis_tkeep), .tx_axis_tready(tx_axis_tready),
        .m_axis_awaddr(m_axis_awaddr), .m_axis_awlen(m_axis_awlen), .m_axis_awsize(m_axis_awsize), .m_axis_awburst(m_axis_awburst),
        .m_axis_awcache(m_axis_awcache), .m_axis_awprot(m_axis_awprot), .m_axis_awvalid(m_axis_awvalid), .m_axis_awready(m_axis_awready),
        .m_axis_wdata(m_axis_wdata), .m_axis_wstrb(m_axis_wstrb), .m_axis_wlast(m_axis_wlast), .m_axis_wvalid(m_axis_wvalid), .m_axis_wready(m_axis_wready),
        .m_axis_bresp(m_axis_bresp), .m_axis_bvalid(m_axis_bvalid), .m_axis_bready(m_axis_bready),
        .m_axis_s2mm_awaddr(m_axis_s2mm_awaddr), .m_axis_s2mm_awlen(m_axis_s2mm_awlen), .m_axis_s2mm_awsize(m_axis_s2mm_awsize), .m_axis_s2mm_awburst(m_axis_s2mm_awburst),
        .m_axis_s2mm_awcache(m_axis_s2mm_awcache), .m_axis_s2mm_awprot(m_axis_s2mm_awprot), .m_axis_s2mm_awvalid(m_axis_s2mm_awvalid), .m_axis_s2mm_awready(m_axis_s2mm_awready),
        .m_axis_s2mm_wdata(m_axis_s2mm_wdata), .m_axis_s2mm_wstrb(m_axis_s2mm_wstrb), .m_axis_s2mm_wlast(m_axis_s2mm_wlast), .m_axis_s2mm_wvalid(m_axis_s2mm_wvalid), .m_axis_s2mm_wready(m_axis_s2mm_wready),
        .m_axis_s2mm_bresp(m_axis_s2mm_bresp), .m_axis_s2mm_bvalid(m_axis_s2mm_bvalid), .m_axis_s2mm_bready(m_axis_s2mm_bready),
        .m_axis_s2mm_araddr(m_axis_s2mm_araddr), .m_axis_s2mm_arlen(m_axis_s2mm_arlen), .m_axis_s2mm_arsize(m_axis_s2mm_arsize), .m_axis_s2mm_arburst(m_axis_s2mm_arburst),
        .m_axis_s2mm_arvalid(m_axis_s2mm_arvalid), .m_axis_s2mm_arready(m_axis_s2mm_arready), .m_axis_s2mm_rdata(m_axis_s2mm_rdata), .m_axis_s2mm_rresp(m_axis_s2mm_rresp),
        .m_axis_s2mm_rlast(m_axis_s2mm_rlast), .m_axis_s2mm_rvalid(m_axis_s2mm_rvalid), .m_axis_s2mm_rready(m_axis_s2mm_rready),
        .m_axis_fetcher_araddr(m_axis_fetcher_araddr), .m_axis_fetcher_arlen(m_axis_fetcher_arlen), .m_axis_fetcher_arsize(m_axis_fetcher_arsize), .m_axis_fetcher_arburst(m_axis_fetcher_arburst),
        .m_axis_fetcher_arvalid(m_axis_fetcher_arvalid), .m_axis_fetcher_arready(m_axis_fetcher_arready), .m_axis_fetcher_rdata(m_axis_fetcher_rdata), .m_axis_fetcher_rresp(m_axis_fetcher_rresp),
        .m_axis_fetcher_rlast(m_axis_fetcher_rlast), .m_axis_fetcher_rvalid(m_axis_fetcher_rvalid), .m_axis_fetcher_rready(m_axis_fetcher_rready), .dma_irq(dma_irq)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_count <= 0;
            for (int i = 0; i < 16; i++) begin
                tx_words[i] <= 32'd0;
                tx_lasts[i] <= 1'b0;
                tx_keeps[i] <= 4'd0;
            end
        end else if (tx_axis_tvalid && tx_axis_tready) begin
            tx_words[tx_count] <= tx_axis_tdata;
            tx_lasts[tx_count] <= tx_axis_tlast;
            tx_keeps[tx_count] <= tx_axis_tkeep;
            tx_count <= tx_count + 1;
        end
    end

    task automatic reset_case;
        begin
            rst_n = 1'b0;
            rx_wr_valid = 1'b0;
            rx_wr_last  = 1'b0;
            rx_wr_data  = 32'd0;
            tx_axis_tready = 1'b0;
            repeat (12) @(posedge clk);
            rst_n = 1'b1;
            repeat (12) @(posedge clk);
        end
    endtask

    task automatic write_csr(input [31:0] addr, input [31:0] data);
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
            s_axil_bready <= 1'b0;
        end
    endtask

    task automatic configure_passthrough;
        begin
            write_csr(32'h0000_0028, 32'h2b7e1516);
            write_csr(32'h0000_002C, 32'h28aed2a6);
            write_csr(32'h0000_0030, 32'habf71588);
            write_csr(32'h0000_0034, 32'h09cf4f3c);
            write_csr(32'h0000_0000, 32'h0000_0008);
            write_csr(32'h0000_0048, 32'h0000_0002);
        end
    endtask

    task automatic drive_word(input [31:0] data, input bit last);
        integer guard_cycles;
        begin
            rx_wr_data  <= data;
            rx_wr_last  <= last;
            rx_wr_valid <= 1'b1;
            guard_cycles = 0;
            do begin
                @(posedge clk);
                guard_cycles = guard_cycles + 1;
                if (guard_cycles > 5000) begin
                    $fatal(1, "drive_word timeout data=%08h last=%0d", data, last);
                end
            end while (!rx_wr_ready);
            rx_wr_valid <= 1'b0;
            rx_wr_last  <= 1'b0;
        end
    endtask

    task automatic send_blocks(input integer block_count);
        integer total_words;
        begin
            total_words = block_count * 4;
            for (int i = 0; i < total_words; i++) begin
                drive_word(32'h2000_0000 + i, (i == total_words - 1));
            end
        end
    endtask

    task automatic wait_for_tx_words(input integer expected_words, input string case_name);
        integer guard_cycles;
        begin
            guard_cycles = 0;
            while (tx_count < expected_words) begin
                @(posedge clk);
                guard_cycles = guard_cycles + 1;
                if (guard_cycles > 20000) begin
                    $fatal(1, "%s timeout waiting for %0d tx words, saw %0d", case_name, expected_words, tx_count);
                end
            end
        end
    endtask

    task automatic check_stream(input integer expected_words, input integer last0, input integer last1, input string case_name);
        begin
            for (int i = 0; i < expected_words; i++) begin
                bit expected_last;
                expected_last = ((i + 1) == last0) || ((i + 1) == last1);
                if (tx_lasts[i] !== expected_last) begin
                    $fatal(1, "%s wrong last at beat %0d: expected %0d got %0d", case_name, i + 1, expected_last, tx_lasts[i]);
                end
                if (tx_keeps[i] !== 4'hF) begin
                    $fatal(1, "%s wrong keep at beat %0d: got %h", case_name, i + 1, tx_keeps[i]);
                end
            end
        end
    endtask

    initial begin
        s_axil_awaddr = 32'd0; s_axil_awvalid = 1'b0; s_axil_wdata = 32'd0; s_axil_wstrb = 4'd0; s_axil_wvalid = 1'b0; s_axil_bready = 1'b0;
        s_axil_araddr = 32'd0; s_axil_arvalid = 1'b0; s_axil_rready = 1'b0;
        rx_wr_valid = 1'b0; rx_wr_data = 32'd0; rx_wr_last = 1'b0; tx_axis_tready = 1'b0; rst_n = 1'b0;
        m_axis_awready = 1'b1; m_axis_wready = 1'b1; m_axis_bresp = 2'b00; m_axis_bvalid = 1'b0;
        m_axis_s2mm_awready = 1'b1; m_axis_s2mm_wready = 1'b1; m_axis_s2mm_bresp = 2'b00; m_axis_s2mm_bvalid = 1'b0;
        m_axis_s2mm_arready = 1'b1; m_axis_s2mm_rdata = 32'd0; m_axis_s2mm_rresp = 2'b00; m_axis_s2mm_rlast = 1'b0; m_axis_s2mm_rvalid = 1'b0;
        m_axis_fetcher_arready = 1'b1; m_axis_fetcher_rdata = 32'd0; m_axis_fetcher_rresp = 2'b00; m_axis_fetcher_rlast = 1'b0; m_axis_fetcher_rvalid = 1'b0;

        reset_case();
        configure_passthrough();
        tx_axis_tready = 1'b1;
        send_blocks(1);
        wait_for_tx_words(4, "dma_single_block");
        check_stream(4, 4, -1, "dma_single_block");

        reset_case();
        configure_passthrough();
        tx_axis_tready = 1'b1;
        send_blocks(2);
        wait_for_tx_words(8, "dma_double_block");
        check_stream(8, 4, 8, "dma_double_block");

        reset_case();
        configure_passthrough();
        tx_axis_tready = 1'b0;
        send_blocks(1);
        repeat (8) @(posedge clk);
        if (tx_count != 0) begin
            $fatal(1, "dma_backpressure advanced while tready=0, saw %0d", tx_count);
        end
        tx_axis_tready = 1'b1;
        wait_for_tx_words(4, "dma_backpressure_after_resume");
        check_stream(4, 4, -1, "dma_backpressure_after_resume");

        $display("PASS: dma_subsystem tx output exposed block-level tlast");
        $finish;
    end

endmodule
