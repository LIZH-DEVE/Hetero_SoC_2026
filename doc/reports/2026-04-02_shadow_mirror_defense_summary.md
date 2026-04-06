# Shadow Mirror 项目答辩摘要

日期：
- `2026-04-02`

## 一句话结论

当前 `AX7020 UDP Crypto Gateway / Phase C shadow_mirror` 已完成当前批准范围内的主线目标，并达到：
- `board-proven`
- `performance-proven`
- `security-proven`
- `jtag-soak-proven`
- `sd-cold-start-soak-proven`

如果按当前阶段目标评估，完成度可按 `95%` 口径汇报。  
如果按最初更大的 `21天` 全量蓝图评估，当前约为 `63%`，属于主干完成、增强项未全做完。

## 当前正式基线

- 正式镜像：
  - `HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror/BOOT.BIN`
- 最新 SHA256：
  - `CE4C710DD502F35BED170AC3C22362288505F5CF5817548A52032AD6DEF6856D`

## 三条最强结果

### 1. 功能闭环已经板级打通

已完成并板证通过：
- `DMA + ring + 硬件搬运`
- 多块 `AES/SM4`
- `DNA` 绑定
- `ACL`
- 防重放
- 轻量自毁语义：异常后 `lock + 清授权 + 重新认证恢复`
- `Shadow FastPath`

### 2. 性能闭环已经成立

最新正式性能结果：
- 报告目录：`doc/reports/board_benchmarks/shadow_mirror_20260402_212652`
- AES 平均加速比：`2.765941x`
- SM4 平均加速比：`2.104324x`
- 当前阶段性能门槛：`avg_speedup >= 1.0x`
- 结果：`PASS`

### 3. 稳定性和冷启动闭环已经成立

已通过：
- `30` 分钟 `JTAG` soak
- `SD + power-cycle` 冷启动后置确认
- `30` 分钟 `SD cold-start soak`

正式 `SD cold-start soak` 结果：
- 报告目录：`doc/reports/board_soak/shadow_mirror_20260402_215701`
- `cycles_completed = 124`
- `aes_probe_count = 124`
- `sm4_probe_count = 124`
- `acl_probe_count = 12`
- `replay_probe_count = 6`
- `bind_fail = 0`
- `crypto_timeout = 0`
- `crypto_fail = 0`

## 工程实现状态

物理实现当前已经收口：
- `Methodology violations = 0`
- `Pblock count = 3`
- `WNS = 3.342 ns`
- `WHS = 0.03 ns`
- `Power = 1.877 W`

这说明当前版本不只是“能跑”，而是：
- 逻辑功能通过
- 板级结果通过
- 物理实现也具备正式交付口径

## 关键边界

### 1. 当前阶段完成，不等于原始全量蓝图完成

未做完的主要是增强项，不是当前主线缺陷：
- 更复杂的 `tamper / JTAG` 全场景自毁
- 更完整的硬件防火墙/ACL 演进
- 更激进的 `zero-copy / 吞吐优化`
- 更大范围的算法扩展
- 更完整的产品化驱动/系统化交付

### 2. 冷启动 UART boot banner 仍有可观测性边界

当前 `CP210x` 链路在真实冷断电场景下，不能稳定抓到 boot banner。  
因此 `SD cold-start soak` 采用的是双证据模型：
- 优先使用 `UART boot evidence`
- 若 `UART` 空，则退到“人工断电后首次控制面成功 + 首次数据面成功”

这不影响当前验收结论，但如果后续要把“必须抓到 boot banner”提升为正式门槛，需要单独继续打磨串口捕获链。

### 3. 资源余量仍然偏紧

当前 `Slice usage` 仍在高位。  
这不影响当前版本通过，但意味着后续如果继续加：
- ILA
- 更多 CSR
- 更复杂安全逻辑
- 更多 debug instrumentation

就有较高概率重新把实现推回高风险区。

## 推荐汇报口径

推荐在答辩或阶段汇报里这样表述：

- `当前 Phase C shadow_mirror 已完成批准范围内的目标，并在 AX7020 实板上完成功能、性能、安全、长稳和冷启动验证。`
- `系统当前正式基线镜像 SHA 为 CE4C710DD502F35BED170AC3C22362288505F5CF5817548A52032AD6DEF6856D。`
- `相对同板软件基线，AES 平均加速比 2.765941x，SM4 平均加速比 2.104324x。`
- `当前阶段可按已完成汇报；若按最初 21 天完整蓝图评估，则仍有增强项未全部展开。`

## 建议的下一步

如果继续往前做，优先级建议是：

1. 建立资源预算红线，防止后续小改动破坏当前实现收敛
2. 如果需要更强可观测性，继续做不增地址的压缩式状态扩展
3. 如果要冲更高规格，再考虑更复杂的安全强化或更激进的性能优化
