# 项目全功能验证清单

生成时间：2026-03-17  
需求基线：`D:\FPGAhanjia\大一寒假\21天硬件安全加速网卡 (1).docx`

状态定义：
- `PASS`：有直接运行证据，且结果满足需求
- `FAIL`：有直接证据表明不满足需求
- `PARTIAL`：实现存在，但只完成静态核对或局部动态验证
- `BLOCKED`：当前验证被工具链或环境阻断

| ID | 需求来源 | 功能描述 | 实现锚点 | 验证方式 | 结论 |
|---|---|---|---|---|---|
| P1-01 | Day 2 / Task 1.1 | 包长定义、16B 对齐、Malformed 检查 | `rtl/inc/pkg_axi_stream.sv`, `rtl/core/parser/rx_parser.sv` | 静态核对 | PARTIAL |
| P1-02 | Day 2 / Task 1.2 | CSR：`CACHE_CTRL(0x40)`、`ACL_COLLISION_CNT(0x44)`、Loopback | `rtl/core/axil_csr.sv` | 静态核对 | PASS |
| P1-03 | Day 2 / Task 1.3 | BFM 对齐验证 | 文档要求，未找到可执行新鲜结果 | 动态验证入口核对 | BLOCKED |
| P1-04 | Day 3 / Task 2.1-2.2 | AXI Master：跨 4K/256 beats 拆包、单 ID 保序、非对齐报错 | `rtl/core/dma/dma_master_engine.sv` | 静态核对 | PARTIAL |
| P1-05 | Day 3 / Task 2.3 | Virtual DDR 随机延迟模型 | 文档要求，未形成可执行新鲜结果 | 动态验证入口核对 | BLOCKED |
| P2-01 | Day 5 / Task 4.1 | Width Gearbox + Golden Model 支撑 | `rtl/core/gearbox_128_to_32.sv`, `tb/crypto_vectors_pkg.sv` | 静态核对 | PARTIAL |
| P2-02 | Day 5 / Task 4.2 | AES/SM4 基本加解密功能 | `rtl/core/crypto/*`, `HCS_SOC/crypto_test_app/src/main.c` | 板级串口结果 | PASS |
| P2-03 | Day 5 / Task 4.2 | SHA-256 实现 | 需求文档要求；仓库运行口径改为 SM4 | 需求/实现偏差核查 | FAIL |
| P2-04 | Day 6 / Task 5.1-5.2 | CBC/IV 逻辑与 Async FIFO CDC | `rtl/core/async_fifo.sv`, 相关 crypto 模块 | 静态核对 | PARTIAL |
| P2-05 | Day 7 / Task 6.1-6.2 | Dispatcher 与 Credit-based Flow Control | `rtl/top/packet_dispatcher.sv`, `rtl/flow/credit_manager.sv` | 静态核对 | PARTIAL |
| P2-06 | Day 8 / Task 7.1-7.2 | PBM 与 Atomic Reservation / Rollback | `rtl/core/pbm/pbm_controller.sv` | 静态核对 + 板级异常场景 | PARTIAL |
| P3-01 | Day 9 / Task 8.2 | RX Parser：长度检查、对齐检查、Meta 处理 | `rtl/core/parser/rx_parser.sv` | 静态核对 | PARTIAL |
| P3-02 | Day 9 / Task 8.3 | ARP 响应链路 | `rtl/core/parser/rx_parser.sv`, `rtl/core/parser/arp_responder.sv` | 静态核对 | FAIL |
| P3-03 | Day 10 / Task 9.1-9.2 | TX Checksum、Padding、字段交换 | `rtl/core/tx/tx_stack.sv` | 静态核对 | PARTIAL |
| P3-04 | Day 11 / Task 10.1-10.2 | HW Init 与 Ring Pointer 管理 | `rtl/top/crypto_dma_subsystem.sv`, 相关 DMA/CSR 模块 | 静态核对 | PARTIAL |
| P3-05 | Day 12-13 / Task 11.x | DMA Engines 与 Loopback Mux | `rtl/core/dma/*`, `rtl/top/crypto_dma_subsystem.sv` | 静态核对 | PARTIAL |
| P3-06 | Day 14 / Task 13.1 | 全系统回环：Wireshark、加密包、Checksum、无 malformed | `tb/tb_day14_full_integration.sv`, `sim/scripts/run_day14_sim.tcl` | 仿真入口验证 | BLOCKED |
| P4-01 | Day 15 / Task 14.1 | Config Packet Auth：Magic + Anti-replay | `rtl/security/config_packet_auth.sv`, `tb/tb_day15_hsm.sv`, `tb/tb_config_packet_auth_sanity.sv` | 静态核对 + 新旧 tb 交叉审阅 | PARTIAL |
| P4-02 | Day 15 / Task 14.2 | Key Vault：DNA 绑定、派生、锁定 | `rtl/security/key_vault.sv`, `tb/tb_day15_hsm.sv`, `tb/tb_key_vault_sanity.sv` | 静态核对 + sanity tb 已补 | PARTIAL |
| P4-03 | Day 16 / Task 15.x | ACL：5-tuple、CRC16/2-way、Drop | `rtl/security/five_tuple_extractor.sv`, `rtl/security/acl_match_engine.sv`, `tb/tb_acl_match_engine_sanity.sv` | 静态核对 + sanity tb 尝试 | PARTIAL |
| P4-04 | Day 17 / Task 16.1 | FastPath：零拷贝、旁路、Checksum 透传 | `rtl/core/fast_path.sv`, `tb/tb_day17_fastpath.sv`, `tb/tb_fast_path_sanity.sv` | 动态仿真 + sanity tb | FAIL |
| P4-05 | Day 18 / Task 17.x | 鲁棒性：Back-pressure、短包、恢复 | `HCS_SOC/crypto_test_app/src/main.c` | 板级串口结果 | PARTIAL |
| P4-06 | Day 21 / Task 20.2 | 真实性能基准：OpenSSL vs SmartNIC ILA 实测 | `scripts/day21_performance_benchmark.py` | 脚本核查 + 环境核查 | FAIL |
| P4-07 | Day 20 / Task 19.1 | 时序收敛、路由完整性 | `constraints/day20_timing_constraints.xdc`, `HCS_SOC/HCS_SOC.runs/impl_1/*.rpt` | 实现报告核查 | PASS |
| P4-08 | Day 21 / Task 20.1 | ILA 观测：drop_reason/fastpath/axi_error | `constraints/day21_ila_instrumentation.tcl` | 静态核对 | PARTIAL |

## 结论汇总

| 状态 | 数量 |
|---|---:|
| PASS | 3 |
| FAIL | 4 |
| PARTIAL | 15 |
| BLOCKED | 3 |

说明：
- `AES/SM4 + 指纹 + 基本板级链路` 已有直接通过证据。
- `ARP 集成链路`、`FastPath 动态行为`、`SHA-256 对需求基线的符合性`、`Day21 真实性能基准` 目前不能判定为已满足需求。
- `Day14/Day15/Day16` 旧仿真入口与当前 Vivado 2024.1 存在兼容性问题，导致部分需求只能停留在静态核对。
- `tb_day15_hsm.sv` 和 `tb_day17_fastpath.sv` 均存在测试契约问题；其中 Day17 已通过新的 `tb_fast_path_sanity.sv` 再次确认 RTL 仍有真实缺陷。
