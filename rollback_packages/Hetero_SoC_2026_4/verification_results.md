# 项目全功能验证结果记录

生成时间：2026-03-17  
验证范围：需求追踪、模块功能、集成链路、用户流程、设计/技术要求  
结果口径：仅依据本次会话中获得的直接证据，不把“代码存在”自动算作“功能通过”

## 1. 验证环境

- 工作区：`D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026`
- 需求基线：`D:\FPGAhanjia\大一寒假\21天硬件安全加速网卡 (1).docx`
- 工具链：
  - `D:\Xilinx\Vivado\2024.1\bin\xvlog.bat`
  - `D:\Xilinx\Vivado\2024.1\bin\xelab.bat`
  - `D:\Xilinx\Vivado\2024.1\bin\xsim.bat`
  - `D:\Xilinx\Vitis\2024.1\bin\xsdb.bat`
- 主机网络：
  - 适配器 `以太网` 状态 `Up`
  - 链路速率 `1 Gbps`
- 主机工具缺口：
  - `openssl` 不在 `PATH`
  - `tshark` 不在 `PATH`
  - `wireshark` 不在 `PATH`

## 2. 本次实际执行的验证命令

### 2.1 通过的自动化命令

```powershell
py -3 -m unittest discover -s HCS_SOC\tests -p "test_*.py"
```

结果：
- `Ran 4 tests in 0.032s`
- `OK`

```powershell
powershell -ExecutionPolicy Bypass -File HCS_SOC\manage_bitstream.ps1 -Action verify
```

结果：
- `authoritative sha256: c672f22e3e891877af93f4d2b7d5be4b7358f22b45dad842b203c326701633fb`
- `errors: none`
- 仅有两条 legacy 副本告警，不影响权威 bitstream 来源

### 2.2 失败或阻断的自动化命令

```powershell
D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv -prj sim/scripts/day14_compile.prj
```

结果：
- `ERROR: [XSIM 43-3217] ... Incorrect project file syntax`

```powershell
D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv -prj sim/scripts/day16_compile.prj
```

结果：
- `ERROR: [XSIM 43-3217] ... Incorrect project file syntax`

```powershell
D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv rtl/core/fast_path.sv tb/tb_day17_fastpath.sv
D:\Xilinx\Vivado\2024.1\bin\xelab.bat -debug typical -relax -snapshot tb_day17_fastpath_behav work.tb_day17_fastpath work.glbl
D:\Xilinx\Vivado\2024.1\bin\xsim.bat tb_day17_fastpath_behav -runall
```

结果：
- `xvlog` 通过
- `xsim` 日志显示 Day17 前 3 项均失败

```powershell
D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv rtl/core/fast_path.sv tb/tb_fast_path_sanity.sv
D:\Xilinx\Vivado\2024.1\bin\xelab.bat -debug typical -relax -snapshot tb_fast_path_sanity_behav work.tb_fast_path_sanity work.glbl
D:\Xilinx\Vivado\2024.1\bin\xsim.bat tb_fast_path_sanity_behav -runall
```

结果：
- 新 sanity tb 编译、展开、运行全部成功
- 仿真在 `135 ns` 直接 `fatal`
- 失败内容：
  - `fp_cnt=0`
  - `cs_cnt=0`
  - `seen_tx=0`
  - `seen_pbm=0`
  - `seen_meta=0`
  - `seen_checksum=0`

```powershell
手动逐文件编译 Day15 compile 清单 + xelab/xsim
```

结果：
- 编译流程长时间挂起，超过 600 秒未完成
- 当前只能证明 Day15 仿真入口不可直接用于新鲜验收，不能证明 HSM 功能通过或失败

```powershell
D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv rtl/security/config_packet_auth.sv tb/tb_config_packet_auth_sanity.sv
D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv rtl/security/acl_match_engine.sv tb/tb_acl_match_engine_sanity.sv
```

结果：
- 当前机器上两条命令都出现 `xvlog` 独立挂起
- 新 sanity tb 已补齐，但安全模块动态验证仍被当前 XSim 编译链阻断

## 3. 逐阶段验证结果

## Phase 1：协议与总线基座

### P1-02 CSR 设计

验证层级：静态  
结论：PASS

证据：
- `rtl/core/axil_csr.sv` 中可直接看到：
  - `0x40` `reg_cache_ctrl`
  - `0x44` `reg_acl_cnt`
  - `0x48` `reg_loopback_mode`
- 读写路径均已实现：
  - `8'h40: reg_cache_ctrl <= ...`
  - `8'h44: reg_acl_cnt <= ...`
  - `8'h48: reg_loopback_mode <= ...`

### P1-04 AXI Burst / 4K Split / 对齐

验证层级：静态  
结论：PARTIAL

证据：
- `rtl/core/dma/dma_master_engine.sv`
  - `addr_unaligned = (i_base_addr[2:0] != 3'b000)`
  - `dist_to_4k = 13'h1000 - current_addr[11:0]`
  - 单次突发限制到 `1024 bytes`
  - `m_axi_awburst = 2'b01`
- 当前缺口：
  - 还没有拿到新的波形或仿真日志去证明跨 4K 和大 burst 的动态行为

### P1-03 / P1-05 BFM 与 Virtual DDR

验证层级：动态  
结论：BLOCKED

原因：
- 旧 `.prj` 仿真入口与 Vivado 2024.1 不兼容
- 没有拿到新的 BFM/DDR 随机延迟验证日志

## Phase 2：算力引擎与流控

### P2-02 AES / SM4 加解密

验证层级：板级  
结论：PASS

证据来源：
- 用户在本次会话提供的 2026-03-17 板级 UART 输出

关键结果：
- `Initial STATUS: 0xACE00403`
- `[VER] Hardware Version: 0xACE (V2.1 Patch Detected) [OK]`
- AES-128 Encryption：`PASS`
- AES-128 Decryption：`PASS`
- SM4-128 Encryption：`PASS`
- SM4-128 Decryption：`PASS`

### P2-03 SHA-256

验证层级：需求符合性核查  
结论：FAIL

原因：
- 需求文档 Day 5 明确写的是 `AES-CBC / SHA-256 实现`
- 当前板级软件和仓库运行口径实际验证的是 `AES + SM4`
- 仓库中存在“SM4 vs SHA-256 is intentional”的后续说明，但本次验收基线按 DOCX，不做自动替换

### P2-06 PBM / 异常流控

验证层级：板级  
结论：PARTIAL

证据来源：
- 用户 UART 输出

关键结果：
- `[PASS] Hardware WREADY Back-pressure verified! No data lost under burst load.`
- 满载状态：`STATUS at full load: 0xACE00401`
- 短包异常：`STATUS: 0xACE00447`

保留问题：
- 回滚资源释放、Meta/PBM 恢复没有新的内部计数器或波形证据

## Phase 3：协议栈与 SmartNIC 子系统

### P3-01 RX Parser

验证层级：静态  
结论：PARTIAL

证据：
- `rtl/core/parser/rx_parser.sv` 有长度/状态机骨架
- 但 ARP 输出未完成，影响整个协议栈闭环判定

### P3-02 ARP 响应链路

验证层级：静态  
结论：FAIL

证据：
- `rtl/core/parser/arp_responder.sv` 存在实际 ARP 响应器
- 但 `rtl/core/parser/rx_parser.sv` 第 166-168 行写死：
  - `assign o_arp_valid = 0;`
  - `assign o_arp_data = 0;`

结论：
- ARP 模块存在
- ARP 集成链路未闭合
- 不能按“已实现静态 ARP 应答”验收通过

### P3-03 TX Stack / Checksum

验证层级：静态  
结论：PARTIAL

证据：
- `rtl/core/tx/tx_stack.sv` 包含动态 checksum 计算和 TX 发包状态
- 但没有新的主机抓包结果证明真实网络报文正确

### P3-06 全系统回环

验证层级：仿真/网络  
结论：BLOCKED

原因：
- Day14 入口脚本编译阶段即失败
- 本机没有 `tshark/wireshark` 可用于本次自动抓包验收
- 本次会话未拿到新的主机直连 ARP/UDP 抓包证据

## Phase 4：安全、FastPath、性能与物理收敛

### P4-01 Config Packet Auth

验证层级：静态 + 仿真尝试  
结论：PARTIAL

证据：
- `rtl/security/config_packet_auth.sv` 明确实现：
  - `MAGIC_NUMBER = 32'hDEADBEEF`
  - `hdr1_data[15:0] > seq_id_reg` 的递增检查
  - 失败包 `ST_DROP` 排空
- 旧 `tb/tb_day15_hsm.sv` 存在验证契约错误：
  - 首字被写成 `{seq_id, magic[15:0]}`
  - 这与 RTL 要求的“首字必须完整等于 `32'hDEADBEEF`，第二字低 16 位才是 `seq_id`”不一致
- 已补写 `tb/tb_config_packet_auth_sanity.sv`

缺口：
- 新旧 testbench 都还没有在当前工具链下形成完整可复用的动态通过日志

### P4-02 Key Vault + DNA Binding

验证层级：静态  
结论：PARTIAL

证据：
- `rtl/security/key_vault.sv` 在 `SYNTHESIS` 分支实例化了 `DNA_PORT`
- 含 DNA 读取、锁定和当前 DNA 保存逻辑
- 已补写 `tb/tb_key_vault_sanity.sv`

缺口：
- 当前还没有新的动态结果证明换板锁定、自毁、非法复位/JTAG 场景

### P4-03 ACL

验证层级：静态  
结论：PARTIAL

证据：
- `rtl/security/acl_match_engine.sv`
  - `NUM_WAYS = 2`
  - 16-bit hash
  - 双路 BRAM 存储
  - `acl_hit / acl_drop / hit_count / miss_count`
- 已补写 `tb/tb_acl_match_engine_sanity.sv`

缺口：
- Day16 仿真入口脚本与当前工具链不兼容
- 当前机器上对安全模块的 `xvlog` 仍可能独立挂起，尚未得到新的动态命中/误杀结果

### P4-04 FastPath

验证层级：动态仿真  
结论：FAIL

直接证据：
- `xsim.log`
- 新 `tb/tb_fast_path_sanity.sv`

失败摘要：
- 旧 `tb_day17_fastpath.sv` 的前 3 项都失败
- 旧 tb 对 `fast_path_enable`、`meta_out_valid` 这类脉冲信号的采样时机不合理，不能单独作为最终裁定
- 但新的 `tb_fast_path_sanity.sv` 在更严格、时序更合理的条件下仍然失败：
  - `fp_cnt=0`
  - `cs_cnt=0`
  - `seen_tx=0`
  - `seen_pbm=0`
  - `seen_meta=0`
  - `seen_checksum=0`

结论：
- 不是单纯旧 tb 误报
- 当前 RTL 在最基本的 FastPath eligible packet 场景下就没有建立有效数据通路

### P4-05 鲁棒性攻防

验证层级：板级  
结论：PARTIAL

证据：
- UART 日志已覆盖：
  - AXI/WREADY Back-pressure
  - 短包异常
- 未覆盖：
  - Runt/Giant Frames
  - Replay Attack 板级验证
  - PBM/Meta 回滚内部计数

### P4-06 Day21 真实性能基准

验证层级：脚本核查 + 环境核查  
结论：FAIL

证据：
- `scripts/day21_performance_benchmark.py`
  - `simulate_ila_sampling()` 使用固定伪造数据
  - 没有接入真实 Vivado Hardware Manager / ILA 数据
- 本机 `openssl` 不在 `PATH`

结论：
- 当前脚本更接近演示草稿，不是可用于验收的真实基准测试

### P4-07 时序收敛与路由

验证层级：实现报告  
结论：PASS

证据：
- `HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper_timing_summary_routed.rpt`
  - `WNS = 3.784 ns`
  - `WHS = 0.048 ns`
  - `All user specified timing constraints are met.`
- `HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper_route_status.rpt`
  - `38422` routable nets
  - `38422` fully routed
  - `0` routing errors

### P4-08 ILA Instrumentation

验证层级：静态  
结论：PARTIAL

证据：
- `constraints/day21_ila_instrumentation.tcl` 中定义了：
  - `u_ila_drop_stats`
  - `u_ila_fastpath`
  - `u_ila_axi`
  - `u_ila_crypto`
  - `u_ila_pbm`

缺口：
- 本次没有新的 `.ltx` 下载与硬件采样结果

## 4. 用户交互流程验证

| 流程 | 结果 | 说明 |
|---|---|---|
| 权威 bitstream 来源固定 | PASS | `manage_bitstream.ps1 -Action verify` 无错误 |
| 烧录后版本指纹读回 | PASS | 用户 UART 显示 `0xACE00403` |
| 软件触发 AES/SM4 流程 | PASS | 用户 UART 全部通过 |
| 安全测试触发与复位提示 | PARTIAL | 短包测试完成，但只给出 `rst -system` 提示，未在本次会话完成恢复闭环 |
| 主机直连网络 ARP/UDP/抓包 | BLOCKED | 缺主机抓包工具与新的链路运行证据 |

## 5. 总体结论

- 已有直接通过证据的核心能力：
  - 权威 bitstream 管理链
  - 硬件指纹读回
  - AES/SM4 基本加解密
  - 基础 back-pressure 与短包异常行为
  - 路由与时序报告
- 已被明确证伪或不满足需求基线的能力：
  - `SHA-256` 需求符合性
  - `ARP` 集成链路
  - `FastPath` 动态行为
  - `Day21` 真实性能基准脚本
- 仍需继续打通验证基础设施的部分：
  - Day14/Day15/Day16 仿真入口
  - 主机直连网络抓包链
  - HSM/ACL/ILA 的新鲜运行证据
