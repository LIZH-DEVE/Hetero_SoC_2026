`timescale 1ns / 1ps

module dma_master_engine #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter integer MAX_OUTSTANDING_WRITES = 4
)(
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic                    i_start,
    input  logic [ADDR_WIDTH-1:0]   i_base_addr,
    input  logic [31:0]             i_total_len,
    output logic                    o_done,
    output logic                    o_error,

    // HP-port baseline: PS software owns coherency. Descriptors/payloads must
    // be flushed before ringing the doorbell, and results invalidated before
    // the CPU consumes them.
    input  logic [DATA_WIDTH-1:0]   i_fifo_rdata,
    input  logic                    i_fifo_empty,
    output logic                    o_fifo_ren,

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
    input  logic [1:0]              m_axi_wresp,
    input  logic                    m_axi_blast,
    input  logic                    m_axi_bvalid,
    output logic                    m_axi_bready,

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

    typedef enum logic [2:0] {
        IDLE,
        CALC,
        ADDR,
        DATA,
        RESP,
        DONE
    } state_t;

    state_t state, next_state;

    logic                    addr_unaligned;
    logic [ADDR_WIDTH-1:0]   current_addr;
    logic [31:0]             bytes_remaining;
    logic [31:0]             burst_bytes_calc;
    logic [7:0]              current_awlen;
    logic [8:0]              beat_count;
    logic [12:0]             dist_to_4k;
    logic [2:0]              outstanding_writes;
    logic                    aw_issue_allowed;

    assign addr_unaligned = (i_base_addr[2:0] != 3'b000);
    assign dist_to_4k = 13'h1000 - {1'b0, current_addr[11:0]};
    assign aw_issue_allowed = (outstanding_writes < MAX_OUTSTANDING_WRITES);

    always_comb begin
        logic [12:0] limit;
        limit = (dist_to_4k < 13'd1024) ? dist_to_4k : 13'd1024;
        burst_bytes_calc = (bytes_remaining < limit) ? bytes_remaining : limit;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_addr <= '0;
            bytes_remaining <= 32'd0;
            current_awlen <= 8'd0;
            beat_count <= 9'd0;
            outstanding_writes <= '0;
            o_done <= 1'b0;
            o_error <= 1'b0;
        end else begin
            state <= next_state;
            o_done <= (next_state == DONE);

            if (state == IDLE) begin
                o_error <= 1'b0;
            end

            if (i_start && addr_unaligned) begin
                o_error <= 1'b1;
            end

            if (m_axi_awvalid && m_axi_awready) begin
                outstanding_writes <= outstanding_writes + 3'd1;
            end
            if (m_axi_bvalid && m_axi_bready) begin
                if (outstanding_writes != 0) begin
                    outstanding_writes <= outstanding_writes - 3'd1;
                end
                if (m_axi_wresp != 2'b00) begin
                    o_error <= 1'b1;
                end
            end

            case (state)
                IDLE: begin
                    if (i_start && i_total_len != 0 && !addr_unaligned) begin
                        current_addr <= i_base_addr;
                        bytes_remaining <= {i_total_len[31:2], 2'b00};
                    end else if (i_start && i_total_len == 0) begin
                        bytes_remaining <= 32'd0;
                    end
                end

                CALC: begin
                    beat_count <= 9'd0;
                    if (burst_bytes_calc[31:2] > 0) begin
                        current_awlen <= burst_bytes_calc[31:2] - 1;
                    end else begin
                        current_awlen <= 8'd0;
                    end
                end

                DATA: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        beat_count <= beat_count + 9'd1;
                    end
                end

                RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        current_addr <= current_addr + burst_bytes_calc;
                        bytes_remaining <= bytes_remaining - burst_bytes_calc;
                    end
                end

                default: begin
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (i_start && i_total_len == 0) begin
                    next_state = DONE;
                end else if (i_start && i_total_len != 0 && !addr_unaligned) begin
                    next_state = CALC;
                end
            end

            CALC: begin
                next_state = ADDR;
            end

            ADDR: begin
                if (m_axi_awvalid && m_axi_awready) begin
                    next_state = DATA;
                end
            end

            DATA: begin
                if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                    next_state = RESP;
                end
            end

            RESP: begin
                if (m_axi_bvalid && m_axi_bready) begin
                    if (bytes_remaining == burst_bytes_calc) begin
                        next_state = DONE;
                    end else begin
                        next_state = CALC;
                    end
                end
            end

            DONE: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    assign m_axi_awvalid = (state == ADDR) && aw_issue_allowed;
    assign m_axi_awaddr  = current_addr;
    assign m_axi_awlen   = current_awlen;
    assign m_axi_awsize  = 3'b010;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000;

    assign m_axi_wvalid = (state == DATA) && !i_fifo_empty;
    assign m_axi_wdata  = i_fifo_rdata;
    assign m_axi_wstrb  = {DATA_WIDTH/8{1'b1}};
    assign m_axi_wlast  = (state == DATA) && (beat_count == current_awlen);
    assign o_fifo_ren   = (state == DATA) && m_axi_wready && !i_fifo_empty;

    assign m_axi_bready = (state == RESP);

    assign m_axi_arvalid = 1'b0;
    assign m_axi_araddr  = '0;
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = 3'd0;
    assign m_axi_arburst = 2'd0;
    assign m_axi_rready  = 1'b0;

endmodule
