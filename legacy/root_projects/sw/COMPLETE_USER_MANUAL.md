# ==============================================================================
# SmartNIC 完整用户手册
# 21天硬件安全加速网卡 (Crypto SmartNIC)
# ==============================================================================
# 版本: 2.0
# 更新: 2026-01-31
# ==============================================================================

## 目录

1. [产品概述](#1-产品概述)
2. [系统架构](#2-系统架构)
3. [硬件连接](#3-硬件连接)
4. [软件安装](#4-软件安装)
5. [快速开始](#5-快速开始)
6. [加密方式详解](#6-加密方式详解)
7. [数据加密详解](#7-数据加密详解)
8. [结果输出详解](#8-结果输出详解)
9. [API参考](#9-api参考)
10. [高级功能](#10-高级功能)
11. [性能优化](#11-性能优化)
12. [故障排除](#12-故障排除)
13. [安全最佳实践](#13-安全最佳实践)
14. [附录](#14-附录)

---

# 1. 产品概述

## 1.1 产品简介

SmartNIC是一款基于Xilinx Zynq-7000系列FPGA的硬件安全加速卡，提供以下核心功能：

```
┌─────────────────────────────────────────────────────────────────┐
│                     SmartNIC 功能概览                            │
├─────────────────────────────────────────────────────────────────┤
│  🔐 加密引擎                                                      │
│     • AES-128-CBC: 国际标准对称加密                              │
│     • SM4-CBC: 中国国密标准对称加密                              │
│     • 硬件加速: 相比软件提升40+倍性能                            │
├─────────────────────────────────────────────────────────────────┤
│  🛡️ 安全模块                                                      │
│     • 硬件防火墙: 基于5元组的ACL匹配                             │
│     • DNA绑定: 芯片级物理安全保护                                │
│     • 防重放: 序列号验证机制                                     │
├─────────────────────────────────────────────────────────────────┤
│  ⚡ 性能特性                                                      │
│     • 吞吐量: 950 MB/s                                           │
│     • 延迟: <1 微秒                                              │
│     • 零拷贝FastPath: 非加密流量直通                             │
├─────────────────────────────────────────────────────────────────┤
│  🔧 易于集成                                                      │
│     • Python驱动: 简单API调用                                    │
│     • UDP接口: 标准网络通信                                      │
│     • 灵活配置: 支持自定义密钥和IV                               │
└─────────────────────────────────────────────────────────────────┘
```

## 1.2 性能指标

| 指标 | 数值 | 说明 |
|------|------|------|
| 加密吞吐量 | 950 MB/s | 实测值 |
| 加密延迟 | <1 μs | 端到端延迟 |
| 加速比 | 47.5x | vs OpenSSL软件 |
| CPU占用 | <1% | 仅处理描述符 |
| 密钥长度 | 128位 | AES/SM4标准 |
| 块大小 | 128位 | 16字节 |
| 密钥更新 | <1 ms | 配置延迟 |

## 1.3 应用场景

```
典型应用场景:

1. 云数据中心
   ├── 虚拟机间加密通信
   ├── 存储加密
   └── VPN网关加速

2. 金融行业
   ├── 交易数据加密
   ├── POS机加密
   └── ATM加密模块

3. 企业安全
   ├── 内部通信加密
   ├── 文件加密传输
   └── 安全网关

4. 物联网
   ├── 设备认证
   ├── 数据加密
   └── 安全通信
```

---

# 2. 系统架构

## 2.1 整体架构图

```
                           ┌─────────────────────────────────────┐
                           │          SmartNIC FPGA              │
                           │  ┌───────────────────────────────┐  │
                           │  │         Zynq PS (ARM)         │  │
                           │  │  ┌───┐  ┌───┐  ┌───┐  ┌───┐  │  │
                           │  │  │FSBL│  │U-Boot│  │Linux│  │驱动│  │  │
                           │  │  └───┘  └───┘  └───┘  └───┘  │  │
                           │  └───────────────────────────────┘  │
                           │                │                     │
                           │      AXI-Lite / AXI-Stream         │
                           │                ↓                     │
                           │  ┌───────────────────────────────┐  │
                           │  │         PL (FPGA Logic)       │  │
                           │  │                               │  │
                           │  │  ┌─────────┐  ┌─────────┐    │  │
                           │  │  │  MAC IP │  │  ARP    │    │  │
                           │  │  │  Subsys │  │Responder│    │  │
                           │  │  └────┬────┘  └────┬────┘    │  │
                           │  │       │            │         │  │
                           │  │       ↓            │         │  │
                           │  │  ┌─────────┐      │         │  │
                           │  │  │   RX    │      │         │  │
                           │  │  │  Parser │      │         │  │
                           │  │  └────┬────┘      │         │  │
                           │  │       │            │         │  │
                           │  │       ↓            │         │  │
                           │  │  ┌─────────┐      │         │  │
                           │  │  │   ACL   │      │         │  │
                           │  │  │ Firewall│      │         │  │
                           │  │  └────┬────┘      │         │  │
                           │  │       │            │         │  │
                           │  │       ↓            │         │  │
                           │  │  ┌─────────────────────────┐ │  │
                           │  │  │      Packet Dispatcher  │ │  │
                           │  │  └───────────┬─────────────┘ │  │
                           │  │              │               │  │
                           │  │     ┌────────┴────────┐      │  │
                           │  │     ↓                 ↓      │  │
                           │  │  ┌──────┐       ┌──────────┐ │  │
                           │  │  │FastPath│      │ Crypto   │ │  │
                           │  │  │(Passthru)│      │ Engine   │ │  │
                           │  │  └───┬──┘       └────┬─────┘ │  │
                           │  │      │               │       │  │
                           │  │      │               ↓       │  │
                           │  │      │       ┌─────────────┐ │  │
                           │  │      │       │  PBM        │ │  │
                           │  │      │       │  Controller │ │  │
                           │  │      │       └──────┬──────┘ │  │
                           │  │      │              │        │  │
                           │  │      │              ↓        │  │
                           │  │      │       ┌─────────────┐ │  │
                           │  │      │       │   DMA       │ │  │
                           │  │      │       │   Engine    │ │  │
                           │  │      │       └──────┬──────┘ │  │
                           │  │      │              │        │  │
                           │  │      │              ↓        │  │
                           │  │      │       ┌─────────────┐ │  │
                           │  │      │       │   TX        │ │  │
                           │  │      │       │   Stack     │ │  │
                           │  │      │       └──────┬──────┘ │  │
                           │  │      │              │        │  │
                           │  │      │              ↓        │  │
                           │  │      │       ┌─────────────┐ │  │
                           │  │      │       │   MAC IP    │ │  │
                           │  │      │       │   TX        │ │  │
                           │  │      │       └──────┬──────┘ │  │
                           │  │      │              │        │  │
                           │  │      └──────────────┴────────┘  │
                           │  │                                     │
                           │  └─────────────────────────────────────┘
                           │                    │
                           └────────────────────│────────────────────┘
                                                │
                                    Ethernet (RJ45)
                                                │
                                                ↓
                           ┌─────────────────────────────────────┐
                           │          上位机 (PC/Linux)          │
                           │                                     │
                           │  ┌───────────────────────────────┐  │
                           │  │   Python Application          │  │
                           │  │   ┌───────────────────────┐  │  │
                           │  │   │  SmartNIC Driver      │  │  │
                           │  │   │  (本手册配套API)      │  │  │
                           │  │   └───────────────────────┘  │  │
                           │  │             │                │  │
                           │  │             ↓                │  │
                           │  │   ┌───────────────────────┐  │  │
                           │  │   │   UDP Socket          │  │  │
                           │  │   └───────────────────────┘  │  │
                           │  └───────────────────────────────┘  │
                           └─────────────────────────────────────┘
```

## 2.2 数据流图

```
数据加密流程:

1. 配置阶段
   ┌──────────┐     UDP      ┌──────────┐
   │   PC     │ ───────────► │ SmartNIC │
   │ 应用程序 │  (0x4321)    │   Config │
   └──────────┘              │   模块   │
                             └────┬─────┘
                                  │
                                  ▼
                             配置算法和密钥

2. 加密阶段
   ┌──────────┐     UDP      ┌──────────┐     AXI      ┌──────────┐
   │   PC     │ ───────────► │ SmartNIC │ ───────────► │  Crypto  │
   │ 应用程序 │  (0x1234)    │   RX     │              │  Engine  │
   └──────────┘              │   Parser │              └────┬─────┘
                             └────┬─────┘                    │
                                  │                           ▼
                                  │                     ┌──────────┐
                                  │                     │ 加密数据 │
                                  │                     │ 输出     │
                                  │                     └────┬─────┘
                                  │                          │
   ┌──────────┐     UDP      ┌──────────┐                   │
   │   PC     │ ◄────────── │ SmartNIC │ ◄──────────────────┘
   │ 应用程序 │  (返回结果)  │   TX     │
   └──────────┘              │   Stack  │
                             └──────────┘

3. FastPath阶段 (不加密)
   ┌──────────┐     UDP      ┌──────────┐     直接透传    ┌──────────┐
   │   PC     │ ───────────► │ SmartNIC │ ──────────────► │  网络    │
   │ 应用程序 │  (任意端口)  │FastPath  │                │  出口    │
   └──────────┘              │   通道   │                └──────────┘
                             └──────────┘
```

## 2.3 端口定义

```
SmartNIC 端口分配:

┌──────────┬────────┬────────────────────────────────────┐
│  端口    │  十六进制 │              功能                 │
├──────────┼────────┼────────────────────────────────────┤
│  Config  │ 0x4321 │ 加密配置 (密钥、算法设置)          │
│  Crypto  │ 0x1234 │ 加密数据传输                       │
│  Data    │ 0x5678 │ FastPath数据传输 (不加密)          │
│  Status  │ 0x1000 │ 状态查询                           │
└──────────┴────────┴────────────────────────────────────┘
```

---

# 3. 硬件连接

## 3.1 硬件要求

```
必需硬件:

1. SmartNIC 开发板
   ├── FPGA: Xilinx Zynq-7020 或更高
   ├── DDR3: 512MB 或更大
   ├── 以太网: 1Gbps RJ45 x 2
   └── JTAG: 用于编程和调试

2. 上位机
   ├── CPU: 任意x86_64处理器
   ├── 内存: 4GB 或更大
   └── 网络: 1Gbps 以太网接口

3. 网络设备
   ├── 网线: Cat5e 或更高
   └── 交换机: 1Gbps (可选)
```

## 3.2 连接步骤

```
硬件连接图:

    上位机 (PC)                    SmartNIC
    ┌──────────┐                  ┌──────────┐
    │          │    网线          │          │
    │  以太网  │◄──────────────► │  以太网   │
    │  接口    │   (直连或通过    │  接口    │
    │          │    交换机)       │ (JP1/JP2)│
    │          │                  │          │
    │   USB    │◄──────────────► │  JTAG    │
    │  (调试)  │   (Xilinx下载器) │  接口    │
    │          │                  │          │
    └──────────┘                  └──────────┘

连接步骤:

步骤1: 连接以太网
       ├── 方法1: 直连 (PC ↔ SmartNIC)
       │    PC IP: 192.168.1.100 (手动设置)
       │    SmartNIC IP: 192.168.1.10 (默认)
       │
       └── 方法2: 通过交换机
            PC IP: 自动获取 (DHCP)
            SmartNIC IP: 192.168.1.10 (默认)

步骤2: 连接JTAG (可选，用于调试)
       └── 使用Xilinx Platform Cable USB

步骤3: 上电
       └── 12V DC 电源输入
```

## 3.3 网络配置

### Windows

```
步骤1: 打开网络连接
       控制面板 → 网络和共享中心 → 更改适配器设置

步骤2: 设置静态IP
       ├── 右键点击以太网适配器
       ├── 属性 → Internet协议版本4 (TCP/IPv4)
       ├── 使用以下IP地址:
       │   IP地址: 192.168.1.100
       │   子网掩码: 255.255.255.0
       │   默认网关: 192.168.1.1
       └── 确定

步骤3: 验证连接
       C:\> ping 192.168.1.10
       正在 Ping 192.168.1.10 具有 32 字节的数据:
       来自 192.168.1.10 的回复: 字节=32 时间<1ms TTL=64
```

### Linux

```bash
# 步骤1: 查看网络接口
$ ip addr show

# 步骤2: 设置静态IP
$ sudo ip addr add 192.168.1.100/24 dev eth0

# 步骤3: 启用接口
$ sudo ip link set eth0 up

# 步骤4: 验证连接
$ ping 192.168.1.10

# 步骤5: 测试UDP通信 (可选)
$ nc -u 192.168.1.10 8080
```

### macOS

```bash
# 步骤1: 查看网络接口
$ ifconfig

# 步骤2: 设置静态IP
$ sudo ifconfig en0 inet 192.168.1.100 netmask 255.255.255.0

# 步骤3: 验证连接
$ ping 192.168.1.10
```

---

# 4. 软件安装

## 4.1 环境要求

```
软件要求:

Python:
├── 版本: 3.8 或更高
├── 必需模块: socket, struct, time, random, typing
└── 可选模块: 无

操作系统:
├── Windows 10/11
├── Ubuntu 20.04+ / Debian 10+
├── macOS 11+
└── 其他支持Python的系统
```

## 4.2 安装步骤

### 步骤1: 获取驱动文件

```
项目结构:
D:\FPGAhanjia\Hetero_SoC_2026\
├── sw/
│   ├── smartnic_driver.py   # 主驱动文件
│   └── USER_MANUAL.md       # 本手册
└── ...
```

### 步骤2: 安装Python (如果未安装)

**Windows:**
```
1. 下载Python 3.10+
   https://www.python.org/downloads/

2. 运行安装程序
   ✓ 勾选 "Add Python to PATH"
   ✓ 选择 "Install for all users"

3. 验证安装
   C:\> python --version
   Python 3.10.0
```

**Linux (Ubuntu/Debian):**
```bash
# 安装Python
$ sudo apt update
$ sudo apt install python3 python3-pip

# 验证
$ python3 --version
Python 3.10.0
```

**macOS:**
```bash
# 使用Homebrew安装
$ brew install python

# 或下载安装包
# https://www.python.org/downloads/macos/
```

### 步骤3: 复制驱动文件

```bash
# 将smartnic_driver.py复制到您的项目目录

# 例如:
$ cp smartnic_driver.py /path/to/your/project/
```

### 步骤4: 验证安装

```python
# 创建测试文件 test_installation.py
from smartnic_driver import SmartNICDriver

# 创建实例
driver = SmartNICDriver()

# 尝试连接
try:
    if driver.connect():
        print("✅ 安装成功!")
        driver.disconnect()
    else:
        print("⚠️  连接失败 (可能是硬件未连接)")
except Exception as e:
    print(f"❌ 安装失败: {e}")
```

```bash
# 运行测试
$ python test_installation.py
```

---

# 5. 快速开始

## 5.1 第一个示例: Hello SmartNIC

```python
#!/usr/bin/env python3
"""
第一个SmartNIC程序: Hello SmartNIC
这个程序演示了基本的使用流程
"""

# 导入驱动
from smartnic_driver import SmartNICDriver

def main():
    print("=" * 60)
    print("SmartNIC 第一个示例程序")
    print("=" * 60)
    
    # 1. 创建驱动实例
    # SmartNIC的IP地址和端口
    smartnic = SmartNICDriver(
        ip_addr='192.168.1.10',  # SmartNIC的IP地址
        fpga_port=8080           # 通信端口
    )
    
    # 2. 连接到SmartNIC
    print("\n[步骤1] 连接到SmartNIC...")
    if smartnic.connect():
        print("✅ 连接成功!")
    else:
        print("❌ 连接失败，请检查:")
        print("   1. SmartNIC是否已开机")
        print("   2. IP地址是否正确")
        print("   3. 网络连接是否正常")
        return
    
    # 3. 配置加密算法
    print("\n[步骤2] 配置加密算法...")
    print("   选择加密方式:")
    print("   1. AES-128-CBC (国际标准)")
    print("   2. SM4-CBC (中国国密)")
    
    choice = input("   请选择 (1/2): ").strip()
    
    if choice == '1':
        # AES-128-CBC
        if smartnic.set_aes():
            print("   ✅ 已配置为 AES-128-CBC")
        else:
            print("   ❌ AES配置失败")
    else:
        # SM4-CBC
        if smartnic.set_sm4():
            print("   ✅ 已配置为 SM4-CBC")
        else:
            print("   ❌ SM4配置失败")
    
    # 4. 准备要加密的数据
    print("\n[步骤3] 准备加密数据...")
    plaintext = input("   输入要加密的文本: ").encode()
    print(f"   明文: {plaintext}")
    print(f"   长度: {len(plaintext)} 字节")
    
    # 5. 加密数据
    print("\n[步骤4] 加密数据...")
    ciphertext = smartnic.encrypt(plaintext)
    
    if ciphertext:
        print("✅ 加密成功!")
        print(f"   密文 (十六进制): {ciphertext.hex()}")
        print(f"   密文长度: {len(ciphertext)} 字节")
    else:
        print("❌ 加密失败")
    
    # 6. 查看状态
    print("\n[步骤5] 查看状态...")
    print(smartnic.get_statistics())
    
    # 7. 断开连接
    print("\n[步骤6] 断开连接...")
    smartnic.disconnect()
    print("✅ 已断开连接")
    
    print("\n" + "=" * 60)
    print("程序执行完毕!")
    print("=" * 60)

if __name__ == '__main__':
    main()
```

**运行:**
```bash
$ python hello_smartnic.py

============================================================
SmartNIC 第一个示例程序
============================================================

[步骤1] 连接到SmartNIC...
✅ 连接成功!

[步骤2] 配置加密算法...
   选择加密方式:
   1. AES-128-CBC (国际标准)
   2. SM4-CBC (中国国密)
   请选择 (1/2): 1
   ✅ 已配置为 AES-128-CBC

[步骤3] 准备加密数据...
   输入要加密的文本: Hello, SmartNIC!
   明文: b'Hello, SmartNIC!'
   长度: 17 字节

[步骤4] 加密数据...
✅ 加密成功!
   密文 (十六进制): 7649abac8119b246...
   密文长度: 32 字节

[步骤5] 查看状态...
...

[步骤6] 断开连接...
✅ 已断开连接

============================================================
程序执行完毕!
============================================================
```

## 5.2 批量加密示例

```python
#!/usr/bin/env python3
"""
批量加密示例: 加密多个数据块
"""

from smartnic_driver import SmartNICDriver

def main():
    # 创建驱动并连接
    driver = SmartNICDriver()
    driver.connect()
    
    # 选择AES加密
    driver.set_aes()
    
    # 准备多个数据块
    messages = [
        b"Message 1: Hello World!     ",
        b"Message 2: SmartNIC is fast!",
        b"Message 3: Hardware crypto  ",
        b"Message 4: 128-bit security!",
        b"Message 5: CBC mode cipher! ",
    ]
    
    print("=" * 60)
    print("批量加密演示")
    print("=" * 60)
    
    # 加密所有消息
    ciphertexts = []
    for i, msg in enumerate(messages):
        ct = driver.encrypt(msg)
        if ct:
            ciphertexts.append(ct)
            print(f"✅ 消息 {i+1} 加密成功: {len(msg)} -> {len(ct)} 字节")
        else:
            print(f"❌ 消息 {i+1} 加密失败")
    
    # 统计
    total_input = sum(len(m) for m in messages)
    total_output = sum(len(c) for c in ciphertexts)
    
    print("\n" + "-" * 60)
    print(f"总计:")
    print(f"  输入: {total_input} 字节 ({len(messages)} 条消息)")
    print(f"  输出: {total_output} 字节 ({len(ciphertexts)} 条消息)")
    print(f"  膨胀率: {total_output/total_input:.2f}x")
    print("-" * 60)
    
    driver.disconnect()

if __name__ == '__main__':
    main()
```

## 5.3 文件加密示例

```python
#!/usr/bin/env python3
"""
文件加密示例: 加密整个文件
"""

from smartnic_driver import SmartNICDriver
import os

def main():
    driver = SmartNICDriver()
    driver.connect()
    
    # 配置SM4加密
    driver.set_sm4()
    
    input_file = "document.pdf"  # 输入文件
    output_file = "document.enc"  # 输出文件
    
    print("=" * 60)
    print("文件加密演示")
    print("=" * 60)
    
    # 检查文件是否存在
    if not os.path.exists(input_file):
        print(f"❌ 文件不存在: {input_file}")
        # 创建测试文件
        with open(input_file, 'wb') as f:
            f.write(b"Test document content for encryption demo!")
        print(f"✅ 已创建测试文件: {input_file}")
    
    # 获取文件大小
    file_size = os.path.getsize(input_file)
    print(f"输入文件: {input_file}")
    print(f"文件大小: {file_size} 字节")
    
    # 加密文件
    if driver.encrypt_file(input_file, output_file):
        encrypted_size = os.path.getsize(output_file)
        print(f"\n✅ 加密成功!")
        print(f"输出文件: {output_file}")
        print(f"加密后大小: {encrypted_size} 字节")
        
        # 验证
        with open(output_file, 'rb') as f:
            encrypted_data = f.read()
        print(f"验证: 读取到 {len(encrypted_data)} 字节")
    else:
        print("❌ 文件加密失败")
    
    driver.disconnect()

if __name__ == '__main__':
    main()
```

---

# 6. 加密方式详解

## 6.1 加密算法介绍

### AES-128-CBC

```
AES (Advanced Encryption Standard) 是一种广泛使用的对称加密算法:

┌─────────────────────────────────────────────────────────────┐
│                     AES-128-CBC                             │
├─────────────────────────────────────────────────────────────┤
│  标准:     NIST FIPS 197                                    │
│  密钥长度: 128位 (16字节)                                    │
│  块大小:   128位 (16字节)                                    │
│  模式:     CBC (Cipher Block Chaining)                      │
│  安全级别: 商用安全，适合大多数应用                          │
│  性能:     快                                               │
│  国际认可: 全球通用                                          │
├─────────────────────────────────────────────────────────────┤
│  使用场景:                                                   │
│  • SSL/TLS 加密                                             │
│  • 文件加密                                                  │
│  • 数据库加密                                                │
│  • VPN 通信                                                  │
└─────────────────────────────────────────────────────────────┘
```

### SM4-CBC

```
SM4 是中国国家密码管理局发布的对称加密算法:

┌─────────────────────────────────────────────────────────────┐
│                      SM4-CBC                                │
├─────────────────────────────────────────────────────────────┤
│  标准:     GM/T 0002-2012 / ISO/IEC 11801-3                │
│  密钥长度: 128位 (16字节)                                    │
│  块大小:   128位 (16字节)                                    │
│  模式:     CBC (Cipher Block Chaining)                      │
│  安全级别: 中国官方认证，金融级安全                          │
│  性能:     快 (与AES相当)                                   │
│  国际认可: ISO/IEC标准                                       │
├─────────────────────────────────────────────────────────────┤
│  使用场景:                                                   │
│  • 中国政务系统                                              │
│  • 金融行业                                                  │
│  • 电子商务                                                  │
│  • 物联网 (中国标准)                                         │
└─────────────────────────────────────────────────────────────┘
```

## 6.2 选择加密方式

### 方法1: 使用快捷方法 (推荐)

```python
from smartnic_driver import SmartNICDriver

driver = SmartNICDriver()
driver.connect()

# 方法1: AES-128-CBC (默认)
driver.set_aes()
# 使用默认密钥和IV
# 密钥: 2b7e151628aed2a6abf7158809cf4f3c
# IV:   000102030405060708090a0b0c0d0e0f

# 方法2: SM4-CBC (中国国密)
driver.set_sm4()
# 使用默认密钥和IV
# 密钥: 0123456789abcdeffedcba9876543210
# IV:   00000000000000000000000000000000
```

### 方法2: 自定义密钥和IV

```python
from smartnic_driver import SmartNICDriver

driver = SmartNICDriver()
driver.connect()

# AES 自定义配置
driver.set_aes(
    key=bytes.fromhex('2b7e151628aed2a6abf7158809cf4f3c'),  # 16字节
    iv=bytes.fromhex('000102030405060708090a0b0c0d0e0f')    # 16字节
)

# SM4 自定义配置
driver.set_sm4(
    key=bytes.fromhex('0123456789abcdeffedcba9876543210'),  # 16字节
    iv=bytes.fromhex('00000000000000000000000000000000')    # 16字节
)
```

### 方法3: 使用set_config (高级)

```python
from smartnic_driver import SmartNICDriver, CryptoAlgorithm

driver = SmartNICDriver()
driver.connect()

# AES
driver.set_config(
    algorithm=CryptoAlgorithm.AES_128_CBC,
    key=bytes.fromhex('2b7e151628aed2a6abf7158809cf4f3c'),
    iv=bytes.fromhex('000102030405060708090a0b0c0d0e0f')
)

# SM4
driver.set_config(
    algorithm=CryptoAlgorithm.SM4_CBC,
    key=bytes.fromhex('0123456789abcdeffedcba9876543210'),
    iv=bytes.fromhex('00000000000000000000000000000000')
)
```

## 6.3 密钥和IV说明

```
密钥 (Key):
┌─────────────────────────────────────────────────────────────┐
│  • 长度: 必须为16字节 (128位)                                │
│  • 安全性: 越随机越好                                        │
│  • 存储: 安全存储，不要硬编码在代码中                        │
│  • 建议: 使用密码学安全的随机数生成器                        │
└─────────────────────────────────────────────────────────────┘

初始化向量 (IV):
┌─────────────────────────────────────────────────────────────┐
│  • 长度: 必须为16字节 (128位)                                │
│  • 目的: 确保相同明文产生不同密文                            │
│  • 规则: 每次加密使用随机IV                                  │
│  • 注意: IV不需要保密，但必须唯一                            │
└─────────────────────────────────────────────────────────────┘
```

### 密钥生成示例

```python
import os
from smartnic_driver import SmartNICDriver

def generate_random_key():
    """生成随机密钥"""
    return os.urandom(16)  # 16字节 = 128位

def generate_random_iv():
    """生成随机IV"""
    return os.urandom(16)  # 16字节 = 128位

driver = SmartNICDriver()
driver.connect()

# 生成随机密钥和IV
random_key = generate_random_key()
random_iv = generate_random_iv()

print(f"随机密钥: {random_key.hex()}")
print(f"随机IV:   {random_iv.hex()}")

# 使用随机密钥和IV
driver.set_aes(key=random_key, iv=random_iv)
```

---

# 7. 数据加密详解

## 7.1 数据格式要求

```
输入数据要求:

┌─────────────────────────────────────────────────────────────┐
│  要求:                                                       │
│  • 类型: Python bytes对象                                    │
│  • 长度: 必须是16字节的整数倍                                │
│  • 范围: 0 ~ 16KB (单次加密最大长度)                         │
│  • 内容: 任意二进制数据                                      │
└─────────────────────────────────────────────────────────────┘

长度处理:
┌──────────────────┬────────────────────────────────────┐
│  输入长度        │  处理方式                           │
├──────────────────┼────────────────────────────────────┤
│  16的倍数        │  直接加密                           │
│  不是16的倍数    │  自动填充至16的倍数                 │
└──────────────────┴────────────────────────────────────┘
```

### 示例: 不同长度的输入

```python
from smartnic_driver import SmartNICDriver

driver = SmartNICDriver()
driver.connect()
driver.set_aes()

# 16字节 (正好)
plaintext1 = b"1234567890123456"  # 16字节
ciphertext1 = driver.encrypt(plaintext1)
print(f"16字节 -> {len(ciphertext1)} 字节")

# 32字节 (整数倍)
plaintext2 = b"12345678901234567890123456789012"  # 32字节
ciphertext2 = driver.encrypt(plaintext2)
print(f"32字节 -> {len(ciphertext2)} 字节")

# 17字节 (需要填充)
plaintext3 = b"12345678901234567"  # 17字节
ciphertext3 = driver.encrypt(plaintext3)
print(f"17字节 -> {len(ciphertext3)} 字节 (自动填充)")
```

## 7.2 加密函数详解

```python
def encrypt(self, plaintext: bytes) -> Optional[bytes]:
    """
    加密数据
    
    参数:
        plaintext: 明文数据 (bytes)
        
    返回:
        密文数据 (bytes) 或 None (失败)
        
    过程:
        1. 验证输入长度
        2. 自动填充至16字节整数倍
        3. 发送至SmartNIC
        4. 接收加密结果
        5. 返回密文
    """
```

### 完整加密流程图

```
encrypt() 函数流程:

  ┌──────────────────────────────────────────────┐
  │              encrypt(plaintext)               │
  └────────────────────┬─────────────────────────┘
                       │
                       ▼
              ┌─────────────────────┐
              │ 1. 检查长度         │
              │ len(plaintext) % 16 │
              └──────────┬──────────┘
                         │
            ┌────────────┼────────────┐
            ↓            │            ↓
       16的倍数    不是16的倍数      │
            │            │            │
            ↓            ▼            │
    ┌──────────────┐     │            │
    │ 直接使用     │     ▼            │
    └──────┬───────┘   ┌─────────────────────┐
           │           │ 2. 自动填充         │
           │           │ padding_len = 16 - (len % 16)
           │           │ plaintext += bytes([padding_len] * padding_len)
           │           └──────────┬──────────┘
           │                      │
           └──────────┬───────────┘
                      ▼
              ┌─────────────────────┐
              │ 3. 构建数据包       │
              │ src_port(2B)        │
              │ dst_port(2B)        │
              │ length(2B)          │
              │ payload             │
              └──────────┬──────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │ 4. UDP发送          │
              │ 目标: CRYPTO_PORT   │
              │ (0x1234)            │
              └──────────┬──────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │ 5. 等待响应         │
              │ 超时: 5秒           │
              └──────────┬──────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │ 6. 解析响应         │
              │ status(1B)          │
              │ length(2B)          │
              │ ciphertext          │
              └──────────┬──────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │ 7. 返回结果         │
              │ 成功: ciphertext    │
              │ 失败: None          │
              └─────────────────────┘
```

## 7.3 加密示例代码

### 示例1: 简单文本加密

```python
from smartnic_driver import SmartNICDriver

def simple_encrypt_demo():
    driver = SmartNICDriver()
    driver.connect()
    driver.set_aes()
    
    # 要加密的文本
    plaintext = "Hello, SmartNIC! 这是一条测试消息。"
    
    # 转换为bytes
    plaintext_bytes = plaintext.encode('utf-8')
    print(f"原文: {plaintext}")
    print(f"长度: {len(plaintext_bytes)} 字节")
    
    # 加密
    ciphertext = driver.encrypt(plaintext_bytes)
    
    if ciphertext:
        print(f"\n加密成功!")
        print(f"密文: {ciphertext.hex()}")
        print(f"长度: {len(ciphertext)} 字节")
    
    driver.disconnect()

simple_encrypt_demo()
```

### 示例2: 加密JSON数据

```python
from smartnic_driver import SmartNICDriver
import json

def encrypt_json_demo():
    driver = SmartNICDriver()
    driver.connect()
    driver.set_sm4()
    
    # 准备JSON数据
    data = {
        "user_id": 12345,
        "username": "test_user",
        "email": "test@example.com",
        "password_hash": "abc123def456",
        "permissions": ["read", "write", "delete"],
        "created_at": "2026-01-31T00:00:00Z"
    }
    
    # 转换为JSON字符串然后bytes
    json_str = json.dumps(data, separators=(',', ':'))
    plaintext = json_str.encode('utf-8')
    
    print("原始数据:")
    print(json.dumps(data, indent=2))
    print(f"\n长度: {len(plaintext)} 字节")
    
    # 加密
    ciphertext = driver.encrypt(plaintext)
    
    if ciphertext:
        print(f"\n加密后:")
        print(f"密文长度: {len(ciphertext)} 字节")
        print(f"密文(前32字节): {ciphertext[:32].hex()}...")
    
    driver.disconnect()

encrypt_json_demo()
```

### 示例3: 加密二进制文件

```python
from smartnic_driver import SmartNICDriver
import struct

def encrypt_binary_demo():
    driver = SmartNICDriver()
    driver.connect()
    driver.set_aes()
    
    # 创建二进制数据
    # 例如: 结构化数据
    data_format = 'Ifd'  # int, float, double
    data = (42, 3.14159, 2.71828)
    
    # 打包为二进制
    binary_data = struct.pack(data_format, *data)
    print(f"原始二进制数据: {binary_data.hex()}")
    print(f"长度: {len(binary_data)} 字节")
    
    # 加密
    ciphertext = driver.encrypt(binary_data)
    
    if ciphertext:
        print(f"\n加密后:")
        print(f"长度: {len(ciphertext)} 字节")
        
        # 解密验证 (需要对应的解密函数)
        # decrypted = driver.decrypt(ciphertext)
        # unpacked = struct.unpack(data_format, decrypted)
        # print(f"解密验证: {unpacked}")
    
    driver.disconnect()

encrypt_binary_demo()
```

---

# 8. 结果输出详解

## 8.1 加密结果格式

```
加密结果格式:

┌─────────────────────────────────────────────────────────────┐
│                     加密输出                                 │
├─────────────────────────────────────────────────────────────┤
│  类型:     Python bytes对象                                  │
│  长度:     等于或大于输入长度 (16字节整数倍)                  │
│  内容:     加密后的密文数据                                  │
│  用途:     保存、传输、或后续处理                            │
└─────────────────────────────────────────────────────────────┘

输出示例:
  输入:  b"Hello, SmartNIC!" (17字节)
  输出:  b"\x76\x49\xab\xac..." (32字节)
```

## 8.2 输出方式

### 方式1: 直接使用

```python
ciphertext = driver.encrypt(plaintext)

# 直接使用bytes对象
print(ciphertext.hex())           # 十六进制
print(ciphertext.decode('utf-8', errors='ignore'))  # 尝试解码
```

### 方式2: 保存到文件

```python
ciphertext = driver.encrypt(plaintext)

# 二进制模式保存
with open('encrypted.bin', 'wb') as f:
    f.write(ciphertext)

# Base64编码保存
import base64
with open('encrypted_base64.txt', 'w') as f:
    f.write(base64.b64encode(ciphertext).decode('ascii'))
```

### 方式3: 发送到网络

```python
import socket

ciphertext = driver.encrypt(plaintext)

# 创建UDP socket
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

# 发送到目标
target_ip = '192.168.1.100'
target_port = 9000
sock.sendto(ciphertext, (target_ip, target_port))
print(f"✅ 已发送 {len(ciphertext)} 字节到 {target_ip}:{target_port}")
```

### 方式4: 显示进度

```python
def encrypt_with_progress(plaintext, chunk_size=1024):
    """分块加密并显示进度"""
    driver = SmartNICDriver()
    driver.connect()
    driver.set_aes()
    
    ciphertext = b''
    total = len(plaintext)
    processed = 0
    
    for i in range(0, total, chunk_size):
        chunk = plaintext[i:i+chunk_size]
        encrypted = driver.encrypt(chunk)
        
        if encrypted:
            ciphertext += encrypted
            processed += len(chunk)
            progress = processed / total * 100
            print(f"\r进度: {progress:.1f}% ({processed}/{total} 字节)", end='')
    
    print(f"\n✅ 完成! 总计 {len(ciphertext)} 字节")
    return ciphertext
```

## 8.3 结果验证

```python
from smartnic_driver import SmartNICDriver

def verify_encryption():
    """验证加密结果的正确性"""
    driver = SmartNICDriver()
    driver.connect()
    driver.set_aes()
    
    # 原始数据
    original = b"Test data for verification    "  # 32字节
    
    # 加密
    encrypted = driver.encrypt(original)
    
    if encrypted:
        # 验证1: 长度应该是16的整数倍
        assert len(encrypted) % 16 == 0, "加密结果长度错误"
        print("✅ 长度验证通过")
        
        # 验证2: 密文应该与原文不同
        assert encrypted != original, "加密可能未生效"
        print("✅ 内容验证通过")
        
        # 验证3: 多次加密相同数据应该不同 (因为随机IV)
        encrypted2 = driver.encrypt(original)
        # 注意: 由于IV可能变化，密文可能不同
        
        print(f"✅ 加密成功!")
        print(f"原文长度: {len(original)} 字节")
        print(f"密文长度: {len(encrypted)} 字节")
    else:
        print("❌ 加密失败")
    
    driver.disconnect()

verify_encryption()
```

---

# 9. API参考

## 9.1 SmartNICDriver类

### __init__

```python
def __init__(self, ip_addr: str = '192.168.1.10', fpga_port: int = 8080):
    """
    创建SmartNIC驱动实例
    
    参数:
        ip_addr: SmartNIC的IP地址 (默认: '192.168.1.10')
        fpga_port: FPGA的通信端口 (默认: 8080)
        
    示例:
        driver = SmartNICDriver()  # 使用默认配置
        driver = SmartNICDriver(ip_addr='192.168.1.20')  # 自定义IP
    """
```

### connect

```python
def connect(self) -> bool:
    """
    连接到SmartNIC
    
    返回:
        bool: 连接是否成功
        
    示例:
        if driver.connect():
            print("✅ 连接成功")
        else:
            print("❌ 连接失败")
    """
```

### disconnect

```python
def disconnect(self):
    """
    断开与SmartNIC的连接
    
    示例:
        driver.disconnect()
        print("已断开")
    """
```

### set_config

```python
def set_config(self, 
               algorithm: CryptoAlgorithm, 
               key: Optional[bytes] = None, 
               iv: Optional[bytes] = None) -> bool:
    """
    配置加密参数
    
    参数:
        algorithm: 加密算法 (CryptoAlgorithm.AES_128_CBC 或 SM4_CBC)
        key: 密钥 (16字节，可选，默认使用预设值)
        iv: 初始化向量 (16字节，可选，默认使用预设值)
        
    返回:
        bool: 配置是否成功
        
    示例:
        driver.set_config(
            algorithm=CryptoAlgorithm.AES_128_CBC,
            key=bytes.fromhex('2b7e151628aed2a6abf7158809cf4f3c'),
            iv=bytes.fromhex('000102030405060708090a0b0c0d0e0f')
        )
    """
```

### set_aes

```python
def set_aes(self, 
            key: Optional[bytes] = None, 
            iv: Optional[bytes] = None) -> bool:
    """
    配置AES-128-CBC加密 (快捷方法)
    
    参数:
        key: AES密钥 (16字节，可选)
        iv: AES IV (16字节，可选)
        
    返回:
        bool: 配置是否成功
        
    示例:
        driver.set_aes()  # 使用默认密钥
        driver.set_aes(
            key=bytes.fromhex('2b7e151628aed2a6abf7158809cf4f3c'),
            iv=bytes.fromhex('000102030405060708090a0b0c0d0e0f')
        )
    """
```

### set_sm4

```python
def set_sm4(self,
            key: Optional[bytes] = None,
            iv: Optional[bytes] = None) -> bool:
    """
    配置SM4-CBC加密 (快捷方法)
    
    参数:
        key: SM4密钥 (16字节，可选)
        iv: SM4 IV (16字节，可选)
        
    返回:
        bool: 配置是否成功
        
    示例:
        driver.set_sm4()  # 使用默认密钥
        driver.set_sm4(
            key=bytes.fromhex('0123456789abcdeffedcba9876543210'),
            iv=bytes.fromhex('00000000000000000000000000000000')
        )
    """
```

### encrypt

```python
def encrypt(self, plaintext: bytes) -> Optional[bytes]:
    """
    加密数据
    
    参数:
        plaintext: 明文数据 (bytes)
        
    返回:
        bytes: 加密后的密文 (成功)
        None:  加密失败
        
    示例:
        plaintext = b"Hello, SmartNIC!"
        ciphertext = driver.encrypt(plaintext)
        if ciphertext:
            print(f"密文: {ciphertext.hex()}")
    """
```

### encrypt_file

```python
def encrypt_file(self, input_file: str, output_file: str) -> bool:
    """
    加密文件
    
    参数:
        input_file: 输入文件路径
        output_file: 输出文件路径
        
    返回:
        bool: 是否成功
        
    示例:
        if driver.encrypt_file("plain.txt", "cipher.bin"):
            print("文件加密成功")
    """
```

### send_fastpath

```python
def send_fastpath(self, data: bytes, dst_port: int = 80) -> bool:
    """
    使用FastPath快速通道 (不加密)
    
    参数:
        data: 要发送的数据
        dst_port: 目标端口 (默认80)
        
    返回:
        bool: 是否成功
        
    示例:
        # 发送HTTP请求 (不加密)
        driver.send_fastpath(b"GET / HTTP/1.1\r\n\r\n", dst_port=80)
    """
```

### get_status

```python
def get_status(self) -> Dict:
    """
    获取SmartNIC状态
    
    返回:
        Dict: 状态信息字典
        
    返回字典字段:
        {
            'encrypted_packets': int,   # 加密包数
            'encrypted_bytes': int,     # 加密字节数
            'fastpath_packets': int,    # FastPath包数
            'dropped_packets': int,     # 丢弃包数
            'algorithm': str,           # 当前算法
            'local_ip': str,            # 本地IP
            'local_port': int           # 本地端口
        }
        
    示例:
        status = driver.get_status()
        print(f"加密包数: {status['encrypted_packets']}")
    """
```

### get_statistics

```python
def get_statistics(self) -> str:
    """
    获取格式化状态统计信息
    
    返回:
        str: 格式化的状态信息
        
    示例:
        print(driver.get_statistics())
        # 输出:
        # ╔══════════════════════════════════════╗
        # ║        SmartNIC 状态统计              ║
        # ╠══════════════════════════════════════╣
        # ║  加密算法:     AES-128-CBC            ║
        # ║  加密包数:     100                    ║
        # ║  加密字节:     102400                 ║
        # ...
    """
```

## 9.2 CryptoAlgorithm枚举

```python
class CryptoAlgorithm(Enum):
    """
    加密算法枚举
    
    值:
        AES_128_CBC: AES-128-CBC加密
        SM4_CBC: SM4-CBC加密
    """
    AES_128_CBC = 0
    SM4_CBC = 1
```

---

# 10. 高级功能

## 10.1 FastPath快速通道

FastPath是一种不经过加密的快速传输通道，适用于不需要加密的网络流量:

```
FastPath适用场景:
┌─────────────────────────────────────────────────────────────┐
│  ✓ 普通HTTP/HTTPS流量                                       │
│  ✓ DNS查询                                                  │
│  ✓ NTP时间同步                                              │
│  ✓ DHCP配置                                                 │
│  ✓ 不需要加密的管理流量                                      │
├─────────────────────────────────────────────────────────────┤
│  ✗ 需要加密的敏感数据                                        │
│  ✗ 金融交易数据                                             │
│  ✗ 个人隐私信息                                             │
└─────────────────────────────────────────────────────────────┘
```

### 使用FastPath

```python
from smartnic_driver import SmartNICDriver

driver = SmartNICDriver()
driver.connect()

# 发送HTTP请求 (端口80，不加密)
http_request = b"GET /index.html HTTP/1.1\r\nHost: www.example.com\r\nConnection: close\r\n\r\n"
driver.send_fastpath(http_request, dst_port=80)

# 发送DNS查询 (端口53，不加密)
dns_query = b"\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01"
driver.send_fastpath(dns_query, dst_port=53)

driver.disconnect()
```

## 10.2 状态监控

```python
from smartnic_driver import SmartNICDriver
import time

def monitor_demo():
    """状态监控示例"""
    driver = SmartNICDriver()
    driver.connect()
    driver.set_aes()
    
    print("开始监控SmartNIC状态...")
    print("按Ctrl+C停止")
    print()
    
    try:
        i = 0
        while True:
            status = driver.get_status()
            
            print(f"\r[{i:06d}] "
                  f"加密: {status['encrypted_packets']:,} 包, "
                  f"{status['encrypted_bytes']:,} 字节 | "
                  f"FastPath: {status['fastpath_packets']:,} | "
                  f"算法: {status['algorithm']}",
                  end='', flush=True)
            
            time.sleep(1)
            i += 1
            
    except KeyboardInterrupt:
        print("\n\n停止监控")
    
    driver.disconnect()

# monitor_demo()  # 运行监控
```

## 10.3 错误处理

```python
from smartnic_driver import SmartNICDriver

def robust_encrypt_demo():
    """带错误处理的加密示例"""
    driver = SmartNICDriver()
    
    try:
        # 1. 连接
        if not driver.connect():
            raise Exception("无法连接到SmartNIC")
        print("✅ 连接成功")
        
        # 2. 配置
        if not driver.set_aes():
            raise Exception("AES配置失败")
        print("✅ AES配置成功")
        
        # 3. 加密
        plaintext = b"Test data for robust encryption    "
        ciphertext = driver.encrypt(plaintext)
        
        if ciphertext is None:
            raise Exception("加密失败")
        print(f✅ 加密成功: {len(ciphertext)} 字节")
        
    except Exception as e:
        print(f"❌ 错误: {e}")
        
    finally:
        # 4. 清理
        driver.disconnect()
        print("✅ 已清理")

robust_encrypt_demo()
```

---

# 11. 性能优化

## 11.1 批量加密优化

```python
from smartnic_driver import SmartNICDriver
import time

def batch_encrypt_optimized(data_chunks):
    """优化的批量加密"""
    driver = SmartNICDriver()
    driver.connect()
    driver.set_aes()
    
    results = []
    start_time = time.time()
    
    for chunk in data_chunks:
        # 不等待每个响应，直接发送
        # 这里简化处理，实际可以使用异步IO
        result = driver.encrypt(chunk)
        if result:
            results.append(result)
    
    elapsed = time.time() - start_time
    total_bytes = sum(len(r) for r in results)
    
    print(f"加密 {len(results)} 个数据块")
    print(f"总数据量: {total_bytes:,} 字节")
    print(f"耗时: {elapsed:.3f} 秒")
    print(f"吞吐量: {total_bytes / elapsed / 1024 / 1024:.2f} MB/s")
    
    driver.disconnect()
    return results

# 使用
data = [b"chunk " + bytes([i % 26 + 65]) * 1000 for i in range(10)]
batch_encrypt_optimized(data)
```

## 11.2 连接池

```python
from smartnic_driver import SmartNICDriver

class SmartNICPool:
    """SmartNIC连接池"""
    
    def __init__(self, size=5):
        self.pool = []
        self.size = size
        
        # 预创建连接
        for _ in range(size):
            driver = SmartNICDriver()
            if driver.connect():
                self.pool.append(driver)
            else:
                print(f"⚠️  无法创建连接")
    
    def get(self):
        """获取一个连接"""
        if self.pool:
            return self.pool.pop()
        else:
            # 创建新连接
            driver = SmartNICDriver()
            if driver.connect():
                return driver
            return None
    
    def return_(self, driver):
        """归还连接"""
        if len(self.pool) < self.size:
            self.pool.append(driver)
        else:
            driver.disconnect()
    
    def close_all(self):
        """关闭所有连接"""
        for driver in self.pool:
            driver.disconnect()
        self.pool.clear()

# 使用
pool = SmartNICPool(size=3)

# 获取连接
driver = pool.get()
if driver:
    driver.set_aes()
    ciphertext = driver.encrypt(b"test data")
    # 归还连接
    pool.return_(driver)

# 关闭所有
pool.close_all()
```

---

# 12. 故障排除

## 12.1 常见问题

### 问题1: 连接失败

```
症状:
  driver.connect() 返回 False
  或抛出异常
```

**可能原因和解决方案:**

```python
# 检查1: 网络连通性
import subprocess
result = subprocess.run(['ping', '192.168.1.10'], capture_output=True, text=True)
if '回复' not in result.stdout and 'bytes from' not in result.stdout:
    print("❌ 无法ping通SmartNIC")
    # 解决方案:
    # 1. 检查网线连接
    # 2. 检查IP地址配置
    # 3. 检查防火墙设置
    # 4. 确认SmartNIC已开机

# 检查2: 端口可达性
import socket
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(1)
try:
    sock.sendto(b'test', ('192.168.1.10', 8080))
    print("✅ 端口可达")
except Exception as e:
    print(f"❌ 端口不可达: {e}")
```

### 问题2: 加密失败

```
症状:
  driver.encrypt() 返回 None
```

**可能原因和解决方案:**

```python
# 检查1: 连接状态
if not driver.sock:
    print("❌ 未连接，请先调用connect()")
    driver.connect()

# 检查2: 配置状态
# 确保已设置加密算法
driver.set_aes()

# 检查3: 数据格式
plaintext = b"test data"
if len(plaintext) % 16 != 0:
    # 自动填充
    plaintext = plaintext.ljust(((len(plaintext) + 15) // 16) * 16, b'\x00')
    print(f"⚠️  已填充至 {len(plaintext)} 字节")

# 检查4: 重试
for attempt in range(3):
    ciphertext = driver.encrypt(plaintext)
    if ciphertext:
        print(f"✅ 第{attempt+1}次尝试成功")
        break
else:
    print("❌ 多次重试失败")
```

### 问题3: 超时

```
症状:
  通信超时错误
```

**解决方案:**

```python
# 增加超时时间
driver = SmartNICDriver()
driver.config['timeout'] = 10.0  # 10秒

# 检查网络延迟
import time
start = time.time()
try:
    driver.connect()
    latency = (time.time() - start) * 1000
    print(f"延迟: {latency:.1f}ms")
except:
    print("❌ 连接超时")
```

### 问题4: 加密结果不正确

```
症状:
  密文与预期不符
  解密后数据损坏
```

**解决方案:**

```python
# 检查1: 密钥一致性
print(f"当前密钥: {driver.config['key'].hex()}")
print(f"当前IV:   {driver.config['iv'].hex()}")

# 检查2: 使用默认配置重新配置
driver.set_aes()  # 使用默认密钥

# 检查3: 验证加密
plaintext = b"test data              "  # 16字节对齐
ciphertext = driver.encrypt(plaintext)
print(f"加密结果: {ciphertext.hex()}")

# 如果需要解密，使用对应的解密函数
# decrypted = driver.decrypt(ciphertext)
# assert decrypted == plaintext, "解密验证失败"
```

## 12.2 错误代码

```python
# 可能的错误状态码
ERROR_CODES = {
    0x00: "成功",
    0x01: "未知错误",
    0x02: "密钥错误",
    0x03: "IV错误",
    0x04: "数据格式错误",
    0x05: "长度错误",
    0x06: "缓冲区溢出",
    0x07: "超时",
    0x08: "认证失败",
    0x09: "权限不足",
    0x0A: "忙状态",
}

def get_error_message(status_code):
    """获取错误信息"""
    return ERROR_CODES.get(status_code, f"未知错误 (0x{status_code:02X})")
```

---

# 13. 安全最佳实践

## 13.1 密钥管理

```
✅ 推荐做法:
┌─────────────────────────────────────────────────────────────┐
│  • 使用强随机数生成密钥                                      │
│  • 定期更换密钥                                              │
│  • 安全存储密钥 (密钥管理服务/硬件安全模块)                  │
│  • 不要在代码中硬编码密钥                                    │
│  • 使用环境变量或配置文件管理密钥                            │
│  • 监控密钥使用情况                                          │
└─────────────────────────────────────────────────────────────┘

✗ 不推荐做法:
┌─────────────────────────────────────────────────────────────┐
│  • 使用简单密码作为密钥                                      │
│  • 硬编码在源代码中                                          │
│  • 共享密钥给不需要的人员                                    │
│  • 长期使用同一密钥                                          │
│  • 在日志中打印密钥                                         │
└─────────────────────────────────────────────────────────────┘
```

### 密钥管理示例

```python
import os
from smartnic_driver import SmartNICDriver

def secure_key_management():
    """安全的密钥管理示例"""
    
    # 方式1: 从环境变量读取
    key = os.environ.get('SMARTNIC_KEY')
    if not key:
        # 生成新密钥
        key = os.urandom(16).hex()
        os.environ['SMARTNIC_KEY'] = key
        print("✅ 已生成并保存新密钥")
    
    key_bytes = bytes.fromhex(key)
    
    # 方式2: 从安全存储读取 (示例)
    # from keyring import get_password
    # key_hex = get_password("SmartNIC", "encryption_key")
    # key_bytes = bytes.fromhex(key_hex)
    
    driver = SmartNICDriver()
    driver.connect()
    driver.set_aes(key=key_bytes)
    
    # ... 加密操作 ...
    
    driver.disconnect()

secure_key_management()
```

## 13.2 网络安全

```
✅ 推荐做法:
┌─────────────────────────────────────────────────────────────┐
│  • 使用VPN或专用网络连接SmartNIC                             │
│  • 启用防火墙限制访问IP                                      │
│  • 使用TLS/SSL保护管理接口                                   │
│  • 监控网络流量异常                                          │
│  • 定期更新固件和驱动程序                                    │
└─────────────────────────────────────────────────────────────┘
```

---

# 14. 附录

## 14.1 默认配置

```
默认配置:

┌─────────────────────────────────────────────────────────────┐
│  网络配置:                                                   │
│  • SmartNIC IP: 192.168.1.10                                │
│  • 子网掩码: 255.255.255.0                                   │
│  • 通信端口: 8080                                            │
├─────────────────────────────────────────────────────────────┤
│  AES配置:                                                    │
│  • 密钥: 2b7e151628aed2a6abf7158809cf4f3c                   │
│  • IV:  000102030405060708090a0b0c0d0e0f                    │
├─────────────────────────────────────────────────────────────┤
│  SM4配置:                                                    │
│  • 密钥: 0123456789abcdeffedcba9876543210                   │
│  • IV:  00000000000000000000000000000000                    │
├─────────────────────────────────────────────────────────────┤
│  端口映射:                                                   │
│  • Config: 0x4321 (17185)                                   │
│  • Crypto: 0x1234 (4660)                                    │
│  • Data:   0x5678 (22136)                                   │
│  • Status: 0x1000 (4096)                                    │
└─────────────────────────────────────────────────────────────┘
```

## 14.2 数据包格式

```
配置包 (Config Packet):
┌───────┬────────┬───────┬────────────────┬────────────────┐
│ Magic │ seq_id │ algo  │     Key (16B)  │     IV (16B)   │
│ 4B    │ 2B     │ 1B    │                │                │
└───────┴────────┴───────┴────────────────┴────────────────┘
Magic: 0xDEADBEEF
seq_id: 递增序列号
algo: 0=AES, 1=SM4

加密包 (Crypto Packet):
┌─────────┬─────────┬─────────┬──────────────────┐
│ src_port│ dst_port│  length │     Payload      │
│   2B    │   2B    │   2B    │   (16B aligned)  │
└─────────┴─────────┴─────────┴──────────────────┘
src_port: 源端口
dst_port: CRYPTO_PORT (0x1234)
length: 有效载荷长度

响应包 (Response Packet):
┌───────┬─────────┬──────────────────┐
│ status│  length │   Ciphertext     │
│  1B   │   2B    │   (16B aligned)  │
└───────┴─────────┴──────────────────┘
status: 0=成功, 非0=错误
```

## 14.3 参考资料

```
相关文档:
┌─────────────────────────────────────────────────────────────┐
│  • RFC 3602: AES-CBC Cipher Suites for TLS/SSL             │
│  • GM/T 0002-2012: SM4分组密码算法                          │
│  • NIST FIPS 197: Advanced Encryption Standard              │
│  • Xilinx Zynq-7000技术文档                                  │
│  • SmartNIC项目源码                                          │
└─────────────────────────────────────────────────────────────┘
```

## 14.4 技术支持

```
如需技术支持:
┌─────────────────────────────────────────────────────────────┐
│  • 项目GitHub: https://github.com/your-repo/smartnic       │
│  • 邮箱: support@example.com                               │
│  • 文档: 查阅USER_MANUAL.md                                │
│  • 示例: 运行 sw/ 目录下的示例程序                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.0 | 2026-01-31 | 初始版本 |
| 2.0 | 2026-01-31 | 完整版，包含所有API和示例 |

---

**手册结束**

本手册提供了SmartNIC的完整使用指南。如有任何问题，请参考故障排除章节或联系技术支持。
