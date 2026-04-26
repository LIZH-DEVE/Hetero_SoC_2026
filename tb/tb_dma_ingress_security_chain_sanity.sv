`timescale 1ns / 1ps

module tb_dma_ingress_security_chain_sanity;

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

    logic        clear_monitors_req;
    logic        rollback_seen;
    logic        stall_seen;
    integer      pbm_write_beat_count;
    integer      acl_drop_pulse_count;
    logic [103:0] acl_rule_tuple_shadow;
    logic [15:0]  acl_rule_hash_shadow;
    string        current_case;

    localparam int PBM_DEPTH_WORDS = (1 << (14 - 2));
    localparam int PBM_FULL_THRESHOLD = PBM_DEPTH_WORDS - 16;
    localparam int NETWORK_PACKET_WORDS = 7;
    localparam int PBM_PRESTALL_PACKETS = PBM_FULL_THRESHOLD / NETWORK_PACKET_WORDS;

    function automatic [15:0] tuple_hash(input [103:0] data);
        logic [15:0] h;
        begin
            h = data[15:0] ^ data[31:16] ^ data[47:32] ^ data[63:48] ^
                data[79:64] ^ data[95:80] ^ {8'h00, data[103:96]};
            h = h ^ {h[7:0], h[15:8]} ^ 16'h9E37;
            tuple_hash = h ^ {h[10:0], h[15:11]} ^ (h >> 3);
        end
    endfunction

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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pbm_write_beat_count <= 0;
            acl_drop_pulse_count <= 0;
            rollback_seen <= 1'b0;
            stall_seen <= 1'b0;
        end else if (clear_monitors_req) begin
            pbm_write_beat_count <= 0;
            acl_drop_pulse_count <= 0;
            rollback_seen <= 1'b0;
            stall_seen <= 1'b0;
        end else begin
            if (dut.aclf_tvalid && dut.pbm_wr_ready) begin
                pbm_write_beat_count <= pbm_write_beat_count + 1;
            end
            if (dut.acl_drop_pulse) begin
                acl_drop_pulse_count <= acl_drop_pulse_count + 1;
            end
            if (dut.u_pbm.o_rollback_active) begin
                rollback_seen <= 1'b1;
            end
            if (dut.aclf_tvalid && !dut.pbm_wr_ready) begin
                stall_seen <= 1'b1;
            end
        end
    end

    task automatic clear_monitors_and_wait;
        begin
            clear_monitors_req <= 1'b1;
            @(posedge clk);
            clear_monitors_req <= 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n <= 1'b0;
            rx_wr_valid <= 1'b0;
            rx_wr_last <= 1'b0;
            rx_wr_data <= '0;
            clear_monitors_req <= 1'b0;
            repeat (8) @(posedge clk);
            rst_n <= 1'b1;
            repeat (8) @(posedge clk);
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

    task automatic configure_ctrl(input bit auth_enable, input bit acl_enable);
        logic [31:0] ctrl_word;
        begin
            ctrl_word = 32'd0;
            ctrl_word[6] = auth_enable;
            ctrl_word[7] = acl_enable;
            write_csr(32'h0000_0000, ctrl_word);
            write_csr(32'h0000_0048, 32'd0);
        end
    endtask

    task automatic force_acl_clear;
        begin
            force dut.acl_cfg_clear = 1'b1;
            @(posedge clk);
            release dut.acl_cfg_clear;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic program_acl_rule(input [103:0] tuple);
        begin
            acl_rule_tuple_shadow = tuple;
            acl_rule_hash_shadow  = tuple_hash(tuple);
            force dut.acl_cfg_addr = acl_rule_hash_shadow[11:0];
            force dut.acl_cfg_data = acl_rule_tuple_shadow;
            force dut.acl_cfg_we   = 1'b1;
            @(posedge clk);
            release dut.acl_cfg_we;
            release dut.acl_cfg_data;
            release dut.acl_cfg_addr;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic wait_pipeline_idle;
        integer idle_cycles;
        integer guard_cycles;
        begin
            idle_cycles = 0;
            guard_cycles = 0;
            while (idle_cycles < 12) begin
                @(posedge clk);
                guard_cycles = guard_cycles + 1;
                if (!rx_wr_valid &&
                    !dut.auth_tvalid &&
                    !dut.ingress_tvalid &&
                    !dut.aclf_tvalid &&
                    !dut.u_pbm.o_rollback_active) begin
                    idle_cycles = idle_cycles + 1;
                end else begin
                    idle_cycles = 0;
                end
                if (guard_cycles > 100000) begin
                    $fatal(1, "wait_pipeline_idle timeout in %s: rx_valid=%0d rx_ready=%0d auth_valid=%0d auth_ready=%0d ingress_valid=%0d ingress_ready=%0d aclf_valid=%0d pbm_ready=%0d usage=%0d",
                           current_case, rx_wr_valid, rx_wr_ready, dut.auth_tvalid, dut.auth_tready,
                           dut.ingress_tvalid, dut.ingress_tready, dut.aclf_tvalid, dut.pbm_wr_ready,
                           dut.u_pbm.o_buffer_usage);
                end
            end
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
                if (guard_cycles > 100000) begin
                    $fatal(1, "drive_word timeout in %s: data=%08h last=%0d rx_ready=%0d auth_valid=%0d auth_ready=%0d ingress_valid=%0d ingress_ready=%0d aclf_valid=%0d pbm_ready=%0d usage=%0d",
                           current_case, data, last, rx_wr_ready, dut.auth_tvalid, dut.auth_tready,
                           dut.ingress_tvalid, dut.ingress_tready, dut.aclf_tvalid, dut.pbm_wr_ready,
                           dut.u_pbm.o_buffer_usage);
                end
            end while (!rx_wr_ready);
            rx_wr_valid <= 1'b0;
            rx_wr_last  <= 1'b0;
            rx_wr_data  <= '0;
        end
    endtask

    task automatic send_network_packet(
        input [31:0] src_ip_addr,
        input [31:0] dst_ip_addr,
        input [15:0] src_port_num,
        input [15:0] dst_port_num,
        input [7:0]  protocol_type
    );
        begin
            drive_word(32'h4500_0000, 1'b0);
            drive_word(32'd40,        1'b0);
            drive_word(32'h0000_0000, 1'b0);
            drive_word({8'd64, protocol_type, 16'h0000}, 1'b0);
            drive_word(src_ip_addr,   1'b0);
            drive_word(dst_ip_addr,   1'b0);
            drive_word({src_port_num, dst_port_num}, 1'b1);
        end
    endtask

    task automatic send_short_packet;
        begin
            drive_word(32'h4500_0000, 1'b0);
            drive_word(32'd16,        1'b0);
            drive_word(32'h1111_2222, 1'b0);
            drive_word(32'h3333_4444, 1'b1);
        end
    endtask

    task automatic send_auth_wrapped_network_packet(
        input bit     valid_magic,
        input [15:0]  seq_id,
        input [31:0]  src_ip_addr,
        input [31:0]  dst_ip_addr,
        input [15:0]  src_port_num,
        input [15:0]  dst_port_num,
        input [7:0]   protocol_type
    );
        begin
            drive_word(valid_magic ? 32'hDEAD_BEEF : 32'hBAAD_BEEF, 1'b0);
            drive_word({16'hCAFE, seq_id}, 1'b0);
            drive_word(32'h4500_0000, 1'b0);
            drive_word(32'd40,        1'b0);
            drive_word(32'h0000_0000, 1'b0);
            drive_word({8'd64, protocol_type, 16'h0000}, 1'b0);
            drive_word(src_ip_addr,   1'b0);
            drive_word(dst_ip_addr,   1'b0);
            drive_word({src_port_num, dst_port_num}, 1'b1);
        end
    endtask

    task automatic fill_pbm_to_prestall;
        integer iter;
        begin
            for (iter = 0; iter < PBM_PRESTALL_PACKETS; iter = iter + 1) begin
                send_network_packet(32'hC0A8_0001, 32'hC0A8_0002, 16'd9000 + iter[15:0], 16'd80, 8'd6);
                wait_pipeline_idle();
            end
            if (!dut.pbm_wr_ready || dut.u_pbm.o_buffer_usage != (PBM_PRESTALL_PACKETS * NETWORK_PACKET_WORDS)) begin
                $fatal(1, "PBM prestall fill failed: ready=%0d usage=%0d expected_usage=%0d packets=%0d",
                       dut.pbm_wr_ready, dut.u_pbm.o_buffer_usage, (PBM_PRESTALL_PACKETS * NETWORK_PACKET_WORDS),
                       PBM_PRESTALL_PACKETS);
            end
        end
    endtask

    initial begin
        logic [103:0] hit_tuple;
        integer       pre_count;
        integer       resume_guard;

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
        tx_axis_tready = 1'b1;
        clear_monitors_req = 1'b0;

        m_axis_awready = 1'b1;
        m_axis_wready = 1'b1;
        m_axis_bresp = 2'b00;
        m_axis_bvalid = 1'b1;
        m_axis_s2mm_awready = 1'b1;
        m_axis_s2mm_wready = 1'b1;
        m_axis_s2mm_bresp = 2'b00;
        m_axis_s2mm_bvalid = 1'b1;
        m_axis_s2mm_arready = 1'b1;
        m_axis_s2mm_rdata = 32'd0;
        m_axis_s2mm_rresp = 2'b00;
        m_axis_s2mm_rlast = 1'b1;
        m_axis_s2mm_rvalid = 1'b0;
        m_axis_fetcher_arready = 1'b1;
        m_axis_fetcher_rdata = 32'd0;
        m_axis_fetcher_rresp = 2'b00;
        m_axis_fetcher_rlast = 1'b1;
        m_axis_fetcher_rvalid = 1'b0;

        hit_tuple = {8'd6, 32'hC0A8_0001, 16'd1234, 32'hC0A8_0002, 16'd80};
        current_case = "reset";

        reset_dut();

        // A1: auth off, acl off -> direct PBM write
        current_case = "A1";
        $display("Running %s", current_case);
        configure_ctrl(1'b0, 1'b0);
        force_acl_clear();
        clear_monitors_and_wait();
        send_network_packet(32'hC0A8_0001, 32'hC0A8_0002, 16'd1234, 16'd80, 8'd6);
        wait_pipeline_idle();
        if (pbm_write_beat_count != 7 || dut.acl_hit_count != 0 || dut.acl_miss_count != 0 || acl_drop_pulse_count != 0) begin
            $fatal(1, "Case A1 failed: pbm_beats=%0d hit=%0d miss=%0d drop_pulses=%0d",
                   pbm_write_beat_count, dut.acl_hit_count, dut.acl_miss_count, acl_drop_pulse_count);
        end

        // A2: auth off, acl on, miss
        current_case = "A2";
        $display("Running %s", current_case);
        reset_dut();
        configure_ctrl(1'b0, 1'b1);
        force_acl_clear();
        program_acl_rule(hit_tuple);
        clear_monitors_and_wait();
        send_network_packet(32'hC0A8_0001, 32'hC0A8_0002, 16'd5678, 16'd80, 8'd6);
        wait_pipeline_idle();
        if (pbm_write_beat_count != 7 || dut.acl_hit_count != 0 || dut.acl_miss_count != 1 || acl_drop_pulse_count != 0) begin
            $fatal(1, "Case A2 failed: pbm_beats=%0d hit=%0d miss=%0d drop_pulses=%0d",
                   pbm_write_beat_count, dut.acl_hit_count, dut.acl_miss_count, acl_drop_pulse_count);
        end

        // A3: auth off, acl on, hit
        current_case = "A3";
        $display("Running %s", current_case);
        reset_dut();
        configure_ctrl(1'b0, 1'b1);
        force_acl_clear();
        program_acl_rule(hit_tuple);
        clear_monitors_and_wait();
        send_network_packet(32'hC0A8_0001, 32'hC0A8_0002, 16'd1234, 16'd80, 8'd6);
        wait_pipeline_idle();
        if (pbm_write_beat_count != 0 || dut.acl_hit_count != 1 || dut.acl_miss_count != 0 || acl_drop_pulse_count != 1) begin
            $fatal(1, "Case A3 failed: pbm_beats=%0d hit=%0d miss=%0d drop_pulses=%0d",
                   pbm_write_beat_count, dut.acl_hit_count, dut.acl_miss_count, acl_drop_pulse_count);
        end

        // B1: short packet bypasses ACL
        current_case = "B1";
        $display("Running %s", current_case);
        reset_dut();
        configure_ctrl(1'b0, 1'b1);
        force_acl_clear();
        program_acl_rule(hit_tuple);
        clear_monitors_and_wait();
        send_short_packet();
        wait_pipeline_idle();
        if (pbm_write_beat_count != 4 || dut.acl_hit_count != 0 || dut.acl_miss_count != 0 || acl_drop_pulse_count != 0) begin
            $fatal(1, "Case B1 failed: pbm_beats=%0d hit=%0d miss=%0d drop_pulses=%0d",
                   pbm_write_beat_count, dut.acl_hit_count, dut.acl_miss_count, acl_drop_pulse_count);
        end

        // B2: auth fail stops before ACL/PBM
        current_case = "B2";
        $display("Running %s", current_case);
        reset_dut();
        configure_ctrl(1'b1, 1'b1);
        force_acl_clear();
        program_acl_rule(hit_tuple);
        clear_monitors_and_wait();
        send_auth_wrapped_network_packet(1'b0, 16'd1, 32'hC0A8_0001, 32'hC0A8_0002, 16'd1234, 16'd80, 8'd6);
        wait_pipeline_idle();
        if (pbm_write_beat_count != 0 || dut.acl_hit_count != 0 || dut.acl_miss_count != 0 || acl_drop_pulse_count != 0) begin
            $fatal(1, "Case B2 failed: pbm_beats=%0d hit=%0d miss=%0d drop_pulses=%0d",
                   pbm_write_beat_count, dut.acl_hit_count, dut.acl_miss_count, acl_drop_pulse_count);
        end

        // B3: auth pass + ACL hit
        current_case = "B3";
        $display("Running %s", current_case);
        reset_dut();
        configure_ctrl(1'b1, 1'b1);
        force_acl_clear();
        program_acl_rule(hit_tuple);
        clear_monitors_and_wait();
        send_auth_wrapped_network_packet(1'b1, 16'd1, 32'hC0A8_0001, 32'hC0A8_0002, 16'd1234, 16'd80, 8'd6);
        wait_pipeline_idle();
        if (pbm_write_beat_count != 0 || dut.acl_hit_count != 1 || dut.acl_miss_count != 0 || acl_drop_pulse_count != 1) begin
            $fatal(1, "Case B3 failed: pbm_beats=%0d hit=%0d miss=%0d drop_pulses=%0d",
                   pbm_write_beat_count, dut.acl_hit_count, dut.acl_miss_count, acl_drop_pulse_count);
        end

        // B4: auth pass + ACL miss
        current_case = "B4";
        $display("Running %s", current_case);
        reset_dut();
        configure_ctrl(1'b1, 1'b1);
        force_acl_clear();
        program_acl_rule(hit_tuple);
        clear_monitors_and_wait();
        send_auth_wrapped_network_packet(1'b1, 16'd1, 32'hC0A8_0001, 32'hC0A8_0002, 16'd5678, 16'd80, 8'd6);
        wait_pipeline_idle();
        if (pbm_write_beat_count != 7 || dut.acl_hit_count != 0 || dut.acl_miss_count != 1 || acl_drop_pulse_count != 0) begin
            $fatal(1, "Case B4 failed: pbm_beats=%0d hit=%0d miss=%0d drop_pulses=%0d",
                   pbm_write_beat_count, dut.acl_hit_count, dut.acl_miss_count, acl_drop_pulse_count);
        end

        // C1: PBM back-pressure by filling buffer, then drain and resume
        current_case = "C1";
        $display("Running %s", current_case);
        reset_dut();
        configure_ctrl(1'b0, 1'b0);
        force_acl_clear();
        clear_monitors_and_wait();
        force dut.bridge_rd_pbm = 1'b0;
        fill_pbm_to_prestall();
        pre_count = pbm_write_beat_count;
        $display("C1 prestall: usage=%0d pbm_beats=%0d", dut.u_pbm.o_buffer_usage, pbm_write_beat_count);
        fork : backpressure_case
            begin
                send_network_packet(32'hC0A8_0001, 32'hC0A8_0002, 16'd7000, 16'd80, 8'd6);
            end
        join_none
        repeat (64) @(posedge clk);
        if (!stall_seen ||
            !(pbm_write_beat_count > pre_count && pbm_write_beat_count < (pre_count + NETWORK_PACKET_WORDS))) begin
            disable backpressure_case;
            $fatal(1, "Case C1 stalled-send phase failed: stall_seen=%0d pbm_beats=%0d pre_count=%0d packet_words=%0d",
                   stall_seen, pbm_write_beat_count, pre_count, NETWORK_PACKET_WORDS);
        end
        $display("C1 stalled: usage=%0d pbm_beats=%0d", dut.u_pbm.o_buffer_usage, pbm_write_beat_count);
        force dut.bridge_rd_pbm = 1'b1;
        resume_guard = 0;
        while (!(dut.pbm_wr_ready && !dut.aclf_tvalid && !dut.ingress_tvalid && !dut.auth_tvalid)) begin
            @(posedge clk);
            resume_guard = resume_guard + 1;
            if (resume_guard > 100000) begin
                $fatal(1, "Case C1 resume wait timeout: pbm_ready=%0d usage=%0d aclf_valid=%0d ingress_valid=%0d auth_valid=%0d bridge_rd=%0d",
                       dut.pbm_wr_ready, dut.u_pbm.o_buffer_usage, dut.aclf_tvalid, dut.ingress_tvalid,
                       dut.auth_tvalid, dut.bridge_rd_pbm);
            end
        end
        $display("C1 resumed: usage=%0d pbm_beats=%0d", dut.u_pbm.o_buffer_usage, pbm_write_beat_count);
        repeat (8) @(posedge clk);
        release dut.bridge_rd_pbm;
        wait_pipeline_idle();
        if (pbm_write_beat_count <= pre_count) begin
            $fatal(1, "Case C1 resume phase failed: pbm_beats=%0d pre_count=%0d",
                   pbm_write_beat_count, pre_count);
        end

        // C2: multi-packet cumulative sequence
        current_case = "C2";
        $display("Running %s", current_case);
        reset_dut();
        configure_ctrl(1'b0, 1'b1);
        force_acl_clear();
        program_acl_rule(hit_tuple);
        clear_monitors_and_wait();
        send_network_packet(32'hC0A8_0001, 32'hC0A8_0002, 16'd5678, 16'd80, 8'd6); // miss
        wait_pipeline_idle();
        send_network_packet(32'hC0A8_0001, 32'hC0A8_0002, 16'd1234, 16'd80, 8'd6); // hit
        wait_pipeline_idle();
        send_short_packet(); // bypass
        wait_pipeline_idle();
        send_network_packet(32'hC0A8_0001, 32'hC0A8_0002, 16'd9000, 16'd80, 8'd6); // miss
        wait_pipeline_idle();
        if (pbm_write_beat_count != 18 || dut.acl_hit_count != 1 || dut.acl_miss_count != 2 || acl_drop_pulse_count != 1) begin
            $fatal(1, "Case C2 failed: pbm_beats=%0d hit=%0d miss=%0d drop_pulses=%0d",
                   pbm_write_beat_count, dut.acl_hit_count, dut.acl_miss_count, acl_drop_pulse_count);
        end

        // D1: force PBM write error -> rollback
        current_case = "D1";
        $display("Running %s", current_case);
        reset_dut();
        configure_ctrl(1'b0, 1'b0);
        force_acl_clear();
        clear_monitors_and_wait();
        force dut.u_pbm.i_wr_error = 1'b1;
        send_network_packet(32'hC0A8_0001, 32'hC0A8_0002, 16'd1234, 16'd80, 8'd6);
        wait_pipeline_idle();
        release dut.u_pbm.i_wr_error;
        if (!rollback_seen || dut.u_pbm.o_buffer_usage != 0) begin
            $fatal(1, "Case D1 failed: rollback_seen=%0d buffer_usage=%0d",
                   rollback_seen, dut.u_pbm.o_buffer_usage);
        end

        $display("PASS: dma ingress security chain sanity");
        $finish;
    end

endmodule
