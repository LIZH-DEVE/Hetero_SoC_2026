`timescale 1ns / 1ps

module network_stage1_path (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        i_network_enable,
    input  logic        i_ingress_inject_sel,
    input  logic        i_arp_enable,
    input  logic [31:0] i_local_ip,
    input  logic [47:0] i_local_mac,

    input  logic        i_inj_clear,
    input  logic        i_inj_push,
    input  logic [31:0] i_inj_data,
    input  logic [15:0] i_inj_expected_words,
    output logic [31:0] o_inj_status,

    input  logic        i_txcap_clear,
    input  logic        i_txcap_pop,
    output logic [31:0] o_txcap_status,
    output logic [31:0] o_txcap_data,
    output logic [31:0] o_debug_status,

    input  logic        i_ext_rx_valid,
    input  logic [31:0] i_ext_rx_data,
    input  logic        i_ext_rx_last,
    output logic        o_ext_rx_ready,

    output logic [31:0] o_inject_tdata,
    output logic        o_inject_tvalid,
    output logic        o_inject_tlast,
    input  logic        i_inject_tready,

    output logic [31:0] o_tx_axis_tdata,
    output logic        o_tx_axis_tvalid,
    output logic        o_tx_axis_tlast,
    output logic [3:0]  o_tx_axis_tkeep
);

    localparam int INJ_DEPTH = 64;
    localparam int TXCAP_DEPTH = 64;

    logic [31:0] inj_data_mem [0:INJ_DEPTH-1];
    logic        inj_last_mem [0:INJ_DEPTH-1];
    logic [5:0]  inj_wr_ptr;
    logic [5:0]  inj_rd_ptr;
    logic [6:0]  inj_count;
    logic [15:0] inj_word_progress;
    logic        inj_overflow;
    logic        inj_done;
    logic        inj_packet_complete;

    logic [31:0] inj_tdata;
    logic        inj_tvalid;
    logic        inj_tlast;
    logic        inj_tready;

    logic [31:0] ingress_tdata;
    logic        ingress_tvalid;
    logic        ingress_tlast;
    logic        ingress_tready;

    logic [31:0] parser_pbm_wdata;
    logic        parser_pbm_wvalid;
    logic        parser_pbm_wlast;
    logic        parser_pbm_werror;
    logic        parser_pbm_ready;
    logic [15:0] parser_meta_data;
    logic        parser_meta_valid;
    logic [47:0] parser_src_mac;
    logic [31:0] parser_src_ip;
    logic [15:0] parser_src_port;
    logic        parser_rec_valid;
    logic [31:0] parser_arp_data;
    logic        parser_arp_valid;
    logic        parser_arp_ready;

    logic [31:0] net_pbm_data;
    logic        net_pbm_empty;
    logic        net_pbm_valid;
    logic        net_pbm_rd_en;

    logic        udp_tx_start;
    logic [15:0] udp_payload_len;
    logic [47:0] udp_dst_mac;
    logic [31:0] udp_dst_ip;
    logic [15:0] udp_dst_port;
    logic        udp_tx_done;
    logic        udp_tx_busy;
    logic [31:0] udp_tx_tdata;
    logic        udp_tx_tvalid;
    logic        udp_tx_tlast;
    logic [3:0]  udp_tx_tkeep;
    logic        udp_tx_tready;

    logic [31:0] arp_body_data;
    logic        arp_body_valid;
    logic        arp_body_ready;
    logic [47:0] arp_reply_dst_mac;
    logic [31:0] arp_tx_tdata;
    logic        arp_tx_tvalid;
    logic        arp_tx_tlast;
    logic [3:0]  arp_tx_tkeep;
    logic        arp_tx_tready;

    logic [31:0] tx_data_sel;
    logic        tx_valid_sel;
    logic        tx_last_sel;
    logic [3:0]  tx_keep_sel;
    logic        tx_ready_sel;

    logic [31:0] txcap_data_mem [0:TXCAP_DEPTH-1];
    logic [3:0]  txcap_keep_mem [0:TXCAP_DEPTH-1];
    logic        txcap_last_mem [0:TXCAP_DEPTH-1];
    logic [5:0]  txcap_wr_ptr;
    logic [5:0]  txcap_rd_ptr;
    logic [6:0]  txcap_count;
    logic        txcap_done;
    logic        txcap_overflow;
    logic        dbg_inj_push_seen;
    logic        dbg_inj_done_seen;
    logic        dbg_inj_fire_seen;
    logic        dbg_parser_arp_seen;
    logic        dbg_parser_pbm_seen;
    logic        dbg_parser_meta_seen;
    logic        dbg_udp_start_seen;
    logic        dbg_arp_body_seen;
    logic        dbg_arp_tx_seen;
    logic        dbg_udp_tx_seen;
    logic        dbg_txcap_write_seen;
    logic        dbg_txcap_done_seen;

    assign inj_tvalid = (inj_count != 0) && inj_packet_complete;
    assign inj_tdata = inj_data_mem[inj_rd_ptr];
    assign inj_tlast = inj_last_mem[inj_rd_ptr];

    assign ingress_tdata = i_ext_rx_data;
    assign ingress_tvalid = i_ext_rx_valid && i_network_enable && !i_ingress_inject_sel;
    assign ingress_tlast = i_ext_rx_last;
    assign inj_tready = i_network_enable && i_ingress_inject_sel && i_inject_tready;
    assign o_ext_rx_ready = i_network_enable && !i_ingress_inject_sel && ingress_tready;

    assign o_inject_tdata = inj_tdata;
    assign o_inject_tvalid = i_network_enable && i_ingress_inject_sel && inj_tvalid;
    assign o_inject_tlast = inj_tlast;

    assign o_inj_status = {13'd0, inj_overflow, inj_done, (inj_count != 0), 9'd0, inj_count};
    assign o_txcap_status = {13'd0, txcap_overflow, txcap_done, (txcap_count != 0), 9'd0, txcap_count};
    assign o_txcap_data = (txcap_count != 0) ? txcap_data_mem[txcap_rd_ptr] : 32'd0;
    assign o_debug_status = {
        20'd0,
        dbg_txcap_done_seen,
        dbg_txcap_write_seen,
        dbg_udp_tx_seen,
        dbg_arp_tx_seen,
        dbg_arp_body_seen,
        dbg_udp_start_seen,
        dbg_parser_meta_seen,
        dbg_parser_pbm_seen,
        dbg_parser_arp_seen,
        dbg_inj_fire_seen,
        dbg_inj_done_seen,
        dbg_inj_push_seen,
        i_ingress_inject_sel,
        i_network_enable
    };

    assign tx_ready_sel = i_network_enable && (txcap_count < TXCAP_DEPTH);

    assign tx_data_sel  = arp_tx_tvalid ? arp_tx_tdata  : udp_tx_tdata;
    assign tx_valid_sel = arp_tx_tvalid ? arp_tx_tvalid : udp_tx_tvalid;
    assign tx_last_sel  = arp_tx_tvalid ? arp_tx_tlast  : udp_tx_tlast;
    assign tx_keep_sel  = arp_tx_tvalid ? arp_tx_tkeep  : udp_tx_tkeep;
    assign arp_tx_tready = tx_ready_sel;
    assign udp_tx_tready = tx_ready_sel && !arp_tx_tvalid;

    assign o_tx_axis_tdata  = tx_data_sel;
    assign o_tx_axis_tvalid = i_network_enable && tx_valid_sel;
    assign o_tx_axis_tlast  = i_network_enable && tx_last_sel;
    assign o_tx_axis_tkeep  = tx_keep_sel;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inj_wr_ptr <= '0;
            inj_rd_ptr <= '0;
            inj_count <= '0;
            inj_word_progress <= '0;
            inj_overflow <= 1'b0;
            inj_done <= 1'b0;
            inj_packet_complete <= 1'b0;
            dbg_inj_push_seen <= 1'b0;
            dbg_inj_done_seen <= 1'b0;
            dbg_inj_fire_seen <= 1'b0;
        end else begin
            inj_done <= 1'b0;
            if (!i_network_enable || i_inj_clear) begin
                inj_wr_ptr <= '0;
                inj_rd_ptr <= '0;
                inj_count <= '0;
                inj_word_progress <= '0;
                inj_overflow <= 1'b0;
                inj_packet_complete <= 1'b0;
                dbg_inj_push_seen <= 1'b0;
                dbg_inj_done_seen <= 1'b0;
                dbg_inj_fire_seen <= 1'b0;
            end else begin
                if (i_inj_push) begin
                    dbg_inj_push_seen <= 1'b1;
                    if (inj_count < INJ_DEPTH) begin
                        inj_data_mem[inj_wr_ptr] <= i_inj_data;
                        inj_last_mem[inj_wr_ptr] <= (i_inj_expected_words != 16'd0) &&
                                                    (inj_word_progress + 16'd1 == i_inj_expected_words);
                        inj_wr_ptr <= inj_wr_ptr + 6'd1;
                        inj_count <= inj_count + 7'd1;
                        if ((i_inj_expected_words != 16'd0) &&
                            (inj_word_progress + 16'd1 == i_inj_expected_words)) begin
                            inj_word_progress <= 16'd0;
                            inj_done <= 1'b1;
                            inj_packet_complete <= 1'b1;
                            dbg_inj_done_seen <= 1'b1;
                        end else begin
                            inj_word_progress <= inj_word_progress + 16'd1;
                        end
                    end else begin
                        inj_overflow <= 1'b1;
                    end
                end

                if (inj_tvalid && inj_tready) begin
                    dbg_inj_fire_seen <= 1'b1;
                    inj_rd_ptr <= inj_rd_ptr + 6'd1;
                    inj_count <= inj_count - 7'd1;
                    if (inj_tlast) begin
                        inj_packet_complete <= 1'b0;
                    end
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            udp_tx_start <= 1'b0;
            udp_payload_len <= 16'd0;
            udp_dst_mac <= 48'd0;
            udp_dst_ip <= 32'd0;
            udp_dst_port <= 16'd0;
            dbg_parser_meta_seen <= 1'b0;
            dbg_udp_start_seen <= 1'b0;
        end else begin
            udp_tx_start <= 1'b0;
            if (!i_network_enable) begin
                udp_payload_len <= 16'd0;
                udp_dst_mac <= 48'd0;
                udp_dst_ip <= 32'd0;
                udp_dst_port <= 16'd0;
                dbg_parser_meta_seen <= 1'b0;
                dbg_udp_start_seen <= 1'b0;
            end else if (parser_meta_valid && parser_rec_valid) begin
                dbg_parser_meta_seen <= 1'b1;
                udp_payload_len <= parser_meta_data;
                udp_dst_mac <= parser_src_mac;
                udp_dst_ip <= parser_src_ip;
                udp_dst_port <= parser_src_port;
                udp_tx_start <= 1'b1;
                dbg_udp_start_seen <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            txcap_wr_ptr <= '0;
            txcap_rd_ptr <= '0;
            txcap_count <= '0;
            txcap_done <= 1'b0;
            txcap_overflow <= 1'b0;
            dbg_txcap_write_seen <= 1'b0;
            dbg_txcap_done_seen <= 1'b0;
        end else begin
            txcap_done <= 1'b0;
            if (!i_network_enable || i_txcap_clear) begin
                txcap_wr_ptr <= '0;
                txcap_rd_ptr <= '0;
                txcap_count <= '0;
                txcap_done <= 1'b0;
                txcap_overflow <= 1'b0;
                dbg_txcap_write_seen <= 1'b0;
                dbg_txcap_done_seen <= 1'b0;
            end else begin
                if (tx_valid_sel && tx_ready_sel) begin
                    dbg_txcap_write_seen <= 1'b1;
                    if (txcap_count < TXCAP_DEPTH) begin
                        txcap_data_mem[txcap_wr_ptr] <= tx_data_sel;
                        txcap_keep_mem[txcap_wr_ptr] <= tx_keep_sel;
                        txcap_last_mem[txcap_wr_ptr] <= tx_last_sel;
                        txcap_wr_ptr <= txcap_wr_ptr + 6'd1;
                        txcap_count <= txcap_count + 7'd1;
                        if (tx_last_sel) begin
                            txcap_done <= 1'b1;
                            dbg_txcap_done_seen <= 1'b1;
                        end
                    end else begin
                        txcap_overflow <= 1'b1;
                    end
                end

                if (i_txcap_pop && (txcap_count != 0)) begin
                    txcap_rd_ptr <= txcap_rd_ptr + 6'd1;
                    txcap_count <= txcap_count - 7'd1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_parser_arp_seen <= 1'b0;
            dbg_parser_pbm_seen <= 1'b0;
            dbg_arp_body_seen <= 1'b0;
            dbg_arp_tx_seen <= 1'b0;
            dbg_udp_tx_seen <= 1'b0;
        end else if (!i_network_enable || i_inj_clear || i_txcap_clear) begin
            dbg_parser_arp_seen <= 1'b0;
            dbg_parser_pbm_seen <= 1'b0;
            dbg_arp_body_seen <= 1'b0;
            dbg_arp_tx_seen <= 1'b0;
            dbg_udp_tx_seen <= 1'b0;
        end else begin
            if (parser_arp_valid) begin
                dbg_parser_arp_seen <= 1'b1;
            end
            if (parser_pbm_wvalid) begin
                dbg_parser_pbm_seen <= 1'b1;
            end
            if (arp_body_valid) begin
                dbg_arp_body_seen <= 1'b1;
            end
            if (arp_tx_tvalid) begin
                dbg_arp_tx_seen <= 1'b1;
            end
            if (udp_tx_tvalid) begin
                dbg_udp_tx_seen <= 1'b1;
            end
        end
    end

    rx_parser u_rx_parser (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(ingress_tdata),
        .s_axis_tvalid(ingress_tvalid),
        .s_axis_tlast(ingress_tlast),
        .s_axis_tuser(1'b0),
        .s_axis_tready(ingress_tready),
        .o_pbm_wdata(parser_pbm_wdata),
        .o_pbm_wvalid(parser_pbm_wvalid),
        .o_pbm_wlast(parser_pbm_wlast),
        .o_pbm_werror(parser_pbm_werror),
        .i_pbm_ready(parser_pbm_ready),
        .o_meta_data(parser_meta_data),
        .o_meta_valid(parser_meta_valid),
        .i_meta_ready(1'b1),
        .o_rec_src_mac(parser_src_mac),
        .o_rec_src_ip(parser_src_ip),
        .o_rec_src_port(parser_src_port),
        .o_rec_valid(parser_rec_valid),
        .o_arp_data(parser_arp_data),
        .o_arp_valid(parser_arp_valid),
        .i_arp_ready(parser_arp_ready)
    );

    pbm_controller #(
        .PBM_ADDR_WIDTH(14),
        .DATA_WIDTH(32)
    ) u_net_pbm (
        .clk(clk),
        .rst_n(rst_n),
        .i_wr_valid(i_network_enable && parser_pbm_wvalid),
        .i_wr_data(parser_pbm_wdata),
        .i_wr_last(parser_pbm_wlast),
        .i_wr_error(parser_pbm_werror),
        .o_wr_ready(parser_pbm_ready),
        .i_rd_en(net_pbm_rd_en),
        .o_rd_data(net_pbm_data),
        .o_rd_valid(net_pbm_valid),
        .o_rd_empty(net_pbm_empty),
        .o_buffer_usage(),
        .o_rollback_active()
    );

    arp_responder u_arp_responder (
        .clk(clk),
        .rst_n(rst_n),
        .i_arp_data(parser_arp_data),
        .i_arp_valid(i_network_enable && parser_arp_valid),
        .i_arp_ready(parser_arp_ready),
        .o_tx_data(arp_body_data),
        .o_tx_valid(arp_body_valid),
        .o_tx_ready(arp_body_ready),
        .o_reply_dst_mac(arp_reply_dst_mac),
        .i_local_mac(i_local_mac),
        .i_local_ip(i_local_ip),
        .i_arp_enable(i_arp_enable)
    );

    arp_tx_framer u_arp_tx_framer (
        .clk(clk),
        .rst_n(rst_n),
        .i_body_data(arp_body_data),
        .i_body_valid(arp_body_valid),
        .i_body_ready(arp_body_ready),
        .i_dst_mac(arp_reply_dst_mac),
        .i_src_mac(i_local_mac),
        .m_axis_tdata(arp_tx_tdata),
        .m_axis_tvalid(arp_tx_tvalid),
        .m_axis_tlast(arp_tx_tlast),
        .m_axis_tkeep(arp_tx_tkeep),
        .m_axis_tready(arp_tx_tready)
    );

    tx_stack u_tx_stack (
        .clk(clk),
        .rst_n(rst_n),
        .i_tx_start(udp_tx_start),
        .i_payload_len(udp_payload_len),
        .i_dst_mac(udp_dst_mac),
        .i_dst_ip(udp_dst_ip),
        .i_dst_port(udp_dst_port),
        .i_local_mac(i_local_mac),
        .i_local_ip(i_local_ip),
        .o_tx_done(udp_tx_done),
        .o_tx_busy(udp_tx_busy),
        .o_pbm_addr(),
        .o_pbm_ren(net_pbm_rd_en),
        .i_pbm_rdata(net_pbm_data),
        .m_axis_tdata(udp_tx_tdata),
        .m_axis_tvalid(udp_tx_tvalid),
        .m_axis_tlast(udp_tx_tlast),
        .m_axis_tkeep(udp_tx_tkeep),
        .m_axis_tready(udp_tx_tready)
    );

endmodule
