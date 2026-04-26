`timescale 1ns / 1ps

module virtual_ddr_model #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_DEPTH  = 65536,
    parameter MIN_LATENCY = 2,
    parameter MAX_LATENCY = 10
)(
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  logic [7:0]             s_axi_awlen,
    input  logic [2:0]             s_axi_awsize,
    input  logic [1:0]             s_axi_awburst,
    input  logic [3:0]             s_axi_awcache,
    input  logic [2:0]             s_axi_awprot,
    input  logic                   s_axi_awvalid,
    output logic                   s_axi_awready,
    input  logic                   s_axi_wlast,
    input  logic                   s_axi_wvalid,
    input  logic [DATA_WIDTH-1:0]  s_axi_wdata,
    input  logic [DATA_WIDTH/8-1:0] s_axi_wstrb,
    output logic                   s_axi_wready,
    output logic [1:0]             s_axi_bresp,
    output logic                   s_axi_bvalid,
    input  logic                   s_axi_bready,

    input  logic [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  logic [7:0]             s_axi_arlen,
    input  logic [2:0]             s_axi_arsize,
    input  logic [1:0]             s_axi_arburst,
    input  logic                   s_axi_arvalid,
    output logic                   s_axi_arready,
    output logic [DATA_WIDTH-1:0]  s_axi_rdata,
    output logic [1:0]             s_axi_rresp,
    output logic                   s_axi_rlast,
    output logic                   s_axi_rvalid,
    input  logic                   s_axi_rready
);

    logic [DATA_WIDTH-1:0] memory [0:MEM_DEPTH-1];

    typedef enum logic [2:0] {IDLE, WRITE_ADDR, WRITE_DATA, WRITE_RESP, READ_ADDR, READ_DATA, DONE} state_t;
    state_t state;

    logic [ADDR_WIDTH-1:0] write_addr;
    logic [7:0]            write_beat_cnt;
    logic [7:0]            write_burst_len;
    logic                   write_active;

    logic [ADDR_WIDTH-1:0] read_addr;
    logic [7:0]            read_beat_cnt;
    logic [7:0]            read_burst_len;
    logic                   read_active;
    logic [DATA_WIDTH-1:0]  read_data_reg;

    logic [3:0]             delay_counter;
    logic [3:0]             random_delay;
    logic                   delay_active;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            delay_counter <= 0;
            delay_active <= 0;
        end else begin
            if (delay_active) begin
                if (delay_counter > 0) begin
                    delay_counter <= delay_counter - 1;
                end else begin
                    delay_active <= 0;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            random_delay <= MIN_LATENCY;
        end else begin
            if ({$random} & 8'hFF) > 8'h80) begin
                random_delay <= {$urandom_range(MAX_LATENCY, MIN_LATENCY)};
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            s_axi_awready <= 0;
            s_axi_wready <= 0;
            s_axi_bvalid <= 0;
            s_axi_bresp <= 2'b00;
            write_beat_cnt <= 0;
            write_active <= 0;
            s_axi_arready <= 0;
            s_axi_rvalid <= 0;
            s_axi_rresp <= 2'b00;
            s_axi_rlast <= 0;
            read_beat_cnt <= 0;
            read_active <= 0;
        end else begin
            case (state)
                IDLE: begin
                    s_axi_awready <= 1;
                    s_axi_arready <= 1;
                    if (s_axi_awvalid && s_axi_awready) begin
                        write_addr <= s_axi_awaddr;
                        write_burst_len <= s_axi_awlen + 1;
                        write_beat_cnt <= 0;
                        write_active <= 1;
                        s_axi_awready <= 0;
                        s_axi_arready <= 0;
                        state <= WRITE_DATA;
                    end else if (s_axi_arvalid && s_axi_arready) begin
                        read_addr <= s_axi_araddr;
                        read_burst_len <= s_axi_arlen + 1;
                        read_beat_cnt <= 0;
                        read_active <= 1;
                        s_axi_awready <= 0;
                        s_axi_arready <= 0;
                        delay_counter <= random_delay;
                        delay_active <= 1;
                        state <= READ_DATA;
                    end
                end

                WRITE_DATA: begin
                    s_axi_wvalid <= 1;
                    s_axi_wdata <= 32'hDEADBEEF;
                    s_axi_wstrb <= 4'hF;
                    s_axi_wlast <= (write_beat_cnt == write_burst_len - 1);

                    if (s_axi_wvalid && s_axi_wready) begin
                        write_beat_cnt <= write_beat_cnt + 1;
                        if (s_axi_wlast) begin
                            s_axi_wvalid <= 0;
                            s_axi_wready <= 0;
                            delay_counter <= random_delay;
                            delay_active <= 1;
                            state <= WRITE_RESP;
                        end
                    end
                end

                WRITE_RESP: begin
                    if (!delay_active) begin
                        s_axi_bvalid <= 1;
                        s_axi_bresp <= 2'b00;
                        write_active <= 0;
                    end

                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 0;
                        s_axi_bready <= 0;
                        state <= IDLE;
                    end
                end

                READ_DATA: begin
                    if (!delay_active) begin
                        s_axi_rvalid <= 1;
                        s_axi_rdata <= memory[read_addr];
                        s_axi_rresp <= 2'b00;

                        if (s_axi_rvalid && s_axi_rready) begin
                            read_beat_cnt <= read_beat_cnt + 1;
                            read_addr <= read_addr + 1;

                            if (read_beat_cnt == read_burst_len - 1) begin
                                s_axi_rlast <= 1;
                                read_active <= 0;
                            end
                        end
                    end

                    if (s_axi_rlast && s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 0;
                        s_axi_rready <= 0;
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign s_axi_rdata = read_data_reg;

endmodule
