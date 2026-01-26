# Project Hetero_SoC: Day 1 - The Communication Protocol

> **日期：** 2026-01-21 (Beijing Time)
> **状态：** 协议层构建完成 (100% Logic Synchronized)

## 1. 项目概述 (Overview)
Day 1 的核心任务是定义并封装工业级总线接口（AXI4-Stream & AXI4-Lite），实现控制流与数据流的物理分离。
架构意义：通过 SystemVerilog 的 `interface` 特性消除散乱导线，实现高内聚设计。

## 2. 协议军火库 (AXI4 Protocol Base)
### A. AXI4-Stream (数据高速公路)
- 用于加密网关等高吞吐量数据传输。
- 核心信号：`tdata` (载荷), `tvalid/tready` (双向握手), `tlast` (边界)。

### B. AXI4-Lite (控制指挥中心)
- 用于 CPU 对外设寄存器的配置。
- 核心优势：去除了突发传输（Burst），大幅节省 FPGA 资源。

## 3. 关键语法特性：modport
在接口中使用了 `modport` 关键字，在硬件层面限定信号方向：
- **Master Side**: `output tdata, tvalid, input tready`
- **Slave Side**: `input tdata, tvalid, output tready`
**价值**：在编译阶段阻断错误接线逻辑，提升安全性。

## 4. 验证与工程闭环
- **静态审计**：为了解决 Vivado 报错，构建了 `async_fifo` 骨架作为临时顶层，激活了 RTL Analysis。
- **Git 工作流**：通过 `branch -M main` 修正命名冲突，完成 `git push -u origin main` 同步。

## 5. 核心认知升级 (Key Learnings)
- **接口即协议**：硬件设计不仅是逻辑门，更是设计数据流动的节奏。
- **解耦思想**：地址与数据通道分离是高性能流水线的物理基础。