`timescale 1ns / 1ps

module axil_csr #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // =========================================================================
    // AXI-Lite Slave Interface (CPU Access)
    // =========================================================================
    // Write Address Channel
    input  logic [ADDR_WIDTH-1:0]  s_axil_awaddr,
    input  logic                   s_axil_awvalid,
    output logic                   s_axil_awready,
    // Write Data Channel
    input  logic [DATA_WIDTH-1:0]  s_axil_wdata,
    input  logic [3:0]             s_axil_wstrb,
    input  logic                   s_axil_wvalid,
    output logic                   s_axil_wready,
    // Write Response Channel
    output logic [1:0]             s_axil_bresp,
    output logic                   s_axil_bvalid,
    input  logic                   s_axil_bready,
    // Read Address Channel
    input  logic [ADDR_WIDTH-1:0]  s_axil_araddr,
    input  logic                   s_axil_arvalid,
    output logic                   s_axil_arready,
    // Read Data Channel
    output logic [DATA_WIDTH-1:0]  s_axil_rdata,
    output logic [1:0]             s_axil_rresp,
    output logic                   s_axil_rvalid,
    input  logic                   s_axil_rready,

    // =========================================================================
    // Hardware Control Interface
    // =========================================================================
    
    // --- Control Triggers & Config (0x00) ---
    output logic                   o_start,       // Bit 0: DMA Start (Pulse)
    output logic                   o_hw_init,     // Bit 1: HW Init Trigger (Pulse)
    output logic                   o_algo_sel,    // Bit 2: 0=AES, 1=SM4
    output logic                   o_enc_dec,     // Bit 3: 0=Dec, 1=Enc

    // --- Linear DMA Config (0x08, 0x0C) ---
    output logic [31:0]            o_base_addr,
    output logic [31:0]            o_len,

    // --- Crypto Keys (0x10 - 0x1C) ---
    output logic [127:0]           o_key,

    // --- Cache & Debug (0x40, 0x44) ---
    output logic                   o_cache_flush,
    input  logic [31:0]            i_acl_cnt,

    // --- [Day 11 New] Descriptor Ring Interface (0x50 - 0x5C) ---
    output logic [31:0]            o_ring_base,   // 0x50: Ring Base Address
    output logic [31:0]            o_ring_size,   // 0x5C: Ring Size (Entries)
    output logic [15:0]            o_sw_tail_ptr, // 0x58: Software Tail Ptr
    input  logic [15:0]            i_hw_head_ptr, // 0x54: Hardware Head Ptr (Read Only)

    // --- Status Inputs ---
    input  logic                   i_done,
    input  logic                   i_error
);

    // =========================================================================
    // Internal Registers
    // =========================================================================
    // 0x00: Control Register
    logic [31:0] reg_ctrl; 

    // 0x08: DMA Linear Base Address
    logic [31:0] reg_base_addr;

    // 0x0C: DMA Linear Length
    logic [31:0] reg_len;

    // 0x10-0x1C: 128-bit Key
    logic [31:0] reg_key0; // LSB
    logic [31:0] reg_key1;
    logic [31:0] reg_key2;
    logic [31:0] reg_key3; // MSB

    // 0x40: Cache Control
    logic [31:0] reg_cache_ctrl;

    // [Day 11] 0x50: Ring Base Address
    logic [31:0] reg_ring_base;

    // [Day 11] 0x58: Ring Tail Pointer
    logic [31:0] reg_ring_tail;

    // [Day 11] 0x5C: Ring Size
    logic [31:0] reg_ring_size;

    // =========================================================================
    // AXI Handshake Logic
    // =========================================================================
    logic aw_received, w_received;
    logic [ADDR_WIDTH-1:0] awaddr_latch;
    logic write_en;
    logic is_unaligned;
    logic hw_error_latch;
    
    // Write enable condition
    assign write_en = aw_received && w_received && ~s_axil_bvalid;

    // Alignment check (Day 2 requirement)
    assign is_unaligned = (reg_base_addr[5:0] != 6'h0);

    // Byte Strobe Application Function
    function logic [31:0] apply_wstrb(input logic [31:0] old_val, input logic [31:0] new_val, input logic [3:0] strb);
        apply_wstrb[ 7: 0] = strb[0] ? new_val[ 7: 0] : old_val[ 7: 0];
        apply_wstrb[15: 8] = strb[1] ? new_val[15: 8] : old_val[15: 8];
        apply_wstrb[23:16] = strb[2] ? new_val[23:16] : old_val[23:16];
        apply_wstrb[31:24] = strb[3] ? new_val[31:24] : old_val[31:24];
    endfunction

    // -------------------------------------------------------------------------
    // Write Channel Logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_awready <= 0; aw_received <= 0; awaddr_latch <= 0;
            s_axil_wready <= 0; w_received <= 0;
            s_axil_bvalid <= 0; s_axil_bresp <= 0;
            
            // Register Reset
            reg_ctrl <= 0; reg_base_addr <= 0; reg_len <= 0;
            reg_key0 <= 0; reg_key1 <= 0; reg_key2 <= 0; reg_key3 <= 0;
            reg_cache_ctrl <= 0;
            reg_ring_base <= 0; reg_ring_tail <= 0; reg_ring_size <= 0;
            
            // Output Triggers & State
            o_start <= 0;
            o_hw_init <= 0;
            hw_error_latch <= 0;
        end else begin
            // 1. AW Channel Handshake
            if (~s_axil_awready && s_axil_awvalid && ~aw_received && ~s_axil_bvalid) begin
                s_axil_awready <= 1;
                aw_received <= 1;
                awaddr_latch <= s_axil_awaddr;
            end else begin
                s_axil_awready <= 0;
            end

            // 2. W Channel Handshake
            if (~s_axil_wready && s_axil_wvalid && ~w_received && ~s_axil_bvalid) begin
                s_axil_wready <= 1;
                w_received <= 1;
            end else begin
                s_axil_wready <= 0;
            end

            // B Channel Handshake Completion
            if (s_axil_bready && s_axil_bvalid) begin
                s_axil_bvalid <= 0;
                aw_received <= 0;
                w_received <= 0;
            end

            // Auto-clear pulses
            o_start <= 0;
            o_hw_init <= 0;
            
            // Error Latching
            if (i_error) hw_error_latch <= 1;

            // 3. Register Update
            if (write_en) begin
                s_axil_bvalid <= 1; 
                s_axil_bresp <= 2'b00; // OKAY

                case (awaddr_latch[7:0])
                    8'h00: begin // Control
                        reg_ctrl <= apply_wstrb(reg_ctrl, s_axil_wdata, s_axil_wstrb);
                        // Bit 0: Start Trigger with Alignment Check
                        if (s_axil_wstrb[0] && s_axil_wdata[0]) begin
                            if (is_unaligned) begin
                                hw_error_latch <= 1;
                                o_start <= 0;
                            end else begin
                                hw_error_latch <= 0;
                                o_start <= 1;
                            end
                        end
                        // Bit 1: HW Init Trigger
                        if (s_axil_wstrb[0] && s_axil_wdata[1]) o_hw_init <= 1;
                    end
                    8'h08: reg_base_addr <= apply_wstrb(reg_base_addr, s_axil_wdata, s_axil_wstrb);
                    8'h0C: reg_len       <= apply_wstrb(reg_len, s_axil_wdata, s_axil_wstrb);
                    8'h10: reg_key0      <= apply_wstrb(reg_key0, s_axil_wdata, s_axil_wstrb);
                    8'h14: reg_key1      <= apply_wstrb(reg_key1, s_axil_wdata, s_axil_wstrb);
                    8'h18: reg_key2      <= apply_wstrb(reg_key2, s_axil_wdata, s_axil_wstrb);
                    8'h1C: reg_key3      <= apply_wstrb(reg_key3, s_axil_wdata, s_axil_wstrb);
                    8'h40: reg_cache_ctrl<= apply_wstrb(reg_cache_ctrl, s_axil_wdata, s_axil_wstrb);
                    
                    // [Day 11] Ring Registers
                    8'h50: reg_ring_base <= apply_wstrb(reg_ring_base, s_axil_wdata, s_axil_wstrb);
                    8'h54: ; // Head Ptr is Read-Only (Hardware Managed)
                    8'h58: reg_ring_tail <= apply_wstrb(reg_ring_tail, s_axil_wdata, s_axil_wstrb);
                    8'h5C: reg_ring_size <= apply_wstrb(reg_ring_size, s_axil_wdata, s_axil_wstrb);
                    default: ;
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // Read Channel Logic
    // -------------------------------------------------------------------------
    logic [31:0] reg_status;
    assign reg_status = {30'd0, (i_error | hw_error_latch), i_done};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_arready <= 0;
            s_axil_rvalid <= 0;
            s_axil_rdata <= 0;
            s_axil_rresp <= 0;
        end else begin
            // 1. AR Channel Handshake
            if (~s_axil_arready && s_axil_arvalid) begin
                s_axil_arready <= 1;
            end else begin
                s_axil_arready <= 0;
            end

            // 2. Read Data Generation
            if (s_axil_arready && s_axil_arvalid && ~s_axil_rvalid) begin
                s_axil_rvalid <= 1;
                s_axil_rresp <= 2'b00; // OKAY
                
                case (s_axil_araddr[7:0])
                    8'h00: s_axil_rdata <= reg_ctrl;
                    8'h04: s_axil_rdata <= reg_status;
                    8'h08: s_axil_rdata <= reg_base_addr;
                    8'h0C: s_axil_rdata <= reg_len;
                    8'h10: s_axil_rdata <= reg_key0;
                    8'h14: s_axil_rdata <= reg_key1;
                    8'h18: s_axil_rdata <= reg_key2;
                    8'h1C: s_axil_rdata <= reg_key3;
                    8'h40: s_axil_rdata <= reg_cache_ctrl;
                    8'h44: s_axil_rdata <= i_acl_cnt; // External counter
                    
                    // [Day 11] Ring Registers
                    8'h50: s_axil_rdata <= reg_ring_base;
                    8'h54: s_axil_rdata <= {16'b0, i_hw_head_ptr}; // HW Driven
                    8'h58: s_axil_rdata <= reg_ring_tail;
                    8'h5C: s_axil_rdata <= reg_ring_size;
                    default: s_axil_rdata <= 32'd0;
                endcase
            end else if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 0;
            end
        end
    end

    // =========================================================================
    // Output Connections
    // =========================================================================
    assign o_base_addr   = reg_base_addr;
    assign o_len         = reg_len;
    assign o_algo_sel    = reg_ctrl[2]; // Bit 2
    assign o_enc_dec     = reg_ctrl[3]; // Bit 3
    assign o_key         = {reg_key3, reg_key2, reg_key1, reg_key0};
    assign o_cache_flush = reg_cache_ctrl[0];
    
    // Day 11 Ring outputs
    assign o_ring_base   = reg_ring_base;
    assign o_ring_size   = reg_ring_size;
    assign o_sw_tail_ptr = reg_ring_tail[15:0];

endmodule