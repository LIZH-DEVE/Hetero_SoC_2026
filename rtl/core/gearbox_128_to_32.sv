`timescale 1ns / 1ps
/**
 * 模块名称: gearbox_128_to_32
 * 描述: [Task 4.1] 位宽转换器
 * 将 128-bit 宽的 Crypto/FIFO 数据拆解为 4 个 32-bit 节拍，适配 AXI DMA。
 */
module gearbox_128_to_32 (
    input  logic           clk,
    input  logic           rst_n,

    // 上游接口 (来自 FIFO 128-bit)
    input  logic [127:0]   din,
    input  logic           din_valid, // FIFO 非空
    output logic           din_ready, // 读 FIFO 使能

    // 下游接口 (去往 DMA 32-bit)
    output logic [31:0]    dout,
    output logic           dout_valid,
    input  logic           dout_ready
);

    logic [1:0] cnt;       // 0..3 计数器
    logic [127:0] data_reg; // 暂存 128-bit 数据
    logic active;          // 当前是否正在拆包中

    // 状态机逻辑
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0;
            active <= 0;
            data_reg <= 0;
        end else begin
            if (!active) begin
                // IDLE状态：如果上游有数，且下游准备好接受第一拍
                if (din_valid && dout_ready) begin
                    active <= 1;
                    data_reg <= din; // 锁存数据
                    cnt <= 1;        // 准备发第2拍 (第1拍在本周期直通)
                end
            end else begin
                // BUSY状态：如果下游握手成功
                if (dout_ready) begin
                    if (cnt == 3) begin
                        active <= 0; // 4拍发完，回 IDLE
                        cnt <= 0;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end
            end
        end
    end

    // 组合逻辑输出
    always_comb begin
        if (!active) begin
            // IDLE: 直通模式，准备发 din[31:0]
            dout = din[31:0];
            dout_valid = din_valid; // 仅当上游有数时有效
            din_ready = dout_ready; // 仅当本周期握手成功，才消耗 FIFO
        end else begin
            // BUSY: 发送暂存寄存器的高位
            case (cnt)
                2'd1: dout = data_reg[63:32];
                2'd2: dout = data_reg[95:64];
                2'd3: dout = data_reg[127:96];
                default: dout = 32'd0;
            endcase
            dout_valid = 1'b1; // 内部寄存器肯定有效
            din_ready = 1'b0;  // 拆包期间不读新数据
        end
    end

endmodule