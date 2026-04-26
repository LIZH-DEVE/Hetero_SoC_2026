`timescale 1ns / 1ps

module tb_dma_gateway_hybrid_board_wrapper;

    localparam integer DATA_WIDTH = 32;
    localparam logic [15:0] UDP_PORT_AES = 16'd4660;
    localparam logic [15:0] UDP_PORT_BAD = 16'd9999;

    logic                  clk;
    logic                  rst_n;
    logic [DATA_WIDTH-1:0] s_axis_tdata;
    logic                  s_axis_tvalid;
    logic                  s_axis_tlast;
    logic                  s_axis_tready;
    logic [DATA_WIDTH-1:0] m_axis_dma_tdata;
    logic                  m_axis_dma_tvalid;
    logic                  m_axis_dma_tlast;
    logic                  m_axis_dma_terror;
    logic                  m_axis_dma_pkt_start;
    logic                  m_axis_dma_pkt_end;
    logic                  m_axis_dma_cbc_mode;
    logic [127:0]          m_axis_dma_iv_header;
    logic                  m_axis_dma_tready;
    logic [31:0]           drop_wrong_port_count;
    logic [31:0]           drop_unaligned_count;
    logic [31:0]           drop_cbc_length_invalid_count;
    logic                  dma_idle;

    logic                  dma_frame_active_q;
    logic [15:0]           ring_sw_tail_ptr_q;
    logic [15:0]           ring_hw_head_ptr_q;
    logic [31:0]           completion_count_q;

    udp_dma_ingress_classifier #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_diag_clear(1'b0),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .m_axis_dma_tdata(m_axis_dma_tdata),
        .m_axis_dma_tvalid(m_axis_dma_tvalid),
        .m_axis_dma_tlast(m_axis_dma_tlast),
        .m_axis_dma_terror(m_axis_dma_terror),
        .m_axis_dma_pkt_start(m_axis_dma_pkt_start),
        .m_axis_dma_pkt_end(m_axis_dma_pkt_end),
        .m_axis_dma_cbc_mode(m_axis_dma_cbc_mode),
        .m_axis_dma_iv_header(m_axis_dma_iv_header),
        .m_axis_dma_tready(m_axis_dma_tready),
        .o_drop_wrong_port_count(drop_wrong_port_count),
        .o_drop_unaligned_count(drop_unaligned_count),
        .o_drop_cbc_length_invalid_count(drop_cbc_length_invalid_count),
        .o_dma_idle(dma_idle)
    );

    always #5 clk = ~clk;

    // Model the ring/completion side effects that the hybrid wrapper must protect:
    // only accepted DMA payload traffic is allowed to move ring pointers or produce
    // a completion event.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_frame_active_q <= 1'b0;
            ring_sw_tail_ptr_q <= 16'd0;
            ring_hw_head_ptr_q <= 16'd0;
            completion_count_q <= 32'd0;
        end else if (m_axis_dma_tvalid && m_axis_dma_tready) begin
            if (!dma_frame_active_q) begin
                dma_frame_active_q <= 1'b1;
                ring_sw_tail_ptr_q <= ring_sw_tail_ptr_q + 16'd1;
            end
            if (m_axis_dma_tlast) begin
                dma_frame_active_q <= 1'b0;
                ring_hw_head_ptr_q <= ring_hw_head_ptr_q + 16'd1;
                completion_count_q <= completion_count_q + 32'd1;
            end
        end
    end

    task automatic drive_word(input logic [31:0] data_word, input logic last_word);
        begin
            @(posedge clk);
            s_axis_tdata  <= data_word;
            s_axis_tlast  <= last_word;
            s_axis_tvalid <= 1'b1;
            while (!s_axis_tready) begin
                @(posedge clk);
            end
            @(posedge clk);
            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
            s_axis_tdata  <= '0;
        end
    endtask

    task automatic drive_drop_word_wrong_port(input logic [31:0] data_word, input logic last_word);
        begin
            @(posedge clk);
            s_axis_tdata  <= data_word;
            s_axis_tlast  <= last_word;
            s_axis_tvalid <= 1'b1;
            while (!s_axis_tready) begin
                // DMA ingress must remain idle while wrong-port frame is drained
                if (m_axis_dma_tvalid !== 1'b0) begin
                    $fatal(1, "DMA ingress must remain idle while wrong-port frame is drained");
                end
                @(posedge clk);
            end
            if (m_axis_dma_tvalid !== 1'b0) begin
                $fatal(1, "DMA ingress must remain idle while wrong-port frame is drained");
            end
            @(posedge clk);
            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
            s_axis_tdata  <= '0;
        end
    endtask

    task automatic send_header_prefix(input logic [15:0] dst_port, input logic [15:0] udp_len);
        integer idx;
        logic [31:0] word_data;
        begin
            for (idx = 0; idx < 11; idx = idx + 1) begin
                word_data = 32'h0000_0000;
                case (idx)
                    3:  word_data = {16'h0800, 16'h0000};
                    9:  word_data = {dst_port, 16'h0000};
                    10: word_data = {16'h0000, udp_len};
                    default: begin
                    end
                endcase
                drive_word(word_data, 1'b0);
            end
        end
    endtask

    task automatic send_wrong_port_frame;
        logic [31:0] wrong_port_base;
        logic [31:0] unaligned_base;
        logic [15:0] sw_tail_base;
        logic [15:0] hw_head_base;
        logic [31:0] completion_base;
        begin
            wrong_port_base = drop_wrong_port_count;
            unaligned_base  = drop_unaligned_count;
            sw_tail_base    = ring_sw_tail_ptr_q;
            hw_head_base    = ring_hw_head_ptr_q;
            completion_base = completion_count_q;

            send_header_prefix(UDP_PORT_BAD, 16'd12);
            drive_drop_word_wrong_port(32'hDEAD_0001, 1'b1);
            repeat (2) @(posedge clk);

            if (drop_wrong_port_count != (wrong_port_base + 32'd1)) begin
                $fatal(1, "wrong-port defensive drop did not increment counter");
            end
            if (drop_unaligned_count != unaligned_base) begin
                $fatal(1, "wrong-port frame incremented unaligned counter");
            end
            if ((ring_sw_tail_ptr_q != sw_tail_base) || (ring_hw_head_ptr_q != hw_head_base)) begin
                $fatal(1, "wrong-port frame changed ring pointers");
            end
            if (completion_count_q != completion_base) begin
                $fatal(1, "wrong-port frame triggered completion");
            end
            $display("WRONG_PORT PASS drop_wrong_port_count=%0d", drop_wrong_port_count);
        end
    endtask

    task automatic send_unaligned_frame;
        logic [31:0] wrong_port_base;
        logic [31:0] unaligned_base;
        logic [15:0] sw_tail_base;
        logic [15:0] hw_head_base;
        logic [31:0] completion_base;
        begin
            wrong_port_base = drop_wrong_port_count;
            unaligned_base  = drop_unaligned_count;
            sw_tail_base    = ring_sw_tail_ptr_q;
            hw_head_base    = ring_hw_head_ptr_q;
            completion_base = completion_count_q;

            send_header_prefix(UDP_PORT_AES, 16'd10);
            drive_word(32'hCAFE_0001, 1'b1);
            repeat (2) @(posedge clk);

            if (drop_unaligned_count != (unaligned_base + 32'd1)) begin
                $fatal(1, "unaligned frame defensive drop did not increment counter");
            end
            if (drop_wrong_port_count != wrong_port_base) begin
                $fatal(1, "unaligned frame touched wrong-port counter");
            end
            if ((ring_sw_tail_ptr_q != sw_tail_base) || (ring_hw_head_ptr_q != hw_head_base)) begin
                $fatal(1, "unaligned frame changed ring pointers");
            end
            if (completion_count_q != completion_base) begin
                $fatal(1, "unaligned frame triggered completion");
            end
            $display("UNALIGNED_REJECT PASS drop_unaligned_count=%0d", drop_unaligned_count);
        end
    endtask

    initial begin
        clk            = 1'b0;
        rst_n          = 1'b0;
        s_axis_tdata   = '0;
        s_axis_tvalid  = 1'b0;
        s_axis_tlast   = 1'b0;
        m_axis_dma_tready = 1'b1;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        send_wrong_port_frame();
        send_unaligned_frame();

        $display("tb_dma_gateway_hybrid_board_wrapper PASS");
        $finish;
    end

endmodule
