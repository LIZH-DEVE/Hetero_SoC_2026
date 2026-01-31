# 完整验证指南 - Day 1-13 代码修复验证

## 修复总结

### Critical Fixes (必须修复)
| BUG # | 文件 | 问题 | 状态 |
|-------|------|------|------|
| 1 | `dma_s2mm_mm2s_engine.sv` | 模块名不匹配 | ✅ 已修复 |
| 2 | `crypto_dma_subsystem.sv` | `dma_wvalid` 硬编码为 0 | ✅ 已修复 |
| 3 | `crypto_dma_subsystem.sv` | 缺少 `m_axis_wvalid` 连接 | ✅ 已修复 |
| 4 | `rx_parser.sv` | 缺少 16-byte 对齐检查 | ✅ 已修复 |
| 5 | `dma_s2mm_mm2s_engine.sv` | `next_state` 赋值位置错误 | ✅ 已修复 |
| 6 | `tb_dma_s2mm_mm2s.sv` | 使用旧模块名 | ✅ 已修复 |
| 7 | `tb_dma_loopback.sv` | 未实例化 DUT | ✅ 已修复 |

---

## 验证方法

### 方法 1: Vivado 语法检查 (最快)

**步骤:**
1. 打开 Vivado
2. 打开项目: `D:\FPGAhanjia\Hetero_SoC_2026\HCS_SOC\HCS_SOC.xpr`
3. 在 Tcl Console 中运行:

```tcl
# 重新扫描所有文件
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# 运行语法检查
launch_simulation -simset sim_1 -mode behavioral

# 或者单独检查特定文件
read_verilog -sv {D:/FPGAhanjia/Hetero_SoC_2026/rtl/core/dma/dma_s2mm_mm2s_engine.sv}
read_verilog -sv {D:/FPGAhanjia/Hetero_SoC_2026/rtl/top/crypto_dma_subsystem.sv}
```

**预期结果:**
- 无 Error 级别的警告
- 只有 Info/Warning 是可以接受的

---

### 方法 2: 运行单元测试 (推荐)

**测试 1: S2MM/MM2S 引擎测试**
```tcl
# 设置 S2MM/MM2S 测试为顶层
set_property top tb_dma_s2mm_mm2s [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
launch_simulation
```

**验证点:**
- [ ] `s2mm_en` 触发后，AXI 写通道正确发起
- [ ] `mm2s_en` 触发后，AXI 读通道正确发起
- [ ] `o_mm2s_data` 正确返回读取的数据

**预期输出:**
```
[TB] Trigger S2MM: Addr=10000000, Data=ABCD_EF01
[TB] S2MM Write: Addr=10000000, Data=ABCD_EF01
[TB] Trigger MM2S: Addr=10000000
[TB] MM2S Read: Addr=10000000, Data=ABCD_EF01
[TB] MM2S Result: ABCD_EF01
[TB] PASS: 数据一致!
```

**测试 2: Loopback Mux 测试**
```tcl
# 设置 Loopback 测试为顶层
set_property top tb_dma_loopback [get_filesets sim_1]
launch_simulation
```

**验证点:**
- [ ] Normal 模式: 数据写入 DDR
- [ ] PBM Passthrough 模式: 数据从 TX 输出，DDR 不写入

**预期输出:**
```
[TB] Test 1: 配置 DMA (Normal 模式 - 写入 DDR)
[TB] Write CSR Addr: 08, Data: 20000000
...
[TB] DDR[0] = DEAD_CAFE11111111  (数据写入成功)
[TB] Test 5: 配置 Loopback 模式 (PBM Passthrough)
[TB] DDR[0] after Passthrough = 00000000 (DDR 未写入)
```

---

### 方法 3: 全系统仿真 (最完整)

**步骤:**
```tcl
# 设置完整系统测试为顶层
set_property top tb_crypto_dma_subsystem [get_filesets sim_1]
launch_simulation -runall
```

**验证清单:**
| 模块 | 验证点 | 状态 |
|------|--------|------|
| axil_csr | 对齐检查 (非 64B 对齐地址触发 error) | ⬜ |
| rx_parser | Payload 16-byte 对齐检查 | ⬜ |
| rx_parser -> PBM | Meta 数据正确传递 | ⬜ |
| crypto_bridge | AES/SM4 切换正常 | ⬜ |
| dma_master_engine | 4K 边界拆分正确 | ⬜ |
| dma_desc_fetcher | Head/Tail 指针更新正确 | ⬜ |
| crypto_dma_subsystem | Loopback 模式切换正常 | ⬜ |

---

### 方法 4: Vivado 综合检查 (最终验证)

**步骤:**
1. 在 Vivado 中点击 **Run Synthesis**
2. 检查 Synthesis 报告

**预期:**
- 无 Critical Warnings
- Timing 分析通过

---

## 快速验证脚本

创建文件 `verify_all.tcl`:

```tcl
# verify_all.tcl - 一键验证所有修复

puts "=========================================="
puts "开始验证 Day 1-13 代码修复"
puts "=========================================="

# 1. 检查关键文件是否存在
set files {
    "rtl/core/dma/dma_s2mm_mm2s_engine.sv"
    "rtl/top/crypto_dma_subsystem.sv"
    "rtl/core/parser/rx_parser.sv"
    "tb/tb_dma_s2mm_mm2s.sv"
    "tb/tb_dma_loopback.sv"
}

foreach f $files {
    if {[file exists $f]} {
        puts "✓ $f"
    } else {
        puts "✗ $f 不存在!"
    }
}

# 2. 检查模块名
puts "\n检查模块名..."
set check_result [exec grep -n "^module dma_s2mm" rtl/core/dma/dma_s2mm_mm2s_engine.sv]
if {$check_result ne ""} {
    puts "✓ dma_s2mm_mm2s_engine 模块名正确"
}

# 3. 检查关键修复
puts "\n检查关键修复..."

# 检查 rx_parser 对齐检查
set check_result [exec grep -n "Alignment check" rtl/core/parser/rx_parser.sv]
if {$check_result ne ""} {
    puts "✓ rx_parser 对齐检查已添加"
}

# 检查 crypto_dma_subsystem m_axis_wvalid
set check_result [exec grep -n "m_axis_wvalid = " rtl/top/crypto_dma_subsystem.sv]
if {$check_result ne ""} {
    puts "✓ m_axis_wvalid 连接已添加"
}

puts "\n=========================================="
puts "验证完成! 请在 Vivado 中运行仿真确认."
puts "=========================================="
```

---

## 问题排查

### 问题 1: "Module not found"
**原因**: 模块名不匹配
**解决**: 
```tcl
# 确认模块名
read_verilog -sv rtl/core/dma/dma_s2mm_mm2s_engine.sv
```

### 问题 2: "Port not connected"
**原因**: 接口连接缺失
**解决**: 检查 `crypto_dma_subsystem.sv` 中的信号连接

### 问题 3: "Timing violation"
**原因**: 关键路径过长
**解决**: 在 Task 20 中添加 Pipeline Register

---

## 验收标准

### Day 1-11 验收
- [ ] 所有模块语法正确
- [ ] rx_parser 丢弃非 16-byte 对齐的包
- [ ] CSR 拒绝非 64-byte 对齐的地址
- [ ] PBM 原子操作和回滚机制正确

### Day 12-13 验收
- [ ] S2MM/MM2S 引擎正确工作
- [ ] Loopback Mux 三种模式切换正常
- [ ] 全系统回环测试通过

### 最终验收 (Day 14)
- [ ] Wireshark 抓包验证加密正确
- [ ] Checksum 验证正确
- [ ] 无 Malformed Packet
