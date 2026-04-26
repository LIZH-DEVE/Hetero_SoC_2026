`timescale 1ns / 1ps

module tb_dma_subsystem_network_inject_sanity;

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

    localparam [31:0] CSR_NET_CFG0       = 32'h0000_0090;
    localparam [31:0] CSR_NET_LOCAL_IP   = 32'h0000_0094;
    localparam [31:0] CSR_NET_LOCAL_MACL = 32'h0000_0098;
    localparam [31:0] CSR_NET_LOCAL_MACH = 32'h0000_009C;
    localparam [31:0] CSR_INJ_CTRL       = 32'h0000_00A0;
    localparam [31:0] CSR_INJ_DATA       = 32'h0000_00A4;
    localparam [31:0] CSR_INJ_STATUS     = 32'h0000_00A8;
    localparam [31:0] CSR_TXCAP_STATUS   = 32'h0000_00B0;
    localparam [31:0] CSR_TXCAP_DATA     = 32'h0000_00B4;
    localparam [31:0] CSR_NETDBG_STATUS  = 32'h0000_00B8;
    localparam [31:0] CSR_NET_APPLIED_CFG0 = 32'h0000_00BC;
    localparam [31:0] CSR_NET_APPLIED_IP   = 32'h0000_00C0;
    localparam [31:0] CSR_NET_APPLIED_MACL = 32'h0000_00C4;
    localparam [31:0] CSR_NET_APPLIED_MACH = 32'h0000_00C8;
    localparam [31:0] UDP_REQ_WORDS      = 32'd19;

    dma_subsystem dut (
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

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

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

    task automatic read_csr(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            s_axil_araddr  <= addr;
            s_axil_arvalid <= 1'b1;
            s_axil_rready  <= 1'b1;
            do @(posedge clk); while (!s_axil_arready);
            s_axil_arvalid <= 1'b0;
            do @(posedge clk); while (!s_axil_rvalid);
            data = s_axil_rdata;
            @(posedge clk);
            s_axil_rready <= 1'b0;
        end
    endtask

    task automatic push_inject_word(input [31:0] word);
        begin
            write_csr(CSR_INJ_DATA, word);
        end
    endtask

    function automatic [15:0] calc_ipv4_checksum(
        input [15:0] total_len,
        input [31:0] src_ip,
        input [31:0] dst_ip
    );
        reg [31:0] acc;
        begin
            acc = 32'd0;
            acc = acc + 16'h4500 + total_len + 16'h1234 + 16'h4000 + 16'h4011;
            acc = acc + src_ip[31:16] + src_ip[15:0] + dst_ip[31:16] + dst_ip[15:0];
            acc = (acc & 32'hFFFF) + (acc >> 16);
            acc = (acc & 32'hFFFF) + (acc >> 16);
            calc_ipv4_checksum = ~acc[15:0];
        end
    endfunction

    task automatic clear_txcap;
        begin
            write_csr(32'h0000_00AC, 32'h0000_0001);
        end
    endtask

    task automatic check_applied_control(
        input [31:0] exp_cfg0,
        input [31:0] exp_ip,
        input [31:0] exp_macl,
        input [31:0] exp_mach
    );
        reg [31:0] got;
        begin
            read_csr(CSR_NET_APPLIED_CFG0, got);
            if (got !== exp_cfg0) begin
                $fatal(1, "NET_APPLIED_CFG0 mismatch: got=0x%08h exp=0x%08h", got, exp_cfg0);
            end
            read_csr(CSR_NET_APPLIED_IP, got);
            if (got !== exp_ip) begin
                $fatal(1, "NET_APPLIED_IP mismatch: got=0x%08h exp=0x%08h", got, exp_ip);
            end
            read_csr(CSR_NET_APPLIED_MACL, got);
            if (got !== exp_macl) begin
                $fatal(1, "NET_APPLIED_MACL mismatch: got=0x%08h exp=0x%08h", got, exp_macl);
            end
            read_csr(CSR_NET_APPLIED_MACH, got);
            if (got !== exp_mach) begin
                $fatal(1, "NET_APPLIED_MACH mismatch: got=0x%08h exp=0x%08h", got, exp_mach);
            end
        end
    endtask

    task automatic read_and_check_arp_reply;
        reg [31:0] status;
        reg [31:0] words [0:15];
        integer idx;
        begin
            repeat (80) @(posedge clk);
            read_csr(CSR_TXCAP_STATUS, status);
            if (status[15:0] != 16'd11 || !status[16]) begin
                $display("DBG inj_status=0x%08h inj_count=%0d parser_state=%0d arp_valid=%0b arp_ready=%0b body_valid=%0b txcap_count=%0d tx_valid=%0b",
                         dut.u_network_stage1.o_inj_status,
                         dut.u_network_stage1.inj_count,
                         dut.u_network_stage1.u_rx_parser.state,
                         dut.u_network_stage1.parser_arp_valid,
                         dut.u_network_stage1.parser_arp_ready,
                         dut.u_network_stage1.arp_body_valid,
                         dut.u_network_stage1.txcap_count,
                         dut.u_network_stage1.tx_valid_sel);
                $display("DBG inj_valid=%0b inj_ready=%0b ingress_valid=%0b ingress_ready=%0b gbl_cnt=%0d pbm_ready=%0b inj_complete=%0b next_word=0x%08h",
                         dut.u_network_stage1.inj_tvalid,
                         dut.u_network_stage1.inj_tready,
                         dut.u_network_stage1.ingress_tvalid,
                         dut.u_network_stage1.ingress_tready,
                         dut.u_network_stage1.u_rx_parser.global_word_cnt,
                         dut.u_network_stage1.parser_pbm_ready,
                         dut.u_network_stage1.inj_packet_complete,
                         dut.u_network_stage1.inj_tdata);
                $fatal(1, "Expected 11-word captured ARP reply frame, got status=0x%08h", status);
            end

            for (idx = 0; idx < 11; idx = idx + 1) begin
                read_csr(CSR_TXCAP_DATA, words[idx]);
            end

            if (words[0]  != 32'h1234_5678 ||
                words[1]  != 32'h9ABC_020A ||
                words[2]  != 32'h3500_0120 ||
                words[3]  != 32'h0806_0000 ||
                words[4]  != 32'h0001_0800 ||
                words[5]  != 32'h0604_0002 ||
                words[6]  != 32'h020A_3500 ||
                words[7]  != 32'h0120_C0A8 ||
                words[8]  != 32'h0114_1234 ||
                words[9]  != 32'h5678_9ABC ||
                words[10] != 32'hC0A8_0102) begin
                for (idx = 0; idx < 11; idx = idx + 1) begin
                    $display("DBG reply[%0d]=0x%08h", idx, words[idx]);
                end
                $fatal(1, "Unexpected ARP reply frame contents");
            end
        end
    endtask

    task automatic read_and_check_udp_reply;
        reg [31:0] status;
        reg [31:0] words [0:31];
        reg [15:0] expected_csum;
        integer idx;
        integer count;
        begin
            repeat (120) @(posedge clk);
            read_csr(CSR_TXCAP_STATUS, status);
            count = status[15:0];
            if (count < 11 || !status[16]) begin
                $display("DBG udp txcap_count=%0d status=0x%08h tx_valid=%0b tx_last=%0b udp_busy=%0b pbm_empty=%0b",
                         count,
                         status,
                         dut.u_network_stage1.tx_valid_sel,
                         dut.u_network_stage1.tx_last_sel,
                         dut.u_network_stage1.udp_tx_busy,
                         dut.u_network_stage1.net_pbm_empty);
                $fatal(1, "Expected captured UDP reply frame, got status=0x%08h", status);
            end

            for (idx = 0; idx < count; idx = idx + 1) begin
                read_csr(CSR_TXCAP_DATA, words[idx]);
            end

            expected_csum = calc_ipv4_checksum(16'h003C, 32'hC0A8_0114, 32'hC0A8_0102);
            if (words[0]  != 32'h1122_3344 ||
                words[1]  != 32'h5566_020A ||
                words[2]  != 32'h3500_0120 ||
                words[3]  != 32'h0800_4500 ||
                words[4]  != 32'h003C_1234 ||
                words[5]  != 32'h4000_4011 ||
                words[6]  != {expected_csum, 16'hC0A8} ||
                words[7]  != 32'h0114_C0A8 ||
                words[8]  != 32'h0102_1234 ||
                words[9]  != 32'h1234_0028) begin
                for (idx = 0; idx < count; idx = idx + 1) begin
                    $display("DBG udp_reply[%0d]=0x%08h", idx, words[idx]);
                end
                $fatal(1, "Unexpected UDP reply frame header");
            end
        end
    endtask

    initial begin
        reg [31:0] dummy;

        rst_n = 1'b0;
        s_axil_awaddr = '0;
        s_axil_awvalid = 1'b0;
        s_axil_wdata = '0;
        s_axil_wstrb = '0;
        s_axil_wvalid = 1'b0;
        s_axil_bready = 1'b0;
        s_axil_araddr = '0;
        s_axil_arvalid = 1'b0;
        s_axil_rready = 1'b0;
        rx_wr_valid = 1'b0;
        rx_wr_data = '0;
        rx_wr_last = 1'b0;
        tx_axis_tready = 1'b0;
        m_axis_awready = 1'b0;
        m_axis_wready = 1'b0;
        m_axis_bresp = 2'b00;
        m_axis_bvalid = 1'b0;
        m_axis_s2mm_awready = 1'b0;
        m_axis_s2mm_wready = 1'b0;
        m_axis_s2mm_bresp = 2'b00;
        m_axis_s2mm_bvalid = 1'b0;
        m_axis_s2mm_arready = 1'b0;
        m_axis_s2mm_rdata = '0;
        m_axis_s2mm_rresp = 2'b00;
        m_axis_s2mm_rlast = 1'b0;
        m_axis_s2mm_rvalid = 1'b0;
        m_axis_fetcher_arready = 1'b0;
        m_axis_fetcher_rdata = '0;
        m_axis_fetcher_rresp = 2'b00;
        m_axis_fetcher_rlast = 1'b0;
        m_axis_fetcher_rvalid = 1'b0;

        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (8) @(posedge clk);

        check_applied_control(32'h0000_0004, 32'hC0A8_0114, 32'h3500_0120, 32'h0000_020A);

        write_csr(CSR_NET_CFG0, 32'h0000_0007);
        check_applied_control(32'h0000_0007, 32'hC0A8_0114, 32'h3500_0120, 32'h0000_020A);

        write_csr(CSR_NET_LOCAL_IP, 32'hC0A8_0114);
        check_applied_control(32'h0000_0007, 32'hC0A8_0114, 32'h3500_0120, 32'h0000_020A);

        write_csr(CSR_NET_LOCAL_IP, 32'hC0A8_0122);
        check_applied_control(32'h0000_0007, 32'hC0A8_0122, 32'h3500_0120, 32'h0000_020A);

        write_csr(CSR_NET_LOCAL_IP, 32'hC0A8_0114);
        write_csr(CSR_NET_LOCAL_MACL, 32'h3500_0120);
        write_csr(CSR_NET_LOCAL_MACH, 32'h0000_020A);
        check_applied_control(32'h0000_0007, 32'hC0A8_0114, 32'h3500_0120, 32'h0000_020A);
        write_csr(CSR_INJ_CTRL, 32'h000A_0000);

        push_inject_word(32'hDEAD_BEEF);
        push_inject_word(32'hAAAA_1234);
        push_inject_word(32'h5678_9ABC);
        push_inject_word(32'h0806_0000);
        push_inject_word(32'h0001_0800);
        push_inject_word(32'h0604_0001);
        push_inject_word(32'h1234_0000);
        push_inject_word(32'h5678_9ABC);
        push_inject_word(32'hC0A8_0102);
        push_inject_word(32'hC0A8_0114);

        read_csr(CSR_INJ_STATUS, dummy);
        read_and_check_arp_reply();
        clear_txcap();

        write_csr(CSR_INJ_CTRL, {UDP_REQ_WORDS[15:0], 16'h0000});
        push_inject_word(32'hDEAD_BEEF);
        push_inject_word(32'hAAAA_1122);
        push_inject_word(32'h3344_5566);
        push_inject_word(32'h0800_0000);
        push_inject_word(32'h003C_0005);
        push_inject_word(32'h0000_0000);
        push_inject_word(32'h0000_0000);
        push_inject_word(32'h0000_C0A8);
        push_inject_word(32'h0102_0000);
        push_inject_word(32'h0000_1234);
        push_inject_word(32'h5678_0028);
        push_inject_word(32'hA0A1_A2A3);
        push_inject_word(32'hB0B1_B2B3);
        push_inject_word(32'hC0C1_C2C3);
        push_inject_word(32'hD0D1_D2D3);
        push_inject_word(32'hE0E1_E2E3);
        push_inject_word(32'hF0F1_F2F3);
        push_inject_word(32'h1122_3344);
        push_inject_word(32'h5566_7788);

        read_csr(CSR_INJ_STATUS, dummy);
        read_and_check_udp_reply();

        $display("PASS: dma_subsystem accepted AXI-Lite packet injection and captured ARP/UDP reply frames");
        $finish;
    end

endmodule
