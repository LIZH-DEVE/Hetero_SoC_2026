`timescale 1ns / 1ps

module dma_raw_copy_engine #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter FIFO_DEPTH = dma_csr_pkg::DMA_RAW_COPY_FIFO_DEPTH
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    i_soft_reset,
    input  logic                    i_start,
    input  logic                    i_stream_tlast,
    input  logic [DATA_WIDTH-1:0]   s_axis_tdata,
    input  logic                    s_axis_tvalid,
    output logic                    s_axis_tready,
    input  logic                    s_axis_tlast,
    input  logic [ADDR_WIDTH-1:0]   i_src_addr,
    input  logic [ADDR_WIDTH-1:0]   i_dst_addr,
    input  logic [31:0]             i_total_len,
    output logic [31:0]             o_actual_len,
    output logic                    o_done,
    output logic                    o_error,
    output logic                    o_busy,
    output logic [1:0]              o_bresp,

    output logic [ADDR_WIDTH-1:0]   m_axi_araddr,
    output logic [7:0]              m_axi_arlen,
    output logic [2:0]              m_axi_arsize,
    output logic [1:0]              m_axi_arburst,
    output logic                    m_axi_arvalid,
    input  logic                    m_axi_arready,
    input  logic [DATA_WIDTH-1:0]   m_axi_rdata,
    input  logic [1:0]              m_axi_rresp,
    input  logic                    m_axi_rlast,
    input  logic                    m_axi_rvalid,
    output logic                    m_axi_rready,

    output logic [ADDR_WIDTH-1:0]   m_axi_awaddr,
    output logic [7:0]              m_axi_awlen,
    output logic [2:0]              m_axi_awsize,
    output logic [1:0]              m_axi_awburst,
    output logic [3:0]              m_axi_awcache,
    output logic [2:0]              m_axi_awprot,
    output logic                    m_axi_awvalid,
    input  logic                    m_axi_awready,
    output logic [DATA_WIDTH-1:0]   m_axi_wdata,
    output logic [DATA_WIDTH/8-1:0] m_axi_wstrb,
    output logic                    m_axi_wlast,
    output logic                    m_axi_wvalid,
    input  logic                    m_axi_wready,
    input  logic [1:0]              m_axi_bresp,
    input  logic                    m_axi_bvalid,
    output logic                    m_axi_bready
);

    import dma_csr_pkg::*;

    localparam integer BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam [2:0] AXI_SIZE_WORD = (DATA_WIDTH == 32) ? 3'b010 : 3'b011;
    localparam integer ALIGNMENT_LSB = $clog2(DMA_ALIGNMENT_BYTES);

    typedef enum logic [1:0] {
        READ_IDLE,
        READ_ADDR,
        READ_DATA
    } read_state_t;

    typedef enum logic [1:0] {
        WRITE_IDLE,
        WRITE_ADDR,
        WRITE_DATA,
        WRITE_RESP
    } write_state_t;

    read_state_t  read_state;
    write_state_t write_state;

    logic                    active_q;
    logic                    fifo_flush_q;
    logic [ADDR_WIDTH-1:0]   src_addr_q;
    logic [ADDR_WIDTH-1:0]   dst_addr_q;
    logic [31:0]             total_len_q;
    logic                    stream_tlast_q;
    logic [31:0]             bytes_read_q;
    logic [31:0]             bytes_written_q;
    logic [ADDR_WIDTH-1:0]   read_addr_q;
    logic [ADDR_WIDTH-1:0]   write_addr_q;
    logic                    write_resp_pending_last;
    logic                    stream_missing_tlast_q;
    logic                    stream_ingress_closed_q;
    logic                    stream_drain_to_tlast_q;

    logic                    fifo_s_tready;
    logic [DATA_WIDTH-1:0]   fifo_s_tdata;
    logic                    fifo_s_tvalid;
    logic                    fifo_s_tlast;
    logic [DATA_WIDTH-1:0]   fifo_m_tdata;
    logic                    fifo_m_tvalid;
    logic                    fifo_m_tlast;
    logic                    fifo_m_tready;
    logic                    fifo_empty;
    logic                    fifo_full;
    logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_level;
    logic                    axis_rst_n;
    logic                    stream_mode_active;
    logic                    stream_input_fire;
    logic                    stream_drain_fire;
    logic                    stream_terminal_beat;
    logic                    fixed_fifo_last;

    assign axis_rst_n = rst_n;
    assign stream_mode_active = active_q && stream_tlast_q;
    assign stream_terminal_beat = s_axis_tlast || ((bytes_read_q + BYTES_PER_BEAT) >= total_len_q);
    assign stream_input_fire = stream_mode_active && !stream_ingress_closed_q && s_axis_tvalid && s_axis_tready;
    assign stream_drain_fire = stream_tlast_q && stream_drain_to_tlast_q && s_axis_tvalid && s_axis_tready;
    assign fixed_fifo_last = (bytes_read_q + BYTES_PER_BEAT >= total_len_q);

    assign fifo_s_tdata  = stream_tlast_q ? s_axis_tdata : m_axi_rdata;
    assign fifo_s_tvalid = stream_tlast_q ?
                           (stream_mode_active && !stream_ingress_closed_q && s_axis_tvalid) :
                           ((read_state == READ_DATA) && m_axi_rvalid && (m_axi_rresp == 2'b00));
    assign fifo_s_tlast  = stream_tlast_q ? stream_terminal_beat : fixed_fifo_last;
    assign s_axis_tready = stream_tlast_q && (active_q || stream_drain_to_tlast_q) ?
                           (stream_drain_to_tlast_q ? 1'b1 :
                            (!stream_ingress_closed_q ? fifo_s_tready : 1'b0)) :
                           1'b0;
    assign o_busy = active_q || stream_drain_to_tlast_q;

    assign m_axi_araddr  = read_addr_q;
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = AXI_SIZE_WORD;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arvalid = (read_state == READ_ADDR) && !fifo_full;
    assign m_axi_rready  = (read_state == READ_DATA) && fifo_s_tready;

    assign m_axi_awaddr  = write_addr_q;
    assign m_axi_awlen   = 8'd0;
    assign m_axi_awsize  = AXI_SIZE_WORD;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awvalid = (write_state == WRITE_ADDR) && fifo_m_tvalid;

    assign m_axi_wdata   = fifo_m_tdata;
    assign m_axi_wstrb   = {DATA_WIDTH/8{1'b1}};
    assign m_axi_wlast   = 1'b1;
    assign m_axi_wvalid  = (write_state == WRITE_DATA) && fifo_m_tvalid;
    assign fifo_m_tready = (write_state == WRITE_DATA) && m_axi_wready && fifo_m_tvalid;

    assign m_axi_bready  = (write_state == WRITE_RESP);
    assign o_actual_len  = bytes_written_q +
                           (((write_state == WRITE_RESP) &&
                             m_axi_bvalid &&
                             m_axi_bready &&
                             (m_axi_bresp == 2'b00)) ? BYTES_PER_BEAT : 32'd0);

    dma_axis_fifo_wrapper #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_axis_fifo (
        .clk(clk),
        .axis_rst_n(axis_rst_n),
        .i_clear(i_soft_reset || fifo_flush_q),
        .s_axis_tdata(fifo_s_tdata),
        .s_axis_tvalid(fifo_s_tvalid),
        .s_axis_tlast(fifo_s_tlast),
        .s_axis_tready(fifo_s_tready),
        .m_axis_tdata(fifo_m_tdata),
        .m_axis_tvalid(fifo_m_tvalid),
        .m_axis_tlast(fifo_m_tlast),
        .m_axis_tready(fifo_m_tready),
        .o_empty(fifo_empty),
        .o_full(fifo_full),
        .o_level(fifo_level)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_state <= READ_IDLE;
            write_state <= WRITE_IDLE;
            active_q <= 1'b0;
            fifo_flush_q <= 1'b0;
            src_addr_q <= '0;
            dst_addr_q <= '0;
            total_len_q <= '0;
            stream_tlast_q <= 1'b0;
            bytes_read_q <= '0;
            bytes_written_q <= '0;
            read_addr_q <= '0;
            write_addr_q <= '0;
            write_resp_pending_last <= 1'b0;
            stream_missing_tlast_q <= 1'b0;
            stream_ingress_closed_q <= 1'b0;
            o_done <= 1'b0;
            o_error <= 1'b0;
            o_bresp <= 2'b00;
            stream_drain_to_tlast_q <= 1'b0;
        end else begin
            o_done <= 1'b0;
            o_error <= 1'b0;
            fifo_flush_q <= 1'b0;

            if (i_soft_reset) begin
                read_state <= READ_IDLE;
                write_state <= WRITE_IDLE;
                active_q <= 1'b0;
                bytes_read_q <= '0;
                bytes_written_q <= '0;
                stream_tlast_q <= 1'b0;
                read_addr_q <= '0;
                write_addr_q <= '0;
                write_resp_pending_last <= 1'b0;
                stream_missing_tlast_q <= 1'b0;
                stream_ingress_closed_q <= 1'b0;
                o_bresp <= 2'b00;
                stream_drain_to_tlast_q <= 1'b0;
            end else begin
                if (!active_q && !stream_drain_to_tlast_q && i_start) begin
                    if ((i_total_len == 0) ||
                        (!i_stream_tlast &&
                         ((i_total_len % DMA_RAW_COPY_LEN_MULTIPLE) != 0)) ||
                        ((i_total_len % BYTES_PER_BEAT) != 0) ||
                        (!i_stream_tlast && (i_src_addr[ALIGNMENT_LSB-1:0] != '0)) ||
                        (i_dst_addr[ALIGNMENT_LSB-1:0] != '0)) begin
                        o_error <= 1'b1;
                        o_bresp <= 2'b00;
                        fifo_flush_q <= 1'b1;
                    end else begin
                        active_q <= 1'b1;
                        src_addr_q <= i_src_addr;
                        dst_addr_q <= i_dst_addr;
                        total_len_q <= i_total_len;
                        stream_tlast_q <= i_stream_tlast;
                        bytes_read_q <= 32'd0;
                        bytes_written_q <= 32'd0;
                        read_addr_q <= i_src_addr;
                        write_addr_q <= i_dst_addr;
                        read_state <= i_stream_tlast ? READ_IDLE : READ_ADDR;
                        write_state <= WRITE_IDLE;
                        write_resp_pending_last <= 1'b0;
                        stream_missing_tlast_q <= 1'b0;
                        stream_ingress_closed_q <= 1'b0;
                        o_bresp <= 2'b00;
                        stream_drain_to_tlast_q <= 1'b0;
                    end
                end

                if (stream_input_fire) begin
                    bytes_read_q <= bytes_read_q + BYTES_PER_BEAT;
                    if (stream_terminal_beat) begin
                        stream_ingress_closed_q <= 1'b1;
                        if (!s_axis_tlast) begin
                            stream_missing_tlast_q <= 1'b1;
                            stream_drain_to_tlast_q <= 1'b1;
                        end
                    end
                end

                if (stream_drain_fire && s_axis_tlast) begin
                    stream_drain_to_tlast_q <= 1'b0;
                end

                case (read_state)
                    READ_IDLE: begin
                        if (active_q && !stream_tlast_q && (bytes_read_q < total_len_q) && !fifo_full) begin
                            read_state <= READ_ADDR;
                        end
                    end

                    READ_ADDR: begin
                        if (m_axi_arvalid && m_axi_arready) begin
                            read_state <= READ_DATA;
                        end
                    end

                    READ_DATA: begin
                        if (m_axi_rvalid && m_axi_rready) begin
                            if (m_axi_rresp != 2'b00) begin
                                active_q <= 1'b0;
                                o_error <= 1'b1;
                                o_bresp <= m_axi_rresp;
                                fifo_flush_q <= 1'b1;
                                read_state <= READ_IDLE;
                                write_state <= WRITE_IDLE;
                                bytes_read_q <= '0;
                                bytes_written_q <= '0;
                                write_resp_pending_last <= 1'b0;
                                stream_missing_tlast_q <= 1'b0;
                                stream_ingress_closed_q <= 1'b0;
                                stream_drain_to_tlast_q <= 1'b0;
                            end else begin
                                bytes_read_q <= bytes_read_q + BYTES_PER_BEAT;
                                read_addr_q <= read_addr_q + BYTES_PER_BEAT;
                                if ((bytes_read_q + BYTES_PER_BEAT) >= total_len_q) begin
                                    read_state <= READ_IDLE;
                                end else begin
                                    read_state <= READ_ADDR;
                                end
                            end
                        end
                    end

                    default: read_state <= READ_IDLE;
                endcase

                case (write_state)
                    WRITE_IDLE: begin
                        if (active_q && fifo_m_tvalid) begin
                            write_state <= WRITE_ADDR;
                        end
                    end

                    WRITE_ADDR: begin
                        if (m_axi_awvalid && m_axi_awready) begin
                            write_state <= WRITE_DATA;
                        end
                    end

                    WRITE_DATA: begin
                        if (m_axi_wvalid && m_axi_wready && fifo_m_tvalid) begin
                            write_resp_pending_last <= fifo_m_tlast;
                            write_state <= WRITE_RESP;
                        end
                    end

                    WRITE_RESP: begin
                        if (m_axi_bvalid && m_axi_bready) begin
                            if (m_axi_bresp != 2'b00) begin
                                active_q <= 1'b0;
                                o_error <= 1'b1;
                                o_bresp <= m_axi_bresp;
                                fifo_flush_q <= 1'b1;
                                read_state <= READ_IDLE;
                                write_state <= WRITE_IDLE;
                                bytes_read_q <= '0;
                                bytes_written_q <= '0;
                                write_resp_pending_last <= 1'b0;
                                stream_missing_tlast_q <= 1'b0;
                                stream_ingress_closed_q <= 1'b0;
                                stream_drain_to_tlast_q <= 1'b0;
                            end else begin
                                bytes_written_q <= bytes_written_q + BYTES_PER_BEAT;
                                write_addr_q <= write_addr_q + BYTES_PER_BEAT;
                                if (write_resp_pending_last) begin
                                    active_q <= 1'b0;
                                    o_done <= !stream_missing_tlast_q;
                                    o_error <= stream_missing_tlast_q;
                                    o_bresp <= 2'b00;
                                    write_state <= WRITE_IDLE;
                                    write_resp_pending_last <= 1'b0;
                                    stream_missing_tlast_q <= 1'b0;
                                    stream_ingress_closed_q <= 1'b0;
                                end else begin
                                    write_state <= WRITE_IDLE;
                                    write_resp_pending_last <= 1'b0;
                                end
                            end
                        end
                    end

                    default: write_state <= WRITE_IDLE;
                endcase
            end
        end
    end

    // Phase 3 stream-mode contract:
    //   * fixed mode keeps the legacy MM2S -> FIFO -> S2MM path.
    //   * stream/TLAST mode bypasses MM2S and injects an external AXIS stream
    //     into the same FIFO/S2MM write path.
    //   * i_total_len is the destination buffer capacity in bytes.
    //   * if capacity is exhausted before TLAST arrives, the engine terminates
    //     on the terminal capacity beat and reports an error after the final
    //     payload B response.

endmodule
