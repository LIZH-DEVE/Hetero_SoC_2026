`timescale 1ns / 1ps

module tb_day18_robustness;

    localparam int AXI_DATA_WIDTH = 32;
    localparam int PBM_ADDR_WIDTH = 14;
    localparam int GIANT_PAYLOAD_WORDS = 376; // 1504-byte payload => >1518B Ethernet frame

    logic clk;
    logic rst_n;

    logic [AXI_DATA_WIDTH-1:0] rx_tdata;
    logic                      rx_tvalid;
    logic                      rx_tlast;
    logic                      rx_tuser;
    logic                      rx_tready;

    logic [AXI_DATA_WIDTH-1:0] pbm_wdata;
    logic                      pbm_wvalid;
    logic                      pbm_wlast;
    logic                      pbm_werror;
    logic                      pbm_wready;

    logic [15:0]               meta_data;
    logic                      meta_valid;
    logic                      meta_ready;

    logic [47:0]               rec_src_mac;
    logic [31:0]               rec_src_ip;
    logic [15:0]               rec_src_port;
    logic                      rec_valid;

    logic [31:0]               arp_data;
    logic                      arp_valid;
    logic                      arp_ready;

    logic [PBM_ADDR_WIDTH:0]   pbm_usage;
    logic                      pbm_rollback_active;

    logic                      clear_monitors_req;
    logic                      meta_seen;
    logic                      rec_seen;
    logic                      rollback_seen;
    integer                    pbm_write_beats;
    integer                    test_pass;
    integer                    test_fail;
    integer                    runt_cnt;
    integer                    giant_cnt;
    integer                    bad_align_cnt;
    integer                    malformed_cnt;
    integer                    rollback_cnt;

    rx_parser #(
        .DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_rx_parser (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axis_tdata   (rx_tdata),
        .s_axis_tvalid  (rx_tvalid),
        .s_axis_tlast   (rx_tlast),
        .s_axis_tuser   (rx_tuser),
        .s_axis_tready  (rx_tready),
        .o_pbm_wdata    (pbm_wdata),
        .o_pbm_wvalid   (pbm_wvalid),
        .o_pbm_wlast    (pbm_wlast),
        .o_pbm_werror   (pbm_werror),
        .i_pbm_ready    (pbm_wready),
        .o_meta_data    (meta_data),
        .o_meta_valid   (meta_valid),
        .i_meta_ready   (meta_ready),
        .o_rec_src_mac  (rec_src_mac),
        .o_rec_src_ip   (rec_src_ip),
        .o_rec_src_port (rec_src_port),
        .o_rec_valid    (rec_valid),
        .o_arp_data     (arp_data),
        .o_arp_valid    (arp_valid),
        .i_arp_ready    (arp_ready)
    );

    pbm_controller #(
        .PBM_ADDR_WIDTH(PBM_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_pbm (
        .clk               (clk),
        .rst_n             (rst_n),
        .i_wr_valid        (pbm_wvalid),
        .i_wr_data         (pbm_wdata),
        .i_wr_last         (pbm_wlast),
        .i_wr_error        (pbm_werror),
        .o_wr_ready        (pbm_wready),
        .i_rd_en           (1'b0),
        .o_rd_data         (),
        .o_rd_valid        (),
        .o_rd_empty        (),
        .o_buffer_usage    (pbm_usage),
        .o_rollback_active (pbm_rollback_active)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta_seen <= 1'b0;
            rec_seen <= 1'b0;
            rollback_seen <= 1'b0;
            pbm_write_beats <= 0;
        end else if (clear_monitors_req) begin
            meta_seen <= 1'b0;
            rec_seen <= 1'b0;
            rollback_seen <= 1'b0;
            pbm_write_beats <= 0;
        end else begin
            if (meta_valid) begin
                meta_seen <= 1'b1;
            end
            if (rec_valid) begin
                rec_seen <= 1'b1;
            end
            if (pbm_rollback_active) begin
                rollback_seen <= 1'b1;
            end
            if (pbm_wvalid && pbm_wready) begin
                pbm_write_beats <= pbm_write_beats + 1;
            end
        end
    end

    task automatic clear_drive;
        begin
            rx_tdata <= '0;
            rx_tvalid <= 1'b0;
            rx_tlast <= 1'b0;
            rx_tuser <= 1'b0;
        end
    endtask

    task automatic clear_monitors_and_wait;
        begin
            clear_monitors_req <= 1'b1;
            @(posedge clk);
            clear_monitors_req <= 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic pulse_reset;
        begin
            rst_n <= 1'b0;
            clear_monitors_req <= 1'b1;
            clear_drive();
            repeat (4) @(posedge clk);
            rst_n <= 1'b1;
            clear_monitors_req <= 1'b0;
            repeat (4) @(posedge clk);
        end
    endtask

    task automatic wait_pipeline_idle;
        integer idle_cycles;
        begin
            idle_cycles = 0;
            while (idle_cycles < 12) begin
                @(posedge clk);
                if (!rx_tvalid && !pbm_wvalid && !meta_valid && !rec_valid && !pbm_rollback_active) begin
                    idle_cycles = idle_cycles + 1;
                end else begin
                    idle_cycles = 0;
                end
            end
        end
    endtask

    task automatic drive_word(
        input [31:0] word,
        input        is_last,
        input        is_error
    );
        begin
            @(negedge clk);
            rx_tdata <= word;
            rx_tvalid <= 1'b1;
            rx_tlast <= is_last;
            rx_tuser <= is_error;
            @(posedge clk);
            while (!rx_tready) @(posedge clk);
            @(negedge clk);
            clear_drive();
        end
    endtask

    task automatic send_ipv4_udp_frame(
        input [15:0] ip_total_len,
        input [15:0] udp_len,
        input integer payload_words,
        input [31:0] payload_base,
        input bit error_on_last
    );
        integer i;
        bit final_is_header;
        begin
            final_is_header = (payload_words == 0);

            drive_word(32'hFFFF_FFFF, 1'b0, 1'b0); // dst mac [47:16]
            drive_word(32'hFFFF_000A, 1'b0, 1'b0); // dst[15:0], src[47:32]
            drive_word(32'h3500_0102, 1'b0, 1'b0); // src[31:0]
            drive_word(32'h0800_0000, 1'b0, 1'b0); // eth_type in [31:16]

            drive_word({ip_total_len, 12'h000, 4'd5}, 1'b0, 1'b0);
            drive_word(32'h0000_1234, 1'b0, 1'b0);
            drive_word(32'h0000_4011, 1'b0, 1'b0);
            drive_word(32'h0000_C0A8, 1'b0, 1'b0); // src ip [31:16] in low half
            drive_word(32'h010A_0000, 1'b0, 1'b0); // src ip [15:0] in high half
            drive_word(32'h5678_1234, 1'b0, 1'b0); // src port in low half
            drive_word({16'h0000, udp_len}, final_is_header, final_is_header && error_on_last);

            for (i = 0; i < payload_words; i = i + 1) begin
                drive_word(payload_base ^ i, (i == payload_words - 1), (i == payload_words - 1) && error_on_last);
            end
        end
    endtask

    task automatic record_result(
        input bit condition,
        input string pass_msg,
        input string fail_msg
    );
        begin
            if (condition) begin
                $display("[PASS] %s", pass_msg);
                test_pass = test_pass + 1;
            end else begin
                $display("[FAIL] %s", fail_msg);
                test_fail = test_fail + 1;
            end
        end
    endtask

    initial begin
        test_pass = 0;
        test_fail = 0;
        runt_cnt = 0;
        giant_cnt = 0;
        bad_align_cnt = 0;
        malformed_cnt = 0;
        rollback_cnt = 0;
        clear_monitors_req = 1'b0;
        meta_ready = 1'b1;
        arp_ready = 1'b1;
        clear_drive();

        $display("========================================");
        $display("Day 18: Robustness Verification");
        $display("========================================");

        // Test 1: runt frame requirement
        pulse_reset();
        send_ipv4_udp_frame(16'd44, 16'd24, 4, 32'h1111_0000, 1'b0); // 58B Ethernet frame
        wait_pipeline_idle();
        record_result(!meta_seen && pbm_write_beats == 0,
                      "Runt frame dropped",
                      $sformatf("Runt frame accepted under current RTL: meta_seen=%0d pbm_write_beats=%0d",
                                meta_seen, pbm_write_beats));
        if (!meta_seen && pbm_write_beats == 0) runt_cnt = runt_cnt + 1;

        // Test 2: giant frame requirement
        pulse_reset();
        send_ipv4_udp_frame(16'd1532, 16'd1512, GIANT_PAYLOAD_WORDS, 32'h2222_0000, 1'b0);
        wait_pipeline_idle();
        record_result(!meta_seen && pbm_write_beats == 0,
                      "Giant frame dropped",
                      $sformatf("Giant frame accepted under current RTL: meta_seen=%0d pbm_write_beats=%0d",
                                meta_seen, pbm_write_beats));
        if (!meta_seen && pbm_write_beats == 0) giant_cnt = giant_cnt + 1;

        // Test 3: bad alignment
        pulse_reset();
        send_ipv4_udp_frame(16'd40, 16'd20, 3, 32'h3333_0000, 1'b0);
        wait_pipeline_idle();
        record_result(!meta_seen && pbm_write_beats == 0,
                      "Bad alignment frame dropped",
                      $sformatf("Bad alignment frame was not dropped: meta_seen=%0d pbm_write_beats=%0d",
                                meta_seen, pbm_write_beats));
        if (!meta_seen && pbm_write_beats == 0) bad_align_cnt = bad_align_cnt + 1;

        // Test 4: malformed header
        pulse_reset();
        send_ipv4_udp_frame(16'd40, 16'd40, 8, 32'h4444_0000, 1'b0);
        wait_pipeline_idle();
        record_result(!meta_seen && pbm_write_beats == 0,
                      "Malformed frame dropped",
                      $sformatf("Malformed frame was not dropped: meta_seen=%0d pbm_write_beats=%0d",
                                meta_seen, pbm_write_beats));
        if (!meta_seen && pbm_write_beats == 0) malformed_cnt = malformed_cnt + 1;

        // Test 5: normal aligned packet
        pulse_reset();
        send_ipv4_udp_frame(16'd60, 16'd40, 8, 32'h5555_0000, 1'b0);
        wait_pipeline_idle();
        record_result(meta_seen && rec_seen && pbm_write_beats == 8 && !rollback_seen && meta_data == 16'd32,
                      "Normal aligned packet accepted without rollback",
                      $sformatf("Normal packet handling mismatch: meta_seen=%0d rec_seen=%0d pbm_write_beats=%0d rollback_seen=%0d meta_data=%0d",
                                meta_seen, rec_seen, pbm_write_beats, rollback_seen, meta_data));

        // Test 6: rollback on MAC error during final payload beat
        pulse_reset();
        send_ipv4_udp_frame(16'd60, 16'd40, 8, 32'h6666_0000, 1'b1);
        wait_pipeline_idle();
        record_result(rollback_seen && !meta_seen && pbm_usage == 0,
                      "PBM rollback triggered on write error",
                      $sformatf("Rollback path mismatch: rollback_seen=%0d meta_seen=%0d pbm_usage=%0d pbm_write_beats=%0d",
                                rollback_seen, meta_seen, pbm_usage, pbm_write_beats));
        if (rollback_seen && !meta_seen && pbm_usage == 0) rollback_cnt = rollback_cnt + 1;

        $display("========================================");
        $display("Day 18 Test Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_pass + test_fail);
        $display("Passed:      %0d", test_pass);
        $display("Failed:      %0d", test_fail);
        $display("Runt Drops:  %0d", runt_cnt);
        $display("Giant Drops: %0d", giant_cnt);
        $display("Bad Align:   %0d", bad_align_cnt);
        $display("Malformed:   %0d", malformed_cnt);
        $display("Rollback:    %0d", rollback_cnt);
        $display("========================================");

        #100;
        $finish;
    end

endmodule
