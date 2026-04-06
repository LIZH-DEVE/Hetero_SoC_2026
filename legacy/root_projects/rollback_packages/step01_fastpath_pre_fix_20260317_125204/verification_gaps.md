# 未实现 / 存在问题功能点详细说明

生成时间：2026-03-17

## G-01 ARP 集成链路未闭合

- 严重级别：高
- 影响范围：Phase 3 协议栈、主机直连网络、Day14 全系统回环
- 现象：
  - `arp_responder` 模块存在
  - 但 `rx_parser` 没有把 ARP 流真正送出去
- 复现方式：
  1. 打开 `rtl/core/parser/rx_parser.sv`
  2. 查看第 166-168 行
  3. 可见 `o_arp_valid` 和 `o_arp_data` 被固定为 0
- 疑似根因：
  - ARP responder 被单独实现，但未与实际 parser 输出链路闭合
- 证据：
  - `rtl/core/parser/rx_parser.sv:166-168`
  - `rtl/core/parser/arp_responder.sv`

## G-02 Day14 / Day16 旧仿真入口与 Vivado 2024.1 不兼容

- 严重级别：高
- 影响范围：Day14 全系统验收、Day16 ACL 动态验收
- 现象：
  - `xvlog -sv -prj` 在读取旧 `.prj` 时直接报语法错误
- 复现方式：
  ```powershell
  D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv -prj sim/scripts/day14_compile.prj
  D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv -prj sim/scripts/day16_compile.prj
  ```
- 直接输出：
  - `ERROR: [XSIM 43-3217] ... Incorrect project file syntax`
- 疑似根因：
  - `.prj` 文件仍使用旧的 `sv <file>` / `v <file>` 行格式，不符合当前 `xvlog` 解析要求
- 证据：
  - `sim/scripts/day14_compile.prj`
  - `sim/scripts/day16_compile.prj`
  - 本次命令行错误输出

## G-03 Day15 HSM 动态验证未形成可验收结果

- 严重级别：中
- 影响范围：Config Auth、Key Vault、DNA 锁定的动态验证
- 现象：
  - Day15 testbench 存在
  - 逐文件手工编译流程长时间挂起，未在 600 秒内完成
  - 且旧 `tb_day15_hsm.sv` 本身存在验证契约错误：首字错误地混入了 `seq_id`
- 复现方式：
  - 按 `day15_compile.prj` 顺序逐文件调用 `xvlog`
  - 后续 `xelab/xsim` 无法在可接受时间内完成
- 当前结论：
  - 不能据此认定功能失败
  - 但也不能给出 `PASS`
- 证据：
  - `tb/tb_day15_hsm.sv`
  - `tb/tb_config_packet_auth_sanity.sv`
  - `tb/tb_key_vault_sanity.sv`
  - `rtl/security/config_packet_auth.sv`
  - `rtl/security/key_vault.sv`

## G-04 FastPath 动态行为存在真实缺陷

- 严重级别：高
- 影响范围：零拷贝快速通道、旁路路径、Checksum 透传、Day17 验收
- 现象：
  - 满足 FastPath 条件时计数器未按预期增加，meta 输出无效
  - 新 sanity tb 下，最基本 eligible packet 场景仍然完全不出数
- 复现方式：
  ```powershell
  D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv rtl/core/fast_path.sv tb/tb_fast_path_sanity.sv
  D:\Xilinx\Vivado\2024.1\bin\xelab.bat -debug typical -relax -snapshot tb_fast_path_sanity_behav work.tb_fast_path_sanity work.glbl
  D:\Xilinx\Vivado\2024.1\bin\xsim.bat tb_fast_path_sanity_behav -runall
  ```
- 关键失败点：
  - `fp_cnt=0`
  - `cs_cnt=0`
  - `seen_tx=0`
  - `seen_pbm=0`
  - `seen_meta=0`
  - `seen_checksum=0`
- 疑似根因：
  - 旧 tb 的确有脉冲采样时机问题
  - 但新的 sanity tb 仍显示 RTL 在最基本场景下没有建立有效数据通路
  - 更像是状态机在首拍判路后没有正确前推数据
- 证据：
  - `rtl/core/fast_path.sv`
  - `tb/tb_day17_fastpath.sv`
  - `tb/tb_fast_path_sanity.sv`
  - `xsim.log`

## G-05 SHA-256 与当前实现存在规格偏差

- 严重级别：高
- 影响范围：Phase 2 需求符合性、文档一致性、最终答辩口径
- 现象：
  - 需求文档 Day 5 写明 `AES-CBC / SHA-256 实现`
  - 当前仓库动态验证的是 `AES + SM4`
- 当前判断：
  - 按本次验收基线，不能把 `SM4` 自动视为 `SHA-256` 的替代
- 建议记录方式：
  - 作为“规格偏差”单列，不与 AES/SM4 的功能通过相互抵消
- 证据：
  - 需求 DOCX 第 48-50 段
  - `HCS_SOC/crypto_test_app/src/main.c`
  - `doc/DEPLOYMENT_CHECKLIST.md`

## G-06 Day21 性能基准脚本不具备真实性能验收资格

- 严重级别：高
- 影响范围：吞吐量、加速比、CPU 卸载率的最终展示与验收
- 现象：
  - `run_hardware_benchmark()` 并未采集真实 ILA 数据
  - 脚本内部调用 `simulate_ila_sampling()`
  - 本机 `openssl` 也不在 `PATH`
- 复现方式：
  1. 查看 `scripts/day21_performance_benchmark.py`
  2. 观察 `simulate_ila_sampling()` 返回固定样本数据
  3. 观察 `openssl speed` 在当前环境不可执行
- 当前结论：
  - 该脚本是演示性脚本，不是最终验收工具
- 证据：
  - `scripts/day21_performance_benchmark.py:111-180`
  - 本次 `Get-Command openssl` 输出

## G-07 主机直连网络验证仍缺少可复用抓包链

- 严重级别：中
- 影响范围：ARP/UDP 往返、Wireshark 验收、Day14 全系统证明
- 现象：
  - 主机以太网物理链路可见，`Status = Up`
  - 但本次环境没有 `tshark/wireshark`
  - 也没有可直接复用的主机发包/抓包自动化脚本
- 当前结论：
  - 网络链路不能宣称“已验收通过”
- 证据：
  - `Get-NetAdapter` 输出
  - `Get-Command tshark, wireshark` 输出

## G-08 HSM / ACL / ILA 存在实现锚点，但缺少新鲜动态证据

- 严重级别：中
- 影响范围：Phase 4 高级特性完整性
- 现象：
  - `config_packet_auth.sv`、`key_vault.sv`、`acl_match_engine.sv`、`day21_ila_instrumentation.tcl` 均存在
  - 已补写 `tb_config_packet_auth_sanity.sv`、`tb_key_vault_sanity.sv`、`tb_acl_match_engine_sanity.sv`
  - 但本次没有拿到完整的新鲜仿真或板级采样结果
  - 当前 XSim 对部分安全模块文件存在独立 `xvlog` 挂起
- 当前结论：
  - 只能标记为 `PARTIAL`
- 证据：
  - `rtl/security/config_packet_auth.sv`
  - `rtl/security/key_vault.sv`
  - `rtl/security/acl_match_engine.sv`
  - `tb/tb_config_packet_auth_sanity.sv`
  - `tb/tb_key_vault_sanity.sv`
  - `tb/tb_acl_match_engine_sanity.sv`
  - `constraints/day21_ila_instrumentation.tcl`

## G-09 旧验证 tb 本身不完全可信

- 严重级别：中
- 影响范围：Day15、Day17 失败结论的可信度
- 现象：
  - `tb_day15_hsm.sv` 的 config packet 构造方式与 RTL 契约不符
  - `tb_day17_fastpath.sv` 在包结束很久后再去检查 `fast_path_enable`、`meta_out_valid` 这类脉冲信号
- 当前结论：
  - 旧 tb 不能直接作为最终裁定依据
  - 但 Day17 已用新的 sanity tb 再次证实 RTL 有真实问题
- 证据：
  - `tb/tb_day15_hsm.sv`
  - `tb/tb_day17_fastpath.sv`
  - `tb/tb_fast_path_sanity.sv`

## 建议的后续优先级

1. 先修复 Day14/15/16 仿真入口与 Vivado 2024.1 的兼容性，否则大量功能只能停留在静态核对。
2. 优先补齐 `rx_parser -> ARP responder` 的真实集成链，否则主机直连网络验收无法成立。
3. 重新定位 FastPath 的状态机/数据前推契约，先把 Day17 动态失败修掉。
4. 把 Day21 性能脚本改成真实 ILA 采集和真实 OpenSSL 基线，而不是模拟数据。
