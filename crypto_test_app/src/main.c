#include <stdio.h>
#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "sleep.h"

/************************** 寄存器映射 (与 RTL 对齐) **************************/
// 这里的基地址必须与你 Vivado Block Design 中的 Address Editor 一致
#define CRYPTO_BASE_ADDR    XPAR_DMA_SUBSYSTEM_0_BASEADDR 

#define REG_START_OFFSET    0x00  // 写 1 启动
#define REG_ALGO_SEL_OFFSET 0x10  // 0: AES, 1: SM4
#define REG_STATUS_OFFSET   0x18  // Bit 0: Done

/************************** 测试逻辑 **************************/
void Crypto_Single_Step_Test(u32 algo_type) {
    if (algo_type == 0)
        xil_printf("\r\n[STEP] Testing AES Core...\r\n");
    else
        xil_printf("\r\n[STEP] Testing SM4 Core...\r\n");

    // 1. 设置算法选择 (Dispatcher 切换)
    Xil_Out32(CRYPTO_BASE_ADDR + REG_ALGO_SEL_OFFSET, algo_type);
    
    // 2. 读回确认 (验证 AXI-Lite 控制通路)
    u32 readback = Xil_In32(CRYPTO_BASE_ADDR + REG_ALGO_SEL_OFFSET);
    xil_printf("   -> Algo Sel Readback: %d\r\n", readback);

    // 3. 发送 Start 脉冲
    Xil_Out32(CRYPTO_BASE_ADDR + REG_START_OFFSET, 1);
    Xil_Out32(CRYPTO_BASE_ADDR + REG_START_OFFSET, 0);

    // 4. 等待硬件 Done
    xil_printf("   -> Waiting for Hardware Done...\r\n");
    u32 status;
    do {
        status = Xil_In32(CRYPTO_BASE_ADDR + REG_STATUS_OFFSET);
    } while ((status & 0x01) == 0); // 轮询 Done 位

    xil_printf("   -> [SUCCESS] %s calculation finished!\r\n", (algo_type == 0 ? "AES" : "SM4"));
}

int main() {
    xil_printf("--- Hetero_SoC Day 7: Dispatcher Dual-Core Test ---\r\n");

    while (1) {
        // 先测 AES
        Crypto_Single_Step_Test(0);
        sleep(1);

        // 再测 SM4
        Crypto_Single_Step_Test(1);
        sleep(2);
    }

    return 0;
}#include <stdio.h>
#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "sleep.h"

/************************** 寄存器映射 (与 RTL 对齐) **************************/
// 这里的基地址必须与你 Vivado Block Design 中的 Address Editor 一致
#define CRYPTO_BASE_ADDR    XPAR_DMA_SUBSYSTEM_0_BASEADDR 

#define REG_START_OFFSET    0x00  // 写 1 启动
#define REG_ALGO_SEL_OFFSET 0x10  // 0: AES, 1: SM4
#define REG_STATUS_OFFSET   0x18  // Bit 0: Done

/************************** 测试逻辑 **************************/
void Crypto_Single_Step_Test(u32 algo_type) {
    if (algo_type == 0)
        xil_printf("\r\n[STEP] Testing AES Core...\r\n");
    else
        xil_printf("\r\n[STEP] Testing SM4 Core...\r\n");

    // 1. 设置算法选择 (Dispatcher 切换)
    Xil_Out32(CRYPTO_BASE_ADDR + REG_ALGO_SEL_OFFSET, algo_type);
    
    // 2. 读回确认 (验证 AXI-Lite 控制通路)
    u32 readback = Xil_In32(CRYPTO_BASE_ADDR + REG_ALGO_SEL_OFFSET);
    xil_printf("   -> Algo Sel Readback: %d\r\n", readback);

    // 3. 发送 Start 脉冲
    Xil_Out32(CRYPTO_BASE_ADDR + REG_START_OFFSET, 1);
    Xil_Out32(CRYPTO_BASE_ADDR + REG_START_OFFSET, 0);

    // 4. 等待硬件 Done
    xil_printf("   -> Waiting for Hardware Done...\r\n");
    u32 status;
    do {
        status = Xil_In32(CRYPTO_BASE_ADDR + REG_STATUS_OFFSET);
    } while ((status & 0x01) == 0); // 轮询 Done 位

    xil_printf("   -> [SUCCESS] %s calculation finished!\r\n", (algo_type == 0 ? "AES" : "SM4"));
}

int main() {
    xil_printf("--- Hetero_SoC Day 7: Dispatcher Dual-Core Test ---\r\n");

    while (1) {
        // 先测 AES
        Crypto_Single_Step_Test(0);
        sleep(1);

        // 再测 SM4
        Crypto_Single_Step_Test(1);
        sleep(2);
    }

    return 0;
}