# Project Hetero_SoC: Day 2 - The Control Plane & System Integration

> **日期：** 2026-01-23 (Beijing Time)
> **状态：** 控制层逻辑闭环与子系统验收完成 (Phase 1 Milestone)

## 1. 项目概述 (Overview)

Day 2 的核心战略是从“定义接口”进阶到“定义规则与大脑”。我们构建了全局参数包（Package）作为系统的“宪法”，并实现了 CSR（控制状态寄存器）作为软硬交互的“大脑”。
最终，通过 `dma_subsystem` 将 CSR 与 DMA 引擎物理整合，实现了由模拟 CPU 指令驱动硬件行为的完整链路。

## 2. 核心架构组件 (Core Architecture)

### A. SystemVerilog Package (`pkg_axi_stream`)

* **定位**：工程的“法律基座”与“真理之源（Single Source of Truth）”。
* **内容**：
* 协议常数：`ETH_HEADER_LEN`, `IP_HEADER_MIN_LEN`。
* 硬件约束：`ALIGN_MASK_64B` (6'h3F) 用于强制 Cache Line 对齐。
* 错误码：定义了 `ERR_BAD_ALIGN`, `ERR_ACL_DROP` 等标准异常。



### B. CSR Design (`axil_csr`)

* **定位**：AXI-Lite 从机，负责将 CPU 的软件指令转化为硬件电平信号。
* **映射**：
* `0x00`: Control Reg (Start bit).
* `0x04`: Status Reg (Done/Error bits).
* `0x08`: Base Address (DMA Source).


* **特性**：实现了读写分离与状态锁存，确保 CPU 能够实时监控硬件健康度。

### C. DMA Subsystem (`dma_subsystem`)

* **定位**：Top-Level Wrapper。
* **作用**：物理连接 `axil_csr` (Control) 与 `dma_master_engine` (Data)，形成独立的硬件子系统，隔离了 AXI-Lite 与 AXI4-Full 时钟域与逻辑。

## 3. 验证与验收 (Verification & Audit)

本次验证采用了 **BFM (Bus Functional Model)** 方法论，而非传统的信号拉线。

* **测试平台**：`tb_dma_subsystem.sv`
* **关键场景 (Task 1.3)**：非对齐地址拦截测试。
* **激励**：模拟 CPU 向 `0x08` 写入 `0x10000007` (非法地址)。
* **响应**：硬件瞬间拉高 `o_error`，且 AXI4 总线保持静默（`AWVALID=0`）。
* **结论**：验证了硬件具备“自我防御机制”，能有效拦截软件侧的非法指令。



## 4. 工程挑战与解决方案 (Challenges & Solutions)

* **编译顺序 (Compile Order)**：
* *问题*：Vivado 报错 `pkg_axi_stream is not declared`。
* *解决*：手动调整编译顺序，将 Package 文件置于所有源文件之首。


* **仿真顶层切换 (Top-Level Switching)**：
* *问题*：仿真器一直运行旧的 DMA 单元测试，导致无法看到 CSR 交互。
* *解决*：通过 `Set as Top` 强制切换至系统级 TB，并重置仿真数据库 (`reset_simulation`)。



## 5. 核心认知升级 (Key Learnings)

* **软硬协同 (Soft-Hard Synergy)**：硬件不再是孤立运转的电路，而是由软件（寄存器）定义的执行机构。
* **防御性编程 (Defensive Hardware)**：永远不要信任软件传入的参数。硬件必须在最底层实施“零信任”检查（如对齐审计），以防止系统崩溃。
* **可追溯性 (Traceability)**：代码中引入 `[Source: XX]` 注解，确保每一行 RTL 逻辑都能追溯到执行手册的具体条款。