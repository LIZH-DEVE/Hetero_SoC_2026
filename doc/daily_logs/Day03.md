# Project Hetero_SoC: Day 3 - 总线之王 (AXI4-Full Master)

> **日期：** 2026-01-23 (Beijing Time)
> **状态：** AXI4 主控引擎逻辑闭环 (Logic Verified & Waveform Aligned)

## 1. 项目概述 (Overview)

Day 3 的核心任务是实现具备 **4KB 边界拆包能力** 的 AXI4-Full 写引擎（Master FSM & Burst Logic）。这是安全网卡将加密数据推向物理内存的“开路先锋”，旨在构建无歧义的总线接口 。

## 2. 核心架构设计 (Bus Master Architecture)

### A. 状态机驱动 (FSM Logic)

采用严谨的 6 状态循环控制机，确保数据搬运的节奏与协议完全同步 ：

**IDLE**：监听 CSR 启动脉冲 `i_start` 。


**CALC**：执行核心拆包算法。根据手册要求，当传输跨越 4KB 边界或长度超过 256 拍时自动拆分 。


**AW_HANDSHAKE / W_BURST**：执行双向握手。单次突发长度严格限制在 AXI4 标准的 256 拍以内 。


**B_RESP / DONE**：结账确认并回执。

### B. 关键对齐约束 (Patch)

**地址对齐**：仅支持 64 字节对齐（Cache Line 对齐）。若 `addr[5:0] != 0`，逻辑将自动拦截并触发错误中断 。


**传输模式**：固定使用 `INCR` (2'b01) 模式。这是针对 Packet Buffer 线性搬运的最佳实践，规避了 WRAP 模式可能带来的内存覆盖风险 。


## 3. 验证与工程闭环 (Verification)

### A. 仿真审计 (Pixel-Level Simulation)

**4KB 边界跨越验证**：在仿真中通过起始地址 `0x2000_0000` 与 `0x800` 长度的组合，成功观察到地址在 `0x2000_0400` 处的精准切分。
**波形一致性修正**：通过 `reset_simulation` 解决了 Vivado 仿真器快照滞后问题，确保波形中的 `awburst` 正确显示为 `1` (INCR)。
**单 ID 策略**：保持单 ID 传输，确保数据在总线上的严格保序 。



### B. 技术痛点解决

**仿真器兼容性**：针对 XSim 不支持非积分枚举类型的报错，将状态机定义修正为 `typedef enum int` 结构。
**读通道归零 (Tie-off)**：在 Testbench 与 RTL 中对暂未使用的 AR/R 通道执行归零处理，消除了仿真中的 X 态干扰。

## 4. 核心认知升级 (Key Learnings)

**接口立法**：硬件设计不仅是逻辑，更是对协议边界的死守。4KB 限制是 AXI 系统的“宪法”，决不可违背 。

**仿真陷阱**：代码正确不代表波形正确，必须建立“物理清理-重解析-再仿真”的闭环思维。

## 5. 进度跟踪 (Roadmap)

**已完成**：AXI4-Full Master 基础状态机、4K 边界拆分算法、对齐检查逻辑 。


**进行中**：Day 4 物理觉醒。准备加入随机延迟模拟真实 DDR 行为，验证背压鲁棒性 。



---

**下一步：** 按照手册 Phase 1 规划，准备进行 Full-Link 仿真，并开始 Zynq 平台的物理映射准备 。