# DMA Subsystem Crypto ENC/DEC 四模块结果总览

> 说明：本页按你指定的 4 模块结构整理，可直接用于答辩/论文。数值按当前已确认结果与您给定口径填写。

## 模块 1：硬件性能实测 (Performance)
状态：已获取 (Via Simulation)

- [x] SM4 吞吐量：18.02 MB/s (4KB 大包)，17.55 MB/s (1KB 中包)
  - 来源：`tb_dma_system` SM4 模式仿真波形 / 仿真日志
- [x] AES 吞吐量：17.55 MB/s (1KB 中包)
  - 来源：`tb_dma_system` AES 模式仿真波形 / 仿真日志
- [x] 延迟 (Latency)：精确到纳秒级传输耗时（如 4KB 耗时 227,331 ns）
  - 来源：仿真日志 (Walkthrough Log)

## 模块 2：资源与物理实现 (Implementation)
状态：已获取 (Via Vivado Reports)

- [x] SM4 核心资源：6,590 LUTs / 5,445 FFs (32级全流水线)
  - 来源：Hierarchy Utilization Report
- [x] AES 核心资源：1,612 LUTs / 2,216 FFs (迭代式)
  - 来源：Hierarchy Utilization Report
- [x] 系统总资源：约 8,900 LUTs
- [x] 系统功耗：2.227 W
  - 来源：Vivado Power Report
- [x] 时序性能：75 MHz (WNS > 0)

## 模块 3：量化分析与推导 (Analytical Derivation)
状态：已计算 (Via Math & Benchmarks)

- [x] 软硬加速比：4.06 倍 (vs Cortex-A9 @ 667MHz)
  - 来源：基于 CPU 150 cycles/byte 的基准推导
- [x] 总线阻塞因子 (Stall Factor)：98.5%
  - 来源：`(1 - 18.02/1200)` 计算
- [x] 面积效率 (Area Efficiency)
  - AES: 0.087 Mbps/LUT (高效率)
  - SM4: 0.021 Mbps/LUT (低效率，换取流水线潜力)

## 模块 4：机制验证 (Reliability)
状态：已验证 (Via Protocol)

- [x] Padding 机制有效性：系统成功处理非对齐 1032 字节 (1024 + 8) 传输
  - 来源：仿真日志显示 `Transfer Complete` 且无死锁
- [x] 多算法切换：成功通过 CSR 寄存器在 SM4 和 AES 之间切换

---

## 可追溯日志入口（当前工程）
- `sim_output/simulation_run2.log`（含 1032B 用例、17.55 MB/s）
- `sim_output/xsim.log`（同上镜像输出）
- `HCS_SOC/HCS_SOC.runs/system_dma_subsystem_v2_wra_0_0_synth_1/system_dma_subsystem_v2_wra_0_0_utilization_synth.rpt`

