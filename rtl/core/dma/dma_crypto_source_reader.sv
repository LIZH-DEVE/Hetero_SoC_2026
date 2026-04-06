`timescale 1ns / 1ps

module dma_crypto_source_reader #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter FIFO_DEPTH = dma_csr_pkg::DMA_RAW_COPY_FIFO_DEPTH
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    i_soft_reset,
    input  logic                    i_start,
    input  logic [ADDR_WIDTH-1:0]   i_src_addr,
    input  logic [31:0]             i_total_len,

    output logic [DATA_WIDTH-1:0]   o_rd_data,
    output logic                    o_rd_valid,
    output logic                    o_rd_empty,
    input  logic                    i_rd_en,

    output logic                    o_done,
    output logic                    o_error,
    output logic                    o_busy,
    output logic [1:0]              o_debug_last_rresp,
    output logic [31:0]             o_debug_bytes_fetched,
    output logic [31:0]             o_debug_bytes_delivered,
    output logic [7:0]              o_debug_state,

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
    output logic                    m_axi_rready
);

    import dma_csr_pkg::*;

    localparam integer BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam integer CRYPTO_BLOCK_BYTES = 16;
    localparam [2:0] AXI_SIZE_WORD = (DATA_WIDTH == 32) ? 3'b010 : 3'b011;
    localparam integer ALIGNMENT_LSB = $clog2(DMA_ALIGNMENT_BYTES);
    localparam integer MAX_BURST_BEATS = 16;
    localparam integer MAX_BURST_BYTES = MAX_BURST_BEATS * BYTES_PER_BEAT;

    typedef enum logic [1:0] {
        READ_IDLE,
        READ_CALC,
        READ_ADDR,
        READ_DATA
    } read_state_t;

    read_state_t read_state;

    logic                    active_q;
    logic                    fifo_flush_q;
    logic [1:0]              last_rresp_q;
    logic [31:0]             total_len_q;
    logic [31:0]             bytes_remaining;
    logic [31:0]             bytes_fetched_q;
    logic [31:0]             bytes_delivered_q;
    logic [31:0]             burst_bytes_calc;
    logic [ADDR_WIDTH-1:0]   read_addr_q;
    logic [7:0]              current_arlen;
    logic [8:0]              beat_count;
    logic [12:0]             dist_to_4k;

    logic                    fifo_s_tready;
    logic [DATA_WIDTH-1:0]   fifo_m_tdata;
    logic                    fifo_m_tvalid;
    logic                    fifo_m_tlast;
    logic                    fifo_empty;
    logic                    fifo_full;
    logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_level;
    logic                    axis_rst_n;
    logic                    fifo_pop;
    logic [DATA_WIDTH-1:0]   rd_data_q;
    logic                    rd_valid_q;

    function automatic [DATA_WIDTH-1:0] pbm_word_order(input [DATA_WIDTH-1:0] value);
        begin
            if (DATA_WIDTH == 32) begin
                pbm_word_order = {value[7:0], value[15:8], value[23:16], value[31:24]};
            end else begin
                pbm_word_order = value;
            end
        end
    endfunction

    assign axis_rst_n = rst_n;
    assign fifo_pop = i_rd_en && fifo_m_tvalid;

    assign o_rd_data = rd_data_q;
    assign o_rd_valid = rd_valid_q;
    assign o_rd_empty = !fifo_m_tvalid;
    assign o_busy = active_q;
    assign o_debug_last_rresp = last_rresp_q;
    assign o_debug_bytes_fetched = bytes_fetched_q;
    assign o_debug_bytes_delivered = bytes_delivered_q;
    assign o_debug_state = {5'd0, read_state, active_q};

    assign dist_to_4k = 13'h1000 - {1'b0, read_addr_q[11:0]};

    always_comb begin
        logic [12:0] limit;

        limit = (dist_to_4k < MAX_BURST_BYTES) ? dist_to_4k : MAX_BURST_BYTES;
        burst_bytes_calc = (bytes_remaining < limit) ? bytes_remaining : limit;
    end

    assign m_axi_araddr  = read_addr_q;
    assign m_axi_arlen   = current_arlen;
    assign m_axi_arsize  = AXI_SIZE_WORD;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arvalid = (read_state == READ_ADDR) && !fifo_full;
    assign m_axi_rready  = (read_state == READ_DATA) && fifo_s_tready;

    dma_axis_fifo_wrapper #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_axis_fifo (
        .clk(clk),
        .axis_rst_n(axis_rst_n),
        .i_clear(i_soft_reset || fifo_flush_q),
        .s_axis_tdata(m_axi_rdata),
        .s_axis_tvalid((read_state == READ_DATA) && m_axi_rvalid && (m_axi_rresp == 2'b00)),
        .s_axis_tlast(m_axi_rlast),
        .s_axis_tready(fifo_s_tready),
        .m_axis_tdata(fifo_m_tdata),
        .m_axis_tvalid(fifo_m_tvalid),
        .m_axis_tlast(fifo_m_tlast),
        .m_axis_tready(fifo_pop),
        .o_empty(fifo_empty),
        .o_full(fifo_full),
        .o_level(fifo_level)
    );

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            read_state <= READ_IDLE;
            active_q <= 1'b0;
            fifo_flush_q <= 1'b0;
            total_len_q <= 32'd0;
            bytes_remaining <= 32'd0;
            bytes_fetched_q <= 32'd0;
            bytes_delivered_q <= 32'd0;
            read_addr_q <= '0;
            current_arlen <= 8'd0;
            beat_count <= 9'd0;
            last_rresp_q <= 2'b00;
            rd_data_q <= '0;
            rd_valid_q <= 1'b0;
            o_done <= 1'b0;
            o_error <= 1'b0;
        end else begin
            o_done <= 1'b0;
            o_error <= 1'b0;
            fifo_flush_q <= 1'b0;
            rd_valid_q <= 1'b0;

            if (i_soft_reset) begin
                read_state <= READ_IDLE;
                active_q <= 1'b0;
                fifo_flush_q <= 1'b1;
                total_len_q <= 32'd0;
                bytes_remaining <= 32'd0;
                bytes_fetched_q <= 32'd0;
                bytes_delivered_q <= 32'd0;
                read_addr_q <= '0;
                current_arlen <= 8'd0;
                beat_count <= 9'd0;
                last_rresp_q <= 2'b00;
                rd_data_q <= '0;
                rd_valid_q <= 1'b0;
            end else begin
                if (!active_q && i_start) begin
                    if ((i_total_len == 0) ||
                        ((i_total_len % CRYPTO_BLOCK_BYTES) != 0) ||
                        ((i_total_len % BYTES_PER_BEAT) != 0) ||
                        (i_src_addr[ALIGNMENT_LSB-1:0] != '0)) begin
                        o_error <= 1'b1;
                        fifo_flush_q <= 1'b1;
                    end else begin
                        active_q <= 1'b1;
                        total_len_q <= i_total_len;
                        bytes_remaining <= i_total_len;
                        bytes_fetched_q <= 32'd0;
                        bytes_delivered_q <= 32'd0;
                        read_addr_q <= i_src_addr;
                        current_arlen <= 8'd0;
                        beat_count <= 9'd0;
                        last_rresp_q <= 2'b00;
                        read_state <= READ_CALC;
                    end
                end

                if (fifo_pop) begin
                    rd_data_q <= pbm_word_order(fifo_m_tdata);
                    rd_valid_q <= 1'b1;
                    bytes_delivered_q <= bytes_delivered_q + BYTES_PER_BEAT;
                    if ((bytes_delivered_q + BYTES_PER_BEAT) >= total_len_q &&
                        bytes_fetched_q >= total_len_q &&
                        bytes_remaining == 32'd0 &&
                        read_state == READ_IDLE) begin
                        active_q <= 1'b0;
                        o_done <= 1'b1;
                    end
                end

                case (read_state)
                    READ_IDLE: begin
                        if (active_q &&
                            (bytes_remaining != 32'd0) &&
                            !fifo_full) begin
                            read_state <= READ_CALC;
                        end
                    end

                    READ_CALC: begin
                        beat_count <= 9'd0;
                        if (burst_bytes_calc[31:2] > 0) begin
                            current_arlen <= burst_bytes_calc[31:2] - 1;
                        end else begin
                            current_arlen <= 8'd0;
                        end
                        read_state <= READ_ADDR;
                    end

                    READ_ADDR: begin
                        if (m_axi_arvalid && m_axi_arready) begin
                            read_state <= READ_DATA;
                        end
                    end

                    READ_DATA: begin
                        if (m_axi_rvalid && m_axi_rready) begin
                            last_rresp_q <= m_axi_rresp;
                            if (m_axi_rresp != 2'b00) begin
                                read_state <= READ_IDLE;
                                active_q <= 1'b0;
                                fifo_flush_q <= 1'b1;
                                total_len_q <= 32'd0;
                                bytes_remaining <= 32'd0;
                                bytes_fetched_q <= 32'd0;
                                bytes_delivered_q <= 32'd0;
                                read_addr_q <= '0;
                                current_arlen <= 8'd0;
                                beat_count <= 9'd0;
                                o_error <= 1'b1;
                            end else begin
                                beat_count <= beat_count + 9'd1;
                                bytes_fetched_q <= bytes_fetched_q + BYTES_PER_BEAT;
                                bytes_remaining <= bytes_remaining - BYTES_PER_BEAT;
                                read_addr_q <= read_addr_q + BYTES_PER_BEAT;
                                if (m_axi_rlast) begin
                                    beat_count <= 9'd0;
                                    if (bytes_remaining == BYTES_PER_BEAT) begin
                                        read_state <= READ_IDLE;
                                    end else begin
                                        read_state <= READ_CALC;
                                    end
                                end
                            end
                        end
                    end

                    default: begin
                        read_state <= READ_IDLE;
                    end
                endcase
            end
        end
    end

endmodule
