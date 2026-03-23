`timescale 1ns / 1ps
`default_nettype none

module crypto_robei_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        algo_sel,
    input  wire        encdec,
    input  wire        aes256_en,
    input  wire [31:0] key_word,
    input  wire        key_word_valid,
    input  wire        key_word_last,
    input  wire [31:0] din_word,
    input  wire        din_word_valid,
    input  wire        din_word_last,
    input  wire        start,
    output wire [31:0] dout_word,
    output wire        dout_word_valid,
    output wire        dout_word_last,
    output wire        busy,
    output wire        done
);

    reg [255:0] key_reg;
    reg [127:0] data_reg;
    reg [3:0]   key_word_count;
    reg [2:0]   data_word_count;
    reg         key_loaded;
    reg         data_loaded;

    wire [127:0] engine_dout;
    wire         engine_done;
    wire         engine_busy;
    wire         gearbox_load;
    wire         gearbox_active;
    wire         gearbox_ready;
    reg          start_pulse;

    assign gearbox_load = engine_done;
    assign busy = engine_busy || gearbox_active;
    assign done = dout_word_valid && dout_word_last;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_reg         <= 256'd0;
            data_reg        <= 128'd0;
            key_word_count  <= 4'd0;
            data_word_count <= 3'd0;
            key_loaded      <= 1'b0;
            data_loaded     <= 1'b0;
            start_pulse     <= 1'b0;
        end else begin
            start_pulse <= 1'b0;

            if (key_word_valid) begin
                key_loaded <= 1'b0;
                if (key_word_count == 4'd0) begin
                    key_reg <= {224'd0, key_word};
                end else begin
                    key_reg <= {key_reg[223:0], key_word};
                end

                if (key_word_last) begin
                    key_word_count <= 4'd0;
                    key_loaded <= 1'b1;
                end else begin
                    key_word_count <= key_word_count + 1'b1;
                end
            end

            if (din_word_valid) begin
                data_loaded <= 1'b0;
                if (data_word_count == 3'd0) begin
                    data_reg <= {96'd0, din_word};
                end else begin
                    data_reg <= {data_reg[95:0], din_word};
                end

                if (din_word_last) begin
                    data_word_count <= 3'd0;
                    data_loaded <= 1'b1;
                end else begin
                    data_word_count <= data_word_count + 1'b1;
                end
            end

            if (start && key_loaded && data_loaded && !engine_busy && !gearbox_active) begin
                start_pulse <= 1'b1;
                data_loaded <= 1'b0;
            end
        end
    end

    crypto_engine u_crypto_engine (
        .clk           (clk),
        .rst_n         (rst_n),
        .algo_sel      (algo_sel),
        .encdec        (encdec),
        .start         (start_pulse),
        .i_total_len   (32'd128),
        .i_iv          (128'd0),
        .done          (engine_done),
        .busy          (engine_busy),
        .s_axil_araddr (8'd0),
        .s_axil_rdata  (),
        .aes256_en     (aes256_en),
        .key           (key_reg),
        .din           (data_reg),
        .dout          (engine_dout)
    );

    gearbox_128_to_32 u_gearbox_128_to_32 (
        .clk       (clk),
        .rst_n     (rst_n),
        .din       (engine_dout),
        .din_valid (gearbox_load),
        .din_ready (gearbox_ready),
        .dout      (dout_word),
        .dout_valid(dout_word_valid),
        .dout_last (dout_word_last)
    );

    assign gearbox_active = !gearbox_ready;

endmodule

`default_nettype wire
