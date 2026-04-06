#ifndef CRYPTO_HAL_H
#define CRYPTO_HAL_H

#include "xparameters.h"
#include "xil_io.h"
#include "xstatus.h"

// ==========================================
// 物理基地址锁定 (来自 xparameters.h)
// ==========================================
#define CRYPTO_BASEADDR XPAR_CRYPTO_ACCEL_AXI_0_BASEADDR

// ==========================================
// 寄存器偏移量映射 (Register Map)
// 假设基于 Vivado 标准 AXI-Lite 模板生成的 4 个寄存器
// ==========================================
#define REG_CTRL       0x00  // 控制寄存器 (写) -> slv_reg0
#define REG_DATA_IN    0x04  // 数据输入通道 (写) -> slv_reg1
#define REG_STATUS     0x08  // 状态寄存器 (读) -> slv_reg2
#define REG_DATA_OUT   0x0C  // 数据输出通道 (读) -> slv_reg3

// ==========================================
// 控制掩码
// ==========================================
#define CMD_START      0x00000001  // 触发加密信号
#define STATUS_READY   0x00000001  // 硬件空闲/计算完成标志

// API 声明
void Crypto_Init(void);
int Crypto_ProcessBlock(const u8* input_16bytes, u8* output_16bytes);

#endif // CRYPTO_HAL_H
