`timescale 1ns / 1ps

/**
 * Module: acl_match_engine
 * Task 15.2: Enhanced Match Engine (Patch)
 * 功能: 抗碰撞ACL匹配引擎
 * - 使用CRC16映射到4K深度BRAM
 * - 使用2-way Set Associative（每个Hash桶存2个指纹）
 * - 命中且指纹匹配 -> Drop
 */

module acl_match_engine #(
    parameter ADDR_WIDTH = 12,    // 4K entries
    parameter DATA_WIDTH = 104,   // 5-tuple: 32+16+32+16+8 = 104 bits
    parameter TAG_WIDTH = 104,    // Full 5-tuple as tag
    parameter NUM_WAYS   = 2      // 2-way set associative
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // =========================================================================
    // 5-Tuple Input
    // =========================================================================
    input  logic [DATA_WIDTH-1:0] tuple_in,
    input  logic                   tuple_valid,

    // =========================================================================
    // ACL Configuration Interface (AXI-Lite)
    // =========================================================================
    input  logic                   acl_write_en,
    input  logic [ADDR_WIDTH-1:0] acl_write_addr,
    input  logic [DATA_WIDTH-1:0] acl_write_data,
    input  logic                   acl_clear,

    // =========================================================================
    // Control Signals
    // =========================================================================
    output logic                   acl_hit,
    output logic                   acl_drop,
    output logic [NUM_WAYS-1:0]   hit_way,
    output logic [31:0]            hit_count,
    output logic [31:0]            miss_count
);

    // =========================================================================
    // CRC16 Calculation (for Hash)
    // =========================================================================
    function [15:0] crc16_hash;
        input [DATA_WIDTH-1:0] data;
        begin
            // Simple CRC16-CCITT
            crc16_hash = 16'h0000;
            for (int i = DATA_WIDTH-1; i >= 0; i--) begin
                if (data[i] ^ crc16_hash[15]) begin
                    crc16_hash = (crc16_hash << 1) ^ 16'h1021;
                end else begin
                    crc16_hash = crc16_hash << 1;
                end
            end
        end
    endfunction

    // =========================================================================
    // Internal Signals
    // =========================================================================
    logic [15:0]                  hash_value;
    logic [ADDR_WIDTH-1:0]        bram_addr;
    logic [NUM_WAYS-1:0]          way_hit;
    logic [NUM_WAYS-1:0]          way_valid;
    logic [TAG_WIDTH-1:0]          way_tag [0:NUM_WAYS-1];
    logic [TAG_WIDTH-1:0]          bram_dout [0:NUM_WAYS-1];
    logic [TAG_WIDTH-1:0]          bram_din;
    logic                          bram_wen;
    logic [NUM_WAYS-1:0]          bram_wen_way;
    logic                          acl_match;

    // Counters
    logic [31:0]                  hit_cnt;
    logic [31:0]                  miss_cnt;

    // =========================================================================
    // Hash Calculation
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hash_value <= 16'd0;
        end else begin
            if (tuple_valid) begin
                hash_value <= crc16_hash(tuple_in);
            end
        end
    end

    assign bram_addr = hash_value[ADDR_WIDTH-1:0];

    // =========================================================================
    // 2-way Set Associative BRAM
    // =========================================================================
    // Way 0 BRAM
    (* RAM_STYLE = "BLOCK" *)
    logic [TAG_WIDTH-1:0] bram_way0 [0:(1<<ADDR_WIDTH)-1];

    // Way 1 BRAM
    (* RAM_STYLE = "BLOCK" *)
    logic [TAG_WIDTH-1:0] bram_way1 [0:(1<<ADDR_WIDTH)-1];

    // BRAM Read
    always_ff @(posedge clk) begin
        if (!acl_write_en && tuple_valid) begin
            bram_dout[0] <= bram_way0[bram_addr];
            bram_dout[1] <= bram_way1[bram_addr];
        end
    end

    // BRAM Write
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize BRAM to zero
            for (int i = 0; i < (1<<ADDR_WIDTH); i++) begin
                bram_way0[i] <= {(TAG_WIDTH){1'b0}};
                bram_way1[i] <= {(TAG_WIDTH){1'b0}};
            end
        end else begin
            // Write to ACL BRAM
            if (acl_write_en) begin
                // Round-robin allocation
                if (bram_way0[acl_write_addr] == {(TAG_WIDTH){1'b0}}) begin
                    bram_way0[acl_write_addr] <= acl_write_data;
                end else if (bram_way1[acl_write_addr] == {(TAG_WIDTH){1'b0}}) begin
                    bram_way1[acl_write_addr] <= acl_write_data;
                end else begin
                    // Both ways occupied, replace way 0
                    bram_way0[acl_write_addr] <= acl_write_data;
                end
            end

            // Clear ACL
            if (acl_clear) begin
                for (int i = 0; i < (1<<ADDR_WIDTH); i++) begin
                    bram_way0[i] <= {(TAG_WIDTH){1'b0}};
                    bram_way1[i] <= {(TAG_WIDTH){1'b0}};
                end
            end
        end
    end

    // =========================================================================
    // Tag Comparison
    // =========================================================================
    always_comb begin
        way_hit[0] = (bram_dout[0] != {TAG_WIDTH{1'b0}}) &&
                     (bram_dout[0] == tuple_in);
        way_hit[1] = (bram_dout[1] != {TAG_WIDTH{1'b0}}) &&
                     (bram_dout[1] == tuple_in);
        way_valid[0] = (bram_dout[0] != {TAG_WIDTH{1'b0}});
        way_valid[1] = (bram_dout[1] != {TAG_WIDTH{1'b0}});
        way_tag[0] = bram_dout[0];
        way_tag[1] = bram_dout[1];
    end

    assign acl_match = (way_hit[0] || way_hit[1]);

    // Hit Way Selection (priority to way 0)
    always_comb begin
        if (way_hit[0]) begin
            hit_way = 2'b01;  // Way 0 hit
        end else if (way_hit[1]) begin
            hit_way = 2'b10;  // Way 1 hit
        end else begin
            hit_way = 2'b00;
        end
    end

    // =========================================================================
    // Counters
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hit_cnt <= 32'd0;
            miss_cnt <= 32'd0;
        end else begin
            if (tuple_valid) begin
                if (acl_match) begin
                    hit_cnt <= hit_cnt + 1'b1;
                end else begin
                    miss_cnt <= miss_cnt + 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign acl_hit = acl_match;
    assign acl_drop = acl_match;  // Hit -> Drop
    assign hit_count = hit_cnt;
    assign miss_count = miss_cnt;

endmodule
