`timescale 1ns / 1ps

module tb_all_features_verification;

    // Clock and Reset
    logic clk = 0;
    logic rst_n = 0;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        #100;
        rst_n = 1;
        #100;
        rst_n = 0;
    end

    // =========================================================
    // Test 1: Packet Dispatcher Verification
    // =========================================================
    logic [31:0] disp_in_data;
    logic        disp_in_valid, disp_in_last;
    logic [31:0] disp_out0_data, disp_out1_data;
    logic        disp_out0_valid, disp_out1_valid;
    logic        disp_out0_ready, disp_out1_ready;
    logic        disp_in_ready;
    logic [1:0] disp_mode;

    packet_dispatcher u_dispatcher (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(disp_in_data), .s_axis_tvalid(disp_in_valid),
        .s_axis_tlast(disp_in_last), .s_axis_tkeep(4'hF),
        .s_axis_tuser(1'b0), .s_axis_tready(disp_in_ready),
        .m_axis0_tdata(disp_out0_data), .m_axis0_tvalid(disp_out0_valid),
        .m_axis0_tlast(), .m_axis0_tkeep(),
        .m_axis0_tready(disp_out0_ready),
        .m_axis1_tdata(disp_out1_data), .m_axis1_tvalid(disp_out1_valid),
        .m_axis1_tlast(), .m_axis1_tkeep(),
        .m_axis1_tready(disp_out1_ready),
        .disp_mode(disp_mode)
    );

    // =========================================================
    // Test 2: Credit Manager Verification
    // =========================================================
    logic [31:0] cred_in_data, cred_out_data;
    logic        cred_in_valid, cred_out_valid;
    logic        credit_init, credit_update;
    logic [7:0]  credit_add, credit_set;
    logic [7:0] credit_avail;
    logic        credit_full, credit_empty;

    credit_manager #(.DATA_WIDTH(32), .CREDIT_WIDTH(8), .MAX_CREDITS(8'd16)) u_credit_mgr (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(cred_in_data), .s_axis_tvalid(cred_in_valid),
        .s_axis_tlast(1'b1), .s_axis_tkeep(4'hF),
        .m_axis_tdata(cred_out_data), .m_axis_tvalid(cred_out_valid),
        .m_axis_tlast(), .m_axis_tready(1'b1),
        .s_axis_tready(),
        .d_axis_tdata(), .d_axis_tvalid(), .d_axis_tlast(),
        .d_axis_tready(1'b1), .d_axis_tready(),
        .i_credit_init(credit_init), .i_credit_add(credit_add),
        .i_credit_set(credit_set), .i_credit_update(credit_update),
        .o_credit_avail(credit_avail), .o_credit_full(credit_full),
        .o_credit_empty(credit_empty)
    );

    // =========================================================
    // Test 3: ARP Responder Verification
    // =========================================================
    logic [31:0] arp_in_data, arp_out_data;
    logic        arp_in_valid, arp_out_valid;
    logic [47:0] local_mac = 48'h00_0A_35_00_01_02;
    logic [31:0] local_ip = 32'hC0_A8_01_0A;

    arp_responder u_arp (
        .clk(clk), .rst_n(rst_n),
        .i_arp_data(arp_in_data), .i_arp_valid(arp_in_valid),
        .i_arp_ready(),
        .o_tx_data(arp_out_data), .o_tx_valid(arp_out_valid),
        .o_tx_ready(1'b1),
        .i_local_mac(local_mac), .i_local_ip(local_ip),
        .i_arp_enable(1'b1)
    );

    // =========================================================
    // Test Sequence
    // =========================================================
    integer test_phase;

    initial begin
        #200;
        $display("========================================");
        $display("All Features Verification Testbench");
        $display("========================================");

        // Test 1: Dispatcher
        $display("[Phase 1] Testing Packet Dispatcher...");
        test_phase = 1;
        disp_mode = 2'b00; // tuser mode
        disp_in_data = 32'h12345678;
        disp_in_valid = 1;
        disp_in_last = 1;
        #200;
        if (disp_out1_valid) begin
            $display("[PASS] Dispatcher: tuser=1 -> path1 selected");
        end else begin
            $display("[FAIL] Dispatcher: path1 not selected");
        end
        #100;
        disp_in_valid = 0;

        // Test 2: Credit Manager
        #500;
        $display("[Phase 2] Testing Credit Manager...");
        test_phase = 2;
        credit_init = 1;
        #200;
        credit_init = 0;
        if (credit_avail == 8'd16) begin
            $display("[PASS] Credit Manager: initialized to 16 credits");
        end
        credit_add = 8'd1;
        #200;
        if (credit_avail == 8'd17) begin
            $display("[FAIL] Credit Manager: overflow");
        end
        credit_in_data = 32'hAABBCCDD;
        cred_in_valid = 1;
        #500;
        cred_in_valid = 0;
        #200;
        if (cred_out_valid) begin
            $display("[PASS] Credit Manager: data transferred");
        end

        // Test 3: ARP Responder
        #1000;
        $display("[Phase 3] Testing ARP Responder...");
        test_phase = 3;
        arp_in_data = 32'h00010800; // Hardware type = Ethernet
        arp_in_valid = 1;
        #200;
        arp_in_data = 32'h08000604; // Protocol type = IPv4
        #200;
        arp_in_data = 32'h04000604; // Hlen=6, Plen=4, Op=Request
        #200;
        arp_in_data = 32'h001234567; // Src MAC[31:0]
        #200;
        arp_in_data = 32'h89AB0000; // Src MAC[47:32]
        #200;
        arp_in_data = 32'hC0A8010A; // Src IP (192.168.1.10)
        #200;
        arp_in_data = 32'hC0A8010A; // Dst IP (192.168.1.10)
        #200;
        arp_in_valid = 0;
        #1000;
        if (arp_out_valid) begin
            $display("[PASS] ARP Responder: reply generated");
        end

        $display("========================================");
        $display("All Tests Completed!");
        $display("========================================");
        #1000;
        $finish;
    end

endmodule
