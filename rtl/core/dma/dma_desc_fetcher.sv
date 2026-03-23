`timescale 1ns / 1ps

module dma_desc_fetcher #(
    parameter ADDR_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // CSR-facing ring configuration.
    input  logic [31:0]            i_ring_base,
    input  logic [31:0]            i_ring_size,
    input  logic                   i_ring_doorbell,
    input  logic [15:0]            i_sw_tail_ptr,
    output logic [15:0]            o_hw_head_ptr,

    // Decoded descriptor output toward the DMA engine.
    output logic                   o_dma_start,
    output logic [31:0]            o_dma_addr,
    output logic [31:0]            o_dma_len,
    output logic                   o_dma_algo,
    input  logic                   i_dma_done,

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
    output logic                   m_axi_rready
);

    typedef enum logic [2:0] {
        IDLE,
        FETCH_REQ,
        FETCH_DAT,
        DECODE,
        EXEC_WAIT,
        UPDATE_HEAD
    } state_t;

    state_t state;

    logic [15:0] head_ptr;
    logic [15:0] next_head_ptr;
    logic [31:0] desc_word0_addr;
    logic [31:0] desc_word1_ctrl;
    logic [1:0]  fetch_cnt;
    logic        fetch_active;

    assign next_head_ptr = (i_ring_size == 0 || head_ptr == i_ring_size[15:0] - 1) ? 16'd0 : (head_ptr + 16'd1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            head_ptr <= 16'd0;
            desc_word0_addr <= 32'd0;
            desc_word1_ctrl <= 32'd0;
            fetch_cnt <= 2'd0;
            fetch_active <= 1'b0;
            o_dma_start <= 1'b0;
        end else begin
            o_dma_start <= 1'b0;

            case (state)
                IDLE: begin
                    if (i_ring_doorbell) begin
                        fetch_active <= 1'b1;
                    end

                    if ((i_ring_doorbell || fetch_active) &&
                        (i_ring_size != 0) &&
                        (head_ptr != i_sw_tail_ptr)) begin
                        fetch_active <= 1'b1;
                        state <= FETCH_REQ;
                    end else if (head_ptr == i_sw_tail_ptr) begin
                        fetch_active <= 1'b0;
                    end
                end

                FETCH_REQ: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        fetch_cnt <= 2'd0;
                        state <= FETCH_DAT;
                    end
                end

                FETCH_DAT: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        if (fetch_cnt == 2'd0) desc_word0_addr <= m_axi_rdata;
                        if (fetch_cnt == 2'd1) desc_word1_ctrl <= m_axi_rdata;
                        fetch_cnt <= fetch_cnt + 2'd1;

                        if (m_axi_rlast) begin
                            state <= DECODE;
                        end
                    end
                end

                DECODE: begin
                    o_dma_start <= 1'b1;
                    state <= EXEC_WAIT;
                end

                EXEC_WAIT: begin
                    if (i_dma_done) begin
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
    assign o_dma_len  = {8'b0, desc_word1_ctrl[23:0]};
    assign o_dma_algo = desc_word1_ctrl[31];

    assign m_axi_araddr  = i_ring_base + ({16'b0, head_ptr} << 4);
    assign m_axi_arlen   = 8'd3;
    assign m_axi_arsize  = 3'b010;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arvalid = (state == FETCH_REQ);
    assign m_axi_rready  = (state == FETCH_DAT);

endmodule
