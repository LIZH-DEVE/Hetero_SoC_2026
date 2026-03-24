`timescale 1ns / 1ps

module tb_dma_ring_ps_bfm_writeback;

    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam DDR_WORDS = 16384;
    localparam RING_BASE_ADDR = 32'h0000_1000;
    localparam RING_SIZE_ENTRIES = 4;
    localparam DESC_STRIDE_BYTES = 32;
    localparam DESC_CTRL_OFFSET = 8;
    localparam DESC_CSW_OFFSET  = 16;
    localparam CTRL_ALGO_BIT  = 31;
    localparam CTRL_LEN_MASK  = 32'h00FF_FFFF;
    localparam CSW_OWNER_BIT  = 31;
    localparam CSW_DONE_BIT   = 30;
    localparam CSW_ERR_BIT    = 29;
    localparam CSW_STS_LSB    = 0;

    logic clk;
    logic rst_n;

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

    logic                   csr_start;
    logic                   csr_hw_init;
    logic                   csr_algo_sel;
    logic                   csr_encdec;
    logic                   csr_s2mm_en;
    logic                   csr_mm2s_en;
    logic                   csr_auth_en;
    logic                   csr_acl_en;
    logic                   csr_dna_lock_en;
    logic [31:0]            csr_s2mm_addr;
    logic [31:0]            csr_s2mm_data;
    logic [1:0]             csr_loopback_mode;
    logic                   csr_acl_write_en;
    logic                   csr_acl_clear;
    logic [11:0]            csr_acl_write_addr;
    logic [103:0]           csr_acl_write_data;
    logic                   csr_network_enable;
    logic                   csr_network_ingress_sel;
    logic                   csr_arp_enable;
    logic [31:0]            csr_net_local_ip;
    logic [47:0]            csr_net_local_mac;
    logic                   csr_net_cfg0_we;
    logic                   csr_net_local_ip_we;
    logic                   csr_net_local_mac_lo_we;
    logic                   csr_net_local_mac_hi_we;
    logic                   csr_inj_clear;
    logic                   csr_inj_push;
    logic [31:0]            csr_inj_data;
    logic [15:0]            csr_inj_expected_words;
    logic                   csr_txcap_clear;
    logic                   csr_txcap_pop;
    logic [31:0]            csr_base_addr;
    logic [31:0]            csr_len;
    logic [127:0]           csr_key;
    logic [127:0]           csr_key_hi;
    logic                   csr_aes256_en;
    logic                   csr_cache_flush;
    logic [31:0]            csr_acl_cnt;
    logic                   ring_doorbell;
    logic [31:0]            ring_base;
    logic [31:0]            ring_size;
    logic [15:0]            sw_tail_ptr;
    logic [15:0]            hw_head_ptr;

    logic                   dma_done;
    logic                   dma_error;
    logic                   dma_busy;
    logic [1:0]             dma_status_bresp;

    logic                   fetch_dma_start;
    logic [31:0]            fetch_dma_addr;
    logic [31:0]            fetch_dma_len;
    logic                   fetch_dma_algo;

    logic [ADDR_WIDTH-1:0]  fetch_araddr;
    logic [7:0]             fetch_arlen;
    logic [2:0]             fetch_arsize;
    logic [1:0]             fetch_arburst;
    logic                   fetch_arvalid;
    logic                   fetch_arready;
    logic [31:0]            fetch_rdata;
    logic                   fetch_rlast;
    logic                   fetch_rvalid;
    logic                   fetch_rready;

    logic [ADDR_WIDTH-1:0]  fetch_wb_awaddr;
    logic [7:0]             fetch_wb_awlen;
    logic [2:0]             fetch_wb_awsize;
    logic [1:0]             fetch_wb_awburst;
    logic [3:0]             fetch_wb_awcache;
    logic [2:0]             fetch_wb_awprot;
    logic                   fetch_wb_awvalid;
    logic                   fetch_wb_awready;
    logic [31:0]            fetch_wb_wdata;
    logic [3:0]             fetch_wb_wstrb;
    logic                   fetch_wb_wlast;
    logic                   fetch_wb_wvalid;
    logic                   fetch_wb_wready;
    logic [1:0]             fetch_wb_bresp;
    logic                   fetch_wb_bvalid;
    logic                   fetch_wb_bready;
    logic                   fetch_wb_active;

    logic [31:0]            fifo_rdata;
    logic                   fifo_empty;
    logic                   fifo_ren;

    logic [ADDR_WIDTH-1:0]  dma_awaddr;
    logic [7:0]             dma_awlen;
    logic [2:0]             dma_awsize;
    logic [1:0]             dma_awburst;
    logic [3:0]             dma_awcache;
    logic [2:0]             dma_awprot;
    logic                   dma_awvalid;
    logic                   dma_awready;
    logic [31:0]            dma_wdata;
    logic [3:0]             dma_wstrb;
    logic                   dma_wlast;
    logic                   dma_wvalid;
    logic                   dma_wready;
    logic [1:0]             dma_bresp;
    logic                   dma_blast;
    logic                   dma_bvalid;
    logic                   dma_bready;

    logic [ADDR_WIDTH-1:0]  bus_awaddr;
    logic [7:0]             bus_awlen;
    logic [2:0]             bus_awsize;
    logic [1:0]             bus_awburst;
    logic [3:0]             bus_awcache;
    logic [2:0]             bus_awprot;
    logic                   bus_awvalid;
    logic                   bus_awready;
    logic [31:0]            bus_wdata;
    logic [3:0]             bus_wstrb;
    logic                   bus_wlast;
    logic                   bus_wvalid;
    logic                   bus_wready;
    logic [1:0]             bus_bresp;
    logic                   bus_bvalid;
    logic                   bus_bready;

    logic [15:0]            lfsr_aw;
    logic [15:0]            lfsr_w;
    logic [15:0]            lfsr_b;

    logic [31:0]            ddr_mem [0:DDR_WORDS-1];
    logic [31:0]            payload_fifo_mem [0:255];
    integer                 payload_fifo_count;
    integer                 payload_fifo_rd_idx;
    integer                 payload_fifo_wr_idx;
    integer                 active_desc_idx;
    integer                 fetch_start_count;

    integer                 sink_words_written;
    integer                 expected_total_words;
    integer                 expected_desc_words [0:3];
    logic [31:0]            expected_payload [0:3][0:31];
    logic [31:0]            observed_payload [0:3][0:31];
    integer                 observed_words [0:3];
    logic [31:0]            expected_desc_word3 [0:3];
    logic [31:0]            expected_desc_word5 [0:3];
    logic [31:0]            expected_desc_word6 [0:3];
    logic [31:0]            expected_desc_word7 [0:3];

    logic [ADDR_WIDTH-1:0]  pending_b_addr;
    logic [7:0]             pending_b_delay;
    logic                   pending_b_valid;
    logic [1:0]             pending_bresp;
    logic                   awaiting_writeback_before_next_fetch;
    integer                 completed_dma_transactions;
    integer                 writeback_transactions;
    logic                   inject_payload_slverr;
    logic [31:0]            csw0;
    logic [31:0]            csw1;
    logic [31:0]            csw2;

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

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    axil_csr u_csr (
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
        .o_start(csr_start),
        .o_hw_init(csr_hw_init),
        .o_algo_sel(csr_algo_sel),
        .o_enc_dec(csr_encdec),
        .o_s2mm_en(csr_s2mm_en),
        .o_mm2s_en(csr_mm2s_en),
        .o_auth_en(csr_auth_en),
        .o_acl_en(csr_acl_en),
        .o_dna_lock_en(csr_dna_lock_en),
        .o_s2mm_addr(csr_s2mm_addr),
        .o_s2mm_data(csr_s2mm_data),
        .o_loopback_mode(csr_loopback_mode),
        .o_acl_write_en(csr_acl_write_en),
        .o_acl_clear(csr_acl_clear),
        .o_acl_write_addr(csr_acl_write_addr),
        .o_acl_write_data(csr_acl_write_data),
        .o_network_enable(csr_network_enable),
        .o_network_ingress_sel(csr_network_ingress_sel),
        .o_arp_enable(csr_arp_enable),
        .o_net_local_ip(csr_net_local_ip),
        .o_net_local_mac(csr_net_local_mac),
        .o_net_cfg0_we(csr_net_cfg0_we),
        .o_net_local_ip_we(csr_net_local_ip_we),
        .o_net_local_mac_lo_we(csr_net_local_mac_lo_we),
        .o_net_local_mac_hi_we(csr_net_local_mac_hi_we),
        .o_inj_clear(csr_inj_clear),
        .o_inj_push(csr_inj_push),
        .o_inj_data(csr_inj_data),
        .o_inj_expected_words(csr_inj_expected_words),
        .i_inj_status(32'd0),
        .o_txcap_clear(csr_txcap_clear),
        .o_txcap_pop(csr_txcap_pop),
        .i_txcap_status(32'd0),
        .i_txcap_data(32'd0),
        .i_netdbg_status(32'd0),
        .i_net_applied_cfg0(32'd0),
        .i_net_applied_local_ip(32'd0),
        .i_net_applied_local_mac_lo(32'd0),
        .i_net_applied_local_mac_hi(32'd0),
        .o_base_addr(csr_base_addr),
        .o_len(csr_len),
        .o_key(csr_key),
        .o_key_hi(csr_key_hi),
        .o_aes256_en(csr_aes256_en),
        .o_cache_flush(csr_cache_flush),
        .i_acl_inc(1'b0),
        .o_acl_cnt(csr_acl_cnt),
        .o_ring_doorbell(ring_doorbell),
        .o_ring_base(ring_base),
        .o_ring_size(ring_size),
        .o_sw_tail_ptr(sw_tail_ptr),
        .i_hw_head_ptr(hw_head_ptr),
        .i_done(dma_done),
        .i_error(dma_error),
        .i_busy(dma_busy)
    );

    dma_desc_fetcher u_fetcher (
        .clk(clk),
        .rst_n(rst_n),
        .i_ring_base(ring_base),
        .i_ring_size(ring_size),
        .i_ring_doorbell(ring_doorbell),
        .i_sw_tail_ptr(sw_tail_ptr),
        .o_hw_head_ptr(hw_head_ptr),
        .o_dma_start(fetch_dma_start),
        .o_dma_addr(fetch_dma_addr),
        .o_dma_len(fetch_dma_len),
        .o_dma_algo(fetch_dma_algo),
        .i_dma_done(dma_done),
        .i_dma_error(dma_error),
        .i_dma_bresp(dma_status_bresp),
        .m_axi_araddr(fetch_araddr),
        .m_axi_arlen(fetch_arlen),
        .m_axi_arsize(fetch_arsize),
        .m_axi_arburst(fetch_arburst),
        .m_axi_arvalid(fetch_arvalid),
        .m_axi_arready(fetch_arready),
        .m_axi_rdata(fetch_rdata),
        .m_axi_rlast(fetch_rlast),
        .m_axi_rvalid(fetch_rvalid),
        .m_axi_rready(fetch_rready),
        .m_axi_awaddr(fetch_wb_awaddr),
        .m_axi_awlen(fetch_wb_awlen),
        .m_axi_awsize(fetch_wb_awsize),
        .m_axi_awburst(fetch_wb_awburst),
        .m_axi_awcache(fetch_wb_awcache),
        .m_axi_awprot(fetch_wb_awprot),
        .m_axi_awvalid(fetch_wb_awvalid),
        .m_axi_awready(fetch_wb_awready),
        .m_axi_wdata(fetch_wb_wdata),
        .m_axi_wstrb(fetch_wb_wstrb),
        .m_axi_wlast(fetch_wb_wlast),
        .m_axi_wvalid(fetch_wb_wvalid),
        .m_axi_wready(fetch_wb_wready),
        .m_axi_bresp(fetch_wb_bresp),
        .m_axi_bvalid(fetch_wb_bvalid),
        .m_axi_bready(fetch_wb_bready),
        .o_wb_active(fetch_wb_active)
    );

    dma_master_engine #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MAX_OUTSTANDING_WRITES(4)
    ) u_dma (
        .clk(clk),
        .rst_n(rst_n),
        .i_start(fetch_dma_start),
        .i_base_addr(fetch_dma_addr),
        .i_total_len(fetch_dma_len),
        .o_done(dma_done),
        .o_error(dma_error),
        .o_bresp(dma_status_bresp),
        .i_fifo_rdata(fifo_rdata),
        .i_fifo_empty(fifo_empty),
        .o_fifo_ren(fifo_ren),
        .m_axi_awaddr(dma_awaddr),
        .m_axi_awlen(dma_awlen),
        .m_axi_awsize(dma_awsize),
        .m_axi_awburst(dma_awburst),
        .m_axi_awcache(dma_awcache),
        .m_axi_awprot(dma_awprot),
        .m_axi_awvalid(dma_awvalid),
        .m_axi_awready(dma_awready),
        .m_axi_wdata(dma_wdata),
        .m_axi_wstrb(dma_wstrb),
        .m_axi_wlast(dma_wlast),
        .m_axi_wvalid(dma_wvalid),
        .m_axi_wready(dma_wready),
        .m_axi_wresp(dma_bresp),
        .m_axi_blast(dma_blast),
        .m_axi_bvalid(dma_bvalid),
        .m_axi_bready(dma_bready),
        .m_axi_araddr(),
        .m_axi_arlen(),
        .m_axi_arsize(),
        .m_axi_arburst(),
        .m_axi_arvalid(),
        .m_axi_arready(1'b0),
        .m_axi_rdata(32'd0),
        .m_axi_rresp(2'b00),
        .m_axi_rlast(1'b0),
        .m_axi_rvalid(1'b0),
        .m_axi_rready()
    );

    assign dma_busy = fetch_dma_start || fetch_wb_active || dma_awvalid || dma_wvalid || dma_bready;

    assign bus_awaddr  = fetch_wb_active ? fetch_wb_awaddr  : dma_awaddr;
    assign bus_awlen   = fetch_wb_active ? fetch_wb_awlen   : dma_awlen;
    assign bus_awsize  = fetch_wb_active ? fetch_wb_awsize  : dma_awsize;
    assign bus_awburst = fetch_wb_active ? fetch_wb_awburst : dma_awburst;
    assign bus_awcache = fetch_wb_active ? fetch_wb_awcache : dma_awcache;
    assign bus_awprot  = fetch_wb_active ? fetch_wb_awprot  : dma_awprot;
    assign bus_awvalid = fetch_wb_active ? fetch_wb_awvalid : dma_awvalid;
    assign bus_wdata   = fetch_wb_active ? fetch_wb_wdata   : dma_wdata;
    assign bus_wstrb   = fetch_wb_active ? fetch_wb_wstrb   : dma_wstrb;
    assign bus_wlast   = fetch_wb_active ? fetch_wb_wlast   : dma_wlast;
    assign bus_wvalid  = fetch_wb_active ? fetch_wb_wvalid  : dma_wvalid;
    assign bus_bready  = fetch_wb_active ? fetch_wb_bready  : dma_bready;

    assign fetch_wb_awready = fetch_wb_active ? bus_awready : 1'b0;
    assign fetch_wb_wready  = fetch_wb_active ? bus_wready  : 1'b0;
    assign fetch_wb_bresp   = fetch_wb_active ? bus_bresp   : 2'b00;
    assign fetch_wb_bvalid  = fetch_wb_active ? bus_bvalid  : 1'b0;

    assign dma_awready = (!fetch_wb_active) ? bus_awready : 1'b0;
    assign dma_wready  = (!fetch_wb_active) ? bus_wready  : 1'b0;
    assign dma_bresp   = (!fetch_wb_active) ? bus_bresp   : 2'b00;
    assign dma_bvalid  = (!fetch_wb_active) ? bus_bvalid  : 1'b0;
    assign dma_blast   = (!fetch_wb_active) ? bus_bvalid  : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_aw <= 16'h1357;
            lfsr_w  <= 16'h2468;
            lfsr_b  <= 16'h369C;
        end else begin
            lfsr_aw <= {lfsr_aw[14:0], lfsr_aw[15] ^ lfsr_aw[13] ^ lfsr_aw[12] ^ lfsr_aw[10]};
            lfsr_w  <= {lfsr_w[14:0], lfsr_w[15]  ^ lfsr_w[14]  ^ lfsr_w[12]  ^ lfsr_w[3]};
            lfsr_b  <= {lfsr_b[14:0], lfsr_b[15]  ^ lfsr_b[11]  ^ lfsr_b[2]   ^ lfsr_b[0]};
        end
    end

    integer fetch_rd_idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_arready <= 1'b0;
            fetch_rvalid <= 1'b0;
            fetch_rdata <= 32'd0;
            fetch_rlast <= 1'b0;
            fetch_rd_idx <= 0;
        end else begin
            fetch_arready <= 1'b1;
            if (fetch_arvalid && fetch_arready) begin
                fetch_rd_idx <= 0;
                fetch_rvalid <= 1'b1;
                fetch_rdata <= ddr_mem[addr_to_word(fetch_araddr)];
                fetch_rlast <= (fetch_arlen == 0);
            end else if (fetch_rvalid && fetch_rready) begin
                if (fetch_rd_idx == fetch_arlen) begin
                    fetch_rvalid <= 1'b0;
                    fetch_rlast <= 1'b0;
                end else begin
                    fetch_rd_idx <= fetch_rd_idx + 1;
                    fetch_rdata <= ddr_mem[addr_to_word(fetch_araddr) + fetch_rd_idx + 1];
                    fetch_rlast <= ((fetch_rd_idx + 1) == fetch_arlen);
                end
            end
        end
    end

    assign fifo_empty = (payload_fifo_count == 0);
    assign fifo_rdata = payload_fifo_mem[payload_fifo_rd_idx];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            payload_fifo_count <= 0;
            payload_fifo_rd_idx <= 0;
            payload_fifo_wr_idx <= 0;
            active_desc_idx <= 0;
            fetch_start_count <= 0;
        end else begin
            if (fetch_dma_start) begin
                payload_fifo_rd_idx <= 0;
                payload_fifo_wr_idx <= expected_desc_words[fetch_start_count];
                payload_fifo_count <= expected_desc_words[fetch_start_count];
                active_desc_idx <= fetch_start_count;
                fetch_start_count <= fetch_start_count + 1;
            end else if (fifo_ren && !fifo_empty) begin
                payload_fifo_rd_idx <= payload_fifo_rd_idx + 1;
                payload_fifo_count <= payload_fifo_count - 1;
            end
        end
    end

    genvar gi;
    generate
        for (gi = 0; gi < 32; gi = gi + 1) begin : g_payload_preset
            always_comb begin
                payload_fifo_mem[gi] = expected_payload[active_desc_idx][gi];
            end
        end
    endgenerate

    logic [ADDR_WIDTH-1:0] inflight_awaddr;
    logic [7:0]            inflight_awlen;
    logic [7:0]            inflight_beat_idx;
    logic                  inflight_is_writeback;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bus_awready <= 1'b0;
            bus_wready <= 1'b0;
            bus_bvalid <= 1'b0;
            bus_bresp <= 2'b00;
            pending_b_valid <= 1'b0;
            pending_b_delay <= 8'd0;
            pending_bresp <= 2'b00;
            inflight_awaddr <= '0;
            inflight_awlen <= '0;
            inflight_beat_idx <= '0;
            inflight_is_writeback <= 1'b0;
            sink_words_written <= 0;
            completed_dma_transactions <= 0;
            writeback_transactions <= 0;
            awaiting_writeback_before_next_fetch <= 1'b0;
        end else begin
            bus_awready <= (lfsr_aw[3:0] < 4'd11);
            bus_wready  <= (lfsr_w[3:0] < 4'd10);

            if (fetch_arvalid && awaiting_writeback_before_next_fetch) begin
                $fatal(1, "fetch started before prior descriptor CSW write-back completed");
            end

            if (bus_awvalid && bus_awready) begin
                inflight_awaddr <= bus_awaddr;
                inflight_awlen <= bus_awlen;
                inflight_beat_idx <= 0;
                inflight_is_writeback <= fetch_wb_active;
                if (fetch_wb_active) begin
                    if (bus_awlen != 8'd0) begin
                        $fatal(1, "CSW write-back must be single-word AWLEN=0, got %0d", bus_awlen);
                    end
                    if (bus_awaddr[1:0] != 2'b00) begin
                        $fatal(1, "CSW write-back address not 32-bit aligned: %08h", bus_awaddr);
                    end
                end
            end

            if (bus_wvalid && bus_wready) begin
                automatic integer wr_idx;
                wr_idx = addr_to_word(inflight_awaddr) + inflight_beat_idx;
                for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
                    if (bus_wstrb[byte_idx]) begin
                        ddr_mem[wr_idx][byte_idx*8 +: 8] <= bus_wdata[byte_idx*8 +: 8];
                    end
                end

                if (inflight_is_writeback) begin
                    if (bus_wstrb != 4'hF) begin
                        $fatal(1, "CSW write-back must use full single-word WSTRB, got %h", bus_wstrb);
                    end
                end else begin
                    observed_payload[active_desc_idx][observed_words[active_desc_idx]] <= bus_wdata;
                    observed_words[active_desc_idx] <= observed_words[active_desc_idx] + 1;
                    sink_words_written <= sink_words_written + 1;
                end

                if (bus_wlast) begin
                    pending_b_valid <= 1'b1;
                    pending_b_delay <= {1'b0, (lfsr_b[6:0] % 8'd37)};
                    pending_bresp <= (!inflight_is_writeback && inject_payload_slverr) ? 2'b10 : 2'b00;
                    if (!inflight_is_writeback) begin
                        completed_dma_transactions <= completed_dma_transactions + 1;
                        awaiting_writeback_before_next_fetch <= 1'b1;
                    end
                end else begin
                    inflight_beat_idx <= inflight_beat_idx + 1;
                end
            end

            if (pending_b_valid && !bus_bvalid) begin
                if (pending_b_delay == 0) begin
                    bus_bvalid <= 1'b1;
                    bus_bresp <= pending_bresp;
                end else begin
                    pending_b_delay <= pending_b_delay - 1;
                end
            end

            if (bus_bvalid && bus_bready) begin
                if (inflight_is_writeback) begin
                    writeback_transactions <= writeback_transactions + 1;
                    awaiting_writeback_before_next_fetch <= 1'b0;
                end
                bus_bvalid <= 1'b0;
                pending_b_valid <= 1'b0;
                pending_bresp <= 2'b00;
                if (inflight_is_writeback) begin
                    inject_payload_slverr <= 1'b0;
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
            delay_cycles = lfsr_b[3:0];
            repeat (delay_cycles) @(posedge clk);
        end
    endtask

    task automatic init_descriptor_words(
        input integer desc_idx,
        input [31:0] dst_addr,
        input [31:0] src_addr,
        input bit algo,
        input integer word_count
    );
        integer base_idx;
        begin
            base_idx = addr_to_word(RING_BASE_ADDR + desc_idx * DESC_STRIDE_BYTES);
            ddr_mem[base_idx + 0] = dst_addr;
            ddr_mem[base_idx + 1] = src_addr;
            ddr_mem[base_idx + 2] = build_ctrl(algo, word_count * 4);
            ddr_mem[base_idx + 3] = expected_desc_word3[desc_idx];
            ddr_mem[base_idx + 4] = build_owner_csw();
            ddr_mem[base_idx + 5] = expected_desc_word5[desc_idx];
            ddr_mem[base_idx + 6] = expected_desc_word6[desc_idx];
            ddr_mem[base_idx + 7] = expected_desc_word7[desc_idx];
        end
    endtask

    task automatic submit_desc_via_ps_bfm(
        input integer new_sw_tail
    );
        begin
            ps_bfm_random_dsb();
            axil_write(32'h0000_0058, new_sw_tail);
            ps_bfm_random_dsb();
            axil_write(32'h0000_004C, 32'h1);
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
                if (guard > 20000) begin
                    $fatal(1, "PS BFM timed out polling descriptor %0d CSW", desc_idx);
                end
                csw_value = ddr_mem[base_idx];
            end
        end
    endtask

    task automatic check_descriptor_untouched(input integer desc_idx);
        integer base_idx;
        begin
            base_idx = addr_to_word(RING_BASE_ADDR + desc_idx * DESC_STRIDE_BYTES);
            if (ddr_mem[base_idx + 3] !== expected_desc_word3[desc_idx]) begin
                $fatal(1, "descriptor %0d word3 corrupted by write-back", desc_idx);
            end
            if (ddr_mem[base_idx + 5] !== expected_desc_word5[desc_idx]) begin
                $fatal(1, "descriptor %0d word5 corrupted by write-back", desc_idx);
            end
            if (ddr_mem[base_idx + 6] !== expected_desc_word6[desc_idx]) begin
                $fatal(1, "descriptor %0d word6 corrupted by write-back", desc_idx);
            end
            if (ddr_mem[base_idx + 7] !== expected_desc_word7[desc_idx]) begin
                $fatal(1, "descriptor %0d word7 corrupted by write-back", desc_idx);
            end
        end
    endtask

    task automatic check_payload_match(input integer desc_idx);
        begin
            for (int i = 0; i < expected_desc_words[desc_idx]; i++) begin
                if (observed_payload[desc_idx][i] !== expected_payload[desc_idx][i]) begin
                    $fatal(1, "payload mismatch desc=%0d word=%0d got=%08h exp=%08h",
                           desc_idx, i, observed_payload[desc_idx][i], expected_payload[desc_idx][i]);
                end
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        s_axil_awaddr = '0; s_axil_awvalid = 1'b0; s_axil_wdata = '0; s_axil_wstrb = 4'h0; s_axil_wvalid = 1'b0; s_axil_bready = 1'b0;
        s_axil_araddr = '0; s_axil_arvalid = 1'b0; s_axil_rready = 1'b0;
        expected_total_words = 0;

        for (int i = 0; i < DDR_WORDS; i++) begin
            ddr_mem[i] = 32'd0;
        end
        for (int desc = 0; desc < 4; desc++) begin
            expected_desc_words[desc] = 0;
            observed_words[desc] = 0;
            expected_desc_word3[desc] = 32'hA300_0000 + desc;
            expected_desc_word5[desc] = 32'hB500_0000 + desc;
            expected_desc_word6[desc] = 32'hC600_0000 + desc;
            expected_desc_word7[desc] = 32'hD700_0000 + desc;
            for (int j = 0; j < 32; j++) begin
                expected_payload[desc][j] = 32'd0;
                observed_payload[desc][j] = 32'd0;
            end
        end

        repeat (12) @(posedge clk);
        rst_n = 1'b1;
        repeat (12) @(posedge clk);

        axil_write(32'h0000_0050, RING_BASE_ADDR);
        axil_write(32'h0000_005C, RING_SIZE_ENTRIES);

        expected_desc_words[0] = 4;
        expected_desc_words[1] = 4;
        expected_desc_words[2] = 4;
        expected_total_words = expected_desc_words[0] + expected_desc_words[1];
        for (int i = 0; i < 4; i++) begin
            expected_payload[0][i] = 32'h1111_0000 + i;
            expected_payload[1][i] = 32'h2222_0000 + i;
            expected_payload[2][i] = 32'h3333_0000 + i;
        end

        init_descriptor_words(0, 32'h0000_2000, 32'h0000_3000, 1'b0, expected_desc_words[0]);
        init_descriptor_words(1, 32'h0000_2100, 32'h0000_3100, 1'b1, expected_desc_words[1]);

        submit_desc_via_ps_bfm(2);

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
        inject_payload_slverr <= 1'b1;
        @(posedge clk);
        init_descriptor_words(2, 32'h0000_2200, 32'h0000_3200, 1'b0, expected_desc_words[2]);
        submit_desc_via_ps_bfm(3);

        wait_csw_complete(2, csw2);
        if (csw2 !== build_done_csw(1'b1, 2'b10)) begin
            $fatal(1, "descriptor 2 error CSW mismatch: got=%08h exp=%08h", csw2, build_done_csw(1'b1, 2'b10));
        end
        check_descriptor_untouched(2);

        $display("PASS: PS BFM polls CSW write-back and DMA payload matches source buffer");
        $finish;
    end

endmodule
