`timescale 1ns / 1ps

module dma_desc_fetcher #(
    parameter ADDR_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   i_soft_reset,

    // CSR-facing ring configuration.
    input  logic [31:0]            i_ring_base,
    input  logic [31:0]            i_ring_size,
    input  logic                   i_ring_doorbell,
    input  logic [15:0]            i_sw_tail_ptr,
    output logic [15:0]            o_hw_head_ptr,

    // Decoded descriptor output toward the DMA engine.
    output logic                   o_dma_start,
    output logic [31:0]            o_dma_addr,
    output logic [31:0]            o_dma_src_addr,
    output logic [31:0]            o_dma_len,
    output logic                   o_dma_algo,
    output logic                   o_dma_stream_tlast,
    input  logic                   i_dma_done,
    input  logic                   i_dma_error,
    input  logic [1:0]             i_dma_bresp,
    input  logic [31:0]            i_dma_actual_len,

    // Completion event: pulses only after both actual_len and CSW writebacks complete.
    output logic                   o_completion_event,

    // AXI read channel for descriptor fetches.
    output logic [ADDR_WIDTH-1:0]  m_axi_araddr,
    output logic [7:0]             m_axi_arlen,
    output logic [2:0]             m_axi_arsize,
    output logic [1:0]             m_axi_arburst,
    output logic                   m_axi_arvalid,
    input  logic                   m_axi_arready,
    input  logic [31:0]            m_axi_rdata,
    input  logic                   m_axi_rlast,
    input  logic                   m_axi_rvalid,
    output logic                   m_axi_rready,

    // AXI single-word write-back channel for descriptor completion metadata.
    output logic [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output logic [7:0]             m_axi_awlen,
    output logic [2:0]             m_axi_awsize,
    output logic [1:0]             m_axi_awburst,
    output logic [3:0]             m_axi_awcache,
    output logic [2:0]             m_axi_awprot,
    output logic                   m_axi_awvalid,
    input  logic                   m_axi_awready,
    output logic [31:0]            m_axi_wdata,
    output logic [3:0]             m_axi_wstrb,
    output logic                   m_axi_wlast,
    output logic                   m_axi_wvalid,
    input  logic                   m_axi_wready,
    input  logic [1:0]             m_axi_bresp,
    input  logic                   m_axi_bvalid,
    output logic                   m_axi_bready,
    output logic                   o_wb_active
);

    import dma_csr_pkg::*;

    typedef enum logic [3:0] {
        IDLE,
        FETCH_REQ,
        FETCH_DAT,
        DECODE,
        EXEC_WAIT,
        WB_ACTUAL_AW,
        WB_ACTUAL_W,
        WB_ACTUAL_B,
        WB_CSW_AW,
        WB_CSW_W,
        WB_CSW_B,
        UPDATE_HEAD
    } state_t;

    state_t state;

    logic [15:0] head_ptr;
    logic [15:0] next_head_ptr;
    logic [2:0]  fetch_cnt;
    logic        fetch_active;

    logic [31:0] desc_word0_addr;
    logic [31:0] desc_word1_src_addr;
    logic [31:0] desc_word2_ctrl;
    logic [31:0] desc_word4_csw;
    logic [31:0] current_desc_addr;
    logic [31:0] wb_csw_data;
    logic [31:0] wb_actual_len_data;
    logic [31:0] dma_status_word;
    logic        desc_owned_by_hw;
    logic [1:0]  dma_bresp_sanitized;
    logic        wb_actual_phase;

    function automatic logic [31:0] compute_dma_status_word(
        input logic        dma_error,
        input logic [1:0]  dma_bresp,
        input logic        stream_tlast
    );
        begin
            if (!dma_error) begin
                compute_dma_status_word = DMA_DESC_CSW_STS_OK;
            end else if (dma_bresp != 2'b00) begin
                compute_dma_status_word = DMA_DESC_CSW_STS_AXI_RESP;
            end else if (stream_tlast) begin
                compute_dma_status_word = DMA_DESC_CSW_STS_OVERFLOW_OR_MISSING_TLAST;
            end else begin
                compute_dma_status_word = DMA_DESC_CSW_STS_INTERNAL;
            end
        end
    endfunction

    assign next_head_ptr = (i_ring_size == 0 || head_ptr == i_ring_size[15:0] - 1) ? 16'd0 : (head_ptr + 16'd1);
    assign desc_owned_by_hw = desc_word4_csw[DMA_DESC_CSW_BIT_OWNER];
    assign dma_bresp_sanitized =
        ((i_dma_bresp === 2'b00) ||
         (i_dma_bresp === 2'b01) ||
         (i_dma_bresp === 2'b10) ||
         (i_dma_bresp === 2'b11)) ? i_dma_bresp : 2'b00;
    assign wb_actual_phase =
        (state == WB_ACTUAL_AW) ||
        (state == WB_ACTUAL_W) ||
        (state == WB_ACTUAL_B);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || i_soft_reset) begin
            state <= IDLE;
            head_ptr <= 16'd0;
            fetch_cnt <= 3'd0;
            fetch_active <= 1'b0;
            desc_word0_addr <= 32'd0;
            desc_word1_src_addr <= 32'd0;
            desc_word2_ctrl <= 32'd0;
            desc_word4_csw <= 32'd0;
            current_desc_addr <= 32'd0;
            wb_csw_data <= 32'd0;
            wb_actual_len_data <= 32'd0;
            dma_status_word <= DMA_DESC_CSW_STS_OK;
            o_dma_start <= 1'b0;
            o_completion_event <= 1'b0;
        end else begin
            o_dma_start <= 1'b0;
            o_completion_event <= 1'b0;

            case (state)
                IDLE: begin
                    if (i_ring_doorbell) begin
                        fetch_active <= 1'b1;
                    end

                    if ((i_ring_doorbell || fetch_active) &&
                        (i_ring_size != 0) &&
                        (head_ptr != i_sw_tail_ptr)) begin
                        current_desc_addr <= i_ring_base + ({16'b0, head_ptr} * DMA_DESC_SIZE_BYTES);
                        state <= FETCH_REQ;
                    end else if (head_ptr == i_sw_tail_ptr) begin
                        fetch_active <= 1'b0;
                    end
                end

                FETCH_REQ: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        fetch_cnt <= 3'd0;
                        state <= FETCH_DAT;
                    end
                end

                FETCH_DAT: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        case (fetch_cnt)
                            3'd0: desc_word0_addr <= m_axi_rdata;
                            3'd1: desc_word1_src_addr <= m_axi_rdata;
                            3'd2: desc_word2_ctrl <= m_axi_rdata;
                            3'd4: desc_word4_csw  <= m_axi_rdata;
                            default: begin end
                        endcase
                        fetch_cnt <= fetch_cnt + 3'd1;

                        if (m_axi_rlast) begin
                            state <= DECODE;
                        end
                    end
                end

                DECODE: begin
                    if (desc_owned_by_hw) begin
                        o_dma_start <= 1'b1;
                        state <= EXEC_WAIT;
                    end else begin
                        state <= UPDATE_HEAD;
                    end
                end

                EXEC_WAIT: begin
                    if (i_dma_done || i_dma_error) begin
                        dma_status_word <= compute_dma_status_word(
                            i_dma_error,
                            dma_bresp_sanitized,
                            desc_word2_ctrl[DMA_DESC_CTRL_BIT_STREAM_TLAST]
                        );
                        wb_actual_len_data <= i_dma_actual_len;
                        wb_csw_data <= DMA_DESC_CSW_DONE |
                                       (i_dma_error ? DMA_DESC_CSW_ERR : 32'd0) |
                                       compute_dma_status_word(
                                           i_dma_error,
                                           dma_bresp_sanitized,
                                           desc_word2_ctrl[DMA_DESC_CTRL_BIT_STREAM_TLAST]
                                       );
                        state <= WB_ACTUAL_AW;
                    end
                end

                WB_ACTUAL_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        state <= WB_ACTUAL_W;
                    end
                end

                WB_ACTUAL_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        state <= WB_ACTUAL_B;
                    end
                end

                WB_ACTUAL_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        state <= WB_CSW_AW;
                    end
                end

                WB_CSW_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        state <= WB_CSW_W;
                    end
                end

                WB_CSW_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        state <= WB_CSW_B;
                    end
                end

                WB_CSW_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        o_completion_event <= 1'b1;
                        state <= UPDATE_HEAD;
                    end
                end

                UPDATE_HEAD: begin
                    head_ptr <= next_head_ptr;
                    if (next_head_ptr == i_sw_tail_ptr) begin
                        fetch_active <= 1'b0;
                    end
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    assign o_hw_head_ptr = head_ptr;
    assign o_dma_addr = desc_word0_addr;
    assign o_dma_src_addr = desc_word1_src_addr;
    assign o_dma_len  = (desc_word2_ctrl & DMA_DESC_CTRL_MASK_LEN);
    assign o_dma_algo = desc_word2_ctrl[DMA_DESC_CTRL_BIT_ALGO];
    assign o_dma_stream_tlast = desc_word2_ctrl[DMA_DESC_CTRL_BIT_STREAM_TLAST];

    assign m_axi_araddr  = current_desc_addr;
    assign m_axi_arlen   = (DMA_DESC_CSW_BYTE_OFFSET / DMA_DESC_WORD_BYTES);
    assign m_axi_arsize  = 3'b010;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arvalid = (state == FETCH_REQ);
    assign m_axi_rready  = (state == FETCH_DAT);

    assign m_axi_awaddr  = wb_actual_phase ?
                           (current_desc_addr + DMA_DESC_ACTUAL_LEN_BYTE_OFFSET) :
                           (current_desc_addr + DMA_DESC_CSW_BYTE_OFFSET);
    assign m_axi_awlen   = 8'd0;
    assign m_axi_awsize  = 3'b010;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awvalid = (state == WB_ACTUAL_AW) || (state == WB_CSW_AW);

    assign m_axi_wdata   = wb_actual_phase ? wb_actual_len_data : wb_csw_data;
    assign m_axi_wstrb   = 4'hF;
    assign m_axi_wlast   = 1'b1;
    assign m_axi_wvalid  = (state == WB_ACTUAL_W) || (state == WB_CSW_W);

    assign m_axi_bready  = (state == WB_ACTUAL_B) || (state == WB_CSW_B);
    assign o_wb_active   = wb_actual_phase ||
                           (state == WB_CSW_AW) ||
                           (state == WB_CSW_W) ||
                           (state == WB_CSW_B);

endmodule
