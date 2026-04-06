# UART 测试成功进度保存

## 日期
2026-03-15

## 当前状态
✅ **UART 测试完全成功！**

## 成功的配置

### 硬件配置
- 开发板：ALINX AX7020 (XC7Z020)
- UART：UART1 (MIO48/MIO49)
- 波特率：115200
- CP2102 USB-UART 芯片正常工作

### 软件配置
- Vivado/Vitis 版本：2024.1
- XSA 文件：`HCS_SOC/design_1_wrapper.xsa`
- 测试程序：`HCS_SOC/crypto_test_app/src/main.c`

### XSDB 初始化命令（成功）
```tcl
# 1. 连接
connect

# 2. 选择目标
targets 2

# 3. 停止
stop

# 4. 加载 ps7_init.tcl
source D:/test_uart/ps7_init.tcl

# 5. 初始化 PS
ps7_init
ps7_post_config
after 500

# 6. 配置 UART1
mwr 0xF8000008 0x0000DF0D
mwr 0xF800012C 0x016C004D
mwr 0xF80007C0 0x00001607
mwr 0xF80007C4 0x00001607
mwr 0xF8000004 0x0000767B

mwr 0xE0001000 0x00000014
mwr 0xE0001018 0x0000007B
mwr 0xE0001034 0x00000006
mwr 0xE0001004 0x00000020

# 7. 下载程序
dow D:/test_uart/crypto_test_app.elf

# 8. 运行
con
```

### 关键发现
1. **第一台电脑问题**：
   - 驱动安装不完整
   - XSDB 连接配置问题
   - 可能是 USB 端口兼容性问题

2. **第二台电脑成功原因**：
   - 驱动正确安装
   - XSDB 正确连接
   - 硬件配置正确

## 下一步计划
1. 恢复完整加密测试程序
2. 测试加密模块功能（地址：0x43C00000）
3. 测试 AES/SM4 加密解密
4. 测试 DMA 传输
5. 性能测试

## 文件备份位置
- 当前 UART 测试程序：`HCS_SOC/crypto_test_app/src/main.c`
- 原始完整加密测试程序：`crypto_test_app/src/main.c`（根目录下）

## 成功的测试输出示例
```
========================================
   UART ONLY Test - No Crypto Access
========================================

[TEST 1] Direct UART Output
  - This message is sent via direct UART register access
  - If you see this, UART is working!

[TEST 2] UART Status Register
  - UART_SR = 0x...

[TEST 3] Loop Test
  - Loop iteration 0
  - Loop iteration 1
  ...

[SUCCESS] UART Test Complete!
```

## 注意事项
- 加密模块地址：0x43C00000
- 之前访问该地址会导致 Data Abort 异常
- 需要确认 PL 是否正确初始化
- 需要确认 AXI 总线是否正常工作
