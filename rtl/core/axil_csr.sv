`timescale 1ns / 1ps

/**
 * 模块名称: axil_csr
 * 版本: 3.0 (Day 6 - 集成双引擎控制逻辑)
 * 描述: AXI4-Lite 控制/状态寄存器从机 (Slave)
 *
 * [核心功能]
 * 1. 寄存器读写映射 (0x00 - 0x1C)。
 * 2. 硬件防御机制：拦截非对齐地址 (Task 1.3)。
 * 3. 协议稳健性：实现读写通道解耦，防止总线死锁。
 * 4. [Day 6 新增] 双引擎调度：支持 AES/SM4 算法切换与密钥配置。
 */

module axil_csr #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // =========================================================================
    // 1. AXI-Lite 从机接口 (来自 Zynq PS / CPU)
    // [Source: AMBA AXI4-Lite Protocol Specification]
    // =========================================================================
    
    // 写地址通道 (Write Address Channel)
    input  logic [ADDR_WIDTH-1:0]  s_axil_awaddr,
    input  logic                   s_axil_awvalid,
    output logic                   s_axil_awready,
    
    // 写数据通道 (Write Data Channel)
    input  logic [DATA_WIDTH-1:0]  s_axil_wdata,
    input  logic [3:0]             s_axil_wstrb, // [关键] 字节选通掩码
    input  logic                   s_axil_wvalid,
    output logic                   s_axil_wready,
    
    // 写响应通道 (Write Response Channel)
    output logic [1:0]             s_axil_bresp,
    output logic                   s_axil_bvalid,
    input  logic                   s_axil_bready,

    // 读地址通道 (Read Address Channel)
    input  logic [ADDR_WIDTH-1:0]  s_axil_araddr,
    input  logic                   s_axil_arvalid,
    output logic                   s_axil_arready,
    
    // 读数据通道 (Read Data Channel)
    output logic [DATA_WIDTH-1:0]  s_axil_rdata,
    output logic                   s_axil_rvalid,
    input  logic                   s_axil_rready,

    // =========================================================================
    // 2. 硬件控制接口 (直连 DMA Engine & Crypto Engine)
    // [Source: Internal Micro-Architecture Definition]
    // =========================================================================
    
    // --- DMA 控制信号 ---
    output logic                   o_start,     // 启动脉冲 (Auto-clearing)
    output logic [31:0]            o_base_addr, // DMA 源地址
    output logic [31:0]            o_len,       // DMA 传输长度
    
    // --- [Day 6 新增] 加密核心控制信号 ---
    output logic                   o_algo_sel,  // 0: AES, 1: SM4
    output logic                   o_enc_dec,   // 0: Encrypt, 1: Decrypt (预留)
    output logic [127:0]           o_key,       // 128-bit 通用密钥
    
    // --- 状态反馈信号 ---
    input  logic                   i_done,      // 硬件完成信号
    input  logic                   i_error      // 硬件错误信号
);

    // =========================================================================
    // 内部寄存器定义 (Register Map)
    // =========================================================================
    logic [31:0] reg_ctrl;       // Offset: 0x00 (Control: Start, Algo, Mode)
    logic [31:0] reg_base_addr;  // Offset: 0x08 (Source Address)
    logic [31:0] reg_len;        // Offset: 0x0C (Length)
    
    // [Day 6 Expansion] 128-bit 密钥寄存器组
    // [Source: NIST AES / GM/T SM4 Spec] 双算法均需 128-bit 密钥
    logic [31:0] reg_key0;       // Offset: 0x10 (Key[31:0])
    logic [31:0] reg_key1;       // Offset: 0x14 (Key[63:32])
    logic [31:0] reg_key2;       // Offset: 0x18 (Key[95:64])
    logic [31:0] reg_key3;       // Offset: 0x1C (Key[127:96])

    // 握手状态标志 (Handshake Flags)
    // [Source: Robust Design Pattern] 用于解耦 AW 和 W 通道
    logic aw_received;          
    logic w_received;           
    logic [ADDR_WIDTH-1:0] awaddr_latch; 

    // 硬件防御逻辑
    logic is_unaligned;
    assign is_unaligned = (reg_base_addr[5:0] != 6'h0);
    logic hw_error_latch;

    // [辅助函数] 字节选通掩码应用
    function logic [31:0] apply_wstrb(input logic [31:0] old_val, input logic [31:0] new_val, input logic [3:0] strb);
        apply_wstrb[ 7: 0] = strb[0] ? new_val[ 7: 0] : old_val[ 7: 0];
        apply_wstrb[15: 8] = strb[1] ? new_val[15: 8] : old_val[15: 8];
        apply_wstrb[23:16] = strb[2] ? new_val[23:16] : old_val[23:16];
        apply_wstrb[31:24] = strb[3] ? new_val[31:24] : old_val[31:24];
    endfunction

    // =========================================================================
    // Part 1: 写通道逻辑 (Write Channel - Decoupled Architecture)
    // =========================================================================
    
    // 1.1 AW Ready Generation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_awready <= 1'b0;
            aw_received    <= 1'b0;
            awaddr_latch   <= '0;
        end else begin
            if (~s_axil_awready && s_axil_awvalid && ~aw_received && ~s_axil_bvalid) begin
                s_axil_awready <= 1'b1;
                aw_received    <= 1'b1;
                awaddr_latch   <= s_axil_awaddr;
            end else begin
                s_axil_awready <= 1'b0;
            end
            
            if (s_axil_bvalid && s_axil_bready) begin
                aw_received <= 1'b0;
            end
        end
    end

    // 1.2 W Ready Generation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_wready <= 1'b0;
            w_received    <= 1'b0;
        end else begin
            if (~s_axil_wready && s_axil_wvalid && ~w_received && ~s_axil_bvalid) begin
                s_axil_wready <= 1'b1;
                w_received    <= 1'b1;
            end else begin
                s_axil_wready <= 1'b0;
            end

            if (s_axil_bvalid && s_axil_bready) begin
                w_received <= 1'b0;
            end
        end
    end

    // 1.3 寄存器更新逻辑 (Register Update)
    logic write_en;
    assign write_en = aw_received && w_received && ~s_axil_bvalid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl      <= 0;
            reg_base_addr <= 0;
            reg_len       <= 0;
            reg_key0      <= 0;
            reg_key1      <= 0;
            reg_key2      <= 0;
            reg_key3      <= 0;
            o_start       <= 0;
            hw_error_latch <= 0;
        end else begin
            // [Auto-clear] 启动信号脉冲，下一拍自动拉低
            o_start <= 1'b0; 
            
            // [Error Latch] 锁存硬件错误
            if (i_error) hw_error_latch <= 1'b1;

            if (write_en) begin
                case (awaddr_latch[7:0])
                    8'h00: begin // --- Control Register ---
                        logic [31:0] next_ctrl;
                        next_ctrl = apply_wstrb(reg_ctrl, s_axil_wdata, s_axil_wstrb);
                        
                        // [Critical Logic] 安全启动检查
                        // 仅当写入 Bit 0 为 '1' 时触发
                        if (s_axil_wstrb[0] && s_axil_wdata[0]) begin
                            if (is_unaligned) begin
                                hw_error_latch <= 1'b1; // 地址未对齐，报错
                                o_start        <= 1'b0; // 拦截启动
                            end else begin
                                hw_error_latch <= 1'b0; // 清除旧错误
                                o_start        <= 1'b1; // 允许启动
                            end
                        end
                        reg_ctrl <= next_ctrl;
                    end
                    
                    8'h08: reg_base_addr <= apply_wstrb(reg_base_addr, s_axil_wdata, s_axil_wstrb);
                    8'h0C: reg_len       <= apply_wstrb(reg_len, s_axil_wdata, s_axil_wstrb);
                    
                    // [Day 6 Feature] Key Configuration
                    8'h10: reg_key0      <= apply_wstrb(reg_key0, s_axil_wdata, s_axil_wstrb);
                    8'h14: reg_key1      <= apply_wstrb(reg_key1, s_axil_wdata, s_axil_wstrb);
                    8'h18: reg_key2      <= apply_wstrb(reg_key2, s_axil_wdata, s_axil_wstrb);
                    8'h1C: reg_key3      <= apply_wstrb(reg_key3, s_axil_wdata, s_axil_wstrb);
                    
                    default: ; // Ignore undefined
                endcase
            end
        end
    end

    // 1.4 写响应生成 (Write Response)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_bvalid <= 1'b0;
            s_axil_bresp  <= 2'b00;
        end else begin
            if (write_en) begin
                s_axil_bvalid <= 1'b1;
                s_axil_bresp  <= 2'b00; // OKAY
            end else if (s_axil_bready && s_axil_bvalid) begin
                s_axil_bvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Part 2: 读通道逻辑 (Read Channel)
    // =========================================================================
    
    // 状态字拼接：{Reserved, Error, Done}
    logic [31:0] reg_status;
    assign reg_status = {30'd0, (i_error | hw_error_latch), i_done};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= 0;
        end else begin
            // 2.1 读地址握手
            if (~s_axil_arready && s_axil_arvalid) begin
                s_axil_arready <= 1'b1;
            end else begin
                s_axil_arready <= 1'b0;
            end

            // 2.2 读数据返回 (Latency = 1)
            if (s_axil_arready && s_axil_arvalid && ~s_axil_rvalid) begin
                s_axil_rvalid <= 1'b1;
                case (s_axil_araddr[7:0])
                    8'h00: s_axil_rdata <= reg_ctrl;
                    8'h04: s_axil_rdata <= reg_status;
                    8'h08: s_axil_rdata <= reg_base_addr;
                    8'h0C: s_axil_rdata <= reg_len;
                    
                    // [Debug Capability] 支持回读密钥以验证配置
                    8'h10: s_axil_rdata <= reg_key0;
                    8'h14: s_axil_rdata <= reg_key1;
                    8'h18: s_axil_rdata <= reg_key2;
                    8'h1C: s_axil_rdata <= reg_key3;
                    
                    default: s_axil_rdata <= 32'h0;
                endcase
            end else if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 3. 硬件直连输出映射 (Output Mapping)
    // =========================================================================
    assign o_base_addr = reg_base_addr;
    assign o_len       = reg_len;
    
    // [Day 6 Mapping] 控制信号与密钥拼接
    assign o_algo_sel  = reg_ctrl[1]; // Bit 1: 0=AES, 1=SM4
    assign o_enc_dec   = reg_ctrl[2]; // Bit 2: 0=Enc, 1=Dec
    
    // 注意：FPGA 内部大端序通常为 {Key3, Key2, Key1, Key0} 对应 128-bit
    assign o_key       = {reg_key3, reg_key2, reg_key1, reg_key0}; 

endmodule