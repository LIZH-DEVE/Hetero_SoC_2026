# 完整回退包 - UART 正常工作状态

## 📅 保存日期
2026-03-15 14:59

## ✅ 当前状态
**UART 测试完全成功！端口正常输出！**

---

## 📁 备份文件清单

### 1. 核心文件
| 文件 | 说明 |
|------|------|
| `main.c` | 当前 UART 测试程序（简化版，不访问加密模块） |
| `design_1_wrapper.xsa` | 硬件平台定义文件 |
| `design_1_wrapper.bit` | FPGA 位流文件 |
| `ps7_init.tcl` | PS 初始化脚本 |
| `crypto_test_app.elf` | 编译好的程序（来自 uart_test_package） |

### 2. 辅助文件
| 文件 | 说明 |
|------|------|
| `crypto_hal.c` | 加密 HAL 层（备用） |
| `crypto_hal.h` | 加密 HAL 头文件（备用） |
| `xsdb_complete_init.tcl` | XSDB 初始化脚本 |
| `PROGRESS_SAVE_UART_SUCCESS.md` | 成功配置记录 |

---

## 🚀 如何回退到此状态

### 方法 1：使用 XSDB 手动执行

```tcl
# 1. 启动 XSDB
D:\Xilinx\Vivado\2024.1\bin\xsdb.bat

# 2. 连接
connect

# 3. 选择目标
targets 2

# 4. 停止
stop

# 5. 烧录位流
fpga -f design_1_wrapper.bit
after 2000

# 6. 加载 PS 初始化脚本
source ps7_init.tcl

# 7. 初始化 PS
ps7_init
ps7_post_config
after 500

# 8. 配置 UART1
mwr 0xF8000008 0x0000DF0D
mwr 0xF800012C 0x016C004D
mwr 0xF80007C0 0x00001607
mwr 0xF80007C4 0x00001607
mwr 0xF8000004 0x0000767B

mwr 0xE0001000 0x00000014
mwr 0xE0001018 0x0000007B
mwr 0xE0001034 0x00000006
mwr 0xE0001004 0x00000020

# 9. 下载程序
dow crypto_test_app.elf

# 10. 运行
con
```

### 方法 2：使用 XSDB 脚本

```tcl
source xsdb_complete_init.tcl
```

---

## 📋 预期输出

成功后，PuTTY 应该显示：

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
If you see this message, the UART hardware is working correctly.
The problem is with the crypto module access at 0x43C00000.

.........
```

---

## ⚠️ 注意事项

### 1. 关于加密模块
- 加密模块地址：`0x43C00000`
- 当前程序**不访问**加密模块
- 访问加密模块可能导致 Data Abort 异常

### 2. 关于硬件
- 开发板：ALINX AX7020 (XC7Z020)
- UART：UART1 (MIO48/MIO49)
- 波特率：115200

### 3. 关于驱动
- 需要 CP2102 驱动
- 需要 Digilent JTAG 驱动

---

## 🔄 下一步计划

1. 恢复完整加密测试程序
2. 测试加密模块功能
3. 解决加密模块访问问题

---

## 📞 如果遇到问题

### 问题 1：PuTTY 无输出
- 检查驱动是否正确安装
- 检查 USB 线是否支持数据传输
- 检查 COM 端口号是否正确

### 问题 2：XSDB 连接失败
- 检查 JTAG 线是否连接
- 检查开发板是否上电
- 检查驱动是否安装

### 问题 3：程序崩溃
- 检查是否访问了加密模块
- 检查 PS 是否正确初始化
- 检查位流是否正确烧录

---

**此备份包保证可以随时回退到 UART 正常工作的状态！**
