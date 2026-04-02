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

    localparam [7:0] REG_CTRL       = 8'h00;
    localparam [7:0] REG_PACKET_LEN = 8'h04;
    localparam integer BYTES_PER_BEAT = DATA_WIDTH / 8;

    logic [ADDR_WIDTH-1:0] awaddr_q;
    logic                  awaddr_valid_q;
    logic [DATA_WIDTH-1:0] wdata_q;
    logic [3:0]            wstrb_q;
    logic                  wdata_valid_q;

    logic [31:0]           packet_len_q;
    logic [31:0]           byte_index_q;
    logic                  busy_q;

    function automatic [31:0] apply_wstrb32(
        input [31:0] prior_value,
        input [31:0] write_value,
        input [3:0]  write_strobe
    );
        integer byte_idx;
        begin
            apply_wstrb32 = prior_value;
            for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1) begin
                if (write_strobe[byte_idx]) begin
                    apply_wstrb32[(byte_idx * 8) +: 8] = write_value[(byte_idx * 8) +: 8];
                end
            end
        end
    endfunction

    // PACKET_LEN must be a multiple of 4 in this phase.
    function automatic logic packet_len_is_word_granular(input [31:0] packet_len);
        begin
            packet_len_is_word_granular = (packet_len != 32'd0) && (packet_len[1:0] == 2'b00);
        end
    endfunction

    // byte n on the stream is n & 8'hFF.
    function automatic [DATA_WIDTH-1:0] pattern_word(input [31:0] start_byte_idx);
        integer byte_idx;
        logic [DATA_WIDTH-1:0] data_word;
        begin
            data_word = '0;
            for (byte_idx = 0; byte_idx < BYTES_PER_BEAT; byte_idx = byte_idx + 1) begin
                data_word[(byte_idx * 8) +: 8] = (start_byte_idx + byte_idx) & 32'h0000_00FF;
            end
            pattern_word = data_word;
        end
    endfunction

    assign s_axil_awready = !awaddr_valid_q;
    assign s_axil_wready  = !wdata_valid_q;
    assign s_axil_arready = !s_axil_rvalid;

    assign m_axis_tvalid = busy_q;
    assign m_axis_tdata  = pattern_word(byte_index_q);
    assign m_axis_tlast  = busy_q && ((byte_index_q + BYTES_PER_BEAT) >= packet_len_q);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awaddr_q        <= '0;
            awaddr_valid_q  <= 1'b0;
            wdata_q         <= '0;
            wstrb_q         <= 4'd0;
            wdata_valid_q   <= 1'b0;
            packet_len_q    <= 32'd0;
            byte_index_q    <= 32'd0;
            busy_q          <= 1'b0;
            s_axil_bresp    <= 2'b00;
            s_axil_bvalid   <= 1'b0;
            s_axil_rdata    <= 32'd0;
            s_axil_rresp    <= 2'b00;
            s_axil_rvalid   <= 1'b0;
        end else begin
            if (s_axil_awready && s_axil_awvalid) begin
                awaddr_q       <= s_axil_awaddr;
                awaddr_valid_q <= 1'b1;
            end

            if (s_axil_wready && s_axil_wvalid) begin
                wdata_q       <= s_axil_wdata;
                wstrb_q       <= s_axil_wstrb;
                wdata_valid_q <= 1'b1;
            end

            if (awaddr_valid_q && wdata_valid_q && !s_axil_bvalid) begin
                s_axil_bresp  <= 2'b00;
                s_axil_bvalid <= 1'b1;

                case (awaddr_q[7:0])
                    REG_CTRL: begin
                        if (wstrb_q[0] && wdata_q[0] && !busy_q && packet_len_is_word_granular(packet_len_q)) begin
                            busy_q       <= 1'b1;
                            byte_index_q <= 32'd0;
                        end
                    end

                    REG_PACKET_LEN: begin
                        packet_len_q <= apply_wstrb32(packet_len_q, wdata_q, wstrb_q);
                    end

                    default: begin
                    end
                endcase

                awaddr_valid_q <= 1'b0;
                wdata_valid_q  <= 1'b0;
            end

            if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end

            if (s_axil_arready && s_axil_arvalid) begin
                s_axil_rvalid <= 1'b1;
                s_axil_rresp  <= 2'b00;
                case (s_axil_araddr[7:0])
                    REG_CTRL:       s_axil_rdata <= {31'd0, busy_q};
                    REG_PACKET_LEN: s_axil_rdata <= packet_len_q;
                    default:        s_axil_rdata <= 32'd0;
                endcase
            end else if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end

            if (busy_q && m_axis_tvalid && m_axis_tready) begin
                if ((byte_index_q + BYTES_PER_BEAT) >= packet_len_q) begin
                    busy_q <= 1'b0;
                end else begin
                    byte_index_q <= byte_index_q + BYTES_PER_BEAT;
                end
            end
        end
    end

endmodule
