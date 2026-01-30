# Project Pre-Burn: Day 11 - The Infinite Loop: Descriptor Rings & System Closure

> **Date:** 2026-01-30 (Simulated Time)
> **Status:** Simulation Passed (Behavioral)
> **Author:** Future IC Engineer

## 1. 项目概述 (Overview)

Day 11 标志着我们从“单点模块设计”正式跨入“子系统集成”时代。
**核心目标**：构建基于 **描述符环 (Descriptor Ring)** 的自动化搬运机制，将 Day 5 的加密引擎、Day 8 的 PBM 缓存与 DMA 控制器彻底打通。
**战略意义**：
1.  **CPU 卸载 (CPU Offload)**：CPU 仅需更新“尾指针 (Tail Pointer)”，硬件自动从内存抓取任务单，无需 CPU 逐字干预。
2.  **闭环验证 (System Closure)**：实现了 `Fetcher (读指令)` -> `PBM (读数据)` -> `Crypto (算数据)` -> `DMA (写结果)` 的全自动流水线。

## 2. 理论军火库 (Knowledge Base)

### A. 描述符环 (Descriptor Ring)
* **机制**：内存中开辟一块环形区域存放任务结构体（源地址、长度、算法类型）。
* **硬件逻辑**：
    * **SW_TAIL (软件尾指针)**：CPU 告诉硬件“我放了新任务”。
    * **HW_HEAD (硬件头指针)**：硬件告诉 CPU“我处理到了哪里”。
    * **追赶逻辑**：当 `HEAD != TAIL` 时，硬件自动启动 Fetcher。

### B. AXI4 通道拆分 (Channel Splitting)
* 为了提高效率，我们在顶层将 AXI4 Master 接口一分为二：
    * **AR/R 通道**：由 `dma_desc_fetcher` 独占，用于从 DDR 读取任务描述符。
    * **AW/W/B 通道**：由 `dma_master_engine` 独占，用于将加密后的密文写回 DDR。

## 3. 模块定义与架构 (Architecture)

### 顶层集成: `crypto_dma_subsystem.sv`
这是目前的“系统之王”，内部实例化并连接了以下核心：
1.  **CSR**: 配置寄存器与中断状态。
2.  **Fetcher**: 指令取指器（Day 11 新增）。
3.  **PBM**: 数据包缓冲管理。
4.  **Crypto Bridge**: 协议适配层。
5.  **DMA Engine**: 写回引擎。

### 关键修复 (Critical Fixes)
在集成过程中，我们解决了 SystemVerilog 的两大隐形杀手：
* **显式连接 (Explicit Connection)**：弃用 `.*`，手动连接 `m_axi_arsize` 等关键总线信号，解决了 Vivado 无法识别隐式端口的 Elaboration Error。
* **环境隔离 (Nettype Isolation)**：在遗留的 `.v` 文件头部强制添加 `` `default_nettype wire ``，防止了由 `pkg_axi_stream.sv` 引入的严谨模式导致的编译污染。

## 4. 验证与审计 (Verification & Audit)

### 仿真场景 (Testbench Scenario)
* **Step 1**: 配置 Ring Base 和 Ring Size。
* **Step 2**: 触发硬件初始化 (SM4 Key Expansion)，等待 Ready。
* **Step 3**: 向 PBM 注入 32 字节明文数据（**加入 Valid/Ready 握手保护**）。
* **Step 4**: 更新 Tail 指针，触发硬件自动搬运。
* **Step 5**: 监测 DMA Done 信号。

### 调试报告 (Diagnostic Report)
在经历了多次 Timeout 后，通过加入自动诊断逻辑，最终验证通过：
```text
[TB] >>> DMA DONE SIGNAL DETECTED! TEST PASSED! <<<