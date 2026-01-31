`timescale 1ns / 1ps

module dma_s2mm_mm2s_engine #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // --- Control Interface ---
    input  logic                   i_s2mm_en,
    input  logic                   i_mm2s_en,
    input  logic [ADDR_WIDTH-1:0]  i_s2mm_addr,
    input  logic [DATA_WIDTH-1:0]  i_s2mm_data,
    output logic [DATA_WIDTH-1:0]  o_mm2s_data,

    // --- AXI4 Master Interface ---
    output logic [ADDR_WIDTH-1:0]  m_axis_awaddr,
    output logic [7:0]             m_axis_awlen,
    output logic [2:0]             m_axis_awsize,
    output logic [1:0]             m_axis_awburst,
    output logic [3:0]             m_axis_awcache,
    output logic [2:0]             m_axis_awprot,
    output logic                   m_axis_awvalid,
    input  logic                   m_axis_awready,
    output logic [DATA_WIDTH-1:0]  m_axis_wdata,
    output logic [DATA_WIDTH/8-1:0] m_axis_wstrb,
    output logic                   m_axis_wlast,
    output logic                   m_axis_wvalid,
    input  logic                   m_axis_wready,
    input  logic [1:0]             m_axis_bresp,
    input  logic                   m_axis_bvalid,
    output logic                   m_axis_bready,
    
    output logic [ADDR_WIDTH-1:0]  m_axis_araddr,
    output logic [7:0]             m_axis_arlen,
    output logic [2:0]             m_axis_arsize,
    output logic [1:0]             m_axis_arburst,
    output logic                   m_axis_arvalid,
    input  logic                   m_axis_arready,
    input  logic [DATA_WIDTH-1:0]  m_axis_rdata,
    input  logic [1:0]             m_axis_rresp,
    input  logic                   m_axis_rlast,
    input  logic                   m_axis_rvalid,
    output logic                   m_axis_rready
);

    typedef enum logic [2:0] {
        IDLE,
        S2MM_WRITE_ADDR,
        S2MM_WRITE_DATA,
        S2MM_WAIT_RESP,
        MM2S_READ_ADDR,
        MM2S_READ_DATA,
        DONE
    } state_t;

    state_t state, next_state;
    logic [ADDR_WIDTH-1:0] addr_reg;
    logic [DATA_WIDTH-1:0] data_reg;
    logic [DATA_WIDTH-1:0] read_data_reg;
    logic data_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            addr_reg <= 0;
            data_reg <= 0;
            read_data_reg <= 0;
            data_valid <= 0;
        end else begin
            state <= next_state;
            
            case (state)
                IDLE: begin
                    data_valid <= 0;
                    if (i_s2mm_en) begin
                        addr_reg <= i_s2mm_addr;
                        data_reg <= i_s2mm_data;
                    end else if (i_mm2s_en) begin
                        addr_reg <= i_s2mm_addr;
                    end
                end
                
                MM2S_READ_DATA: begin
                    if (m_axis_rvalid && m_axis_rready) begin
                        read_data_reg <= m_axis_rdata;
                        data_valid <= 1;
                    end
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (i_s2mm_en) 
                    next_state = S2MM_WRITE_ADDR;
                else if (i_mm2s_en) 
                    next_state = MM2S_READ_ADDR;
            end
            
            S2MM_WRITE_ADDR: begin
                if (m_axis_awready) 
                    next_state = S2MM_WRITE_DATA;
            end
            
            S2MM_WRITE_DATA: begin
                if (m_axis_wready) 
                    next_state = S2MM_WAIT_RESP;
            end
            
            S2MM_WAIT_RESP: begin
                if (m_axis_bvalid && m_axis_bready) 
                    next_state = DONE;
            end
            
            MM2S_READ_ADDR: begin
                if (m_axis_arready) 
                    next_state = MM2S_READ_DATA;
            end
            
            MM2S_READ_DATA: begin
                if (m_axis_rvalid && m_axis_rready) 
                    next_state = DONE;
            end
            
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end

    assign m_axis_awaddr  = (state == S2MM_WRITE_ADDR) ? addr_reg : 0;
    assign m_axis_awlen   = 8'd0;
    assign m_axis_awsize  = 3'b010;
    assign m_axis_awburst = 2'b01;
    assign m_axis_awcache = 4'b0000;
    assign m_axis_awprot  = 3'b000;
    assign m_axis_awvalid = (state == S2MM_WRITE_ADDR);
    
    assign m_axis_wdata   = (state == S2MM_WRITE_DATA) ? data_reg : 0;
    assign m_axis_wstrb   = 4'hF;
    assign m_axis_wlast   = (state == S2MM_WRITE_DATA);
    assign m_axis_wvalid  = (state == S2MM_WRITE_DATA);
    assign m_axis_bready  = (state == S2MM_WAIT_RESP);

    assign m_axis_araddr  = (state == MM2S_READ_ADDR) ? addr_reg : 0;
    assign m_axis_arlen   = 8'd0;
    assign m_axis_arsize  = 3'b010;
    assign m_axis_arburst = 2'b01;
    assign m_axis_arvalid = (state == MM2S_READ_ADDR);
    assign m_axis_rready  = (state == MM2S_READ_DATA);

    assign o_mm2s_data = data_valid ? read_data_reg : 0;

endmodule
