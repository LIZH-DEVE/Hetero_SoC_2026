`timescale 1ns / 1ps

/**
 * Day 16: Hardware Firewall (ACL) verification
 *
 * Scope:
 * - 5-tuple extraction from simplified IPv4 stream
 * - ACL write / hit / miss / clear behavior
 */

module tb_day16_acl;

    logic clk;
    logic rst_n;

    logic [31:0] extractor_s_tdata;
    logic [3:0]  extractor_s_tkeep;
    logic        extractor_s_tlast;
    logic        extractor_s_tvalid;
    logic        extractor_s_tready;

    logic [31:0] src_ip;
    logic [15:0] src_port;
    logic [31:0] dst_ip;
    logic [15:0] dst_port;
    logic [7:0]  protocol;
    logic        tuple_valid;
    logic        tuple_last;

    logic [103:0] manual_tuple_in;
    logic         manual_tuple_valid;
    logic         use_manual_lookup;
    logic         acl_write_en;
    logic [11:0]  acl_write_addr;
    logic [103:0] acl_write_data;
    logic         acl_clear;
    logic         result_valid;
    logic         acl_hit;
    logic         acl_drop;
    logic [1:0]   hit_way;
    logic [31:0]  hit_count;
    logic [31:0]  miss_count;

    logic         tuple_seen;
    logic [31:0]  seen_src_ip;
    logic [15:0]  seen_src_port;
    logic [31:0]  seen_dst_ip;
    logic [15:0]  seen_dst_port;
    logic [7:0]   seen_protocol;
    logic [103:0] extracted_tuple;
    logic [103:0] engine_tuple_in;
    logic         engine_tuple_valid;
    logic         enable_extractor_lookup;
    logic [103:0] hit_tuple;
    logic [103:0] miss_tuple;
    logic [15:0]  hit_hash;
    logic [11:0]  hit_addr;

    int test_pass;
    int test_fail;

    function automatic [15:0] tuple_hash(input [103:0] data);
        logic [15:0] h;
        begin
            h = data[15:0] ^ data[31:16] ^ data[47:32] ^ data[63:48] ^
                data[79:64] ^ data[95:80] ^ {8'h00, data[103:96]};
            h = h ^ {h[7:0], h[15:8]} ^ 16'h9E37;
            tuple_hash = h ^ {h[10:0], h[15:11]} ^ (h >> 3);
        end
    endfunction

    assign extracted_tuple = {protocol, src_ip, src_port, dst_ip, dst_port};
    assign engine_tuple_in = use_manual_lookup ? manual_tuple_in : extracted_tuple;
    assign engine_tuple_valid = use_manual_lookup ? manual_tuple_valid : (enable_extractor_lookup && tuple_valid);

    five_tuple_extractor u_extractor (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(extractor_s_tdata),
        .s_axis_tkeep(extractor_s_tkeep),
        .s_axis_tlast(extractor_s_tlast),
        .s_axis_tvalid(extractor_s_tvalid),
        .s_axis_tready(extractor_s_tready),
        .src_ip(src_ip),
        .src_port(src_port),
        .dst_ip(dst_ip),
        .dst_port(dst_port),
        .protocol(protocol),
        .tuple_valid(tuple_valid),
        .tuple_last(tuple_last)
    );

    acl_match_engine #(
        .ADDR_WIDTH(12),
        .DATA_WIDTH(104),
        .TAG_WIDTH(104),
        .NUM_WAYS(2)
    ) u_acl_engine (
        .clk(clk),
        .rst_n(rst_n),
        .tuple_in(engine_tuple_in),
        .tuple_valid(engine_tuple_valid),
        .acl_write_en(acl_write_en),
        .acl_write_addr(acl_write_addr),
        .acl_write_data(acl_write_data),
        .acl_clear(acl_clear),
        .result_valid(result_valid),
        .acl_hit(acl_hit),
        .acl_drop(acl_drop),
        .hit_way(hit_way),
        .hit_count(hit_count),
        .miss_count(miss_count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        #40;
        rst_n = 1'b1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tuple_seen <= 1'b0;
            seen_src_ip <= 32'd0;
            seen_src_port <= 16'd0;
            seen_dst_ip <= 32'd0;
            seen_dst_port <= 16'd0;
            seen_protocol <= 8'd0;
        end else if (tuple_valid) begin
            tuple_seen <= 1'b1;
            seen_src_ip <= src_ip;
            seen_src_port <= src_port;
            seen_dst_ip <= dst_ip;
            seen_dst_port <= dst_port;
            seen_protocol <= protocol;
        end
    end

    task automatic record_result(
        input bit cond,
        input string pass_msg,
        input string fail_msg
    );
        begin
            if (cond) begin
                $display("[PASS] %s", pass_msg);
                test_pass++;
            end else begin
                $display("[FAIL] %s", fail_msg);
                test_fail++;
            end
        end
    endtask

    task automatic send_word(
        input [31:0] data,
        input        last
    );
        begin
            extractor_s_tdata  <= data;
            extractor_s_tkeep  <= 4'hF;
            extractor_s_tlast  <= last;
            extractor_s_tvalid <= 1'b1;
            do @(posedge clk); while (!extractor_s_tready);
            extractor_s_tvalid <= 1'b0;
            extractor_s_tlast  <= 1'b0;
            extractor_s_tdata  <= '0;
        end
    endtask

    task automatic send_ipv4_packet(
        input [31:0] src_ip_addr,
        input [31:0] dst_ip_addr,
        input [15:0] src_port_num,
        input [15:0] dst_port_num,
        input [7:0]  protocol_type
    );
        begin
            send_word(32'h4500_0000, 1'b0);
            send_word(32'd40, 1'b0);
            send_word(32'h0000_0000, 1'b0);
            send_word({8'd64, protocol_type, 16'h0000}, 1'b0);
            send_word(src_ip_addr, 1'b0);
            send_word(dst_ip_addr, 1'b0);
            send_word({src_port_num, dst_port_num}, 1'b1);
        end
    endtask

    task automatic do_manual_lookup(input [103:0] tuple);
        begin
            use_manual_lookup <= 1'b1;
            manual_tuple_in <= tuple;
            manual_tuple_valid <= 1'b1;
            @(posedge clk);
            manual_tuple_valid <= 1'b0;
            manual_tuple_in <= '0;
            do @(posedge clk); while (!result_valid);
            use_manual_lookup <= 1'b0;
        end
    endtask

    task automatic wait_for_acl_result;
        begin
            do @(posedge clk); while (!result_valid);
        end
    endtask

    initial begin
        extractor_s_tdata = '0;
        extractor_s_tkeep = '0;
        extractor_s_tlast = 1'b0;
        extractor_s_tvalid = 1'b0;
        manual_tuple_in = '0;
        manual_tuple_valid = 1'b0;
        use_manual_lookup = 1'b0;
        enable_extractor_lookup = 1'b0;
        acl_write_en = 1'b0;
        acl_write_addr = '0;
        acl_write_data = '0;
        acl_clear = 1'b0;
        test_pass = 0;
        test_fail = 0;

        wait(rst_n);
        repeat (4) @(posedge clk);

        $display("========================================");
        $display("Day 16: Hardware Firewall (ACL)");
        $display("========================================");

        send_ipv4_packet(32'hC0A8_0001, 32'hC0A8_0002, 16'd1234, 16'd80, 8'd6);
        repeat (4) @(posedge clk);
        record_result(
            tuple_seen &&
            seen_src_ip == 32'hC0A8_0001 &&
            seen_dst_ip == 32'hC0A8_0002 &&
            seen_src_port == 16'd1234 &&
            seen_dst_port == 16'd80 &&
            seen_protocol == 8'd6,
            "5-tuple extractor captured IPv4/TCP fields correctly",
            $sformatf("Extractor mismatch: seen=%0d src_ip=%h dst_ip=%h src_port=%0d dst_port=%0d proto=%0d",
                      tuple_seen, seen_src_ip, seen_dst_ip, seen_src_port, seen_dst_port, seen_protocol)
        );

        hit_tuple  = {8'd6, 32'hC0A8_0001, 16'd1234, 32'hC0A8_0002, 16'd80};
        miss_tuple = {8'd6, 32'hC0A8_0001, 16'd5678, 32'hC0A8_0002, 16'd80};
        hit_hash   = tuple_hash(hit_tuple);
        hit_addr   = hit_hash[11:0];

        acl_write_addr <= hit_addr;
        acl_write_data <= hit_tuple;
        acl_write_en <= 1'b1;
        @(posedge clk);
        acl_write_en <= 1'b0;
        repeat (2) @(posedge clk);

        enable_extractor_lookup = 1'b1;

        send_ipv4_packet(32'hC0A8_0001, 32'hC0A8_0002, 16'd1234, 16'd80, 8'd6);
        wait_for_acl_result();
        record_result(
            acl_hit && acl_drop && hit_count == 32'd1 && miss_count == 32'd0,
            "ACL engine matched the extractor-driven tuple end-to-end",
            $sformatf("ACL hit mismatch: hit=%0d drop=%0d hit_count=%0d miss_count=%0d hit_way=%0d",
                      acl_hit, acl_drop, hit_count, miss_count, hit_way)
        );

        send_ipv4_packet(32'hC0A8_0001, 32'hC0A8_0002, 16'd5678, 16'd80, 8'd6);
        wait_for_acl_result();
        record_result(
            !acl_hit && !acl_drop && hit_count == 32'd1 && miss_count == 32'd1,
            "ACL engine rejected a non-matching extractor-driven tuple",
            $sformatf("ACL miss mismatch: hit=%0d drop=%0d hit_count=%0d miss_count=%0d",
                      acl_hit, acl_drop, hit_count, miss_count)
        );

        acl_clear <= 1'b1;
        @(posedge clk);
        acl_clear <= 1'b0;
        repeat (2) @(posedge clk);

        send_ipv4_packet(32'hC0A8_0001, 32'hC0A8_0002, 16'd1234, 16'd80, 8'd6);
        wait_for_acl_result();
        record_result(
            !acl_hit && !acl_drop && hit_count == 32'd1 && miss_count == 32'd2,
            "ACL clear invalidated previous entries",
            $sformatf("ACL clear mismatch: hit=%0d drop=%0d hit_count=%0d miss_count=%0d",
                      acl_hit, acl_drop, hit_count, miss_count)
        );

        $display("========================================");
        $display("Day 16 Test Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_pass + test_fail);
        $display("Passed:      %0d", test_pass);
        $display("Failed:      %0d", test_fail);

        if (test_fail != 0) begin
            $fatal(1, "Day 16 ACL verification failed with %0d failing tests", test_fail);
        end

        $display("[PASS] Day 16 ACL combined sanity completed");
        $finish;
    end

endmodule
