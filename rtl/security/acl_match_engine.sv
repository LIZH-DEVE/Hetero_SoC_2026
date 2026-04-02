`ifndef ACL_MATCH_ENGINE_SV
`define ACL_MATCH_ENGINE_SV

`timescale 1ns / 1ps

module acl_match_engine #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 104,
    parameter TAG_WIDTH  = 104,
    parameter NUM_WAYS   = 2
)(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic [DATA_WIDTH-1:0]  tuple_in,
    input  logic                   tuple_valid,
    input  logic                   acl_write_en,
    input  logic [ADDR_WIDTH-1:0]  acl_write_addr,
    input  logic [DATA_WIDTH-1:0]  acl_write_data,
    input  logic                   acl_clear,
    output logic                   result_valid,
    output logic                   acl_hit,
    output logic                   acl_drop,
    output logic [NUM_WAYS-1:0]    hit_way,
    output logic [31:0]            hit_count,
    output logic [31:0]            miss_count
);

    localparam int DEPTH = (1 << ADDR_WIDTH);
    localparam int GEN_WIDTH = 16;

    function automatic [15:0] tuple_hash;
        input [DATA_WIDTH-1:0] data;
        logic [15:0] h;
        begin
            h = data[15:0] ^ data[31:16] ^ data[47:32] ^ data[63:48] ^
                data[79:64] ^ data[95:80] ^ {8'h00, data[103:96]};
            h = h ^ {h[7:0], h[15:8]} ^ 16'h9E37;
            tuple_hash = h ^ {h[10:0], h[15:11]} ^ (h >> 3);
        end
    endfunction

    (* RAM_STYLE = "BLOCK" *) logic [TAG_WIDTH-1:0] bram_way0 [0:DEPTH-1];
    (* RAM_STYLE = "BLOCK" *) logic [TAG_WIDTH-1:0] bram_way1 [0:DEPTH-1];
    logic [GEN_WIDTH-1:0] gen_way0 [0:DEPTH-1];
    logic [GEN_WIDTH-1:0] gen_way1 [0:DEPTH-1];
    logic                 replace_sel [0:DEPTH-1];
    integer init_idx;

    logic [GEN_WIDTH-1:0] active_gen;

    logic [ADDR_WIDTH-1:0] lookup_addr_q;
    logic [TAG_WIDTH-1:0]  lookup_tuple_q;
    logic [GEN_WIDTH-1:0]  lookup_gen_q;
    logic                  lookup_req_q;

    logic [TAG_WIDTH-1:0]  rd_way0_q, rd_way1_q;
    logic [GEN_WIDTH-1:0]  rd_gen0_q, rd_gen1_q;
    logic                  match_valid_q;

    logic way0_valid_cmp, way1_valid_cmp;
    logic way0_hit_cmp, way1_hit_cmp;
    logic any_hit_cmp;

    logic result_valid_r;
    logic acl_hit_r, acl_drop_r;
    logic [NUM_WAYS-1:0] hit_way_r;
    logic [31:0] hit_cnt, miss_cnt;
    logic [15:0] tuple_hash_now;

    assign tuple_hash_now = tuple_hash(tuple_in);

    assign way0_valid_cmp = (rd_gen0_q == lookup_gen_q);
    assign way1_valid_cmp = (rd_gen1_q == lookup_gen_q);
    assign way0_hit_cmp = way0_valid_cmp && (rd_way0_q == lookup_tuple_q);
    assign way1_hit_cmp = way1_valid_cmp && (rd_way1_q == lookup_tuple_q);
    assign any_hit_cmp  = way0_hit_cmp || way1_hit_cmp;

    initial begin
        for (init_idx = 0; init_idx < DEPTH; init_idx = init_idx + 1) begin
            bram_way0[init_idx] = '0;
            bram_way1[init_idx] = '0;
            gen_way0[init_idx] = '0;
            gen_way1[init_idx] = '0;
            replace_sel[init_idx] = 1'b0;
        end
    end

    // Keep the BRAM-facing lookup pipeline synchronous so inferred RAM address
    // pins are not driven by async-reset flops.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            lookup_addr_q  <= '0;
            lookup_tuple_q <= '0;
            lookup_gen_q   <= '0;
            lookup_req_q   <= 1'b0;
        end else begin
            lookup_req_q  <= tuple_valid;

            if (tuple_valid) begin
                lookup_addr_q  <= tuple_hash_now[ADDR_WIDTH-1:0];
                lookup_tuple_q <= tuple_in;
                lookup_gen_q   <= active_gen;
            end
        end
    end

    // Keep BRAM write-side generation state on synchronous reset so RAM
    // control pins are not driven by async-reset flops.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            active_gen     <= {{(GEN_WIDTH-1){1'b0}}, 1'b1};
            match_valid_q  <= 1'b0;
            result_valid_r <= 1'b0;
            acl_hit_r      <= 1'b0;
            acl_drop_r     <= 1'b0;
            hit_way_r      <= '0;
            hit_cnt        <= 32'd0;
            miss_cnt       <= 32'd0;
        end else begin
            match_valid_q <= lookup_req_q;
            result_valid_r <= 1'b0;
            acl_hit_r <= 1'b0;
            acl_drop_r <= 1'b0;
            hit_way_r <= '0;

            if (acl_clear) begin
                if (active_gen == {GEN_WIDTH{1'b1}}) begin
                    active_gen <= {{(GEN_WIDTH-1){1'b0}}, 1'b1};
                end else begin
                    active_gen <= active_gen + 1'b1;
                end
            end

            if (match_valid_q) begin
                result_valid_r <= 1'b1;
                acl_hit_r  <= any_hit_cmp;
                acl_drop_r <= any_hit_cmp;

                if (way0_hit_cmp) begin
                    hit_way_r <= {{(NUM_WAYS-1){1'b0}}, 1'b1};
                end else if (way1_hit_cmp) begin
                    hit_way_r <= {1'b1, {(NUM_WAYS-1){1'b0}}};
                end else begin
                    hit_way_r <= '0;
                end

                if (any_hit_cmp) begin
                    hit_cnt <= hit_cnt + 1'b1;
                end else begin
                    miss_cnt <= miss_cnt + 1'b1;
                end
            end
        end
    end

    // Memory access block: no async reset so BRAM inference remains valid.
    always_ff @(posedge clk) begin
        if (lookup_req_q) begin
            rd_way0_q <= bram_way0[lookup_addr_q];
            rd_way1_q <= bram_way1[lookup_addr_q];
            rd_gen0_q <= gen_way0[lookup_addr_q];
            rd_gen1_q <= gen_way1[lookup_addr_q];
        end

        if (acl_write_en) begin
            if (gen_way0[acl_write_addr] != active_gen) begin
                bram_way0[acl_write_addr] <= acl_write_data;
                gen_way0[acl_write_addr]  <= active_gen;
                replace_sel[acl_write_addr] <= 1'b1;
            end else if (gen_way1[acl_write_addr] != active_gen) begin
                bram_way1[acl_write_addr] <= acl_write_data;
                gen_way1[acl_write_addr]  <= active_gen;
                replace_sel[acl_write_addr] <= 1'b0;
            end else if (replace_sel[acl_write_addr] == 1'b1) begin
                bram_way1[acl_write_addr] <= acl_write_data;
                gen_way1[acl_write_addr]  <= active_gen;
                replace_sel[acl_write_addr] <= 1'b0;
            end else begin
                bram_way0[acl_write_addr] <= acl_write_data;
                gen_way0[acl_write_addr]  <= active_gen;
                replace_sel[acl_write_addr] <= 1'b1;
            end
        end
    end

    assign result_valid = result_valid_r;
    assign acl_hit    = acl_hit_r;
    assign acl_drop   = acl_drop_r;
    assign hit_way    = hit_way_r;
    assign hit_count  = hit_cnt;
    assign miss_count = miss_cnt;

endmodule
`endif
