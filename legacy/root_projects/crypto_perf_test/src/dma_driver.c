#include "dma_driver.h"

// 全局标志位
volatile int RxDone;
volatile int Error;

// ---------------------------------------------------------
// 中断服务程序 (ISR)
// ---------------------------------------------------------
static void DmaIntrHandler(void *CallbackRef) {
    (void)CallbackRef;
    
    // 1. 读取状态 (如果有状态寄存器的话)
    // 假设 axil_csr.sv 的 bit 0 是 Done? 
    // RTL分析显示: assign i_done = dma_done; assign reg_status = {..., i_done};
    // 状态寄存器在 0x04
    u32 Status = Xil_In32(DMA_CSR_BASE + 0x04);

    // 2. 清除中断 (如果是电平触发，需要写清除)
    // 但我们的 RTL 似乎是脉冲触发给 GIC，所以不需要清除 IP 内部
    // 如果需要清除: Xil_Out32(DMA_CSR_BASE + 0x04, Status);
    
    // 3. 设置标志位
    RxDone = 1;
}

// ---------------------------------------------------------
// 初始化函数
// ---------------------------------------------------------
int Setup_Intr_System(XScuGic *IntcInstancePtr, u16 IntrId) {
    int Status;
    XScuGic_Config *IntcConfig;

    // 1. 初始化 GIC
    IntcConfig = XScuGic_LookupConfig(INTC_DEVICE_ID);
    if (NULL == IntcConfig) return XST_FAILURE;

    Status = XScuGic_CfgInitialize(IntcInstancePtr, IntcConfig, IntcConfig->CpuBaseAddress);
    if (Status != XST_SUCCESS) return XST_FAILURE;

    // 2. 设置优先级和触发类型 (0xA0=Priority, 0x3=Rising Edge)
    XScuGic_SetPriorityTriggerType(IntcInstancePtr, IntrId, 0xA0, 0x3);

    // 3. 连接 ISR
    Status = XScuGic_Connect(IntcInstancePtr, IntrId,
                (Xil_InterruptHandler)DmaIntrHandler, NULL);
    if (Status != XST_SUCCESS) return Status;

    // 4. 在 GIC 启用中断
    XScuGic_Enable(IntcInstancePtr, IntrId);

    // 5. 在 CPU 层启用异常
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                (Xil_ExceptionHandler)XScuGic_InterruptHandler, IntcInstancePtr);
    Xil_ExceptionEnable();

    return XST_SUCCESS;
}

// ---------------------------------------------------------
// 自定义 DMA 操作
// ---------------------------------------------------------
void DMA_Soft_Init() {
    // 复位或清零操作
    Xil_Out32(DMA_CSR_BASE + REG_CTRL, 0x00000000);
}

void DMA_Start_Transfer(u32 SrcAddr, u32 DestAddr, u32 Length) {
    // 0. 强制下刷 Cache (Memory Barrier)
    Xil_DCacheFlushRange((UINTPTR)SrcAddr, Length);
    Xil_DCacheFlushRange((UINTPTR)DestAddr, Length);

    // 1. 设置源地址 (MM2S 读取) -> 0x20
    Xil_Out32(DMA_CSR_BASE + REG_SRC_ADDR, SrcAddr);

    // 2. 设置目的地址 (S2MM 写入) -> 0x08
    Xil_Out32(DMA_CSR_BASE + REG_DEST_ADDR, DestAddr);

    // 3. 设置长度 -> 0x0C
    Xil_Out32(DMA_CSR_BASE + REG_LEN, Length);

    // 4. 启动传输 -> 写入 Control Register (0x00)
    // 需要同时置位 S2MM_EN(Bit4), MM2S_EN(Bit5), 和 START(Bit0)
    u32 CtrlVal = CTRL_START_MASK | CTRL_S2MM_EN | CTRL_MM2S_EN;
    
    // 读取当前控制字以保留 Key/Algo 设置
    u32 CurrentCtrl = Xil_In32(DMA_CSR_BASE + REG_CTRL);
    
    // 写入
    Xil_Out32(DMA_CSR_BASE + REG_CTRL, CurrentCtrl | CtrlVal);
}

int Crypto_Config(u32 AlgoSel, u8 *Key, u8 Encrypt) {
    u32 *k32 = (u32 *)Key;
    
    // Write Key (128-bit, little-endian)
    Xil_Out32(DMA_CSR_BASE + REG_KEY_0_OFFSET, k32[0]);
    Xil_Out32(DMA_CSR_BASE + REG_KEY_1_OFFSET, k32[1]);
    Xil_Out32(DMA_CSR_BASE + REG_KEY_2_OFFSET, k32[2]);
    Xil_Out32(DMA_CSR_BASE + REG_KEY_3_OFFSET, k32[3]);
    
    // Build Control Register
    u32 CtrlVal = 0;
    
    // Algorithm Selection (Bit 2): 0=AES, 1=SM4
    if (AlgoSel == 1) {
        CtrlVal |= CTRL_ALGO_SM4;
    }
    
    // Encrypt/Decrypt Selection (Bit 3): 0=Decrypt, 1=Encrypt
    if (Encrypt) {
        CtrlVal |= CTRL_ENC;
    }
    
    // Write Control Register
    Xil_Out32(DMA_CSR_BASE + REG_CTRL, CtrlVal);
    
    return XST_SUCCESS;
}


// ---------------------------------------------------------
// 定时器函数
// ---------------------------------------------------------
int Timer_Init(XScuTimer *TimerInstancePtr, u16 TimerDeviceId) {
    XScuTimer_Config *ConfigPtr;
    int Status;

    ConfigPtr = XScuTimer_LookupConfig(TimerDeviceId);
    if (!ConfigPtr) return XST_FAILURE;

    Status = XScuTimer_CfgInitialize(TimerInstancePtr, ConfigPtr, ConfigPtr->BaseAddr);
    if (Status != XST_SUCCESS) return XST_FAILURE;

    XScuTimer_DisableAutoReload(TimerInstancePtr);
    XScuTimer_LoadTimer(TimerInstancePtr, 0xFFFFFFFF);
    return XST_SUCCESS;
}

void Timer_Start(XScuTimer *TimerInstancePtr) {
    XScuTimer_LoadTimer(TimerInstancePtr, 0xFFFFFFFF);
    XScuTimer_Start(TimerInstancePtr);
}

u32 Timer_GetElapsed(XScuTimer *TimerInstancePtr) {
    u32 Curr = XScuTimer_GetCounterValue(TimerInstancePtr);
    return 0xFFFFFFFF - Curr;
}

double Timer_GetTimeUs(XScuTimer *TimerInstancePtr, u32 Counts) {
    double Freq = (double)XPAR_CPU_CORE_CLOCK_FREQ_HZ / 2.0;
    return ((double)Counts / Freq) * 1000000.0;
}
