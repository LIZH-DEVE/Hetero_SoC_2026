# Project Pre-Burn: Day 07 - The Dual-Core Dispatcher

> **Date:** 2026-01-28
> **Status:** Simulation Passed (RTL Verified) / No Board Required
> **Module:** `crypto_engine.sv` (Dispatcher Architecture)

## 1. 项目概述 (Overview)

本项目是《21天硬件安全加速网卡》的第七天里程碑。
**核心目标**：打破“单一算法”的限制，构建基于 **Dispatcher（分发器）** 的双核并联架构。
**战略意义**：
1.  **软件定义硬件 (SDH)**：通过寄存器配置 (`algo_sel`)，软件可以毫秒级无缝切换底层加密算法 (AES-128-CBC <-> SM4-CBC)。
2.  **资源隔离 (Isolation)**：实现了物理级的门控逻辑，未被选中的算法核处于静默状态，降低动态功耗。
3.  **统一接口 (Unified I/O)**：对上层模块（DMA/FIFO）屏蔽了底层算法差异，提供统一的 `start/done/busy` 握手协议。

## 2. 开发环境 (Environment)

* **IDE**: Xilinx Vivado 2024.1
* **Language**: SystemVerilog (RTL + Automated Testbench)
* **Simulation**: Vivado XSim (Behavioral)
* **Key Files**:
    * `rtl/core/crypto/crypto_engine.sv`: 分发器与多路复用核心
    * `tb/tb_crypto_engine.sv`: 自动化双核验证平台

## 3. 架构设计 (Architecture)

在 Day 07 中，我们将 `crypto_engine` 升级为“智能路由节点”：

### A. 硬件分发 (The Dispatcher)
* **逻辑**：根据 `algo_sel` 信号，将输入的 `start` 脉冲路由至指定引擎。
* **实现**：
    ```systemverilog
    assign aes_start = (algo_sel == 0) ? start : 1'b0;
    assign sm4_start = (algo_sel == 1) ? start : 1'b0;
    ```

### B. 结果汇聚 (The Arbiter/Mux)
* **逻辑**：无论哪个核在工作，其输出数据 `dout` 和状态信号 `done` 最终都汇聚到同一根总线上，供下游 PBM 或 FIFO 读取。
* **实现**：
    ```systemverilog
    assign dout = (algo_sel == 1) ? w_sm4_dout : w_aes_dout;
    assign done = (algo_sel == 1) ? sm4_done   : aes_done;
    ```

### C. 统一反压 (Backpressure)
* **机制**：引入 `busy` 寄存器。收到 `start` 拉高，收到 `done` 拉低。上层模块无需关心具体是哪个核在忙，只需检测 `busy` 即可决定是否暂停发数。

## 4. 验证与审计 (Verification & Audit)

由于暂无开发板，本次采用 **"Deep Simulation" (深度仿真)** 策略，通过 Tcl Console 抓取日志进行验收。

### 自动化测试平台 (`tb_crypto_engine.sv`)
构建了模拟 CPU 行为的 Testbench，自动执行以下序列：
1.  复位系统。
2.  配置 `algo_sel = 0` (AES)，发送标准向量，等待 Done。
3.  配置 `algo_sel = 1` (SM4)，发送相同向量，等待 Done。
4.  比对两次输出是否不同。

### 仿真证据 (Tcl Console Log) - *PASSED*
```text
[DAY 07] 开始双核分发器仿真验证...
[TIME: 120000] -> 切换至 AES 模式
[TIME: 655000] -> [成功] AES 输出: 92e63835ae00d04e6602c313b09e7dc8
...
[TIME: 755000] -> 切换至 SM4 模式
[TIME: 1075000] -> [成功] SM4 输出: 897e115d90edafcad340622625d7e570
[DAY 07] 所有分发测试已完成！