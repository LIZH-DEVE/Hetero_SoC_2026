# Project Pre-Burn: Day 09 - The "Brain" (RX Parser & Protocol Security)

> **Date:** 2026-01-29
> **Status:** Behavioral Simulation Passed (Protocol Alignment & Rollback Verified)
> **Module:** RX Parser (Protocol Aware Engine)

## 1. 项目概述 (Overview)

本项目是《预燃行动 (Project Pre-Burn)》的第九天里程碑。
**核心目标**：赋予网卡“理解力”，从单纯的数据搬运升级为**协议感知 (Protocol Awareness)**。
**战略意义**：
1.  **深度包检测 (DPI)**：硬件级解析 Ethernet -> IP -> UDP 头部，提取关键元数据（如 Payload Length）。
2.  **安检机制 (Security Check)**：实现 **Task 8.2** 的长度校验逻辑，防止畸形包进入内存。
3.  **原子回滚闭环 (Rollback Loop)**：Parser 发现错误后，直接触发 Day 8 PBM 的指针回弹，实现零软件干预的坏包丢弃。

## 2. 开发环境 (Environment)

* **IDE**: Xilinx Vivado 2024.1
* **Simulation**: Vivado Simulator (XSim)
* **Language**: SystemVerilog (FSM + Datapath)

## 3. 理论军火库 (Knowledge Base)

在 Day 9 中，我们攻克了硬件解析最棘手的两个问题：

### A. 绝对坐标系 (Absolute Counter)
* **痛点**：依赖状态机跳转来重置计数器容易产生 1-2 拍的“累积误差” (Off-by-One Error)，导致抓错协议字段。
* **解法**：引入 `global_word_cnt`。无论状态机如何跳变，数据流的物理位置是绝对的。
    * **Word 2** = Eth Type
    * **Word 3** = IP Total Length
    * **Word 9** = UDP Length
* **效果**：实现了零误差的精准抓取。

### B. 硬件安检门 (Hardware Gatekeeper)
* **逻辑**：$$\text{IP\_Total\_Len} \stackrel{?}{=} \text{UDP\_Len} + 20 \text{ Bytes (IP Header)}$$
* **动作**：
    * **Pass**: 状态机进入 `COMMIT`，写入 Meta FIFO。
    * **Fail**: 状态机进入 `ROLLBACK`，拉高 `o_pbm_werror`，PBM 丢弃当前包。

## 4. 模块定义与架构更新 (Specs & Architecture)

### 核心模块: `rx_parser.sv` (V4 Stable)
集成了 FSM（状态控制）与 Datapath（数据提取），负责将 AXI-Stream 数据流拆解为 Payload（存 PBM）和 Meta（存 FIFO）。

### 顶层架构更新: `dma_subsystem.sv`
链路升级为：`MAC` -> **`RX Parser`** -> `PBM` -> `DMA` -> `AXI`。

| 信号名 | 方向 | 描述 | Day 9 状态 |
| :--- | :--- | :--- | :--- |
| `rx_axis_*` | input | 来自 MAC 的原始数据流 | **Connected** |
| `o_pbm_werror`| output| 触发 PBM 回滚的关键信号 | **Active** |
| `o_meta_valid`| output| 告知系统“收到一个好包” | **Active** |
| `global_word_cnt` | internal | 全局字计数器 | **New** |

## 5. 验证与审计 (Verification & Audit)

### 仿真测试: `tb_dma_subsystem.sv`
本次验证针对协议解析的准确性和错误拦截能力进行了严苛测试。

#### 场景 1：精准解析 (Alignment Check)
* **激励**：发送标准 UDP 包。
* **波形审计** (基于 `image_458576.png`)：
    * `global_word_cnt` 从 0 稳定递增。
    * 在 count=3 时，`ip_total_len` 精准捕获 **`0030`** (48字节)。
    * 在 count=9 时，`udp_len` 精准捕获 **`0064`** (100字节，用于测试)。
* **结论**：**时序对齐逻辑完美工作，消除了之前的错位 Bug。**

#### 场景 2：坏包拦截 (Security Rollback)
* **激励**：注入长度欺诈包 (IP=48, UDP=100)。
    * 校验逻辑：$100 + 20 \neq 48$。
* **波形结果**：
    * 包结束瞬间，`state` 从 `CHECKSUM` 跳变为 **`ROLLBACK (7)`**。
    * `o_pbm_werror` 产生脉冲。
    * `o_meta_valid` **保持为 0** (拒绝提交)。
* **结论**：**硬件成功识别并拦截了非法数据包。**

## 6. 核心认知升级 (Key Learnings)

1.  **时序的相对与绝对**：在流式处理中，依赖相对增量（状态机内部计数）不如依赖绝对坐标（全局计数器）可靠。
2.  **大端序的陷阱**：网络协议是 Big-Endian，而 x86/ARM 往往是 Little-Endian。在 Verilog 中提取 `{udp_len, padding}` 时，必须精准选择 `[31:16]` 还是 `[15:0]`。
3.  **验证的价值**：看到波形中那个红色的 `ROLLBACK` 状态出现时，才意味着设计真正有了灵魂——它学会了拒绝。

## 7. 顾问评价 (Advisor's Note)

> "Day 9 的成功在于你不仅修好了 Bug，更理解了 Bug 的本质。
> 你从最初的‘盲目抓取’进化到了现在的‘绝对坐标系’，这是硬件思维成熟的标志。
> 现在的 RX Parser 像一个严苛的签证官，只有合法的数据才能通过。
> Next Stop: Day 10，我们将把这些不可见的 `0030` 和 `0064`，变成肉眼可见的光。"

---
*Project Pre-Burn: From Silicon to Intelligence*