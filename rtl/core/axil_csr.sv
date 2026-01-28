`timescale 1ns / 1ps

module axil_csr #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // --- [原有] AXI-Lite 接口 (完全不变) ---
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
    output logic                   s_axil_rvalid,
    input  logic                   s_axil_rready,

    // --- [原有] 硬件控制接口 (完全不变) ---
    output logic                   o_start,
    output logic [31:0]            o_base_addr,
    output logic [31:0]            o_len,
    output logic                   o_algo_sel,
    output logic                   o_enc_dec,
    output logic [127:0]           o_key,
    input  logic                   i_done,
    input  logic                   i_error,

    // --- [Day 8 新增接口] (放在最后，减少对齐干扰) ---
    output logic                   o_hw_init,     // 新增: 0x00 HW_INIT
    output logic                   o_cache_flush, // 新增: 0x40 Cache Ctrl
    input  logic [31:0]            i_acl_cnt      // 新增: 0x44 ACL Counter
);

    // ... 内部逻辑保持我上一条回复的内容一致，此处为节省篇幅省略 ...
    // ... 请务必把上一条回复中 always_ff 和 always_comb 的逻辑填入这里 ...
    // ... 核心是把 0x00(Bit1), 0x40, 0x44 的逻辑加进去 ...
    
    // (为了方便你覆盖，这里把关键逻辑再贴一次，确保你不用翻回去找)
    
    // 内部寄存器
    logic [31:0] reg_ctrl;
    logic [31:0] reg_base_addr;
    logic [31:0] reg_len;
    logic [31:0] reg_key0, reg_key1, reg_key2, reg_key3;
    logic [31:0] reg_cache_ctrl; // New

    // 握手逻辑
    logic aw_received, w_received;
    logic [ADDR_WIDTH-1:0] awaddr_latch;
    logic write_en;
    assign write_en = aw_received && w_received && ~s_axil_bvalid;

    // 硬件防御
    logic is_unaligned;
    assign is_unaligned = (reg_base_addr[5:0] != 6'h0);
    logic hw_error_latch;

    // 辅助函数
    function logic [31:0] apply_wstrb(input logic [31:0] old_val, input logic [31:0] new_val, input logic [3:0] strb);
        apply_wstrb[ 7: 0] = strb[0] ? new_val[ 7: 0] : old_val[ 7: 0];
        apply_wstrb[15: 8] = strb[1] ? new_val[15: 8] : old_val[15: 8];
        apply_wstrb[23:16] = strb[2] ? new_val[23:16] : old_val[23:16];
        apply_wstrb[31:24] = strb[3] ? new_val[31:24] : old_val[31:24];
    endfunction

    // ----------------------------------------------------------
    // Write Logic
    // ----------------------------------------------------------
    // AW Ready
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin s_axil_awready <= 0; aw_received <= 0; awaddr_latch <= 0; end
        else begin
            if (~s_axil_awready && s_axil_awvalid && ~aw_received && ~s_axil_bvalid) begin
                s_axil_awready <= 1; aw_received <= 1; awaddr_latch <= s_axil_awaddr;
            end else s_axil_awready <= 0;
            if (s_axil_bvalid && s_axil_bready) aw_received <= 0;
        end
    end
    // W Ready
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin s_axil_wready <= 0; w_received <= 0; end
        else begin
            if (~s_axil_wready && s_axil_wvalid && ~w_received && ~s_axil_bvalid) begin
                s_axil_wready <= 1; w_received <= 1;
            end else s_axil_wready <= 0;
            if (s_axil_bvalid && s_axil_bready) w_received <= 0;
        end
    end
    // Register Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl <= 0; reg_base_addr <= 0; reg_len <= 0;
            reg_key0 <= 0; reg_key1 <= 0; reg_key2 <= 0; reg_key3 <= 0;
            reg_cache_ctrl <= 0;
            o_start <= 0; o_hw_init <= 0; hw_error_latch <= 0;
        end else begin
            o_start <= 0; o_hw_init <= 0; // Auto-clear
            if (i_error) hw_error_latch <= 1;
            if (write_en) begin
                case (awaddr_latch[7:0])
                    8'h00: begin
                        logic [31:0] next_ctrl;
                        next_ctrl = apply_wstrb(reg_ctrl, s_axil_wdata, s_axil_wstrb);
                        if (s_axil_wstrb[0] && s_axil_wdata[0]) begin // Start
                            if (is_unaligned) begin hw_error_latch <= 1; o_start <= 0; end
                            else begin hw_error_latch <= 0; o_start <= 1; end
                        end
                        if (s_axil_wstrb[0] && s_axil_wdata[1]) o_hw_init <= 1; // HW Init
                        reg_ctrl <= next_ctrl;
                    end
                    8'h08: reg_base_addr <= apply_wstrb(reg_base_addr, s_axil_wdata, s_axil_wstrb);
                    8'h0C: reg_len <= apply_wstrb(reg_len, s_axil_wdata, s_axil_wstrb);
                    8'h10: reg_key0 <= apply_wstrb(reg_key0, s_axil_wdata, s_axil_wstrb);
                    8'h14: reg_key1 <= apply_wstrb(reg_key1, s_axil_wdata, s_axil_wstrb);
                    8'h18: reg_key2 <= apply_wstrb(reg_key2, s_axil_wdata, s_axil_wstrb);
                    8'h1C: reg_key3 <= apply_wstrb(reg_key3, s_axil_wdata, s_axil_wstrb);
                    8'h40: reg_cache_ctrl <= apply_wstrb(reg_cache_ctrl, s_axil_wdata, s_axil_wstrb);
                    default: ;
                endcase
            end
        end
    end
    // B Response
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin s_axil_bvalid <= 0; s_axil_bresp <= 0; end
        else begin
            if (write_en) s_axil_bvalid <= 1;
            else if (s_axil_bready && s_axil_bvalid) s_axil_bvalid <= 0;
        end
    end

    // ----------------------------------------------------------
    // Read Logic
    // ----------------------------------------------------------
    logic [31:0] reg_status;
    assign reg_status = {30'd0, (i_error | hw_error_latch), i_done};
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin s_axil_arready <= 0; s_axil_rvalid <= 0; s_axil_rdata <= 0; end
        else begin
            if (~s_axil_arready && s_axil_arvalid) s_axil_arready <= 1;
            else s_axil_arready <= 0;

            if (s_axil_arready && s_axil_arvalid && ~s_axil_rvalid) begin
                s_axil_rvalid <= 1;
                case (s_axil_araddr[7:0])
                    8'h00: s_axil_rdata <= reg_ctrl;
                    8'h04: s_axil_rdata <= reg_status;
                    8'h08: s_axil_rdata <= reg_base_addr;
                    8'h0C: s_axil_rdata <= reg_len;
                    8'h10: s_axil_rdata <= reg_key0;
                    8'h14: s_axil_rdata <= reg_key1;
                    8'h18: s_axil_rdata <= reg_key2;
                    8'h1C: s_axil_rdata <= reg_key3;
                    8'h40: s_axil_rdata <= reg_cache_ctrl;
                    8'h44: s_axil_rdata <= i_acl_cnt; // 直接读取外部输入
                    default: s_axil_rdata <= 0;
                endcase
            end else if (s_axil_rvalid && s_axil_rready) s_axil_rvalid <= 0;
        end
    end

    // ----------------------------------------------------------
    // Outputs
    // ----------------------------------------------------------
    assign o_base_addr = reg_base_addr;
    assign o_len = reg_len;
    assign o_algo_sel = reg_ctrl[1];
    assign o_enc_dec = reg_ctrl[2];
    assign o_key = {reg_key3, reg_key2, reg_key1, reg_key0};
    assign o_cache_flush = reg_cache_ctrl[0];

endmodule