`timescale 1ns / 1ps

module stream_dummy_source #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32
)(
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic [ADDR_WIDTH-1:0]   s_axil_awaddr,
    input  logic                    s_axil_awvalid,
    output logic                    s_axil_awready,
    input  logic [DATA_WIDTH-1:0]   s_axil_wdata,
    input  logic [3:0]              s_axil_wstrb,
    input  logic                    s_axil_wvalid,
    output logic                    s_axil_wready,
    output logic [1:0]              s_axil_bresp,
    output logic                    s_axil_bvalid,
    input  logic                    s_axil_bready,
    input  logic [ADDR_WIDTH-1:0]   s_axil_araddr,
    input  logic                    s_axil_arvalid,
    output logic                    s_axil_arready,
    output logic [DATA_WIDTH-1:0]   s_axil_rdata,
    output logic [1:0]              s_axil_rresp,
    output logic                    s_axil_rvalid,
    input  logic                    s_axil_rready,

    output logic [DATA_WIDTH-1:0]   m_axis_tdata,
    output logic                    m_axis_tvalid,
    input  logic                    m_axis_tready,
    output logic                    m_axis_tlast
);

    localparam integer BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam logic [7:0] REG_CTRL = 8'h00;
    localparam logic [7:0] REG_PACKET_LEN = 8'h04;

    logic [ADDR_WIDTH-1:0] awaddr_q;
    logic                  aw_seen_q;
    logic [DATA_WIDTH-1:0] wdata_q;
    logic [3:0]            wstrb_q;
    logic                  w_seen_q;
    logic [ADDR_WIDTH-1:0] araddr_q;

    logic [31:0]           packet_len_q;
    logic [31:0]           remaining_bytes_q;
    logic [31:0]           byte_index_q;
    logic                  active_q;

    function automatic logic [31:0] apply_wstrb(
        input logic [31:0] old_val,
        input logic [31:0] new_val,
        input logic [3:0]  strb
    );
        begin
            apply_wstrb[7:0]   = strb[0] ? new_val[7:0]   : old_val[7:0];
            apply_wstrb[15:8]  = strb[1] ? new_val[15:8]  : old_val[15:8];
            apply_wstrb[23:16] = strb[2] ? new_val[23:16] : old_val[23:16];
            apply_wstrb[31:24] = strb[3] ? new_val[31:24] : old_val[31:24];
        end
    endfunction

    function automatic logic [DATA_WIDTH-1:0] gen_word(input logic [31:0] byte_index);
        integer i;
        begin
            gen_word = '0;
            for (i = 0; i < BYTES_PER_BEAT; i = i + 1) begin
                gen_word[(i * 8) +: 8] = (byte_index + i) & 32'h0000_00FF;
            end
        end
    endfunction

    assign s_axil_bresp = 2'b00;
    assign s_axil_rresp = 2'b00;
    assign s_axil_awready = !aw_seen_q && !s_axil_bvalid;
    assign s_axil_wready = !w_seen_q && !s_axil_bvalid;
    assign s_axil_arready = !s_axil_rvalid;

    assign m_axis_tvalid = active_q;
    assign m_axis_tdata = gen_word(byte_index_q);
    assign m_axis_tlast = active_q && (remaining_bytes_q == BYTES_PER_BEAT);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awaddr_q <= '0;
            aw_seen_q <= 1'b0;
            wdata_q <= '0;
            wstrb_q <= '0;
            w_seen_q <= 1'b0;
            araddr_q <= '0;
            s_axil_bvalid <= 1'b0;
            s_axil_rvalid <= 1'b0;
            s_axil_rdata <= '0;
            packet_len_q <= 32'd0;
            remaining_bytes_q <= 32'd0;
            byte_index_q <= 32'd0;
            active_q <= 1'b0;
        end else begin
            if (s_axil_awvalid && s_axil_awready) begin
                awaddr_q <= s_axil_awaddr;
                aw_seen_q <= 1'b1;
            end

            if (s_axil_wvalid && s_axil_wready) begin
                wdata_q <= s_axil_wdata;
                wstrb_q <= s_axil_wstrb;
                w_seen_q <= 1'b1;
            end

            if (aw_seen_q && w_seen_q && !s_axil_bvalid) begin
                case (awaddr_q[7:0])
                    REG_CTRL: begin
                        if (!active_q && wstrb_q[0] && wdata_q[0] &&
                            (packet_len_q != 32'd0) &&
                            ((packet_len_q % BYTES_PER_BEAT) == 0)) begin
                            active_q <= 1'b1;
                            remaining_bytes_q <= packet_len_q;
                            byte_index_q <= 32'd0;
                        end
                    end
                    REG_PACKET_LEN: begin
                        packet_len_q <= apply_wstrb(packet_len_q, wdata_q, wstrb_q);
                    end
                    default: begin
                    end
                endcase

                s_axil_bvalid <= 1'b1;
                aw_seen_q <= 1'b0;
                w_seen_q <= 1'b0;
            end

            if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end

            if (s_axil_arvalid && s_axil_arready) begin
                araddr_q <= s_axil_araddr;
                s_axil_rvalid <= 1'b1;
                case (s_axil_araddr[7:0])
                    REG_CTRL: begin
                        s_axil_rdata <= {31'd0, active_q};
                    end
                    REG_PACKET_LEN: begin
                        s_axil_rdata <= packet_len_q;
                    end
                    default: begin
                        s_axil_rdata <= 32'd0;
                    end
                endcase
            end

            if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end

            if (active_q && m_axis_tvalid && m_axis_tready) begin
                if (remaining_bytes_q == BYTES_PER_BEAT) begin
                    active_q <= 1'b0;
                    remaining_bytes_q <= 32'd0;
                    byte_index_q <= 32'd0;
                end else begin
                    remaining_bytes_q <= remaining_bytes_q - BYTES_PER_BEAT;
                    byte_index_q <= byte_index_q + BYTES_PER_BEAT;
                end
            end
        end
    end

endmodule
