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
    output logic                   o_s2mm_en,     // Bit 4: S2MM Enable
    output logic                   o_mm2s_en,     // Bit 5: MM2S Enable
    output logic                   o_auth_en,     // Bit 6: Config Auth Enable
    output logic                   o_acl_en,      // Bit 7: ACL Filter Enable
    output logic                   o_dna_lock_en, // Bit 8: DNA Lock Enable
    
    // --- S2MM/MM2S Interface (0x20 - 0x24) ---
    output logic [31:0]            o_s2mm_addr,   // 0x20: S2MM Address
    output logic [31:0]            o_s2mm_data,   // 0x24: S2MM Data
    
    // --- Loopback Mode (0x48) ---
    output logic [1:0]             o_loopback_mode, // Bit[1:0]: 0=Normal, 1=DDR Loopback, 2=PBM Passthrough

    // --- ACL Config (0x60 - 0x70) ---
    output logic                   o_acl_write_en,  // Pulse
    output logic                   o_acl_clear,     // Pulse
    output logic [11:0]            o_acl_write_addr,
    output logic [103:0]           o_acl_write_data,

    // --- Network / Injector Control (0x90 - 0xC8) ---
    output logic                   o_network_enable,
    output logic                   o_network_ingress_sel,
    output logic                   o_arp_enable,
    output logic [31:0]            o_net_local_ip,
    output logic [47:0]            o_net_local_mac,
    output logic                   o_net_cfg0_we,
    output logic                   o_net_local_ip_we,
    output logic                   o_net_local_mac_lo_we,
    output logic                   o_net_local_mac_hi_we,
    output logic                   o_inj_clear,
    output logic                   o_inj_push,
    output logic [31:0]            o_inj_data,
    output logic [15:0]            o_inj_expected_words,
    input  logic [31:0]            i_inj_status,
    output logic                   o_txcap_clear,
    output logic                   o_txcap_pop,
    input  logic [31:0]            i_txcap_status,
    input  logic [31:0]            i_txcap_data,
    input  logic [31:0]            i_netdbg_status,
    input  logic [31:0]            i_net_applied_cfg0,
    input  logic [31:0]            i_net_applied_local_ip,
    input  logic [31:0]            i_net_applied_local_mac_lo,
    input  logic [31:0]            i_net_applied_local_mac_hi,

    // --- Linear DMA Config (0x08, 0x0C) ---
    output logic [31:0]            o_base_addr,
    output logic [31:0]            o_len,

    // --- Crypto Keys (0x10 - 0x1C) ---
    output logic [127:0]           o_key,
    output logic [127:0]           o_key_hi,
    output logic                   o_aes256_en,

    // --- Cache & Debug (0x40, 0x44) ---
    output logic                   o_cache_flush,
    input  logic                   i_acl_inc,    // ACL Collision Increment Signal
    output logic [31:0]            o_acl_cnt,    // ACL Collision Counter Output

    // --- [Day 11 New] Descriptor Ring Interface (0x4C - 0x5C) ---
    output logic                   o_ring_doorbell, // 0x4C: write-1 pulse, wakes fetcher
    output logic [31:0]            o_ring_base,   // 0x50: Ring Base Address
    output logic [31:0]            o_ring_size,   // 0x5C: Ring Size (Entries)
    output logic [15:0]            o_sw_tail_ptr, // 0x58: Software Tail Ptr
    input  logic [15:0]            i_hw_head_ptr, // 0x54: Hardware Head Ptr (Read Only)

    // --- Status Inputs ---
    input  logic                   i_done,
    input  logic                   i_error,
    input  logic                   i_busy
);

    // =========================================================================
    // Internal Registers
    // =========================================================================
    // 0x00: Control Register
    logic [31:0] reg_ctrl; 
    
    // [Day 11] 0x08: S2MM/MM2S Address
    logic [31:0] reg_s2mm_addr;
    
    // [Day 11] 0x0C: S2MM/MM2S Data
    logic [31:0] reg_s2mm_data;
    
    // [Day 11] 0x10: Loopback Mode
    logic [31:0] reg_loopback_mode; 

    // 0x08: DMA Linear Base Address
    logic [31:0] reg_base_addr;

    // 0x0C: DMA Linear Length
    logic [31:0] reg_len;

    // 0x28-0x34: 128-bit Key (write-only, read masked)
    logic [31:0] reg_key0; // LSB
    logic [31:0] reg_key1;
    logic [31:0] reg_key2;
    logic [31:0] reg_key3; // MSB
    logic [31:0] reg_key4;
    logic [31:0] reg_key5;
    logic [31:0] reg_key6;
    logic [31:0] reg_key7;

    // 0x40: Cache Control
    logic [31:0] reg_acl_cnt;
    logic [31:0] reg_cache_ctrl;

    // [Day 11] 0x50: Ring Base Address
    logic [31:0] reg_ring_base;

    // [Day 11] 0x58: Ring Tail Pointer
    logic [31:0] reg_ring_tail;

    // [Day 11] 0x5C: Ring Size
    logic [31:0] reg_ring_size;

    // Security / ACL Registers (0x60 - 0x70)
    logic [31:0] reg_acl_addr;
    logic [31:0] reg_acl_data0;
    logic [31:0] reg_acl_data1;
    logic [31:0] reg_acl_data2;
    logic [31:0] reg_acl_data3;
    logic [31:0] reg_net_cfg0;
    logic [31:0] reg_net_local_ip;
    logic [31:0] reg_net_local_mac_lo;
    logic [31:0] reg_net_local_mac_hi;
    logic [31:0] reg_inj_ctrl;
    logic [31:0] reg_inj_data;

    // =========================================================================
    // AXI Handshake Logic
    // =========================================================================
    logic aw_received, w_received;
    logic [ADDR_WIDTH-1:0] awaddr_latch;
    logic write_en;
    logic is_unaligned;
    logic hw_error_latch;
    logic txcap_pop_pending;
    logic txcap_pop_on_read;
    
    // Write enable condition
    assign write_en = aw_received && w_received && ~s_axil_bvalid;
    assign txcap_pop_on_read = s_axil_arready && s_axil_arvalid && ~s_axil_rvalid &&
                               (s_axil_araddr[7:0] == 8'hB4);

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
            reg_key0 <= 0; reg_key1 <= 0; reg_key2 <= 0; reg_key3 <= 0; reg_key4 <= 0; reg_key5 <= 0; reg_key6 <= 0; reg_key7 <= 0;
            reg_cache_ctrl <= 0;
            reg_acl_cnt <= 0;
            reg_ring_base <= 0; reg_ring_tail <= 0; reg_ring_size <= 0;
            reg_s2mm_addr <= 0; reg_s2mm_data <= 0; reg_loopback_mode <= 0;
            reg_acl_addr <= 0; reg_acl_data0 <= 0; reg_acl_data1 <= 0; reg_acl_data2 <= 0; reg_acl_data3 <= 0;
            reg_net_cfg0 <= 0; reg_net_local_ip <= 32'hC0A8_0114; reg_net_local_mac_lo <= 32'h3500_0120; reg_net_local_mac_hi <= 32'h0000_020A;
            reg_inj_ctrl <= 0; reg_inj_data <= 0;
            
            // Output Triggers & State
            o_start <= 0;
            o_hw_init <= 0;
            o_acl_write_en <= 0;
            o_acl_clear <= 0;
            o_ring_doorbell <= 0;
            o_net_cfg0_we <= 0;
            o_net_local_ip_we <= 0;
            o_net_local_mac_lo_we <= 0;
            o_net_local_mac_hi_we <= 0;
            o_inj_clear <= 0;
            o_inj_push <= 0;
            o_txcap_clear <= 0;
            o_txcap_pop <= 0;
            hw_error_latch <= 0;
            txcap_pop_pending <= 0;
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
            o_acl_write_en <= 0;
            o_acl_clear <= 0;
            o_ring_doorbell <= 0;
            o_net_cfg0_we <= 0;
            o_net_local_ip_we <= 0;
            o_net_local_mac_lo_we <= 0;
            o_net_local_mac_hi_we <= 0;
            o_inj_clear <= 0;
            o_inj_push <= 0;
            o_txcap_clear <= 0;
            o_txcap_pop <= 0;

            if (txcap_pop_pending || txcap_pop_on_read) begin
                o_txcap_pop <= 1'b1;
            end
            if (txcap_pop_pending) begin
                txcap_pop_pending <= 1'b0;
            end
            
            // Error Latching
            if (i_error) hw_error_latch <= 1;

            
            // ACL Counter Increment Logic
            if (i_acl_inc && reg_acl_cnt < 32'hFFFFFFFF) begin
                reg_acl_cnt <= reg_acl_cnt + 1'b1;
            end
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
                    
                    // [Day 11] S2MM/MM2S Registers
                    8'h20: reg_s2mm_addr  <= apply_wstrb(reg_s2mm_addr, s_axil_wdata, s_axil_wstrb);
                    8'h24: reg_s2mm_data  <= apply_wstrb(reg_s2mm_data, s_axil_wdata, s_axil_wstrb);
                    
                    // Key Registers (shifted to make room for S2MM/MM2S)
                    8'h28: reg_key0      <= apply_wstrb(reg_key0, s_axil_wdata, s_axil_wstrb);
                    8'h2C: reg_key1      <= apply_wstrb(reg_key1, s_axil_wdata, s_axil_wstrb);
                    8'h30: reg_key2      <= apply_wstrb(reg_key2, s_axil_wdata, s_axil_wstrb);
                    8'h34: reg_key3      <= apply_wstrb(reg_key3, s_axil_wdata, s_axil_wstrb);
                    8'h74: reg_key4      <= apply_wstrb(reg_key4, s_axil_wdata, s_axil_wstrb);
                    8'h78: reg_key5      <= apply_wstrb(reg_key5, s_axil_wdata, s_axil_wstrb);
                    8'h7C: reg_key6      <= apply_wstrb(reg_key6, s_axil_wdata, s_axil_wstrb);
                    8'h80: reg_key7      <= apply_wstrb(reg_key7, s_axil_wdata, s_axil_wstrb);
                    
                    8'h40: reg_cache_ctrl<= apply_wstrb(reg_cache_ctrl, s_axil_wdata, s_axil_wstrb);
                    8'h44: reg_acl_cnt   <= apply_wstrb(reg_acl_cnt, s_axil_wdata, s_axil_wstrb);
                    
                    // [Day 11] Loopback Mode Register
                    8'h48: reg_loopback_mode <= apply_wstrb(reg_loopback_mode, s_axil_wdata, s_axil_wstrb);

                    // [DMA MVP] Doorbell pulse. CPU writes this after flushing
                    // descriptors/payload/tail in DDR to wake the fetcher.
                    8'h4C: begin
                        if (|s_axil_wstrb && (s_axil_wdata != 32'd0)) o_ring_doorbell <= 1'b1;
                    end
                    
                    // [Day 11] Ring Registers
                    8'h50: reg_ring_base <= apply_wstrb(reg_ring_base, s_axil_wdata, s_axil_wstrb);
                    8'h54: ; // Head Ptr is Read-Only (Hardware Managed)
                    8'h58: reg_ring_tail <= apply_wstrb(reg_ring_tail, s_axil_wdata, s_axil_wstrb);
                    8'h5C: reg_ring_size <= apply_wstrb(reg_ring_size, s_axil_wdata, s_axil_wstrb);

                    // ACL Config Registers
                    8'h60: reg_acl_addr  <= apply_wstrb(reg_acl_addr,  s_axil_wdata, s_axil_wstrb);
                    8'h64: reg_acl_data0 <= apply_wstrb(reg_acl_data0, s_axil_wdata, s_axil_wstrb);
                    8'h68: reg_acl_data1 <= apply_wstrb(reg_acl_data1, s_axil_wdata, s_axil_wstrb);
                    8'h6C: reg_acl_data2 <= apply_wstrb(reg_acl_data2, s_axil_wdata, s_axil_wstrb);
                    8'h70: begin
                        reg_acl_data3 <= apply_wstrb(reg_acl_data3, s_axil_wdata, s_axil_wstrb);
                        if (s_axil_wstrb[0] && s_axil_wdata[0]) o_acl_write_en <= 1'b1;
                        if (s_axil_wstrb[0] && s_axil_wdata[1]) o_acl_clear <= 1'b1;
                    end
                    8'h90: begin
                        reg_net_cfg0 <= apply_wstrb(reg_net_cfg0, s_axil_wdata, s_axil_wstrb);
                        o_net_cfg0_we <= 1'b1;
                    end
                    8'h94: begin
                        reg_net_local_ip <= apply_wstrb(reg_net_local_ip, s_axil_wdata, s_axil_wstrb);
                        o_net_local_ip_we <= 1'b1;
                    end
                    8'h98: begin
                        reg_net_local_mac_lo <= apply_wstrb(reg_net_local_mac_lo, s_axil_wdata, s_axil_wstrb);
                        o_net_local_mac_lo_we <= 1'b1;
                    end
                    8'h9C: begin
                        reg_net_local_mac_hi <= apply_wstrb(reg_net_local_mac_hi, s_axil_wdata, s_axil_wstrb);
                        o_net_local_mac_hi_we <= 1'b1;
                    end
                    8'hA0: begin
                        reg_inj_ctrl <= apply_wstrb(reg_inj_ctrl, s_axil_wdata, s_axil_wstrb);
                        if (s_axil_wstrb[0] && s_axil_wdata[0]) o_inj_clear <= 1'b1;
                    end
                    8'hA4: begin
                        reg_inj_data <= apply_wstrb(reg_inj_data, s_axil_wdata, s_axil_wstrb);
                        o_inj_push <= 1'b1;
                    end
                    8'hAC: begin
                        if (s_axil_wstrb[0] && s_axil_wdata[0]) o_txcap_clear <= 1'b1;
                        if (s_axil_wstrb[0] && s_axil_wdata[1]) txcap_pop_pending <= 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // Read Channel Logic
    // -------------------------------------------------------------------------
    logic [31:0] reg_status;
    assign reg_status = {29'd0, i_busy, (i_error | hw_error_latch), i_done};

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
                    
                    // [Day 11] S2MM/MM2S Registers
                    8'h20: s_axil_rdata <= reg_s2mm_addr;
                    8'h24: s_axil_rdata <= reg_s2mm_data;
                    
                    // Key Registers (shifted to make room for S2MM/MM2S)
                    8'h28: s_axil_rdata <= 32'd0;
                    8'h2C: s_axil_rdata <= 32'd0;
                    8'h30: s_axil_rdata <= 32'd0;
                    8'h34: s_axil_rdata <= 32'd0;
                    8'h74: s_axil_rdata <= 32'd0;
                    8'h78: s_axil_rdata <= 32'd0;
                    8'h7C: s_axil_rdata <= 32'd0;
                    8'h80: s_axil_rdata <= 32'd0;
                    
                    8'h40: s_axil_rdata <= reg_cache_ctrl;
                    8'h44: s_axil_rdata <= reg_acl_cnt; // ACL Collision Counter
                    
                    // [Day 11] Loopback Mode Register
                    8'h48: s_axil_rdata <= reg_loopback_mode;
                    8'h4C: s_axil_rdata <= 32'd0;
                    
                    // [Day 11] Ring Registers
                    8'h50: s_axil_rdata <= reg_ring_base;
                    8'h54: s_axil_rdata <= {16'b0, i_hw_head_ptr}; // HW Driven
                    8'h58: s_axil_rdata <= reg_ring_tail;
                    8'h5C: s_axil_rdata <= reg_ring_size;

                    // ACL Config Registers
                    8'h60: s_axil_rdata <= reg_acl_addr;
                    8'h64: s_axil_rdata <= reg_acl_data0;
                    8'h68: s_axil_rdata <= reg_acl_data1;
                    8'h6C: s_axil_rdata <= reg_acl_data2;
                    8'h70: s_axil_rdata <= reg_acl_data3;
                    8'h90: s_axil_rdata <= reg_net_cfg0;
                    8'h94: s_axil_rdata <= reg_net_local_ip;
                    8'h98: s_axil_rdata <= reg_net_local_mac_lo;
                    8'h9C: s_axil_rdata <= reg_net_local_mac_hi;
                    8'hA0: s_axil_rdata <= reg_inj_ctrl;
                    8'hA4: s_axil_rdata <= reg_inj_data;
                    8'hA8: s_axil_rdata <= i_inj_status;
                     8'hB0: s_axil_rdata <= i_txcap_status;
                     8'hB4: begin
                         s_axil_rdata <= i_txcap_data;
                     end
                     8'hB8: s_axil_rdata <= i_netdbg_status;
                     8'hBC: s_axil_rdata <= i_net_applied_cfg0;
                     8'hC0: s_axil_rdata <= i_net_applied_local_ip;
                     8'hC4: s_axil_rdata <= i_net_applied_local_mac_lo;
                     8'hC8: s_axil_rdata <= i_net_applied_local_mac_hi;
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
    assign o_s2mm_en     = reg_ctrl[4]; // Bit 4
    assign o_mm2s_en     = reg_ctrl[5]; // Bit 5
    assign o_auth_en      = reg_ctrl[6]; // Bit 6
    assign o_acl_en       = reg_ctrl[7]; // Bit 7
    assign o_dna_lock_en  = reg_ctrl[8]; // Bit 8
    assign o_key          = {reg_key3, reg_key2, reg_key1, reg_key0};
    assign o_key_hi       = {reg_key7, reg_key6, reg_key5, reg_key4};
    assign o_aes256_en    = reg_ctrl[9];
    assign o_cache_flush = reg_cache_ctrl[0];
    assign o_acl_cnt = reg_acl_cnt;
    
    // Day 11 S2MM/MM2S outputs
    assign o_s2mm_addr    = reg_s2mm_addr;
    assign o_s2mm_data    = reg_s2mm_data;
    
    // Day 11 Loopback mode output
    assign o_loopback_mode = reg_loopback_mode[1:0]; // Bit[1:0]: 0=Normal, 1=DDR Loopback, 2=PBM Passthrough
    
    // Day 11 Ring outputs
    assign o_ring_base   = reg_ring_base;
    assign o_ring_size   = reg_ring_size;
    assign o_sw_tail_ptr = reg_ring_tail[15:0];

    assign o_acl_write_addr = reg_acl_addr[11:0];
    assign o_acl_write_data = {reg_acl_data3[7:0], reg_acl_data2, reg_acl_data1, reg_acl_data0};
    assign o_network_enable = reg_net_cfg0[0];
    assign o_network_ingress_sel = reg_net_cfg0[1];
    assign o_arp_enable = reg_net_cfg0[2];
    assign o_net_local_ip = reg_net_local_ip;
    assign o_net_local_mac = {reg_net_local_mac_hi[15:0], reg_net_local_mac_lo};
    assign o_inj_data = reg_inj_data;
    assign o_inj_expected_words = reg_inj_ctrl[31:16];

endmodule



