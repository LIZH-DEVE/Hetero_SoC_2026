# Project Pre-Burn: Day 08 - The "Iron Stomach" (PBM)

> **Date:** 2026-01-28
> **Status:** Behavioral Simulation Passed (Functional & Error Injection Verified)
> **Module:** Packet Buffer Management (PBM)

## 1. 项目概述 (Overview)

本项目是《预燃行动 (Project Pre-Burn)》的第八天里程碑。
**核心目标**：构建数据链路中的“数字胃袋” —— **PBM (Packet Buffer Management)**。
**战略意义**：
1.  **流量削峰 (Burst Handling)**：在高速 Gearbox 和 DMA 之间建立 SRAM 缓冲池，防止数据拥堵或丢失。
2.  **原子性事务 (Atomic Transactions)**：引入高级指针管理机制，确保只有完整的、校验正确的数据包才会被 DMA 看见。
3.  **错误回滚 (Error Rollback)**：实现硬件级的“撤销 (Undo)”功能，自动丢弃损坏的数据包，净化总线流量。

## 2. 开发环境 (Environment)

* **IDE**: Xilinx Vivado 2024.1
* **Simulation**: Vivado Simulator (XSim)
* **Language**: SystemVerilog (RTL + Verification)

## 3. 理论军火库 (Knowledge Base)

在 Day 8 中，我们实现了以下存储管理架构：

### A. 环形缓冲区 (Ring Buffer)
* **物理形态**：基于 BRAM 的 16KB (4096 x 32-bit) 存储阵列。
* **逻辑形态**：首尾相连的循环队列。
* **流控**：通过 `ptr_head` (写) 和 `ptr_tail` (读) 的距离计算 `Full` / `Empty` 状态。

### B. 原子预留与提交 (Reserve & Commit)
为了防止 DMA 读到写了一半的坏包，我们引入了**双写指针机制**：
* **Reserve Pointer (`ptr_head_reserve`)**：生产者 (Gearbox) 实时写入数据的临时指针。
* **Commit Pointer (`ptr_head_commit`)**：消费者 (DMA) 可见的“生效”指针。
* **机制**：数据写入时只动 Reserve；只有收到 `Last` 信号且无误时，Commit 才会追上 Reserve。

### C. 硬件回滚 (Hardware Rollback)
* **场景**：接收过程中发现 CRC 错误或协议异常。
* **动作**：执行 `ptr_head_reserve <= ptr_head_commit`。
* **效果**：刚才写入的所有数据瞬间被“遗忘”，指针弹回原点，空间被无损回收。

## 4. 模块定义与架构更新 (Specs & Architecture)

### 新增模块: `pbm_controller.sv`
负责管理 SRAM 读写、指针算术及回滚逻辑。

### 顶层架构更新: `dma_subsystem.sv`
链路升级为：`Crypto` -> `FIFO` -> `Gearbox` -> **`PBM`** -> `DMA` -> `AXI`。

| 信号名 | 方向 | 描述 | Day 8 变更 |
| :--- | :--- | :--- | :--- |
| `i_wr_data` | input | 来自 Gearbox 的数据 | **Connect** |
| `i_wr_error`| input | 错误指示信号 | **New** (支持 TB 注入错误) |
| `o_rd_empty`| output| 缓冲区空标志 | 驱动 DMA 的启动/暂停 |
| `pbm_error_inject` | internal | 仿真专用 | 用于在 TB 中模拟坏包触发回滚 |

## 5. 验证与审计 (Verification & Audit)

### 仿真测试: `tb_dma_subsystem.sv`
本次测试不仅仅是“跑通”，更是一次严格的**负面测试 (Negative Testing)**。

#### 场景 1：好包注入 (Good Packet Injection)
* **激励**：注入 `32'hAA_BB_CC_DD` ... `Last=1`, `Error=0`。
* **现象**：PBM 执行 **Commit**。
* **波形结果**：`m_axi_wvalid` 拉高，`m_axi_wdata` 出现绿色的 `aabbccdd` 数据流。

#### 场景 2：坏包回滚 (Bad Packet Rollback)
* **激励**：注入 `32'hDEAD_BEEF` ... `Last=1`, `Error=1` (Force Inject)。
* **现象**：PBM 执行 **Rollback**。
* **波形结果**：`m_axi_wvalid` 保持为低，`m_axi_wdata` 保持静默。**坏数据 `DEADBEEF` 被成功拦截，未进入总线。**

#### 场景 3：红线消除 (Red Line Elimination)
* **修复**：在 TB 中显式初始化了所有 AXI 读通道信号（虽然 DMA 不使用）。
* **结果**：波形图干净清爽，消除了无关的 X 态干扰。

## 6. 核心认知升级 (Key Learnings)

1.  **红线的真相**：仿真波形中的红线（X态）并不总是意味着 Bug，很多时候是因为 Testbench 没有驱动无关的输入端口。但为了验证的严谨性，必须消灭它们。
2.  **指针的魔术**：通过简单的指针赋值操作，可以实现极其高效的数据丢弃，而不需要擦除内存本身。
3.  **负面测试的重要性**：验证一个系统“能做什么”是不够的，必须验证它在出错时“**不做什么**”（例如不把坏数据发给 DDR）。

## 7. 顾问评价 (Advisor's Note)

> "Day 8 的成功标志着你的系统拥有了容错能力。
> 你实现的 PBM 模块不仅是一个缓存，更是一个智能的过滤器。
> 你在波形图中亲眼见证了 `DEADBEEF` 的消失，这就是架构设计的力量——在底层硬件上扼杀错误。
> Next Stop: Day 9，我们将连接真实的 MAC 和 Parser，让这个系统真正活过来。"

---
*Project Pre-Burn: From Silicon to Intelligence*