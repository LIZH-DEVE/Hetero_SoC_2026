`timescale 1ns / 1ps

/**
 * Day 17: Zero-Copy FastPath verification
 *
 * Current RTL contract:
 * - Eligible packets are consumed by fast_path and forwarded to TX/PBM.
 * - Non-eligible packets are classified as bypass/drop and are not consumed by
 *   fast_path itself. The module keeps tready low until the external owner of
 *   that path takes over and meta_valid deasserts.
 */

module tb_day17_fastpath;

    localparam CRYPTO_PORT = 16'h1234;
    localparam CONFIG_PORT = 16'h4321;

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

    integer test_pass;
    integer test_fail;

    fast_path #(
        .AXI_DATA_WIDTH(32),
        .CRYPTO_PORT(CRYPTO_PORT),
        .CONFIG_PORT(CONFIG_PORT)
    ) u_fast_path (
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
        end else begin
            if (m_axis_tvalid && m_axis_tready) begin
                seen_tx <= 1'b1;
            end
            if (pbm_wvalid && pbm_ready) begin
                seen_pbm <= 1'b1;
            end
            if (meta_out_valid) begin
                seen_meta <= 1'b1;
            end
            if (meta_out_checksum_valid && meta_out_checksum == 16'h5678) begin
                seen_checksum <= 1'b1;
            end
        end
    end

    task automatic clear_monitors;
        begin
            seen_tx <= 1'b0;
            seen_pbm <= 1'b0;
            seen_meta <= 1'b0;
            seen_checksum <= 1'b0;
        end
    endtask

    task automatic clear_drive;
        begin
            s_axis_tdata <= '0;
            s_axis_tkeep <= 4'hF;
            s_axis_tlast <= 1'b0;
            s_axis_tvalid <= 1'b0;
            dst_port <= '0;
            payload_len <= '0;
            drop_flag <= 1'b0;
            meta_valid <= 1'b0;
            ip_checksum <= '0;
            udp_checksum <= '0;
            checksum_valid <= 1'b0;
        end
    endtask

    task automatic drive_fast_packet(
        input [15:0] port,
        input [15:0] length,
        input        checksum_en
    );
        begin
            dst_port <= port;
            payload_len <= length;
            drop_flag <= 1'b0;
            meta_valid <= 1'b1;
            ip_checksum <= 16'h1234;
            udp_checksum <= 16'h5678;
            checksum_valid <= checksum_en;

            s_axis_tdata <= 32'hDEAD_BEEF;
            s_axis_tkeep <= 4'hF;
            s_axis_tlast <= 1'b0;
            s_axis_tvalid <= 1'b1;
            do @(posedge clk); while (!s_axis_tready);

            s_axis_tdata <= 32'hAABB_CCDD;
            s_axis_tlast <= 1'b1;
            do @(posedge clk); while (!s_axis_tready);

            clear_drive();
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

    task automatic record_result(input bit cond, input string pass_msg, input string fail_msg);
        begin
            if (cond) begin
                $display("[PASS] %s", pass_msg);
                test_pass++;
            end else begin
                $display("[FAIL] %s", fail_msg);
                test_fail++;
            end
        end
    endtask

    initial begin
        test_pass = 0;
        test_fail = 0;
        pbm_ready = 1'b1;
        m_axis_tready = 1'b1;
        clear_drive();

        wait(rst_n);
        repeat (4) @(posedge clk);

        $display("========================================");
        $display("Day 17: Zero-Copy FastPath");
        $display("========================================");

        clear_monitors();
        drive_fast_packet(16'h1235, 16'd32, 1'b1);
        repeat (4) @(posedge clk);
        record_result(
            fast_path_cnt == 32'd1 &&
            checksum_pass_cnt == 32'd1 &&
            seen_tx && seen_pbm && seen_meta && seen_checksum,
            "Eligible packet used FastPath and preserved checksum",
            $sformatf("Eligible packet failed: fp_cnt=%0d cs_cnt=%0d seen_tx=%0d seen_pbm=%0d seen_meta=%0d seen_checksum=%0d",
                      fast_path_cnt, checksum_pass_cnt, seen_tx, seen_pbm, seen_meta, seen_checksum)
        );

        clear_monitors();
        pbm_ready <= 1'b0;
        dst_port <= 16'h1235;
        payload_len <= 16'd32;
        drop_flag <= 1'b0;
        meta_valid <= 1'b1;
        ip_checksum <= 16'h1234;
        udp_checksum <= 16'h5678;
        checksum_valid <= 1'b1;
        s_axis_tdata <= 32'hCAFE_BABE;
        s_axis_tkeep <= 4'hF;
        s_axis_tlast <= 1'b0;
        s_axis_tvalid <= 1'b1;
        repeat (6) @(posedge clk);
        record_result(
            s_axis_tready == 1'b0 &&
            fast_path_cnt == 32'd1 &&
            checksum_pass_cnt == 32'd1,
            "PBM back-pressure stalls eligible packet before completion",
            $sformatf("PBM back-pressure mismatch: tready=%0d fp_cnt=%0d cs_cnt=%0d",
                      s_axis_tready, fast_path_cnt, checksum_pass_cnt)
        );
        pbm_ready <= 1'b1;
        do @(posedge clk); while (!s_axis_tready);
        s_axis_tdata <= 32'h1234_5678;
        s_axis_tlast <= 1'b1;
        do @(posedge clk); while (!s_axis_tready);
        clear_drive();
        repeat (4) @(posedge clk);
        record_result(
            fast_path_cnt == 32'd2 &&
            checksum_pass_cnt == 32'd2,
            "PBM back-pressure packet completes after ready restore",
            $sformatf("PBM restore mismatch: fp_cnt=%0d cs_cnt=%0d", fast_path_cnt, checksum_pass_cnt)
        );

        m_axis_tready <= 1'b0;
        dst_port <= 16'h1235;
        payload_len <= 16'd32;
        drop_flag <= 1'b0;
        meta_valid <= 1'b1;
        ip_checksum <= 16'h1234;
        udp_checksum <= 16'h5678;
        checksum_valid <= 1'b1;
        s_axis_tdata <= 32'hABCD_0001;
        s_axis_tkeep <= 4'hF;
        s_axis_tlast <= 1'b0;
        s_axis_tvalid <= 1'b1;
        repeat (6) @(posedge clk);
        record_result(
            s_axis_tready == 1'b0 &&
            fast_path_cnt == 32'd2 &&
            checksum_pass_cnt == 32'd2,
            "TX back-pressure stalls eligible packet before completion",
            $sformatf("TX back-pressure mismatch: tready=%0d fp_cnt=%0d cs_cnt=%0d",
                      s_axis_tready, fast_path_cnt, checksum_pass_cnt)
        );
        m_axis_tready <= 1'b1;
        do @(posedge clk); while (!s_axis_tready);
        s_axis_tdata <= 32'hABCD_0002;
        s_axis_tlast <= 1'b1;
        do @(posedge clk); while (!s_axis_tready);
        clear_drive();
        repeat (4) @(posedge clk);
        record_result(
            fast_path_cnt == 32'd3 &&
            checksum_pass_cnt == 32'd3,
            "TX back-pressure packet completes after ready restore",
            $sformatf("TX restore mismatch: fp_cnt=%0d cs_cnt=%0d", fast_path_cnt, checksum_pass_cnt)
        );

        pbm_ready <= 1'b0;
        m_axis_tready <= 1'b0;
        dst_port <= 16'h1235;
        payload_len <= 16'd32;
        drop_flag <= 1'b0;
        meta_valid <= 1'b1;
        ip_checksum <= 16'h1234;
        udp_checksum <= 16'h5678;
        checksum_valid <= 1'b1;
        s_axis_tdata <= 32'hABCD_1001;
        s_axis_tkeep <= 4'hF;
        s_axis_tlast <= 1'b0;
        s_axis_tvalid <= 1'b1;
        repeat (6) @(posedge clk);
        record_result(
            s_axis_tready == 1'b0 &&
            fast_path_cnt == 32'd3 &&
            checksum_pass_cnt == 32'd3,
            "Combined TX/PBM back-pressure stalls eligible packet before completion",
            $sformatf("Combined back-pressure mismatch: tready=%0d fp_cnt=%0d cs_cnt=%0d",
                      s_axis_tready, fast_path_cnt, checksum_pass_cnt)
        );
        pbm_ready <= 1'b1;
        m_axis_tready <= 1'b1;
        do @(posedge clk); while (!s_axis_tready);
        s_axis_tdata <= 32'hABCD_1002;
        s_axis_tlast <= 1'b1;
        do @(posedge clk); while (!s_axis_tready);
        clear_drive();
        repeat (4) @(posedge clk);
        record_result(
            fast_path_cnt == 32'd4 &&
            checksum_pass_cnt == 32'd4,
            "Combined back-pressure packet completes after both ready signals restore",
            $sformatf("Combined restore mismatch: fp_cnt=%0d cs_cnt=%0d", fast_path_cnt, checksum_pass_cnt)
        );

        clear_monitors();
        hold_non_fast_packet_for_classification(CRYPTO_PORT, 16'd32, 1'b0);
        repeat (6) @(posedge clk);
        record_result(
            s_axis_tready == 1'b0 &&
            bypass_cnt == 32'd1 &&
            !seen_tx && !seen_pbm && !seen_meta,
            "Crypto port packet classified as bypass",
            $sformatf("Crypto bypass mismatch: tready=%0d bypass_cnt=%0d seen_tx=%0d seen_pbm=%0d seen_meta=%0d",
                      s_axis_tready, bypass_cnt, seen_tx, seen_pbm, seen_meta)
        );
        clear_drive();
        repeat (2) @(posedge clk);
        record_result(
            !fast_path_enable &&
            bypass_cnt == 32'd1 &&
            s_axis_tready == 1'b0,
            "BYPASS state recovers cleanly when meta_valid drops",
            $sformatf("BYPASS recovery mismatch: fast_path_enable=%0d bypass_cnt=%0d tready=%0d",
                      fast_path_enable, bypass_cnt, s_axis_tready)
        );

        clear_monitors();
        hold_non_fast_packet_for_classification(CONFIG_PORT, 16'd32, 1'b0);
        repeat (6) @(posedge clk);
        record_result(
            s_axis_tready == 1'b0 &&
            bypass_cnt == 32'd2 &&
            !seen_tx && !seen_pbm && !seen_meta,
            "Config port packet classified as bypass",
            $sformatf("Config bypass mismatch: tready=%0d bypass_cnt=%0d seen_tx=%0d seen_pbm=%0d seen_meta=%0d",
                      s_axis_tready, bypass_cnt, seen_tx, seen_pbm, seen_meta)
        );
        clear_drive();
        repeat (2) @(posedge clk);

        clear_monitors();
        hold_non_fast_packet_for_classification(16'h1235, 16'd32, 1'b1);
        repeat (6) @(posedge clk);
        record_result(
            s_axis_tready == 1'b0 &&
            bypass_cnt == 32'd2 &&
            drop_cnt == 32'd1 &&
            !seen_tx && !seen_pbm && !seen_meta,
            "ACL drop packet classified without entering FastPath",
            $sformatf("ACL drop mismatch: tready=%0d bypass_cnt=%0d drop_cnt=%0d seen_tx=%0d seen_pbm=%0d seen_meta=%0d",
                      s_axis_tready, bypass_cnt, drop_cnt, seen_tx, seen_pbm, seen_meta)
        );
        clear_drive();
        repeat (2) @(posedge clk);

        clear_monitors();
        hold_non_fast_packet_for_classification(16'h1235, 16'd31, 1'b0);
        repeat (6) @(posedge clk);
        record_result(
            s_axis_tready == 1'b0 &&
            bypass_cnt == 32'd3 &&
            !seen_tx && !seen_pbm && !seen_meta,
            "Misaligned payload classified as bypass",
            $sformatf("Misaligned payload mismatch: tready=%0d bypass_cnt=%0d seen_tx=%0d seen_pbm=%0d seen_meta=%0d",
                      s_axis_tready, bypass_cnt, seen_tx, seen_pbm, seen_meta)
        );
        clear_drive();
        repeat (2) @(posedge clk);

        clear_monitors();
        hold_non_fast_packet_for_classification(16'h1235, 16'd0, 1'b0);
        repeat (6) @(posedge clk);
        record_result(
            s_axis_tready == 1'b0 &&
            bypass_cnt == 32'd4 &&
            !seen_tx && !seen_pbm && !seen_meta,
            "Zero-length payload classified as bypass",
            $sformatf("Zero-length mismatch: tready=%0d bypass_cnt=%0d seen_tx=%0d seen_pbm=%0d seen_meta=%0d",
                      s_axis_tready, bypass_cnt, seen_tx, seen_pbm, seen_meta)
        );
        clear_drive();
        repeat (2) @(posedge clk);

        clear_monitors();
        drive_fast_packet(16'h1235, 16'd32, 1'b0);
        repeat (4) @(posedge clk);
        record_result(
            fast_path_cnt == 32'd5 &&
            checksum_pass_cnt == 32'd4 &&
            seen_tx && seen_pbm && seen_meta && !seen_checksum && !meta_out_checksum_valid,
            "Eligible packet without checksum stayed on FastPath",
            $sformatf("Checksum-disabled fast path mismatch: fp_cnt=%0d cs_cnt=%0d seen_tx=%0d seen_pbm=%0d seen_meta=%0d seen_checksum=%0d meta_out_checksum_valid=%0d",
                      fast_path_cnt, checksum_pass_cnt, seen_tx, seen_pbm, seen_meta, seen_checksum, meta_out_checksum_valid)
        );

        clear_monitors();
        drive_fast_packet(16'h1235, 16'd32, 1'b1);
        drive_fast_packet(16'h1235, 16'd32, 1'b1);
        repeat (4) @(posedge clk);
        record_result(
            fast_path_cnt == 32'd7 &&
            checksum_pass_cnt == 32'd6,
            "Consecutive eligible packets accumulate counters correctly",
            $sformatf("Consecutive packet mismatch: fp_cnt=%0d cs_cnt=%0d", fast_path_cnt, checksum_pass_cnt)
        );

        clear_monitors();
        dst_port <= 16'h1235;
        payload_len <= 16'd32;
        drop_flag <= 1'b0;
        meta_valid <= 1'b1;
        ip_checksum <= 16'h1234;
        udp_checksum <= 16'h5678;
        checksum_valid <= 1'b1;
        s_axis_tdata <= 32'h0BAD_F00D;
        s_axis_tkeep <= 4'hF;
        s_axis_tlast <= 1'b0;
        s_axis_tvalid <= 1'b1;
        do @(posedge clk); while (!s_axis_tready);
        s_axis_tvalid <= 1'b0;
        repeat (4) @(posedge clk);
        record_result(
            fast_path_cnt == 32'd7 &&
            checksum_pass_cnt == 32'd6 &&
            fast_path_enable,
            "Transient valid drop does not complete packet early",
            $sformatf("Transient valid-drop mismatch before resume: fp_cnt=%0d cs_cnt=%0d fast_path_enable=%0d",
                      fast_path_cnt, checksum_pass_cnt, fast_path_enable)
        );
        s_axis_tdata <= 32'h0BAD_F00E;
        s_axis_tlast <= 1'b1;
        s_axis_tvalid <= 1'b1;
        do @(posedge clk); while (!s_axis_tready);
        clear_drive();
        repeat (4) @(posedge clk);
        record_result(
            fast_path_cnt == 32'd8 &&
            checksum_pass_cnt == 32'd7,
            "Transient valid drop packet completes after traffic resumes",
            $sformatf("Transient valid-drop mismatch after resume: fp_cnt=%0d cs_cnt=%0d",
                      fast_path_cnt, checksum_pass_cnt)
        );

        clear_monitors();
        dst_port <= 16'h1235;
        payload_len <= 16'd32;
        drop_flag <= 1'b0;
        meta_valid <= 1'b1;
        ip_checksum <= 16'h1234;
        udp_checksum <= 16'h5678;
        checksum_valid <= 1'b1;
        s_axis_tdata <= 32'hCA11_AB1E;
        s_axis_tkeep <= 4'hF;
        s_axis_tlast <= 1'b0;
        s_axis_tvalid <= 1'b1;
        do @(posedge clk); while (!s_axis_tready);
        rst_n <= 1'b0;
        repeat (2) @(posedge clk);
        rst_n <= 1'b1;
        clear_drive();
        repeat (4) @(posedge clk);
        record_result(
            fast_path_cnt == 32'd0 &&
            bypass_cnt == 32'd0 &&
            drop_cnt == 32'd0 &&
            checksum_pass_cnt == 32'd0 &&
            !fast_path_enable,
            "Mid-packet reset clears counters and returns to idle",
            $sformatf("Mid-packet reset mismatch: fp_cnt=%0d bypass_cnt=%0d drop_cnt=%0d cs_cnt=%0d fast_path_enable=%0d",
                      fast_path_cnt, bypass_cnt, drop_cnt, checksum_pass_cnt, fast_path_enable)
        );

        clear_monitors();
        drive_fast_packet(16'h1235, 16'd32, 1'b1);
        repeat (4) @(posedge clk);
        record_result(
            fast_path_cnt == 32'd1 &&
            checksum_pass_cnt == 32'd1 &&
            seen_tx && seen_pbm && seen_meta && seen_checksum,
            "FastPath recovers cleanly after mid-packet reset",
            $sformatf("Post-reset recovery mismatch: fp_cnt=%0d cs_cnt=%0d seen_tx=%0d seen_pbm=%0d seen_meta=%0d seen_checksum=%0d",
                      fast_path_cnt, checksum_pass_cnt, seen_tx, seen_pbm, seen_meta, seen_checksum)
        );

        $display("========================================");
        $display("Day 17 Test Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_pass + test_fail);
        $display("Passed:      %0d", test_pass);
        $display("Failed:      %0d", test_fail);

        if (test_fail != 0) begin
            $fatal(1, "Day 17 FastPath verification failed with %0d failing tests", test_fail);
        end

        $display("[PASS] All Day 17 FastPath tests passed under the current RTL contract");
        $finish;
    end

endmodule
