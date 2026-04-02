`timescale 1ns / 1ps

module udp_gateway_shadow_ctrl_csr #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic [ADDR_WIDTH-1:0]  s_axil_awaddr,
    input  logic                   s_axil_awvalid,
    output logic                   s_axil_awready,
    input  logic [DATA_WIDTH-1:0]  s_axil_wdata,
    input  logic [3:0]             s_axil_wstrb,
    input  logic                   s_axil_wvalid,
    output logic                   s_axil_wready,
    output logic [1:0]             s_axil_bresp,
    output logic                   s_axil_bvalid,
    input  logic                   s_axil_bready,
    input  logic [ADDR_WIDTH-1:0]  s_axil_araddr,
    input  logic                   s_axil_arvalid,
    output logic                   s_axil_arready,
    output logic [DATA_WIDTH-1:0]  s_axil_rdata,
    output logic [1:0]             s_axil_rresp,
    output logic                   s_axil_rvalid,
    input  logic                   s_axil_rready,

    output logic                   o_network_enable,
    output logic                   o_network_ingress_sel,
    output logic                   o_arp_enable,
    output logic [31:0]            o_net_local_ip,
    output logic [47:0]            o_net_local_mac,
    output logic                   o_inj_clear,
    output logic                   o_inj_push,
    output logic [31:0]            o_inj_data,
    output logic [15:0]            o_inj_expected_words,
    output logic                   o_txcap_clear,
    output logic                   o_txcap_pop,
    output logic                   o_acl_en,
    output logic                   o_acl_write_en,
    output logic                   o_acl_clear,
    output logic                   o_fastpath_en,
    output logic [11:0]            o_acl_write_addr,
    output logic [103:0]           o_acl_write_data,

    input  logic [31:0]            i_inj_status,
    input  logic [31:0]            i_txcap_status,
    input  logic [31:0]            i_txcap_data,
    input  logic [31:0]            i_netdbg_status,
    input  logic [31:0]            i_net_applied_cfg0,
    input  logic [31:0]            i_net_applied_local_ip,
    input  logic [31:0]            i_net_applied_local_mac_lo,
    input  logic [31:0]            i_net_applied_local_mac_hi,
    input  logic [31:0]            i_drop_wrong_port_count,
    input  logic [31:0]            i_drop_unaligned_count,
    input  logic [31:0]            i_device_dna_lo,
    input  logic [31:0]            i_device_dna_hi,
    input  logic [31:0]            i_device_dna_status,
    input  logic [31:0]            i_fastpath_status,
    input  logic [31:0]            i_fastpath_hit_count,
    input  logic [31:0]            i_fastpath_fallback_count,
    input  logic                   i_acl_inc,
    input  logic                   i_busy
);

    logic [31:0] reg_ctrl;
    logic [31:0] reg_net_cfg0;
    logic [31:0] reg_net_local_ip;
    logic [31:0] reg_net_local_mac_lo;
    logic [31:0] reg_net_local_mac_hi;
    logic [31:0] reg_acl_cnt;
    logic [31:0] reg_acl_addr;
    logic [31:0] reg_acl_data0;
    logic [31:0] reg_acl_data1;
    logic [31:0] reg_acl_data2;
    logic [31:0] reg_acl_data3;
    logic [31:0] acl_data3_effective;
    logic [31:0] reg_inj_ctrl;
    logic [31:0] reg_inj_data;
    logic [31:0] reg_txcap_ctrl;

    logic aw_received;
    logic w_received;
    logic [ADDR_WIDTH-1:0] awaddr_latch;
    logic write_en;

    function automatic logic [31:0] apply_wstrb(
        input logic [31:0] old_val,
        input logic [31:0] new_val,
        input logic [3:0] strb
    );
        apply_wstrb[7:0] = strb[0] ? new_val[7:0] : old_val[7:0];
        apply_wstrb[15:8] = strb[1] ? new_val[15:8] : old_val[15:8];
        apply_wstrb[23:16] = strb[2] ? new_val[23:16] : old_val[23:16];
        apply_wstrb[31:24] = strb[3] ? new_val[31:24] : old_val[31:24];
    endfunction

    assign write_en = aw_received && w_received && !s_axil_bvalid;

    always_comb begin
        acl_data3_effective = reg_acl_data3;
        if (write_en && (awaddr_latch[7:0] == 8'h70)) begin
            acl_data3_effective = apply_wstrb(reg_acl_data3, s_axil_wdata, s_axil_wstrb);
        end
    end

    // Keep shadow inject/network control on synchronous reset so XPM FIFO
    // control pins are not driven by async-reset flops.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s_axil_awready <= 1'b0;
            s_axil_wready <= 1'b0;
            s_axil_bvalid <= 1'b0;
            s_axil_bresp <= 2'b00;
            aw_received <= 1'b0;
            w_received <= 1'b0;
            awaddr_latch <= '0;

            reg_ctrl <= 32'd0;
            reg_net_cfg0 <= 32'd0;
            reg_net_local_ip <= 32'hC0A8_0114;
            reg_net_local_mac_lo <= 32'h3500_0120;
            reg_net_local_mac_hi <= 32'h0000_020A;
            reg_acl_cnt <= 32'd0;
            reg_inj_ctrl <= 32'd0;
            reg_inj_data <= 32'd0;
            reg_txcap_ctrl <= 32'd0;

            o_inj_clear <= 1'b0;
            o_inj_push <= 1'b0;
            o_txcap_clear <= 1'b0;
            o_txcap_pop <= 1'b0;
        end else begin
            o_inj_clear <= 1'b0;
            o_inj_push <= 1'b0;
            o_txcap_clear <= 1'b0;
            o_txcap_pop <= 1'b0;

            if (!s_axil_awready && s_axil_awvalid && !aw_received && !s_axil_bvalid) begin
                s_axil_awready <= 1'b1;
                aw_received <= 1'b1;
                awaddr_latch <= s_axil_awaddr;
            end else begin
                s_axil_awready <= 1'b0;
            end

            if (!s_axil_wready && s_axil_wvalid && !w_received && !s_axil_bvalid) begin
                s_axil_wready <= 1'b1;
                w_received <= 1'b1;
            end else begin
                s_axil_wready <= 1'b0;
            end

            if (i_acl_inc && reg_acl_cnt < 32'hFFFFFFFF) begin
                reg_acl_cnt <= reg_acl_cnt + 1'b1;
            end

            if (write_en) begin
                case (awaddr_latch[7:0])
                    8'h00: reg_ctrl <= apply_wstrb(reg_ctrl, s_axil_wdata, s_axil_wstrb);
                    8'h44: reg_acl_cnt <= apply_wstrb(reg_acl_cnt, s_axil_wdata, s_axil_wstrb);
                    8'h90: reg_net_cfg0 <= apply_wstrb(reg_net_cfg0, s_axil_wdata, s_axil_wstrb);
                    8'h94: reg_net_local_ip <= apply_wstrb(reg_net_local_ip, s_axil_wdata, s_axil_wstrb);
                    8'h98: reg_net_local_mac_lo <= apply_wstrb(reg_net_local_mac_lo, s_axil_wdata, s_axil_wstrb);
                    8'h9C: reg_net_local_mac_hi <= apply_wstrb(reg_net_local_mac_hi, s_axil_wdata, s_axil_wstrb);
                    8'hA0: begin
                        reg_inj_ctrl <= apply_wstrb(reg_inj_ctrl, s_axil_wdata, s_axil_wstrb);
                        if (s_axil_wstrb[0] && s_axil_wdata[0]) begin
                            o_inj_clear <= 1'b1;
                        end
                    end
                    8'hA4: begin
                        reg_inj_data <= apply_wstrb(reg_inj_data, s_axil_wdata, s_axil_wstrb);
                        o_inj_push <= 1'b1;
                    end
                    8'hAC: begin
                        reg_txcap_ctrl <= apply_wstrb(reg_txcap_ctrl, s_axil_wdata, s_axil_wstrb);
                        if (s_axil_wstrb[0] && s_axil_wdata[0]) begin
                            o_txcap_clear <= 1'b1;
                        end
                        if (s_axil_wstrb[0] && s_axil_wdata[1]) begin
                            o_txcap_pop <= 1'b1;
                        end
                    end
                    default: begin
                    end
                endcase

                s_axil_bvalid <= 1'b1;
                s_axil_bresp <= 2'b00;
                aw_received <= 1'b0;
                w_received <= 1'b0;
            end else if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end
        end
    end

    // Keep ACL BRAM-facing write address/data/control on synchronous reset so
    // the inferred RAM address/control pins are not driven by async-reset flops.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            reg_acl_addr <= 32'd0;
            reg_acl_data0 <= 32'd0;
            reg_acl_data1 <= 32'd0;
            reg_acl_data2 <= 32'd0;
            reg_acl_data3 <= 32'd0;
            o_acl_write_en <= 1'b0;
            o_acl_clear <= 1'b0;
        end else begin
            o_acl_write_en <= 1'b0;
            o_acl_clear <= 1'b0;

            if (write_en) begin
                case (awaddr_latch[7:0])
                    8'h60: reg_acl_addr <= apply_wstrb(reg_acl_addr, s_axil_wdata, s_axil_wstrb);
                    8'h64: reg_acl_data0 <= apply_wstrb(reg_acl_data0, s_axil_wdata, s_axil_wstrb);
                    8'h68: reg_acl_data1 <= apply_wstrb(reg_acl_data1, s_axil_wdata, s_axil_wstrb);
                    8'h6C: reg_acl_data2 <= apply_wstrb(reg_acl_data2, s_axil_wdata, s_axil_wstrb);
                    8'h70: begin
                        reg_acl_data3 <= apply_wstrb(reg_acl_data3, s_axil_wdata, s_axil_wstrb);
                        if (s_axil_wstrb[1] && s_axil_wdata[8]) begin
                            o_acl_write_en <= 1'b1;
                        end
                        if (s_axil_wstrb[1] && s_axil_wdata[9]) begin
                            o_acl_clear <= 1'b1;
                        end
                    end
                    default: begin
                    end
                endcase
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_arready <= 1'b0;
            s_axil_rvalid <= 1'b0;
            s_axil_rresp <= 2'b00;
            s_axil_rdata <= 32'd0;
        end else begin
            if (!s_axil_arready && s_axil_arvalid && !s_axil_rvalid) begin
                s_axil_arready <= 1'b1;
                s_axil_rvalid <= 1'b1;
                s_axil_rresp <= 2'b00;
                case (s_axil_araddr[7:0])
                    8'h00: s_axil_rdata <= reg_ctrl;
                    8'h04: s_axil_rdata <= {31'd0, i_busy};
                    8'h44: s_axil_rdata <= reg_acl_cnt;
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
                    8'hAC: s_axil_rdata <= reg_txcap_ctrl;
                    8'hB0: s_axil_rdata <= i_txcap_status;
                    8'hB4: s_axil_rdata <= i_txcap_data;
                    8'hB8: s_axil_rdata <= i_netdbg_status;
                    8'hBC: s_axil_rdata <= i_net_applied_cfg0;
                    8'hC0: s_axil_rdata <= i_net_applied_local_ip;
                    8'hC4: s_axil_rdata <= i_net_applied_local_mac_lo;
                    8'hC8: s_axil_rdata <= i_net_applied_local_mac_hi;
                    8'hCC: s_axil_rdata <= i_drop_wrong_port_count;
                    8'hD0: s_axil_rdata <= i_drop_unaligned_count;
                    8'hD4: s_axil_rdata <= i_device_dna_lo;
                    8'hD8: s_axil_rdata <= i_device_dna_hi;
                    8'hDC: s_axil_rdata <= i_device_dna_status;
                    8'hE0: s_axil_rdata <= i_fastpath_status;
                    8'hE4: s_axil_rdata <= i_fastpath_hit_count;
                    8'hE8: s_axil_rdata <= i_fastpath_fallback_count;
                    default: s_axil_rdata <= 32'd0;
                endcase
            end else begin
                s_axil_arready <= 1'b0;
                if (s_axil_rvalid && s_axil_rready) begin
                    s_axil_rvalid <= 1'b0;
                end
            end
        end
    end

    assign o_acl_en = reg_ctrl[7];
    assign o_fastpath_en = reg_ctrl[11];
    assign o_network_enable = reg_net_cfg0[0];
    assign o_network_ingress_sel = reg_net_cfg0[1];
    assign o_arp_enable = reg_net_cfg0[2];
    assign o_net_local_ip = reg_net_local_ip;
    assign o_net_local_mac = {reg_net_local_mac_hi[15:0], reg_net_local_mac_lo};
    assign o_inj_data = reg_inj_data;
    assign o_inj_expected_words = reg_inj_ctrl[31:16];
    assign o_acl_write_addr = reg_acl_addr[11:0];
    assign o_acl_write_data = {acl_data3_effective[7:0], reg_acl_data2, reg_acl_data1, reg_acl_data0};

endmodule
