# Project Pre-Burn: Day 5 - The Dual-Engine Core (双引擎之心)

> **Date:** 2026-01-26
> **Status:** Simulation Passed / Architecture Frozen
> **Author:** Future IC Engineer

## 1. 项目概述 (Overview)

本项目是《预燃行动 (Project Pre-Burn)》的第五天里程碑。
**核心目标**：打破单一算法限制，在 Day 4 AES 的基础上，成功集成国产商密 **SM4 算法**，并构建支持动态切换的 **双引擎架构 (Dual-Engine Architecture)**。
**战略意义**：
1.  **国标支持 (Compliance)**：引入 GM/T 0002-2012 标准，具备了处理国产敏感数据的能力。
2.  **架构升级 (System Integration)**：从“单一模块”进化为“加解密子系统”，通过 `algo_sel` 信号实现了硬件级的算法热切换。
3.  **工程化思维 (Engineering)**：实践了“集成成熟开源 IP (Golden Reference)”的开发模式，而非盲目造轮子。

## 2. 开发环境 (Environment)

* **IDE**: Xilinx Vivado 2024.1
* **Language**: SystemVerilog (Top) / Verilog 2001 (Core)
* **Simulator**: Vivado XSim
* **External IP**: `gongxunwu/sm4-verilog` (Standard SM4 Implementation)

## 3. 理论军火库 (Knowledge Base)

在 Day 5 中，我们解决了以下核心工程挑战：

### A. 算法多路复用 (Algorithm Muxing)
* **痛点**：如何在不重新综合的情况下，让一套硬件支持两种完全不同的算法？
* **解法**：在 `crypto_engine` 层构建 **Mux (多路选择器)**。
    * **输入分流**：根据 `algo_sel` 信号，将 `start` 脉冲和密钥/数据路由至指定的 Core。
    * **输出汇流**：`assign dout = (algo_sel) ? sm4_dout : aes_dout;`，确保总线只能看到当前激活算法的结果。

### B. 开源 IP 集成 (IP Integration)
* **挑战**：开源代码 (`sm4_top`) 的接口定义（如 `user_key_in`）与本项目标准接口（`key`）不一致。
* **对策**：编写 **Wrapper (桥接层)**。在 `crypto_engine.sv` 中实例化开源模块，并手动映射端口，解决了 "Module not found" 和 "Port mismatch" 问题。

## 4. 模块定义与架构 (Architecture & Specs)

### 核心模块: `crypto_engine.sv`
这是 Day 5 的核心战场，它向下管理两个核，向上对 DMA/CPU 提供统一接口。

| 端口名 | 方向 | 位宽 | 描述 | 逻辑行为 |
| :--- | :--- | :--- | :--- | :--- |
| `clk/rst_n` | input | 1 | 全局时钟复位 | System Control |
| `algo_sel` | input | 1 | **算法选择** | **0: AES-128, 1: SM4** |
| `start` | input | 1 | 启动信号 | 握手开始 |
| `key` | input | 128 | 密钥 | 通用密钥输入 |
| `din` | input | 128 | 明文输入 | 通用数据输入 |
| `dout` | output| 128 | 密文输出 | Mux 后的结果 |
| `done` | output| 1 | 完成信号 | 握手结束 |

### 层级结构 (Hierarchy)
```text
dma_subsystem
└── crypto_core
    └── crypto_engine (双引擎调度)
        ├── u_aes_core (Day 4 成果)
        └── u_sm4_opensource (Day 5 集成, gongxunwu版)