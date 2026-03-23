`timescale 1ns / 1ps

module tb_fast_path_sanity;

    logic clk;
    logic rst_n;
    logic [31:0] s_axis_tdata;
    logic [3:0]  s_axis_tkeep;
    logic        s_axis_tlast;
    logic        s_axis_tvalid;
    logic        s_axis_tready;
    logic [15:0] dst_port;
    logic [15:0] payload_len;
    logic        drop_flag;
    logic        meta_valid;
    logic [15:0] ip_checksum;
    logic [15:0] udp_checksum;
    logic        checksum_valid;
    logic [31:0] pbm_wdata;
    logic        pbm_wvalid;
    logic        pbm_wlast;
    logic        pbm_ready;
    logic [31:0] m_axis_tdata;
    logic [3:0]  m_axis_tkeep;
    logic        m_axis_tlast;
    logic        m_axis_tvalid;
    logic        m_axis_tready;
    logic [15:0] meta_out_data;
    logic        meta_out_valid;
    logic [15:0] meta_out_checksum;
    logic        meta_out_checksum_valid;
    logic        fast_path_enable;
    logic [31:0] fast_path_cnt;
    logic [31:0] bypass_cnt;
    logic [31:0] drop_cnt;
    logic [31:0] checksum_pass_cnt;

    logic seen_tx;
    logic seen_pbm;
    logic seen_meta;
    logic seen_checksum;
    integer tx_beat_count;
    integer pbm_beat_count;
    logic [31:0] tx_words [0:3];
    logic [31:0] pbm_words [0:3];
    logic        tx_lasts [0:3];
    logic        pbm_lasts [0:3];

    fast_path dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .dst_port(dst_port),
        .payload_len(payload_len),
        .drop_flag(drop_flag),
        .meta_valid(meta_valid),
        .ip_checksum(ip_checksum),
        .udp_checksum(udp_checksum),
        .checksum_valid(checksum_valid),
        .pbm_wdata(pbm_wdata),
        .pbm_wvalid(pbm_wvalid),
        .pbm_wlast(pbm_wlast),
        .pbm_ready(pbm_ready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .meta_out_data(meta_out_data),
        .meta_out_valid(meta_out_valid),
        .meta_out_checksum(meta_out_checksum),
        .meta_out_checksum_valid(meta_out_checksum_valid),
        .fast_path_enable(fast_path_enable),
        .fast_path_cnt(fast_path_cnt),
        .bypass_cnt(bypass_cnt),
        .drop_cnt(drop_cnt),
        .checksum_pass_cnt(checksum_pass_cnt)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        #40;
        rst_n = 1'b1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seen_tx <= 1'b0;
            seen_pbm <= 1'b0;
            seen_meta <= 1'b0;
            seen_checksum <= 1'b0;
            tx_beat_count <= 0;
            pbm_beat_count <= 0;
        end else begin
            if (m_axis_tvalid && m_axis_tready) begin
                seen_tx <= 1'b1;
                if (tx_beat_count < 4) begin
                    tx_words[tx_beat_count] <= m_axis_tdata;
                    tx_lasts[tx_beat_count] <= m_axis_tlast;
                end
                tx_beat_count <= tx_beat_count + 1;
            end
            if (pbm_wvalid && pbm_ready) begin
                seen_pbm <= 1'b1;
                if (pbm_beat_count < 4) begin
                    pbm_words[pbm_beat_count] <= pbm_wdata;
                    pbm_lasts[pbm_beat_count] <= pbm_wlast;
                end
                pbm_beat_count <= pbm_beat_count + 1;
            end
            if (meta_out_valid) seen_meta <= 1'b1;
            if (meta_out_checksum_valid && meta_out_checksum == 16'h5678) seen_checksum <= 1'b1;
        end
    end

    task automatic clear_monitors;
        integer idx;
        begin
            seen_tx = 1'b0;
            seen_pbm = 1'b0;
            seen_meta = 1'b0;
            seen_checksum = 1'b0;
            tx_beat_count = 0;
            pbm_beat_count = 0;
            for (idx = 0; idx < 4; idx = idx + 1) begin
                tx_words[idx] = '0;
                pbm_words[idx] = '0;
                tx_lasts[idx] = 1'b0;
                pbm_lasts[idx] = 1'b0;
            end
        end
    endtask

    task automatic expect_two_beat_alignment(input [255:0] label);
        begin
            if (tx_beat_count != 2 ||
                pbm_beat_count != 2 ||
                tx_words[0] != 32'hDEAD_BEEF ||
                tx_words[1] != 32'hAABB_CCDD ||
                pbm_words[0] != 32'hDEAD_BEEF ||
                pbm_words[1] != 32'hAABB_CCDD ||
                tx_words[0] != pbm_words[0] ||
                tx_words[1] != pbm_words[1] ||
                tx_lasts[0] != 1'b0 ||
                tx_lasts[1] != 1'b1 ||
                pbm_lasts[0] != 1'b0 ||
                pbm_lasts[1] != 1'b1) begin
                $fatal(1, "%0s alignment mismatch: tx_count=%0d pbm_count=%0d tx0=%h tx1=%h pbm0=%h pbm1=%h tx_last={%0d,%0d} pbm_last={%0d,%0d}",
                       label, tx_beat_count, pbm_beat_count,
                       tx_words[0], tx_words[1], pbm_words[0], pbm_words[1],
                       tx_lasts[0], tx_lasts[1], pbm_lasts[0], pbm_lasts[1]);
            end
        end
    endtask

    task automatic drive_fast_packet(input [15:0] port);
        begin
            dst_port <= port;
            payload_len <= 16'd32;
            drop_flag <= 1'b0;
            meta_valid <= 1'b1;
            ip_checksum <= 16'h1234;
            udp_checksum <= 16'h5678;
            checksum_valid <= 1'b1;

            s_axis_tdata <= 32'hDEAD_BEEF;
            s_axis_tkeep <= 4'hF;
            s_axis_tlast <= 1'b0;
            s_axis_tvalid <= 1'b1;
            do @(posedge clk); while (!s_axis_tready);

            s_axis_tdata <= 32'hAABB_CCDD;
            s_axis_tlast <= 1'b1;
            do @(posedge clk); while (!s_axis_tready);

            s_axis_tvalid <= 1'b0;
            s_axis_tlast <= 1'b0;
            meta_valid <= 1'b0;
            checksum_valid <= 1'b0;
        end
    endtask

    task automatic hold_non_fast_packet_for_classification(
        input [15:0] port,
        input [15:0] length,
        input        acl_drop
    );
        begin
            dst_port <= port;
            payload_len <= length;
            drop_flag <= acl_drop;
            meta_valid <= 1'b1;
            ip_checksum <= 16'h1234;
            udp_checksum <= 16'h5678;
            checksum_valid <= 1'b1;
            s_axis_tdata <= 32'hDEAD_BEEF;
            s_axis_tkeep <= 4'hF;
            s_axis_tlast <= 1'b0;
            s_axis_tvalid <= 1'b1;
        end
    endtask

    task automatic clear_packet_drive;
        begin
            s_axis_tvalid <= 1'b0;
            s_axis_tlast <= 1'b0;
            meta_valid <= 1'b0;
            checksum_valid <= 1'b0;
            drop_flag <= 1'b0;
            payload_len <= '0;
            dst_port <= '0;
        end
    endtask

    initial begin
        s_axis_tdata = '0;
        s_axis_tkeep = 4'hF;
        s_axis_tlast = 1'b0;
        s_axis_tvalid = 1'b0;
        dst_port = '0;
        payload_len = '0;
        drop_flag = 1'b0;
        meta_valid = 1'b0;
        ip_checksum = '0;
        udp_checksum = '0;
        checksum_valid = 1'b0;
        pbm_ready = 1'b1;
        m_axis_tready = 1'b1;

        wait(rst_n);
        repeat (4) @(posedge clk);

        clear_monitors();
        drive_fast_packet(16'h1235);
        repeat (4) @(posedge clk);
        if (fast_path_cnt != 32'd1 || checksum_pass_cnt != 32'd1 || !seen_tx || !seen_pbm || !seen_meta || !seen_checksum) begin
            $fatal(1, "Fast-path eligible packet failed: fp_cnt=%0d cs_cnt=%0d seen_tx=%0d seen_pbm=%0d seen_meta=%0d seen_checksum=%0d",
                   fast_path_cnt, checksum_pass_cnt, seen_tx, seen_pbm, seen_meta, seen_checksum);
        end
        expect_two_beat_alignment("Initial eligible packet");

        clear_monitors();
        pbm_ready <= 1'b0;
        dst_port <= 16'h1235;
        payload_len <= 16'd32;
        drop_flag <= 1'b0;
        meta_valid <= 1'b1;
        ip_checksum <= 16'h1234;
        udp_checksum <= 16'h5678;
        checksum_valid <= 1'b1;
        s_axis_tdata <= 32'hDEAD_BEEF;
        s_axis_tkeep <= 4'hF;
        s_axis_tlast <= 1'b0;
        s_axis_tvalid <= 1'b1;
        repeat (6) @(posedge clk);

        if (s_axis_tready !== 1'b0 || fast_path_cnt != 32'd1) begin
            $fatal(1, "Expected fast-path back-pressure stall: tready=%0d fast_path_cnt=%0d",
                   s_axis_tready, fast_path_cnt);
        end

        pbm_ready <= 1'b1;
        do @(posedge clk); while (!s_axis_tready);
        s_axis_tdata <= 32'hFACE_CAFE;
        s_axis_tlast <= 1'b1;
        do @(posedge clk); while (!s_axis_tready);
        clear_packet_drive();
        repeat (4) @(posedge clk);

        if (fast_path_cnt != 32'd2 || checksum_pass_cnt != 32'd2) begin
            $fatal(1, "Expected stalled fast-path packet to complete after ready restore: fp_cnt=%0d cs_cnt=%0d",
                   fast_path_cnt, checksum_pass_cnt);
        end
        if (tx_beat_count != 2 || pbm_beat_count != 2 || tx_words[0] != 32'hDEAD_BEEF || tx_words[1] != 32'hFACE_CAFE ||
            pbm_words[0] != 32'hDEAD_BEEF || pbm_words[1] != 32'hFACE_CAFE || tx_words[0] != pbm_words[0] ||
            tx_words[1] != pbm_words[1] || tx_lasts[1] != 1'b1 || pbm_lasts[1] != 1'b1) begin
            $fatal(1, "Stalled packet alignment mismatch after PBM restore: tx_count=%0d pbm_count=%0d tx0=%h tx1=%h pbm0=%h pbm1=%h tx_last={%0d,%0d} pbm_last={%0d,%0d}",
                   tx_beat_count, pbm_beat_count, tx_words[0], tx_words[1], pbm_words[0], pbm_words[1],
                   tx_lasts[0], tx_lasts[1], pbm_lasts[0], pbm_lasts[1]);
        end

        clear_monitors();
        pbm_ready <= 1'b0;
        m_axis_tready <= 1'b0;
        dst_port <= 16'h1235;
        payload_len <= 16'd32;
        drop_flag <= 1'b0;
        meta_valid <= 1'b1;
        ip_checksum <= 16'h1234;
        udp_checksum <= 16'h5678;
        checksum_valid <= 1'b1;
        s_axis_tdata <= 32'hD00D_0001;
        s_axis_tkeep <= 4'hF;
        s_axis_tlast <= 1'b0;
        s_axis_tvalid <= 1'b1;
        repeat (6) @(posedge clk);

        if (s_axis_tready !== 1'b0 || fast_path_cnt != 32'd2) begin
            $fatal(1, "Expected combined back-pressure stall: tready=%0d fast_path_cnt=%0d",
                   s_axis_tready, fast_path_cnt);
        end

        pbm_ready <= 1'b1;
        m_axis_tready <= 1'b1;
        do @(posedge clk); while (!s_axis_tready);
        s_axis_tdata <= 32'hD00D_0002;
        s_axis_tlast <= 1'b1;
        do @(posedge clk); while (!s_axis_tready);
        clear_packet_drive();
        repeat (4) @(posedge clk);

        if (fast_path_cnt != 32'd3 || checksum_pass_cnt != 32'd3) begin
            $fatal(1, "Expected combined-stall fast-path packet to complete after ready restore: fp_cnt=%0d cs_cnt=%0d",
                   fast_path_cnt, checksum_pass_cnt);
        end
        if (tx_beat_count != 2 || pbm_beat_count != 2 || tx_words[0] != 32'hD00D_0001 || tx_words[1] != 32'hD00D_0002 ||
            pbm_words[0] != 32'hD00D_0001 || pbm_words[1] != 32'hD00D_0002 || tx_words[0] != pbm_words[0] ||
            tx_words[1] != pbm_words[1] || tx_lasts[1] != 1'b1 || pbm_lasts[1] != 1'b1) begin
            $fatal(1, "Combined-stall packet alignment mismatch after ready restore: tx_count=%0d pbm_count=%0d tx0=%h tx1=%h pbm0=%h pbm1=%h tx_last={%0d,%0d} pbm_last={%0d,%0d}",
                   tx_beat_count, pbm_beat_count, tx_words[0], tx_words[1], pbm_words[0], pbm_words[1],
                   tx_lasts[0], tx_lasts[1], pbm_lasts[0], pbm_lasts[1]);
        end

        clear_monitors();
        hold_non_fast_packet_for_classification(16'h1234, 16'd32, 1'b0);
        repeat (6) @(posedge clk);

        if (s_axis_tready !== 1'b0 || bypass_cnt != 32'd1) begin
            $fatal(1, "Expected bypass classification for crypto port: tready=%0d bypass_cnt=%0d",
                   s_axis_tready, bypass_cnt);
        end
        clear_packet_drive();
        repeat (2) @(posedge clk);

        if (fast_path_enable !== 1'b0 || bypass_cnt != 32'd1 || s_axis_tready !== 1'b0) begin
            $fatal(1, "Expected bypass state to recover after meta_valid drop: fast_path_enable=%0d bypass_cnt=%0d tready=%0d",
                   fast_path_enable, bypass_cnt, s_axis_tready);
        end

        hold_non_fast_packet_for_classification(16'h1235, 16'd32, 1'b1);
        repeat (6) @(posedge clk);

        if (drop_cnt != 32'd1 || bypass_cnt != 32'd1 || s_axis_tready !== 1'b0) begin
            $fatal(1, "Expected ACL drop classification: drop_cnt=%0d bypass_cnt=%0d tready=%0d",
                   drop_cnt, bypass_cnt, s_axis_tready);
        end
        clear_packet_drive();
        repeat (2) @(posedge clk);

        $display("PASS: fast_path sanity verified eligible path plus bypass/drop classification semantics");
        $finish;
    end

endmodule
