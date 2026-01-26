`timescale 1ns / 1ps

/**
 * 模块名称: axil_csr
 * 版本: 2.2 (修复 WSTRB 端口缺失与协议合规性)
 * 描述: AXI4-Lite 控制/状态寄存器从机 (Slave)
 * * [核心功能]
 * 1. 寄存器读写映射 (0x00, 0x04, 0x08, 0x0C)。
 * 2. 硬件防御机制：拦截非对齐地址 (Task 1.3)。
 * 3. 协议稳健性：实现读写通道解耦，防止总线死锁。
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
    
    // [关键修复] 写选通信号 (Write Strobe)
    // [Source: AXI4 Spec] 每一位对应数据总线的一个字节。
    // CPU 可能只写低8位 (STRB=0001) 或全写 (STRB=1111)。硬件必须尊重此掩码，否则会破坏数据。
    input  logic [3:0]             s_axil_wstrb, 
    
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
    // 2. 硬件控制接口 (直连 DMA Engine)
    // [Source: Internal Micro-Architecture Defintion]
    // =========================================================================
    output logic                   o_start,     // 启动脉冲 (Auto-clearing)
    output logic [31:0]            o_base_addr, // DMA 源地址
    output logic [31:0]            o_len,       // DMA 传输长度
    input  logic                   i_done,      // 硬件完成信号
    input  logic                   i_error      // 硬件错误信号
);

    // =========================================================================
    // 内部寄存器定义 (Register Map)
    // =========================================================================
    logic [31:0] reg_ctrl;       // Addr Offset: 0x00 (Control)
    logic [31:0] reg_base_addr;  // Addr Offset: 0x08 (Source Address)
    logic [31:0] reg_len;        // Addr Offset: 0x0C (Length)

    // 握手状态标志 (Handshake Flags)
    // [Source: Robust Design Pattern] 用于解耦 AW 和 W 通道，允许任意顺序到达
    logic aw_received;           
    logic w_received;            
    logic [ADDR_WIDTH-1:0] awaddr_latch; // 必须锁存地址，因为总线地址可能在握手后立即改变

    // =========================================================================
    // Part 1: 写通道逻辑 (Write Channel - Decoupled Architecture)
    // =========================================================================

    // -------------------------------------------------------------------------
    // 1.1 写地址握手 (AW Ready Generation)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_awready <= 1'b0;
            aw_received    <= 1'b0;
            awaddr_latch   <= '0;
        end else begin
            // [逻辑解析] 仅当空闲(ready=0)且收到valid请求，且当前没有悬而未决的B通道事务时，才接收新地址
            if (~s_axil_awready && s_axil_awvalid && ~aw_received && ~s_axil_bvalid) begin
                s_axil_awready <= 1'b1;
                aw_received    <= 1'b1;
                awaddr_latch   <= s_axil_awaddr; // 立即锁存地址
            end else begin
                s_axil_awready <= 1'b0; // 单周期脉冲，协议要求 Ready 不能一直拉高等待
            end
            
            // 当写响应(B)完成握手，清除接收标志，允许下一轮事务
            if (s_axil_bvalid && s_axil_bready) begin
                aw_received <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 1.2 写数据握手 (W Ready Generation)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_wready <= 1'b0;
            w_received    <= 1'b0;
        end else begin
            // [逻辑解析] 独立于地址通道，允许数据先于地址到达，或后于地址到达
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

    // -------------------------------------------------------------------------
    // 1.3 寄存器更新逻辑 (Register Update)
    // -------------------------------------------------------------------------
    
    // [Source: AXI4 Spec] 只有当 AW 和 W 都成功接收后，才执行实际的寄存器写入
    logic write_en;
    assign write_en = aw_received && w_received && ~s_axil_bvalid;

    // [Source: Task 1.3] 地址对齐检查逻辑 (64-Byte Alignment)
    // 检查 reg_base_addr 的低 6 位是否为 0。如果非零，说明不是 64 字节对齐。
    logic is_unaligned;
    assign is_unaligned = (reg_base_addr[5:0] != 6'h0); 

    // 内部错误锁存器 (用于记录瞬时错误并保持给 CPU 读取)
    logic hw_error_latch;

    // [辅助函数] 字节选通掩码应用
    // 根据 wstrb 的每一位，决定是否更新对应的 8bit 数据
    function logic [31:0] apply_wstrb(input logic [31:0] old_val, input logic [31:0] new_val, input logic [3:0] strb);
        apply_wstrb[ 7: 0] = strb[0] ? new_val[ 7: 0] : old_val[ 7: 0];
        apply_wstrb[15: 8] = strb[1] ? new_val[15: 8] : old_val[15: 8];
        apply_wstrb[23:16] = strb[2] ? new_val[23:16] : old_val[23:16];
        apply_wstrb[31:24] = strb[3] ? new_val[31:24] : old_val[31:24];
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl      <= 0;
            reg_base_addr <= 0;
            reg_len       <= 0;
            o_start       <= 0;
            hw_error_latch <= 0;
        end else begin
            // [Auto-clear] 启动信号是脉冲，下一拍自动拉低
            o_start <= 1'b0; 

            // [Error Latch] 只要 DMA 报了错，或者内部拦截了错误，就锁存住，直到复位
            if (i_error) hw_error_latch <= 1'b1; 

            if (write_en) begin
                // 使用锁存的地址 (awaddr_latch) 进行译码
                case (awaddr_latch[7:0])
                    8'h00: begin // --- Control Register ---
                        logic [31:0] next_ctrl;
                        next_ctrl = apply_wstrb(reg_ctrl, s_axil_wdata, s_axil_wstrb);
                        
                        // [关键逻辑] 启动拦截机制
                        // 仅当 CPU 试图写入 Bit 0 为 '1' 时，触发检查
                        if (s_axil_wstrb[0] && s_axil_wdata[0]) begin
                            if (is_unaligned) begin
                                // [Case 1] 地址未对齐：报警，拦截启动
                                hw_error_latch <= 1'b1; 
                                o_start        <= 1'b0; 
                            end else begin
                                // [Case 2] 地址正常：允许启动，清除旧错误
                                o_start        <= 1'b1; 
                                hw_error_latch <= 1'b0; 
                            end
                        end
                        reg_ctrl <= next_ctrl;
                    end
                    
                    8'h08: begin // --- Base Address Register ---
                        reg_base_addr <= apply_wstrb(reg_base_addr, s_axil_wdata, s_axil_wstrb);
                    end
                    
                    8'h0C: begin // --- Length Register ---
                        reg_len <= apply_wstrb(reg_len, s_axil_wdata, s_axil_wstrb);
                    end
                    
                    default: ; // Ignore writes to undefined addresses
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // 1.4 写响应生成 (Write Response)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_bvalid <= 1'b0;
            s_axil_bresp  <= 2'b00;
        end else begin
            if (write_en) begin
                s_axil_bvalid <= 1'b1; // 告诉 Master：刚才那个写操作我搞定了
                s_axil_bresp  <= 2'b00; // 2'b00 = OKAY (成功)
            end else if (s_axil_bready && s_axil_bvalid) begin
                s_axil_bvalid <= 1'b0; // 握手完成，撤销 Valid
            end
        end
    end

    // =========================================================================
    // Part 2: 读通道逻辑 (Read Channel - Simple Response)
    // =========================================================================
    
    // 状态寄存器拼接：{Reserved, Error, Done}
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

            // 2.2 读数据返回
            // 当地址握手成功，下一拍立即返回数据 (Latency = 1)
            if (s_axil_arready && s_axil_arvalid && ~s_axil_rvalid) begin
                s_axil_rvalid <= 1'b1;
                case (s_axil_araddr[7:0])
                    8'h00: s_axil_rdata <= reg_ctrl;
                    8'h04: s_axil_rdata <= reg_status; // 读回状态
                    8'h08: s_axil_rdata <= reg_base_addr;
                    8'h0C: s_axil_rdata <= reg_len;
                    default: s_axil_rdata <= 32'h0; // 读取未定义区域返回 0
                endcase
            end else if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0; // 读数据被 Master 取走了
            end
        end
    end

    // 硬件直连输出
    assign o_base_addr = reg_base_addr;
    assign o_len       = reg_len;

endmodule