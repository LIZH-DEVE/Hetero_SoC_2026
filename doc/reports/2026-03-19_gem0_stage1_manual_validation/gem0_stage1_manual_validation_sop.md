# GEM0 Stage1 实网口手工闭环验收 SOP

## 1. 固定口径
- 顶层 bitstream：`system_wrapper`
- 板端 app：`gem0_stage1_bridge_app`
- 板端 IP：`192.168.1.20`
- 板端 MAC：`02:0A:35:00:01:20`
- 主机接口：`以太网`
- 主机 IP：`192.168.1.10`
- 子网掩码：`255.255.255.0`
- 抓包主工具：Wireshark
- 手工 UDP 激励工具：Packet Sender
- 备用抓包工具：[pktmon_capture.ps1](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/scripts/pktmon_capture.ps1)

## 2. 板端准备
1. 构建桥接 app：
   `powershell -ExecutionPolicy Bypass -File D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\build_gem0_stage1_bridge_app.ps1`
2. 下载并抓取启动日志：
   `powershell -ExecutionPolicy Bypass -File D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\capture_gem0_stage1_bridge_log.ps1 -ProgramBoard -Port COM9 -Baud 115200 -TimeoutSeconds 12 -XsdbPath D:\Xilinx\Vitis\2024.1\bin\xsdb.bat`
3. 串口必须至少出现以下关键行：
   - `CONTROL_APPLIED_OK`
   - `PHY_ID1=0x001C`
   - `PHY_ID2=0xC915`
   - `GEM0_INIT_STATUS=0x00000000`
   - `GEM0_FCS_PAD=ON`
   - `BRIDGE_READY`

若以上任一项缺失，本轮不进入主机侧 ARP/UDP 验收。

## 3. 主机准备
1. 物理网线直连 PC `以太网` 与开发板 RJ45。
2. 确认主机 `以太网` 已配置为 `192.168.1.10/24`。
3. 用下列脚本做只读体检：
   `powershell -ExecutionPolicy Bypass -File D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\scripts\check_gem0_manual_link_setup.ps1`
4. Wireshark 抓取接口固定为 `以太网`。
5. Wireshark 初始显示过滤器固定为：
   `arp || icmp || udp`

## 4. 手工 ARP 验收
1. 打开管理员 PowerShell。
2. 清空 ARP 缓存：
   `arp -d *`
3. 在 Wireshark 上开始抓包。
4. 触发 ARP：
   `ping 192.168.1.20 -n 1`
5. 验收通过标准：
   - 先看到主机发出的 ARP request，目标 IP 为 `192.168.1.20`
   - 再看到开发板返回的 ARP reply
   - Reply sender MAC 为 `02:0A:35:00:01:20`
   - Reply sender IP 为 `192.168.1.20`
   - `arp -a` 中出现 `192.168.1.20 -> 02-0a-35-00-01-20`
6. 同时核对串口仍保持运行态，不能出现：
   - `GEM0_INIT_FAIL`
   - `BRIDGE_INJECT_FAIL`
   - `TXCAP_TIMEOUT_STATUS`
   - `GEM0_TX_ERR`

## 5. 手工 UDP 验收
UDP 验收必须在 ARP 已通过后执行。

### Packet Sender 固定配置
- 协议：`UDP`
- 目标 IP：`192.168.1.20`
- 目标端口：`22136`
- 本地端口：`4660`
- 发送模式：`HEX`
- 首轮 payload 固定为 32 字节：

```text
A0 A1 A2 A3 B0 B1 B2 B3 C0 C1 C2 C3 D0 D1 D2 D3
E0 E1 E2 E3 F0 F1 F2 F3 11 22 33 44 55 66 77 88
```

### 触发步骤
1. 保持 Wireshark 抓包。
2. 在 Packet Sender 中手工发送一次 UDP。
3. 观察 Wireshark 是否收到来自 `192.168.1.20` 的 UDP reply。

### 通过标准
- Wireshark 可见主机发出的 UDP request 到 `192.168.1.20`
- Wireshark 可见开发板发出的 UDP reply
- Reply Ethernet source MAC 为 `02:0A:35:00:01:20`
- Reply IPv4 source 为 `192.168.1.20`
- Reply 目标 MAC/IP/端口与主机请求方向一致回写

### 串口联动判据
若未收到回包，必须同步核对板端串口：
- 若出现 `BRIDGE_RX_LEN=...` 但没有 `BRIDGE_TX_LEN=...`，优先看 Stage1 / TXCAP
- 若出现 `BRIDGE_TX_LEN=...` 但主机无回包，优先看 GEM0 TX 或主机抓包路径
- 若出现 `BRIDGE_INJECT_FAIL` 或 `TXCAP_TIMEOUT_STATUS`，直接回到 Stage1 注入链排查

## 6. 重复性验收
- 连续执行 3 次 ARP 验收
- 连续执行 3 次 UDP 验收
- 期望：
  - 无卡死
  - 串口统计单调增长
  - Wireshark 结果稳定可复现

## 7. 失败分流
- ARP 失败且 UDP 失败：
  先按二层链路问题处理，不进入 UDP 深挖。
- ARP 成功但 UDP 失败：
  优先检查桥接 app 是否记录 `BRIDGE_RX_LEN` / `BRIDGE_TX_LEN`。
- Wireshark 无 reply，但串口已有 `BRIDGE_TX_LEN`：
  优先怀疑 GEM0 TX、主机接口选择或抓包链，不先怀疑 Stage1。
- 串口直接出现 `GEM0_INIT_FAIL`：
  回到 GEM0/PHY bring-up。

## 8. 证据归档建议
- 板端 UART 日志：
  `board_gem0_stage1_bridge_*.txt`
- Wireshark 抓包：
  `arp_pass.pcapng`
  `udp_pass.pcapng`
- 若 Wireshark 暂不可用，可用备用命令：
  `powershell -ExecutionPolicy Bypass -File D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\scripts\pktmon_capture.ps1 -Action capture -DurationSeconds 20 -OutputBase gem0_stage1_manual -OutputDir .`
