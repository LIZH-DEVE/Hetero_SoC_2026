# 项目阶段综合状态审查报告

日期：
- `2026-03-31`

审查对象：
- 需求源文档：`D:\FPGAhanjia\大一寒假\21天硬件安全加速网卡 (1).docx`
- 当前工程：`Hetero_SoC_2026`
- 当前验收镜像：`HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror/BOOT.BIN`

## 1. 审查口径

本次审查采用双基线，避免把“当前阶段已完成”和“原始全量蓝图未完成”混为一谈。

基线 A：当前批准执行范围
- 以当前实际推进的 `AX7020 UDP Crypto Gateway / Phase C shadow_mirror / Stage 2 SG proof / full merge-back` 为准
- 这是当前项目阶段的真实交付范围

基线 B：原始《21天硬件安全加速网卡》全量蓝图
- 以 `.docx` 中完整 21 天路线图为准
- 包含 ACL、防火墙、Zero-Copy、真实 DNA_PORT、自毁、ILA、Pblock、Timing/Power 报告等更大范围目标

## 2. 总体进度结论

### 基线 A：当前批准执行范围

- 总体进度：`95%`
- 结论：当前阶段已达到 `board-proven + performance-proven`
- 当前阶段核心目标已经完成，剩余主要是工程收尾和少量未纳入本阶段的硬化项

### 基线 B：原始 21 天全量蓝图

- 总体进度：`63%`
- 结论：原始蓝图中的核心网络/加密/控制/性能主干已经建立，但高级安全模块、硬件防火墙、Zero-Copy、完整物理收敛证据链仍未全部完成

## 3. 里程碑状态

| 里程碑 | 状态 | 证据 | 说明 |
|---|---|---|---|
| M1: Phase C 功能镜像可启动并起网 | 已完成 | `board_uart_boot_115200_20260331_205148.txt` | 板上正常启动，IP/网口/控制面正常 |
| M2: Live AES/SM4 + Shadow Mirror 功能闭环 | 已完成 | `readme.txt`、历史板测 UART | `LIVE_*`、`SHADOW_*` 路径已 board-proven |
| M3: 控制面 4662 会话/控制链路 | 已完成 | `LIVE_CTRL PASS` | `HELLO/SET_KEY/STATUS` 路径可用 |
| M4: Stage 2 SG batch DMA proof | 已完成 | `hybrid_perf_proof_20260331_181431` | AES `4.877192x`，SM4 `2.847728x` |
| M5: Stage 2 merge-back 到 full shadow_mirror | 已完成 | `shadow_mirror_20260331_205148` | full image 板上性能过线 |
| M6: full design 在 xc7z020 上重新实现通过 | 已完成 | `udp_gateway_shadow_mirror_wrapper_utilization_placed.rpt`、bitstream 重建日志 | 硬件瘦身后实现通过 |
| M7: 当前阶段性能验收 | 已完成 | `board_bench_summary.md` | AES `2.724785x`，SM4 `2.056073x` |
| M8: 当前阶段最终文档收口 | 已完成 | `THESIS_DATA_TABLE.md`、final handoff 文档 | 口径已同步 |
| M9: 原始蓝图高级安全模块全量完成 | 未完成 | `.docx` 需求 vs 当前实现 | 真实 DNA、自毁全场景、ACL 等仍未闭环 |

## 4. 已完成任务清单

以下项目可按“已完成”认定。

### 4.1 当前阶段核心功能

- `DMA + ring + 硬件搬运`：已完成
- `稳定多块 AES/SM4`：已完成
- `性能测试与加速比`：已完成
- `Phase C shadow_mirror combined image`：已完成
- `Stage 2 SG proof`：已完成
- `descriptor-driven DMA batch BENCH merge-back`：已完成
- `硬件瘦身后 full image 重新实现`：已完成

### 4.2 控制面与安全收口

- 控制端口 `4662`：已完成
- `HELLO / SET_KEY / STATUS / LOCK / UNLOCK` 基本控制面：已完成
- 控制面 `session_id + seq_id` 防重放：已完成
- 轻量自毁 `锁死 + 清零 key`：已完成
- 未授权/非法长度/错误路径的计数与拒绝：已完成
- fail-open shadow submit 策略：已完成

### 4.3 板级验证与交付

- 实板功能验证：已完成
- 实板性能验证：已完成
- release 镜像与哈希固定：已完成
- final handoff / thesis 数据表 / release readme：已完成

## 5. 未完成或待处理项目项

以下项目未完成，或者未纳入当前阶段交付范围。

| 项目项 | 当前状态 | 剩余工作 | 依赖关系 | 预计完成时间 |
|---|---|---|---|---|
| 真实 `DNA_PORT` 绑定 | 部分完成 | 以真实 FPGA DNA 替换当前 `board_id/mock_dna` 占位逻辑；补齐绑定失败锁死回归 | 需修改 PL/PS 绑定接口并重新板测 | `2-3` 个工作日 |
| 复杂 tamper / JTAG 自毁 | 未完成 | 设计 tamper 触发源、清 key 策略、恢复策略；补硬件/软件联动 | 依赖真实安全威胁模型和资源余量 | `5-10` 个工作日 |
| ACL 防火墙（CRC16/4K/抗碰撞） | 未完成 | 完成 5-tuple 提取、ACL 表结构、碰撞策略和误杀回归 | 依赖 parser、BRAM 预算、资源再评估 | `4-6` 个工作日 |
| Zero-Copy FastPath | 未完成 | 建立 PBM 直通 TX、Checksum 透传、FastPath 规则与延迟回归 | 依赖 TX builder、PBM、资源余量 | `3-5` 个工作日 |
| AES-CBC / SHA-256 原始蓝图路径 | 未完成 | 当前实现是 AES/SM4 网关，不是原始文档里的 AES-CBC/SHA-256 全量版 | 依赖重新定义算法范围和演示目标 | `4-7` 个工作日 |
| Outstanding depth 4 / 极限性能压榨 | 未完成 | AXI Outstanding、burst 策略进一步优化，重新测吞吐上限 | 依赖当前数据面冻结后继续优化 | `2-4` 个工作日 |
| ILA 最终版插桩 | 未完成 | 插入并导出 `drop_reason/fastpath_active/axi_error` 的演示级 ILA | 依赖当前资源余量；有再次挤爆器件风险 | `1-2` 个工作日 |
| Timing / Power / Pblock / CDC 文档化证据 | 部分完成 | 输出 `report_power`、`report_timing_summary`、Pblock、CDC 约束证据 | 依赖当前实现冻结后集中导出 | `1-2` 个工作日 |
| 原始 21 天蓝图中的 Linux 驱动一致性策略 | 未开始 | 将当前裸机/板测路径映射到 Linux `dma_alloc_coherent` 等驱动体系 | 依赖操作系统层切换，不属于当前裸机阶段 | `5-8` 个工作日 |

## 6. 可交付成果状态

| 可交付成果 | 状态 | 路径 |
|---|---|---|
| 最终 acceptance 镜像 | 已完成 | `HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror/BOOT.BIN` |
| 最终 acceptance benchmark JSON | 已完成 | `doc/reports/board_benchmarks/shadow_mirror_20260331_205148/board_bench_report.json` |
| 最终 acceptance benchmark Markdown | 已完成 | `doc/reports/board_benchmarks/shadow_mirror_20260331_205148/board_bench_summary.md` |
| Stage 2 proof benchmark | 已完成 | `doc/reports/board_benchmarks/hybrid_perf_proof_20260331_181431` |
| Thesis 数据表 | 已完成 | `doc/reports/THESIS_DATA_TABLE.md` |
| 最终 handoff | 已完成 | `doc/reports/2026-03-31_phasec_shadow_mirror_final_handoff.md` |
| 最终 release 说明 | 已完成 | `HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror/readme.txt` |
| Power / Timing / Pblock / CDC 证据包 | 未完成 | 待生成 |

## 7. 质量标准与验收准则核对

### 已满足

- `avg_speedup >= 1.0x` per algorithm：满足
  - AES `2.724785x`
  - SM4 `2.056073x`
- `full shadow_mirror` 板级功能可启动、可起网、可响应控制面：满足
- Stage 2 SG batch proof 单次 doorbell、批量描述符路径：满足
- `xc7z020` 上 full design 可实现：满足
- `wrong-port / unaligned / fail-open / sticky halt` 契约：满足

### 未完全满足或未进入当前验收

- 真实 DNA 绑定：未满足
- 复杂 tamper/JTAG 自毁：未满足
- ACL 防火墙：未满足
- Zero-Copy FastPath：未满足
- ILA / Power / Timing / Pblock / CDC 完整答辩证据链：未完全满足
- 原始蓝图中的 AES-CBC / SHA-256 全量算法范围：未满足

## 8. 潜在风险与延误因素

### R1. 资源余量仍然偏紧

- 当前 Slice 使用率 `93.38%`
- 结论：虽然已经能实现，但再加 ACL、ILA、FastPath、真实 DNA 绑定时，极可能再次逼近布局/布线瓶颈
- 风险等级：高

### R2. 当前安全绑定仍是占位版

- 当前 `binding_id` 机制已存在，但不是 `DNA_PORT` 的真实不可克隆绑定
- 风险等级：中高

### R3. 演示级证据链尚未完全物理化

- 性能和功能已经板证成立，但 Power / Timing / Pblock / CDC / ILA 的正式证据包尚未整理齐
- 风险等级：中

### R4. 原始 21 天蓝图与当前收敛路线存在范围偏移

- 原始文档含 ACL、Zero-Copy、AES-CBC/SHA-256 等更大范围目标
- 当前阶段实际成功交付的是 `AES/SM4 + 控制面 + shadow_mirror + DMA batch merge-back`
- 如果对外不澄清范围，会出现“系统已完工”的误解
- 风险等级：中

## 9. 建议的项目状态表述

建议对外使用以下结论：

- 当前批准执行范围内，项目已达到 `board-proven + performance-proven`
- `shadow_mirror` 最终 acceptance 镜像已在 `xc7z020` 上完成 full merge-back，并通过性能门槛
- 原始 21 天全量蓝图尚未全部完成，剩余重点是：
  - 真实 DNA 绑定
  - ACL 防火墙
  - Zero-Copy FastPath
  - Power/Timing/ILA/Pblock/CDC 证据收口

## 10. 最终判断

### 当前项目阶段

- 结论：`已成功完成`
- 完成度：`95%`

### 原始全量蓝图

- 结论：`主干完成，但未全部闭环`
- 完成度：`63%`

工程上最重要的事实是：
- 当前阶段不是“demo 能跑”
- 而是已经在目标器件上形成了可实现、可启动、可测得正向加速比、可交付的最终镜像
