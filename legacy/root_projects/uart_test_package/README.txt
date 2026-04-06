# UART 测试包 - 使用说明

## 文件清单

```
uart_test_package/
├── crypto_test_app.elf      (190 KB) - 测试程序
├── design_1_wrapper.bit     (3.9 MB) - FPGA 位流
├── ps7_init.tcl             (25 KB)  - PS 初始化脚本
└── run_test.tcl             (2 KB)   - 主测试脚本
```

## 使用步骤

### 1. 复制整个文件夹到新电脑

将 `uart_test_package` 文件夹复制到新电脑的任意位置，例如：
- `D:\uart_test_package`
- 或 `C:\temp\uart_test_package`

### 2. 修改脚本路径

打开 `run_test.tcl`，修改第 10 行：

```tcl
set package_dir "D:/uart_test_package"
```

改为你的实际路径，例如：
```tcl
set package_dir "C:/temp/uart_test_package"
```

### 3. 连接硬件

1. 开发板连接 JTAG（UART JTAG 接口）
2. 开发板连接 UART（J7 Micro USB 接口）
3. 打开开发板电源

### 4. 打开 XSDB

方法 1：从开始菜单
- 开始菜单 → Xilinx Design Tools → Vitis → XSCT

方法 2：从命令行
```bash
C:\Xilinx\Vitis\202x.x\bin\xsdb.bat
```

### 5. 运行测试

在 XSDB 中执行：

```tcl
cd D:/uart_test_package
source run_test.tcl
```

### 6. 查看输出

打开 PuTTY：
- 端口：设备管理器中查看（通常是 COMx）
- 波特率：115200
- 数据位：8
- 停止位：1
- 校验：无

## 手动测试 UART

如果 PuTTY 无输出，可以在 XSDB 中手动发送字符：

```tcl
stop
mwr 0xE0001030 0x00000048   # 发送 'H'
mwr 0xE0001030 0x00000069   # 发送 'i'
con
```

## 故障排查

### 问题 1：PuTTY 无输出

可能原因：
1. USB 线只支持充电，不支持数据传输
2. CP2102 驱动未安装
3. TX/RX 接线错误

解决方案：
1. 更换 USB 数据线
2. 安装 CP210x 驱动（从 Silicon Labs 官网下载）
3. 检查硬件连接

### 问题 2：XSDB 连接失败

可能原因：
1. JTAG 线未连接
2. 开发板未上电
3. 驱动未安装

解决方案：
1. 检查 JTAG 连接
2. 打开开发板电源
3. 安装 Digilent JTAG 驱动

### 问题 3：位流烧录失败

可能原因：
1. 位流文件损坏
2. FPGA 配置失败

解决方案：
1. 重新复制 .bit 文件
2. 断电重启开发板

## 技术信息

- 开发板：ALINX AX7020 (XC7Z020)
- UART：UART1 (MIO48/MIO49)
- 波特率：115200
- CP2102 USB-UART 芯片
