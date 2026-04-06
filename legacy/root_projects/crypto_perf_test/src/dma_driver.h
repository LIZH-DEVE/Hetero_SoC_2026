#ifndef DMA_DRIVER_H
#define DMA_DRIVER_H

#include "xscugic.h"
#include "xscutimer.h"
#include "xparameters.h"
#include "xil_printf.h"
#include "xil_cache.h"
#include "xil_io.h"

// =========================================================
// 硬件配置 (Hardware Config)
// =========================================================
// XPAR_DMA_SUBSYSTEM_V2_WRA_0_BASEADDR comes from xparameters.h
// If not found, use hardcoded 0x40000000
#ifdef XPAR_DMA_SUBSYSTEM_V2_WRA_0_BASEADDR
    #define DMA_CSR_BASE    XPAR_DMA_SUBSYSTEM_V2_WRA_0_BASEADDR
#else
    #define DMA_CSR_BASE    0x40000000
#endif

#define INTC_DEVICE_ID      XPAR_SCUGIC_SINGLE_DEVICE_ID

// 定时器 ID (Vitis 2024.1 Standard)
// 如果 xparameters.h 中是 XPAR_XSCUTIMER_0_DEVICE_ID，请修改此处
#ifdef XPAR_SCUTIMER_DEVICE_ID
    #define TIMER_DEVICE_ID     XPAR_SCUTIMER_DEVICE_ID
#else
    #define TIMER_DEVICE_ID     XPAR_XSCUTIMER_0_DEVICE_ID
#endif

// 中断号 (User Specified: Zynq IRQ_F2P[0] = 61)
#define DMA_INTR_ID         61

// =========================================================
// 自定义寄存器映射 (Custom Register Map)
// =========================================================
#define REG_CTRL            0x00
// 假设用户确认 0x08 是 Dest, 0x20 是 Src
#define REG_DEST_ADDR       0x08 // DMA Write / S2MM Address
#define REG_LEN             0x0C // Transfer Length
#define REG_SRC_ADDR        0x20 // DMA Read / MM2S Address

#define REG_S2MM_DATA       0x24

#define REG_KEY_0           0x28 
#define REG_KEY_1           0x2C
// CSR 寄存器偏移定义
// =========================================================
#define REG_CTRL_OFFSET     0x00
#define REG_STATUS_OFFSET   0x04
#define REG_BASE_ADDR       0x08
#define REG_LEN             0x0C

// [Day 11] S2MM/MM2S Address/Data
#define REG_S2MM_ADDR_OFF   0x20
#define REG_S2MM_DATA_OFF   0x24

// Key Registers (Shifted to 0x28)
#define REG_KEY_0_OFFSET    0x28
#define REG_KEY_1_OFFSET    0x2C
#define REG_KEY_2_OFFSET    0x30
#define REG_KEY_3_OFFSET    0x34

// Cache Control
#define REG_CACHE_CTRL      0x40
#define REG_ACL_CNT         0x44
#define REG_LOOPBACK        0x48

// Ring Buffer (Optional)
#define REG_RING_BASE       0x50

// ALGO Select is now Bit 2 of CTRL Register, not separate offset
// But we used 0x20 for Algo Sel in previous code which was wrong.
// Algo Sel is controlled via Config function writing to CTRL reg.

// =========================================================
// 掩码定义
// =========================================================
#define CTRL_START_MASK     0x00000001
#define CTRL_INIT_MASK      0x00000002
#define CTRL_ALGO_AES       0x00000000
#define CTRL_ALGO_SM4       0x00000004 // Bit 2
#define CTRL_DEC            0x00000000
#define CTRL_ENC            0x00000008 // Bit 3
#define CTRL_S2MM_EN        0x00000010 // Bit 4
#define CTRL_MM2S_EN        0x00000020 // Bit 5

// =========================================================
// DDR 内存映射
// =========================================================
#define MEM_BASE_ADDR       0x10000000 
#define TX_BUFFER_BASE      (MEM_BASE_ADDR + 0x01000000)
#define RX_BUFFER_BASE      (MEM_BASE_ADDR + 0x02000000)
#define TEST_PKG_LEN        (1024 * 1024) 

// =========================================================
// 全局变量
// =========================================================
extern volatile int RxDone; // 只关心接收完成
extern volatile int Error;

// =========================================================
// 函数原型
// =========================================================
int Setup_Intr_System(XScuGic *IntcInstancePtr, u16 IntrId);
int Timer_Init(XScuTimer *TimerInstancePtr, u16 TimerDeviceId);
void Timer_Start(XScuTimer *TimerInstancePtr);
u32 Timer_GetElapsed(XScuTimer *TimerInstancePtr);
double Timer_GetTimeUs(XScuTimer *TimerInstancePtr, u32 Counts);

// 自定义驱动函数
void DMA_Soft_Init();
void DMA_Start_Transfer(u32 SrcAddr, u32 DestAddr, u32 Length);
int Crypto_Config(u32 AlgoSel, u8 *Key, u8 Encrypt);

#endif
