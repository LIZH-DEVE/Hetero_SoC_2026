`timescale 1ns / 1ps

module dma_master_engine #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // --- Control Interface ---
    input  logic                   i_start,
    input  logic [ADDR_WIDTH-1:0]  i_base_addr,
    input  logic [31:0]            i_total_len,
    output logic                   o_done,
    
    // --- Data Source (PBM) ---
    input  logic [DATA_WIDTH-1:0]  i_fifo_rdata,
    input  logic                   i_fifo_empty,
    output logic                   o_fifo_ren,

    // --- AXI4 Master Write Interface ---
    output logic [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output logic [7:0]             m_axi_awlen,
    output logic [2:0]             m_axi_awsize,  // [New]
    output logic [1:0]             m_axi_awburst, // [New]
    output logic [3:0]             m_axi_awcache, // [New] Tie-off
    output logic [2:0]             m_axi_awprot,  // [New] Tie-off
    output logic                   m_axi_awvalid,
    input  logic                   m_axi_awready,
    
    output logic [DATA_WIDTH-1:0]  m_axi_wdata,
    output logic [DATA_WIDTH/8-1:0] m_axi_wstrb,  // [New]
    output logic                   m_axi_wlast,
    output logic                   m_axi_wvalid,
    input  logic                   m_axi_wready,
    
    input  logic [1:0]             m_axi_bresp,
    input  logic                   m_axi_bvalid,
    output logic                   m_axi_bready,

    // --- AXI4 Read Interface (新增：为了满足顶层连接) ---
    output logic [ADDR_WIDTH-1:0]  m_axi_araddr,
    output logic [7:0]             m_axi_arlen,
    output logic [2:0]             m_axi_arsize,
    output logic [1:0]             m_axi_arburst,
    output logic                   m_axi_arvalid,
    input  logic                   m_axi_arready,
    input  logic [DATA_WIDTH-1:0]  m_axi_rdata,
    input  logic [1:0]             m_axi_rresp,
    input  logic                   m_axi_rlast,
    input  logic                   m_axi_rvalid,
    output logic                   m_axi_rready
);

    // ========================================================
    // 状态机与逻辑
    // ========================================================
    typedef enum logic [2:0] {IDLE, CALC, ADDR, DATA, RESP, DONE} state_t;
    state_t state, next_state;

    logic [ADDR_WIDTH-1:0] current_addr;
    logic [31:0]           bytes_remaining;
    logic [31:0]           burst_bytes_calc;
    logic [7:0]            current_awlen;
    logic [8:0]            beat_count;
    logic [12:0]           dist_to_4k;

    // --- 4K Boundary Logic ---
    assign dist_to_4k = 13'h1000 - {1'b0, current_addr[11:0]};
    always_comb begin
        logic [12:0] limit;
        limit = (dist_to_4k < 1024) ? dist_to_4k : 1024;
        burst_bytes_calc = (bytes_remaining < limit) ? bytes_remaining : limit;
    end

    // --- FSM ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_addr <= 0; bytes_remaining <= 0;
            current_awlen <= 0; beat_count <= 0; o_done <= 0;
        end else begin
            state <= next_state;
            o_done <= (state == DONE);
            case (state)
                IDLE: if (i_start && i_total_len != 0) begin
                    current_addr <= i_base_addr; bytes_remaining <= i_total_len;
                end
                CALC: begin
                    beat_count <= 0;
                    if (burst_bytes_calc[31:2] > 0) current_awlen <= burst_bytes_calc[31:2] - 1;
                    else current_awlen <= 0;
                end
                DATA: if (m_axi_wvalid && m_axi_wready) beat_count <= beat_count + 1;
                RESP: if (m_axi_bvalid && m_axi_bready) begin
                    current_addr <= current_addr + burst_bytes_calc;
                    bytes_remaining <= bytes_remaining - burst_bytes_calc;
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: if (i_start && i_total_len != 0) next_state = CALC;
            CALC: next_state = ADDR;
            ADDR: if (m_axi_awvalid && m_axi_awready) next_state = DATA;
            DATA: if (m_axi_wlast && m_axi_wvalid && m_axi_wready) next_state = RESP;
            RESP: if (m_axi_bvalid && m_axi_bready) 
                    next_state = (bytes_remaining == burst_bytes_calc) ? DONE : CALC;
            DONE: next_state = IDLE;
        endcase
    end

    // --- Output Logic ---
    assign m_axi_awvalid = (state == ADDR);
    assign m_axi_awaddr  = current_addr;
    assign m_axi_awlen   = current_awlen;
    assign m_axi_awsize  = 3'b010; // 4 bytes
    assign m_axi_awburst = 2'b01;  // INCR
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000;

    assign m_axi_wvalid = (state == DATA) && !i_fifo_empty;
    assign m_axi_wdata  = i_fifo_rdata;
    assign m_axi_wstrb  = 4'hF;
    assign m_axi_wlast  = (state == DATA) && (beat_count == current_awlen);
    
    assign o_fifo_ren   = (state == DATA) && m_axi_wready && !i_fifo_empty;
    assign m_axi_bready = (state == RESP);

    // --- Read Channel Tie-offs (关键修复点) ---
    assign m_axi_arvalid = 0;
    assign m_axi_araddr  = 0;
    assign m_axi_arlen   = 0;
    assign m_axi_arsize  = 0;
    assign m_axi_arburst = 0;
    assign m_axi_rready  = 0;

endmodule