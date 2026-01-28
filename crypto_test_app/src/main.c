/*
 * 模块名称: main.c
 * 所属阶段: Phase 2 - Day 06 软硬协同验证 (Software-Hardware Co-Design)
 * 版本: v2.0 (工业级验证版)
 * 描述: 
 * 验证 Zynq PS 端通过 AXI-Lite 总线对 PL 端 Crypto Engine 的控制能力。
 * [核心验证点]
 * 1. 寄存器读写完整性 (Bus Integrity)
 * 2. 算法模式热切换 (Algo Switching)
 * 3. 128-bit 密钥注入 (Key Injection)
 */

#include <stdio.h>
#include "xil_printf.h"
#include "xil_io.h"
#include "xparameters.h" // [Source: Vitis BSP] 自动生成的硬件参数头文件

// ============================================================================
// 1. 硬件地址映射 (Hardware Address Map)
// [Source: Vivado Address Editor] 必须确认 xparameters.h 中的宏名称匹配
// ============================================================================
// 提示：如果在编译时报错 "Undefine"，请打开 xparameters.h 搜索 "DMA_SUBSYSTEM" 找到真实的宏名
#ifdef XPAR_DMA_SUBSYSTEM_0_BASEADDR
    #define CSR_BASE_ADDR      XPAR_DMA_SUBSYSTEM_0_BASEADDR
#else
    // 备用地址 (Day 02 规划的默认基地址)
    #define CSR_BASE_ADDR      0x43C00000 
#endif

// ============================================================================
// 2. 寄存器偏移定义 (Register Offsets)
// [Source: rtl/core/axil_csr.sv] 必须与 RTL 硬件定义严格一致
// ============================================================================
#define REG_CTRL_OFFSET    0x00  // Control Register
#define REG_STAT_OFFSET    0x04  // Status Register
#define REG_ADDR_OFFSET    0x08  // DMA Source Address
#define REG_LEN_OFFSET     0x0C  // DMA Length
#define REG_KEY0_OFFSET    0x10  // Key[31:0]
#define REG_KEY1_OFFSET    0x14  // Key[63:32]
#define REG_KEY2_OFFSET    0x18  // Key[95:64]
#define REG_KEY3_OFFSET    0x1C  // Key[127:96]

// 控制位掩码 [Source: Day 05 Crypto Spec]
#define CTRL_ALGO_MASK     0x02  // Bit[1]: 0=AES, 1=SM4

// ============================================================================
// 3. 辅助验证函数 (Helper Functions)
// ============================================================================
void Crypto_InjectKey(u32 k0, u32 k1, u32 k2, u32 k3) {
    // [Source: Day 6 Task] 注入 128-bit 密钥
    Xil_Out32(CSR_BASE_ADDR + REG_KEY0_OFFSET, k0);
    Xil_Out32(CSR_BASE_ADDR + REG_KEY1_OFFSET, k1);
    Xil_Out32(CSR_BASE_ADDR + REG_KEY2_OFFSET, k2);
    Xil_Out32(CSR_BASE_ADDR + REG_KEY3_OFFSET, k3);
    xil_printf("  [Info] Key Injected: %08x %08x %08x %08x\r\n", k3, k2, k1, k0);
}

u32 Crypto_VerifyKey(u32 k0, u32 k1, u32 k2, u32 k3) {
    // 回读验证
    u32 r0 = Xil_In32(CSR_BASE_ADDR + REG_KEY0_OFFSET);
    u32 r1 = Xil_In32(CSR_BASE_ADDR + REG_KEY1_OFFSET);
    u32 r2 = Xil_In32(CSR_BASE_ADDR + REG_KEY2_OFFSET);
    u32 r3 = Xil_In32(CSR_BASE_ADDR + REG_KEY3_OFFSET);

    if (r0 != k0 || r1 != k1 || r2 != k2 || r3 != k3) {
        xil_printf("  [Error] Key Mismatch! Readback: %08x %08x %08x %08x\r\n", r3, r2, r1, r0);
        return 1; // Fail
    }
    return 0; // Pass
}

// ============================================================================
// 4. 主程序 (Main Execution)
// ============================================================================
int main() {
    xil_printf("\r\n=== Hetero_SoC Day 06: Hardware Verification Start ===\r\n");
    xil_printf("CSR Base Address: 0x%08x\r\n", CSR_BASE_ADDR);

    // --- [Step 1] 密钥寄存器读写测试 (Key Register R/W Test) ---
    xil_printf("\n[Test 1] Testing Key Register Integrity...\r\n");
    
    // 测试向量：使用非全0/全1的数据，防止总线 stuck-at-0/1 故障
    u32 k0 = 0x11223344;
    u32 k1 = 0x55667788;
    u32 k2 = 0x99AABBCC;
    u32 k3 = 0xDDEEFF00;

    Crypto_InjectKey(k0, k1, k2, k3);
    
    if (Crypto_VerifyKey(k0, k1, k2, k3) == 0) {
        xil_printf("  -> [PASS] Key Registers are fully operational.\r\n");
    } else {
        xil_printf("  -> [FAIL] Key Register R/W check failed.\r\n");
        return -1; // Stop
    }

    // --- [Step 2] 算法切换控制测试 (Algo Selection Mux) ---
    xil_printf("\n[Test 2] Testing Algorithm Switch Logic...\r\n");
    
    // 切换到 SM4 模式 (Bit 1 = 1)
    // [Source: dma_subsystem.sv] 验证 w_algo_sel 信号连接
    u32 ctrl_val = 0x00000002; 
    Xil_Out32(CSR_BASE_ADDR + REG_CTRL_OFFSET, ctrl_val);
    
    u32 ctrl_read = Xil_In32(CSR_BASE_ADDR + REG_CTRL_OFFSET);
    
    if (ctrl_read & CTRL_ALGO_MASK) {
        xil_printf("  [Info] Switched to SM4 Mode. CTRL Reg: 0x%08x\r\n", ctrl_read);
        xil_printf("  -> [PASS] Algo Selection Bit is latching correctly.\r\n");
    } else {
        xil_printf("  -> [FAIL] Failed to switch Algo mode. Read: 0x%08x\r\n", ctrl_read);
    }

    xil_printf("\n=== Day 06 Verification Complete: HARDWARE READY ===\r\n");
    
    return 0;
}