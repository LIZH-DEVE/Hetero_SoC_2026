`timescale 1ns / 1ps

module sync_fifo #(
    parameter WIDTH = 32,
    parameter DEPTH = 16
)(
    input  logic             clk,
    input  logic             rst_n,
    
    input  logic             wr_en,
    input  logic [WIDTH-1:0] din,
    output logic             full,
    
    input  logic             rd_en,
    output logic [WIDTH-1:0] dout,
    output logic             empty
);

    // 存储空间
    logic [WIDTH-1:0] mem [0:DEPTH-1];
    
    // 指针 (位宽要多一位用于判断空满)
    logic [$clog2(DEPTH):0] cnt;
    logic [$clog2(DEPTH)-1:0] wr_ptr, rd_ptr;

    assign full  = (cnt == DEPTH);
    assign empty = (cnt == 0);
    assign dout  = mem[rd_ptr]; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0;
            wr_ptr <= 0;
            rd_ptr <= 0;
        end else begin
            // Write
            if (wr_en && !full) begin
                mem[wr_ptr] <= din;
                wr_ptr <= wr_ptr + 1;
                if (!rd_en) cnt <= cnt + 1;
            end
            
            // Read
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1;
                if (!wr_en) cnt <= cnt - 1;
            end
        end
    end
endmodule