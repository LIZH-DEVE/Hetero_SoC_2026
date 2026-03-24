`timescale 1ns / 1ps

module tb_dma_subsystem_ps_bfm_system;

    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam DDR_WORDS = 16384;

    localparam [31:0] CSR_CTRL       = 32'h0000_0000;
    localparam [31:0] CSR_KEY0       = 32'h0000_0028;
    localparam [31:0] CSR_KEY1       = 32'h0000_002C;
    localparam [31:0] CSR_KEY2       = 32'h0000_0030;
    localparam [31:0] CSR_KEY3       = 32'h0000_0034;
    localparam [31:0] CSR_DOORBELL   = 32'h0000_004C;
    localparam [31:0] CSR_RING_BASE  = 32'h0000_0050;
    localparam [31:0] CSR_SW_TAIL    = 32'h0000_0058;
    localparam [31:0] CSR_RING_SIZE  = 32'h0000_005C;

    localparam [31:0] RING_BASE_ADDR = 32'h0000_1000;
    localparam integer RING_SIZE_ENTRIES = 4;
    localparam integer DESC_STRIDE_BYTES = 32;
    localparam integer DESC_CSW_OFFSET = 16;

    localparam CTRL_ALGO_BIT = 31;
    localparam [31:0] CTRL_LEN_MASK = 32'h00FF_FFFF;
    localparam integer CSW_OWNER_BIT = 31;
    localparam integer CSW_DONE_BIT  = 30;
    localparam integer CSW_ERR_BIT   = 29;
    localparam integer CSW_STS_LSB   = 0;

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

    logic dma_irq;

    logic [31:0] ddr_mem [0:DDR_WORDS-1];

    logic [15:0] lfsr_aw;
    logic [15:0] lfsr_w;
    logic [15:0] lfsr_b;
    logic [15:0] lfsr_dsb;

    logic [31:0] pending_awaddr;
    logic [7:0]  pending_awlen;
    logic [7:0]  pending_beat_idx;
    logic        pending_is_writeback;
    integer      pending_desc_idx;

    logic        pending_b_valid;
    logic [7:0]  pending_b_delay;
    logic [1:0]  pending_bresp;
    logic [1:0]  dbg_last_payload_bresp;
    logic [1:0]  dbg_last_writeback_bresp;
    integer      dbg_last_payload_desc_idx;
    integer      dbg_last_writeback_desc_idx;
    logic [31:0] dbg_last_wlast_awaddr;
    integer      dbg_last_wlast_desc_idx;
    integer      dbg_last_wlast_inject_target;
    logic [1:0]  dbg_last_wlast_bresp;

    logic        awaiting_writeback_before_next_fetch;
    integer      inject_payload_error_desc_idx;

    logic [31:0] csw0;
    logic [31:0] csw1;
    logic [31:0] csw2;

    logic [31:0] expected_plaintext [0:2][0:3];
    logic [31:0] expected_ciphertext [0:2][0:3];
    logic [31:0] observed_payload [0:2][0:3];
    integer      observed_words [0:2];

    logic [31:0] expected_desc_word1 [0:2];
    logic [31:0] expected_desc_word3 [0:2];
    logic [31:0] expected_desc_word5 [0:2];
    logic [31:0] expected_desc_word6 [0:2];
    logic [31:0] expected_desc_word7 [0:2];

    dma_subsystem #(
        .PBM_ADDR_WIDTH(8)
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
        .rx_wr_valid(rx_wr_valid),
        .rx_wr_data(rx_wr_data),
        .rx_wr_last(rx_wr_last),
        .rx_wr_ready(rx_wr_ready),
        .tx_axis_tdata(tx_axis_tdata),
        .tx_axis_tvalid(tx_axis_tvalid),
        .tx_axis_tlast(tx_axis_tlast),
        .tx_axis_tkeep(tx_axis_tkeep),
        .tx_axis_tready(tx_axis_tready),
        .m_axis_awaddr(m_axis_awaddr),
        .m_axis_awlen(m_axis_awlen),
        .m_axis_awsize(m_axis_awsize),
        .m_axis_awburst(m_axis_awburst),
        .m_axis_awcache(m_axis_awcache),
        .m_axis_awprot(m_axis_awprot),
        .m_axis_awvalid(m_axis_awvalid),
        .m_axis_awready(m_axis_awready),
        .m_axis_wdata(m_axis_wdata),
        .m_axis_wstrb(m_axis_wstrb),
        .m_axis_wlast(m_axis_wlast),
        .m_axis_wvalid(m_axis_wvalid),
        .m_axis_wready(m_axis_wready),
        .m_axis_bresp(m_axis_bresp),
        .m_axis_bvalid(m_axis_bvalid),
        .m_axis_bready(m_axis_bready),
        .m_axis_s2mm_awaddr(m_axis_s2mm_awaddr),
        .m_axis_s2mm_awlen(m_axis_s2mm_awlen),
        .m_axis_s2mm_awsize(m_axis_s2mm_awsize),
        .m_axis_s2mm_awburst(m_axis_s2mm_awburst),
        .m_axis_s2mm_awcache(m_axis_s2mm_awcache),
        .m_axis_s2mm_awprot(m_axis_s2mm_awprot),
        .m_axis_s2mm_awvalid(m_axis_s2mm_awvalid),
        .m_axis_s2mm_awready(m_axis_s2mm_awready),
        .m_axis_s2mm_wdata(m_axis_s2mm_wdata),
        .m_axis_s2mm_wstrb(m_axis_s2mm_wstrb),
        .m_axis_s2mm_wlast(m_axis_s2mm_wlast),
        .m_axis_s2mm_wvalid(m_axis_s2mm_wvalid),
        .m_axis_s2mm_wready(m_axis_s2mm_wready),
        .m_axis_s2mm_bresp(m_axis_s2mm_bresp),
        .m_axis_s2mm_bvalid(m_axis_s2mm_bvalid),
        .m_axis_s2mm_bready(m_axis_s2mm_bready),
        .m_axis_s2mm_araddr(m_axis_s2mm_araddr),
        .m_axis_s2mm_arlen(m_axis_s2mm_arlen),
        .m_axis_s2mm_arsize(m_axis_s2mm_arsize),
        .m_axis_s2mm_arburst(m_axis_s2mm_arburst),
        .m_axis_s2mm_arvalid(m_axis_s2mm_arvalid),
        .m_axis_s2mm_arready(m_axis_s2mm_arready),
        .m_axis_s2mm_rdata(m_axis_s2mm_rdata),
        .m_axis_s2mm_rresp(m_axis_s2mm_rresp),
        .m_axis_s2mm_rlast(m_axis_s2mm_rlast),
        .m_axis_s2mm_rvalid(m_axis_s2mm_rvalid),
        .m_axis_s2mm_rready(m_axis_s2mm_rready),
        .m_axis_fetcher_araddr(m_axis_fetcher_araddr),
        .m_axis_fetcher_arlen(m_axis_fetcher_arlen),
        .m_axis_fetcher_arsize(m_axis_fetcher_arsize),
        .m_axis_fetcher_arburst(m_axis_fetcher_arburst),
        .m_axis_fetcher_arvalid(m_axis_fetcher_arvalid),
        .m_axis_fetcher_arready(m_axis_fetcher_arready),
        .m_axis_fetcher_rdata(m_axis_fetcher_rdata),
        .m_axis_fetcher_rresp(m_axis_fetcher_rresp),
        .m_axis_fetcher_rlast(m_axis_fetcher_rlast),
        .m_axis_fetcher_rvalid(m_axis_fetcher_rvalid),
        .m_axis_fetcher_rready(m_axis_fetcher_rready),
        .dma_irq(dma_irq)
    );

    function automatic integer addr_to_word(input [31:0] addr);
        addr_to_word = addr[31:2];
    endfunction

    function automatic [31:0] build_ctrl(input bit algo, input integer byte_len);
        build_ctrl = ({31'd0, algo} << CTRL_ALGO_BIT) | (byte_len & CTRL_LEN_MASK);
    endfunction

    function automatic [31:0] build_owner_csw();
        build_owner_csw = (32'h1 << CSW_OWNER_BIT);
    endfunction

    function automatic [31:0] build_done_csw(input bit err, input [1:0] sts);
        build_done_csw = (32'h1 << CSW_DONE_BIT) |
                         ((err ? 32'h1 : 32'h0) << CSW_ERR_BIT) |
                         ({30'd0, sts} << CSW_STS_LSB);
    endfunction

    function automatic integer payload_desc_idx_from_addr(input [31:0] awaddr);
        begin
            case (awaddr)
                32'h0000_2000: payload_desc_idx_from_addr = 0;
                32'h0000_2100: payload_desc_idx_from_addr = 1;
                32'h0000_2200: payload_desc_idx_from_addr = 2;
                default:       payload_desc_idx_from_addr = -1;
            endcase
        end
    endfunction

    function automatic integer writeback_desc_idx_from_addr(input [31:0] awaddr);
        integer delta;
        begin
            if ((awaddr >= RING_BASE_ADDR) &&
                (awaddr < (RING_BASE_ADDR + (RING_SIZE_ENTRIES * DESC_STRIDE_BYTES))) &&
                (awaddr[4:0] == DESC_CSW_OFFSET[4:0])) begin
                delta = awaddr - RING_BASE_ADDR;
                writeback_desc_idx_from_addr = delta / DESC_STRIDE_BYTES;
            end else begin
                writeback_desc_idx_from_addr = -1;
            end
        end
    endfunction

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_aw  <= 16'h1357;
            lfsr_w   <= 16'h2468;
            lfsr_b   <= 16'h369C;
            lfsr_dsb <= 16'h5A3C;
        end else begin
            lfsr_aw  <= {lfsr_aw[14:0],  lfsr_aw[15]  ^ lfsr_aw[13]  ^ lfsr_aw[12]  ^ lfsr_aw[10]};
            lfsr_w   <= {lfsr_w[14:0],   lfsr_w[15]   ^ lfsr_w[14]   ^ lfsr_w[12]   ^ lfsr_w[3]};
            lfsr_b   <= {lfsr_b[14:0],   lfsr_b[15]   ^ lfsr_b[11]   ^ lfsr_b[2]    ^ lfsr_b[0]};
            lfsr_dsb <= {lfsr_dsb[14:0], lfsr_dsb[15] ^ lfsr_dsb[8]  ^ lfsr_dsb[4]  ^ lfsr_dsb[1]};
        end
    end

    integer fetch_rd_idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_fetcher_arready <= 1'b0;
            m_axis_fetcher_rvalid  <= 1'b0;
            m_axis_fetcher_rdata   <= 32'd0;
            m_axis_fetcher_rresp   <= 2'b00;
            m_axis_fetcher_rlast   <= 1'b0;
            fetch_rd_idx           <= 0;
        end else begin
            m_axis_fetcher_arready <= 1'b1;
            if (m_axis_fetcher_arvalid && m_axis_fetcher_arready) begin
                fetch_rd_idx         <= 0;
                m_axis_fetcher_rvalid <= 1'b1;
                m_axis_fetcher_rdata  <= ddr_mem[addr_to_word(m_axis_fetcher_araddr)];
                m_axis_fetcher_rresp  <= 2'b00;
                m_axis_fetcher_rlast  <= (m_axis_fetcher_arlen == 0);
            end else if (m_axis_fetcher_rvalid && m_axis_fetcher_rready) begin
                if (fetch_rd_idx == m_axis_fetcher_arlen) begin
                    m_axis_fetcher_rvalid <= 1'b0;
                    m_axis_fetcher_rlast  <= 1'b0;
                end else begin
                    fetch_rd_idx          <= fetch_rd_idx + 1;
                    m_axis_fetcher_rdata  <= ddr_mem[addr_to_word(m_axis_fetcher_araddr) + fetch_rd_idx + 1];
                    m_axis_fetcher_rlast  <= ((fetch_rd_idx + 1) == m_axis_fetcher_arlen);
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_awready <= 1'b0;
            m_axis_wready  <= 1'b0;
            m_axis_bvalid  <= 1'b0;
            m_axis_bresp   <= 2'b00;
            pending_awaddr <= 32'd0;
            pending_awlen  <= 8'd0;
            pending_beat_idx <= 8'd0;
            pending_is_writeback <= 1'b0;
            pending_desc_idx <= -1;
            pending_b_valid <= 1'b0;
            pending_b_delay <= 8'd0;
            pending_bresp   <= 2'b00;
            dbg_last_payload_bresp <= 2'b00;
            dbg_last_writeback_bresp <= 2'b00;
            dbg_last_payload_desc_idx <= -1;
            dbg_last_writeback_desc_idx <= -1;
            dbg_last_wlast_awaddr <= 32'd0;
            dbg_last_wlast_desc_idx <= -1;
            dbg_last_wlast_inject_target <= -1;
            dbg_last_wlast_bresp <= 2'b00;
            awaiting_writeback_before_next_fetch <= 1'b0;
        end else begin
            m_axis_awready <= (lfsr_aw[3:0] < 4'd11);
            m_axis_wready  <= (lfsr_w[3:0] < 4'd10);

            if (m_axis_fetcher_arvalid && awaiting_writeback_before_next_fetch) begin
                $fatal(1, "fetch started before prior descriptor CSW write-back completed");
            end

            if (m_axis_awvalid && m_axis_awready) begin
                pending_awaddr <= m_axis_awaddr;
                pending_awlen <= m_axis_awlen;
                pending_beat_idx <= 0;
                pending_desc_idx <= writeback_desc_idx_from_addr(m_axis_awaddr);
                pending_is_writeback <= (writeback_desc_idx_from_addr(m_axis_awaddr) >= 0);

                if (writeback_desc_idx_from_addr(m_axis_awaddr) >= 0) begin
                    if (m_axis_awlen != 8'd0) begin
                        $fatal(1, "CSW write-back must be single-word AWLEN=0, got %0d", m_axis_awlen);
                    end
                    if (m_axis_awaddr[1:0] != 2'b00) begin
                        $fatal(1, "CSW write-back address not 32-bit aligned: %08h", m_axis_awaddr);
                    end
                end else if (payload_desc_idx_from_addr(m_axis_awaddr) < 0) begin
                    $fatal(1, "unexpected payload write address %08h", m_axis_awaddr);
                end
            end

            if (m_axis_wvalid && m_axis_wready) begin
                automatic integer wr_idx;
                automatic integer desc_idx;
                wr_idx = addr_to_word(pending_awaddr) + pending_beat_idx;
                for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
                    if (m_axis_wstrb[byte_idx]) begin
                        ddr_mem[wr_idx][byte_idx*8 +: 8] <= m_axis_wdata[byte_idx*8 +: 8];
                    end
                end

                if (pending_is_writeback) begin
                    if (m_axis_wstrb != 4'hF) begin
                        $fatal(1, "CSW write-back must use full-word WSTRB, got %h", m_axis_wstrb);
                    end
                    if (!m_axis_wlast) begin
                        $fatal(1, "CSW write-back must terminate in one beat");
                    end
                end else begin
                    desc_idx = payload_desc_idx_from_addr(pending_awaddr);
                    if (desc_idx < 0) begin
                        $fatal(1, "payload desc index decode failed for %08h", pending_awaddr);
                    end
                    if (observed_words[desc_idx] > 3) begin
                        $fatal(1, "too many observed payload words for descriptor %0d", desc_idx);
                    end
                    observed_payload[desc_idx][observed_words[desc_idx]] <= m_axis_wdata;
                    observed_words[desc_idx] <= observed_words[desc_idx] + 1;
                end

                if (m_axis_wlast) begin
                    pending_b_valid <= 1'b1;
                    pending_b_delay <= {1'b0, (lfsr_b[6:0] % 8'd101)};
                    dbg_last_wlast_awaddr <= pending_awaddr;
                    dbg_last_wlast_desc_idx <= pending_is_writeback ? pending_desc_idx : payload_desc_idx_from_addr(pending_awaddr);
                    dbg_last_wlast_inject_target <= inject_payload_error_desc_idx;
                    if (!pending_is_writeback &&
                        (payload_desc_idx_from_addr(pending_awaddr) == inject_payload_error_desc_idx)) begin
                        pending_bresp <= 2'b10;
                        dbg_last_wlast_bresp <= 2'b10;
                    end else begin
                        pending_bresp <= 2'b00;
                        dbg_last_wlast_bresp <= 2'b00;
                    end
                    if (!pending_is_writeback) begin
                        awaiting_writeback_before_next_fetch <= 1'b1;
                    end
                end else begin
                    pending_beat_idx <= pending_beat_idx + 1;
                end
            end

            if (pending_b_valid && !m_axis_bvalid) begin
                if (pending_b_delay == 0) begin
                    m_axis_bvalid <= 1'b1;
                    m_axis_bresp  <= pending_bresp;
                end else begin
                    pending_b_delay <= pending_b_delay - 1;
                end
            end

            if (m_axis_bvalid && m_axis_bready) begin
                if (pending_is_writeback) begin
                    dbg_last_writeback_bresp <= m_axis_bresp;
                    dbg_last_writeback_desc_idx <= pending_desc_idx;
                    awaiting_writeback_before_next_fetch <= 1'b0;
                end else begin
                    dbg_last_payload_bresp <= m_axis_bresp;
                    dbg_last_payload_desc_idx <= payload_desc_idx_from_addr(pending_awaddr);
                end
                m_axis_bvalid <= 1'b0;
                pending_b_valid <= 1'b0;
                pending_bresp <= 2'b00;
                if (!pending_is_writeback &&
                    (payload_desc_idx_from_addr(pending_awaddr) == inject_payload_error_desc_idx)) begin
                    inject_payload_error_desc_idx <= -1;
                end
            end
        end
    end

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
            s_axil_bready <= 1'b0;
        end
    endtask

    task automatic ps_bfm_random_dsb;
        integer delay_cycles;
        begin
            delay_cycles = lfsr_dsb[4:0];
            repeat (delay_cycles) @(posedge clk);
        end
    endtask

    task automatic init_descriptor_words(
        input integer desc_idx,
        input [31:0] dst_addr,
        input [31:0] src_reserved,
        input bit algo,
        input integer byte_len
    );
        integer base_idx;
        begin
            base_idx = addr_to_word(RING_BASE_ADDR + desc_idx * DESC_STRIDE_BYTES);
            ddr_mem[base_idx + 0] = dst_addr;
            ddr_mem[base_idx + 1] = src_reserved;
            ddr_mem[base_idx + 2] = build_ctrl(algo, byte_len);
            ddr_mem[base_idx + 3] = expected_desc_word3[desc_idx];
            ddr_mem[base_idx + 4] = build_owner_csw();
            ddr_mem[base_idx + 5] = expected_desc_word5[desc_idx];
            ddr_mem[base_idx + 6] = expected_desc_word6[desc_idx];
            ddr_mem[base_idx + 7] = expected_desc_word7[desc_idx];
        end
    endtask

    task automatic submit_desc_via_ps_bfm(input integer new_sw_tail);
        begin
            ps_bfm_random_dsb();
            axil_write(CSR_SW_TAIL, new_sw_tail);
            ps_bfm_random_dsb();
            axil_write(CSR_DOORBELL, 32'h1);
        end
    endtask

    task automatic wait_csw_complete(
        input integer desc_idx,
        output [31:0] csw_value
    );
        integer base_idx;
        integer guard;
        begin
            base_idx = addr_to_word(RING_BASE_ADDR + desc_idx * DESC_STRIDE_BYTES + DESC_CSW_OFFSET);
            guard = 0;
            csw_value = ddr_mem[base_idx];
            while (csw_value[CSW_OWNER_BIT] || (!csw_value[CSW_DONE_BIT] && !csw_value[CSW_ERR_BIT])) begin
                @(posedge clk);
                guard = guard + 1;
                if (guard > 40000) begin
                    $fatal(1, "PS BFM timed out polling descriptor %0d CSW", desc_idx);
                end
                csw_value = ddr_mem[base_idx];
            end
        end
    endtask

    task automatic drive_rx_word(input [31:0] data, input bit last);
        integer guard;
        begin
            rx_wr_data  <= data;
            rx_wr_last  <= last;
            rx_wr_valid <= 1'b1;
            guard = 0;
            do begin
                @(posedge clk);
                guard = guard + 1;
                if (guard > 4000) begin
                    $fatal(1, "rx word handshake timed out");
                end
            end while (!rx_wr_ready);
            rx_wr_valid <= 1'b0;
            rx_wr_last  <= 1'b0;
        end
    endtask

    task automatic send_packet(input integer desc_idx);
        begin
            for (int i = 0; i < 4; i++) begin
                drive_rx_word(expected_plaintext[desc_idx][i], (i == 3));
            end
        end
    endtask

    task automatic check_descriptor_untouched(input integer desc_idx);
        integer base_idx;
        begin
            base_idx = addr_to_word(RING_BASE_ADDR + desc_idx * DESC_STRIDE_BYTES);
            if (ddr_mem[base_idx + 1] !== expected_desc_word1[desc_idx]) begin
                $fatal(1, "descriptor %0d word1 corrupted", desc_idx);
            end
            if (ddr_mem[base_idx + 3] !== expected_desc_word3[desc_idx]) begin
                $fatal(1, "descriptor %0d word3 corrupted", desc_idx);
            end
            if (ddr_mem[base_idx + 5] !== expected_desc_word5[desc_idx]) begin
                $fatal(1, "descriptor %0d word5 corrupted", desc_idx);
            end
            if (ddr_mem[base_idx + 6] !== expected_desc_word6[desc_idx]) begin
                $fatal(1, "descriptor %0d word6 corrupted", desc_idx);
            end
            if (ddr_mem[base_idx + 7] !== expected_desc_word7[desc_idx]) begin
                $fatal(1, "descriptor %0d word7 corrupted", desc_idx);
            end
        end
    endtask

    task automatic check_payload_match(input integer desc_idx);
        begin
            for (int i = 0; i < 4; i++) begin
                if (observed_payload[desc_idx][i] !== expected_ciphertext[desc_idx][i]) begin
                    $display("DBG desc=%0d observed=%08h_%08h_%08h_%08h expected=%08h_%08h_%08h_%08h",
                             desc_idx,
                             observed_payload[desc_idx][0], observed_payload[desc_idx][1],
                             observed_payload[desc_idx][2], observed_payload[desc_idx][3],
                             expected_ciphertext[desc_idx][0], expected_ciphertext[desc_idx][1],
                             expected_ciphertext[desc_idx][2], expected_ciphertext[desc_idx][3]);
                    $fatal(1, "payload mismatch desc=%0d word=%0d got=%08h exp=%08h",
                           desc_idx, i, observed_payload[desc_idx][i], expected_ciphertext[desc_idx][i]);
                end
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        s_axil_awaddr = '0;
        s_axil_awvalid = 1'b0;
        s_axil_wdata = '0;
        s_axil_wstrb = 4'h0;
        s_axil_wvalid = 1'b0;
        s_axil_bready = 1'b0;
        s_axil_araddr = '0;
        s_axil_arvalid = 1'b0;
        s_axil_rready = 1'b0;
        rx_wr_valid = 1'b0;
        rx_wr_data = 32'd0;
        rx_wr_last = 1'b0;
        tx_axis_tready = 1'b0;

        m_axis_s2mm_awready = 1'b1;
        m_axis_s2mm_wready  = 1'b1;
        m_axis_s2mm_bresp   = 2'b00;
        m_axis_s2mm_bvalid  = 1'b0;
        m_axis_s2mm_arready = 1'b1;
        m_axis_s2mm_rdata   = 32'd0;
        m_axis_s2mm_rresp   = 2'b00;
        m_axis_s2mm_rlast   = 1'b0;
        m_axis_s2mm_rvalid  = 1'b0;

        inject_payload_error_desc_idx = -1;

        for (int i = 0; i < DDR_WORDS; i++) begin
            ddr_mem[i] = 32'd0;
        end
        for (int desc = 0; desc < 3; desc++) begin
            observed_words[desc] = 0;
            expected_desc_word1[desc] = 32'hAA10_0000 + desc;
            expected_desc_word3[desc] = 32'hCC30_0000 + desc;
            expected_desc_word5[desc] = 32'hEE50_0000 + desc;
            expected_desc_word6[desc] = 32'hF660_0000 + desc;
            expected_desc_word7[desc] = 32'hF770_0000 + desc;
            for (int j = 0; j < 4; j++) begin
                expected_plaintext[desc][j]  = 32'd0;
                expected_ciphertext[desc][j] = 32'd0;
                observed_payload[desc][j]    = 32'd0;
            end
        end

        expected_plaintext[0][0]  = 32'h3243F6A8;
        expected_plaintext[0][1]  = 32'h885A308D;
        expected_plaintext[0][2]  = 32'h313198A2;
        expected_plaintext[0][3]  = 32'hE0370734;
        expected_plaintext[1][0]  = 32'h3243F6A8;
        expected_plaintext[1][1]  = 32'h885A308D;
        expected_plaintext[1][2]  = 32'h313198A2;
        expected_plaintext[1][3]  = 32'hE0370734;
        expected_plaintext[2][0]  = 32'h3243F6A8;
        expected_plaintext[2][1]  = 32'h885A308D;
        expected_plaintext[2][2]  = 32'h313198A2;
        expected_plaintext[2][3]  = 32'hE0370734;

        expected_ciphertext[0][0] = 32'h3925841D;
        expected_ciphertext[0][1] = 32'h02DC09FB;
        expected_ciphertext[0][2] = 32'hDC118597;
        expected_ciphertext[0][3] = 32'h196A0B32;
        expected_ciphertext[1][0] = 32'h3925841D;
        expected_ciphertext[1][1] = 32'h02DC09FB;
        expected_ciphertext[1][2] = 32'hDC118597;
        expected_ciphertext[1][3] = 32'h196A0B32;
        expected_ciphertext[2][0] = 32'h3925841D;
        expected_ciphertext[2][1] = 32'h02DC09FB;
        expected_ciphertext[2][2] = 32'hDC118597;
        expected_ciphertext[2][3] = 32'h196A0B32;

        repeat (12) @(posedge clk);
        rst_n = 1'b1;
        repeat (12) @(posedge clk);

        // axil_csr exposes o_key as {reg_key3, reg_key2, reg_key1, reg_key0},
        // so software must write the 128-bit AES key LSW-first to reconstruct
        // the canonical FIPS key ordering inside the crypto path.
        axil_write(CSR_KEY0, 32'h09CF4F3C);
        axil_write(CSR_KEY1, 32'hABF71588);
        axil_write(CSR_KEY2, 32'h28AED2A6);
        axil_write(CSR_KEY3, 32'h2B7E1516);
        axil_write(CSR_CTRL, 32'h0000_000A);
        axil_write(CSR_RING_BASE, RING_BASE_ADDR);
        axil_write(CSR_RING_SIZE, RING_SIZE_ENTRIES);

        init_descriptor_words(0, 32'h0000_2000, expected_desc_word1[0], 1'b0, 16);
        init_descriptor_words(1, 32'h0000_2100, expected_desc_word1[1], 1'b0, 16);
        submit_desc_via_ps_bfm(2);

        send_packet(0);
        send_packet(1);

        wait_csw_complete(0, csw0);
        if (csw0 !== build_done_csw(1'b0, 2'b00)) begin
            $fatal(1, "descriptor 0 CSW mismatch: got=%08h exp=%08h", csw0, build_done_csw(1'b0, 2'b00));
        end
        check_descriptor_untouched(0);

        wait_csw_complete(1, csw1);
        if (csw1 !== build_done_csw(1'b0, 2'b00)) begin
            $fatal(1, "descriptor 1 CSW mismatch: got=%08h exp=%08h", csw1, build_done_csw(1'b0, 2'b00));
        end
        check_descriptor_untouched(1);
        check_payload_match(0);
        check_payload_match(1);

        @(posedge clk);
        inject_payload_error_desc_idx <= 2;
        @(posedge clk);
        init_descriptor_words(2, 32'h0000_2200, expected_desc_word1[2], 1'b0, 16);
        submit_desc_via_ps_bfm(3);
        send_packet(2);

        wait_csw_complete(2, csw2);
        if (csw2 !== build_done_csw(1'b1, 2'b10)) begin
            $fatal(1,
                   "descriptor 2 error CSW mismatch: got=%08h exp=%08h last_payload_desc=%0d last_payload_bresp=%02b last_writeback_desc=%0d last_writeback_bresp=%02b last_wlast_awaddr=%08h last_wlast_desc=%0d last_wlast_inject_target=%0d last_wlast_bresp=%02b",
                   csw2, build_done_csw(1'b1, 2'b10),
                   dbg_last_payload_desc_idx, dbg_last_payload_bresp,
                   dbg_last_writeback_desc_idx, dbg_last_writeback_bresp,
                   dbg_last_wlast_awaddr, dbg_last_wlast_desc_idx,
                   dbg_last_wlast_inject_target, dbg_last_wlast_bresp);
        end
        check_descriptor_untouched(2);

        $display("PASS: dma_subsystem top-level PS BFM polls CSW and AES payload matches golden ciphertext");
        $finish;
    end

endmodule
