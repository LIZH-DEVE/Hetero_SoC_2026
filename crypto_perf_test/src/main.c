#include "dma_driver.h"
#include <stdio.h>
#include <stdlib.h>

// 实例定义
XScuGic Intc;
XScuTimer Timer;

// 密钥与数据
u8 TestKey[16] = {
    0x00, 0x01, 0x02, 0x03, 0x10, 0x11, 0x12, 0x13,
    0x20, 0x21, 0x22, 0x23, 0x30, 0x31, 0x32, 0x33
};

// ---------------------------------------------------------
// 软件 AES 参考
// ---------------------------------------------------------
void AES_Software_Ref(u8 *In, u8 *Out, u32 Len, u8 *Key) {
    // 模拟加密 (XOR)
    for(int i=0; i<Len; i++) {
         Out[i] = In[i] ^ Key[i % 16];
    }
}

int main() {
    int Status;
    u32 *TxBuff = (u32 *)TX_BUFFER_BASE;
    u32 *RxBuff = (u32 *)RX_BUFFER_BASE;
    u8 *TxBuff8 = (u8 *)TX_BUFFER_BASE;
    u8 *RxBuff8 = (u8 *)RX_BUFFER_BASE;

    xil_printf("\r\n=== Hetero SoC High-Precision Test (Custom DMA) ===\r\n");

    // 1. 初始化
    Status = Timer_Init(&Timer, TIMER_DEVICE_ID);
    if(Status != XST_SUCCESS) { xil_printf("Timer Init Failed\r\n"); return -1; }

    Status = Setup_Intr_System(&Intc, DMA_INTR_ID);
    if(Status != XST_SUCCESS) { xil_printf("Intr Setup Failed\r\n"); return -1; }

    DMA_Soft_Init(); // 复位控制寄存器

    // 2. 配置加密核: AES (0), Key, Encrypt(1)
    Crypto_Config(0, TestKey, 1);

    // 3. 准备数据
    for(int i=0; i<TEST_PKG_LEN/4; i++) {
        TxBuff[i] = i + 0x55AA0000;
        RxBuff[i] = 0;
    }
    Xil_DCacheFlushRange((UINTPTR)TxBuff, TEST_PKG_LEN);
    Xil_DCacheFlushRange((UINTPTR)RxBuff, TEST_PKG_LEN);

    // =========================================================
    // 4. 软件基准
    // =========================================================
    xil_printf("Measuring software baseline...\r\n");
    u8 *SwRefBuffer = (u8 *)malloc(TEST_PKG_LEN);
    
    Timer_Start(&Timer);
    if(SwRefBuffer) AES_Software_Ref(TxBuff8, SwRefBuffer, TEST_PKG_LEN, TestKey);
    u32 SwCounts = Timer_GetElapsed(&Timer);
    double SwTimeUs = Timer_GetTimeUs(&Timer, SwCounts);
    
    xil_printf("Software Time: %.2f us, Throughput: %.2f MB/s\r\n", 
            SwTimeUs, (double)TEST_PKG_LEN / (SwTimeUs));

    // =========================================================
    // 5. 硬件加速
    // =========================================================
    xil_printf("Starting Hardware Acceleration...\r\n");
    
    RxDone = 0;
    Error = 0;

    Timer_Start(&Timer); // Start HW Timer

    // 启动传输 (Src, Dest, Len)
    // TxBuff (Source) -> 0x20
    // RxBuff (Dest)   -> 0x08
    DMA_Start_Transfer((u32)TxBuff, (u32)RxBuff, TEST_PKG_LEN);

    // 等待中断 (Memory Barrier + Volatile Check)
    while (!RxDone && !Error) {
        // 防止编译器优化掉空循环
        asm volatile("nop");
    }
    
    u32 HwCounts = Timer_GetElapsed(&Timer); // Stop HW Timer
    double HwTimeUs = Timer_GetTimeUs(&Timer, HwCounts);
    
    // 频率校准：FPGA Logic 运行在 75MHz
    double HwCycles75MHz = HwTimeUs * 75.0;

    if (Error) {
        xil_printf("DMA Error Occurred!\r\n");
    }

    // =========================================================
    // 6. 结果
    // =========================================================
    Xil_DCacheInvalidateRange((UINTPTR)RxBuff, TEST_PKG_LEN);

    xil_printf("\r\n--- Performance Report ---\r\n");
    xil_printf("Data Size      : %d Bytes\r\n", TEST_PKG_LEN);
    xil_printf("Hardware Time  : %.2f us\r\n", HwTimeUs);
    xil_printf("PL frequency   : 75 MHz\r\n");
    xil_printf("HW Cycles      : %.0f cycles\r\n", HwCycles75MHz);
    xil_printf("HW Throughput  : %.2f MB/s\r\n", (double)TEST_PKG_LEN / HwTimeUs);
    xil_printf("Speedup Ratio  : %.2fx\r\n", SwTimeUs / HwTimeUs);

    // 校验
    int Errors = 0;
    if(SwRefBuffer) {
        for(int i=0; i<TEST_PKG_LEN; i++) {
            if(RxBuff8[i] != SwRefBuffer[i]) {
                if(Errors < 5) xil_printf("Mismatch @ %d: HW=0x%02x, SW=0x%02x\r\n", i, RxBuff8[i], SwRefBuffer[i]);
                Errors++;
            }
        }
        if(Errors == 0) xil_printf("Validation: PASS\r\n");
        else xil_printf("Validation: FAILED (%d errors)\r\n", Errors);
        free(SwRefBuffer);
    }

    return 0;
}
