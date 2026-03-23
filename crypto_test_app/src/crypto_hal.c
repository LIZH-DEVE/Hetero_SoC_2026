#include "crypto_hal.h"

// 硬件复位与初始化审计
void Crypto_Init(void) {
    // 强制写入 0，清除任何残留的启动信号
    Xil_Out32(CRYPTO_BASEADDR + REG_CTRL, 0x00000000);
}

// 核心数据泵：处理 1 个 128-bit (16字节) 数据块
// 耗时评估：依赖于你硬件的计算周期，软件侧为轮询等待
int Crypto_ProcessBlock(const u8* input_16bytes, u8* output_16bytes) {
    u32 word_buf;
    int timeout = 100000; // 防死锁超时计数器

    // 1. 密码学大端适配：硬件入端口采用 {reg[95:0], din} 的向左推移位。
    // 为了让 input_16bytes[0] 最终停留在 128-bit 的 [127:120] 位（算法最前沿），
    // ARM 必须先发送 input_16bytes 的前 4 个字节，并且组合成大端的 32-bit Word。
    for (int i = 0; i < 4; i++) {
        // 从左到右依次取这 16 字节里的 4 个 Word 
        // 并在单字内部将内存低位字节（小端）强行拔高至寄存器高位（大端转换）
        word_buf = (input_16bytes[i*4] << 24)     |
                   (input_16bytes[i*4 + 1] << 16) |
                   (input_16bytes[i*4 + 2] << 8)  |
                   (input_16bytes[i*4 + 3]);
                   
        Xil_Out32(CRYPTO_BASEADDR + REG_DATA_IN, word_buf); 
    }

    // 2. 硬件点火
    Xil_Out32(CRYPTO_BASEADDR + REG_CTRL, CMD_START);

    // 3. 极速轮询等待 (等待 STATUS_READY 置位)
    while ((Xil_In32(CRYPTO_BASEADDR + REG_STATUS) & STATUS_READY) == 0) {
        timeout--;
        if (timeout <= 0) {
            return XST_FAILURE; // 硬件未响应，拒绝死等
        }
    }

    // 4. 清除启动信号
    Xil_Out32(CRYPTO_BASEADDR + REG_CTRL, 0x00000000);

    // 5. 结果抽取与组推（齿轮箱 gearbox 也是从左往右先吐出高位 Word: [127:96]）
    for (int i = 0; i < 4; i++) {
        word_buf = Xil_In32(CRYPTO_BASEADDR + REG_DATA_OUT);
        // 收到的第一个 Word 其实是密文最高位的 4 字节，同样执行大端翻转存入内存
        output_16bytes[i*4]     = (u8)((word_buf >> 24) & 0xFF);
        output_16bytes[i*4 + 1] = (u8)((word_buf >> 16) & 0xFF);
        output_16bytes[i*4 + 2] = (u8)((word_buf >> 8) & 0xFF);
        output_16bytes[i*4 + 3] = (u8)(word_buf & 0xFF);
    }

    return XST_SUCCESS;
}
