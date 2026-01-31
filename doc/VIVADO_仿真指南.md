# Vivado 仿真操作指南 - 详细步骤

## 📌 核心要点

**仿真 Top 模块**: 使用 **Testbench**（以 `tb_` 开头的文件）  
**综合 Top 模块**: 使用实际的 RTL 设计模块

---

## 🎯 推荐方案：使用 Vivado GUI 运行仿真

### 步骤 1: 启动 Vivado

```cmd
D:\Xilinx\Vivado\2021.2\bin\vivado.bat
```

或者在开始菜单搜索 "Vivado"

---

### 步骤 2: 在 TCL Console 中运行仿真

Vivado 打开后，在底部的 **Tcl Console** 窗口中输入：

```tcl
# 切换到项目目录
cd D:/FPGAhanjia/Hetero_SoC_2026

# 方法一：运行 Day 14 完整系统测试（推荐从这个开始）
source sim/scripts/run_day14_sim.tcl
```

**这个脚本会自动**：
1. 编译所有 RTL 文件
2. 编译 testbench `tb_day14_full_integration.sv`
3. 设置 `tb_day14_full_integration` 为 Top 模块
4. 运行仿真
5. 生成波形文件

---

### 步骤 3: 查看仿真结果

仿真完成后，检查 Tcl Console 的输出：

✅ **成功标志**:
```
✅ RTL compilation completed
✅ Elaboration completed
✅ Simulation completed
```

❌ **失败标志**:
```
ERROR: Compilation failed!
ERROR: Elaboration failed!
```

---

## 📋 所有可用的测试

| 测试编号 | Testbench 文件 | 测试内容 | 脚本路径 |
|---------|---------------|---------|----------|
| Day 14 | `tb_day14_full_integration.sv` | 完整系统集成测试 | `sim/scripts/run_day14_sim.tcl` |
| Day 15 | `tb_day15_hsm.sv` | 硬件安全模块测试 | `sim/scripts/run_day15_sim.tcl` |
| Day 16 | `tb_day16_acl.sv` | ACL 防火墙测试 | `sim/scripts/run_day16_sim.tcl` |
| Day 17 | `tb_day17_fastpath.sv` | 零拷贝快速通道测试 | `sim/scripts/run_day17_sim.tcl` |

---

## 🔧 方案二：手动创建 Vivado 仿真项目（如果 TCL 脚本失败）

### 1. 创建新项目

1. 打开 Vivado
2. **File → Project → New...**
3. 项目名称: `Hetero_SoC_Sim`
4. 项目位置: `D:\FPGAhanjia\Hetero_SoC_2026\sim`
5. 项目类型: **RTL Project**
6. ✅ 勾选 **Do not specify sources at this time**
7. 选择开发板或器件（例如：Zynq-7020）
8. **Finish**

---

### 2. 添加源文件

#### a) 添加 RTL 设计文件

1. **Flow Navigator → PROJECT MANAGER → Add Sources**
2. 选择 **Add or create design sources**
3. **Add Directories**
4. 添加以下目录：
   ```
   D:\FPGAhanjia\Hetero_SoC_2026\rtl\inc
   D:\FPGAhanjia\Hetero_SoC_2026\rtl\core
   D:\FPGAhanjia\Hetero_SoC_2026\rtl\core\crypto
   D:\FPGAhanjia\Hetero_SoC_2026\rtl\core\parser
   D:\FPGAhanjia\Hetero_SoC_2026\rtl\core\tx
   D:\FPGAhanjia\Hetero_SoC_2026\rtl\core\dma
   D:\FPGAhanjia\Hetero_SoC_2026\rtl\core\pbm
   D:\FPGAhanjia\Hetero_SoC_2026\rtl\flow
   D:\FPGAhanjia\Hetero_SoC_2026\rtl\top
   ```
5. ✅ 勾选 **Scan and add RTL include files**
6. ✅ 勾选 **Copy sources into project**（可选）
7. **Finish**

#### b) 添加仿真文件

1. **Flow Navigator → PROJECT MANAGER → Add Sources**
2. 选择 **Add or create simulation sources**
3. **Add Files**
4. 选择仿真文件（从这一个开始）：
   ```
   D:\FPGAhanjia\Hetero_SoC_2026\tb\tb_day14_full_integration.sv
   ```
5. **Finish**

---

### 3. 设置仿真 Top 模块

1. 在 **Sources** 窗口中
2. 找到 **Simulation Sources → sim_1**
3. 右键点击 `tb_day14_full_integration`
4. 选择 **Set as Top**

---

### 4. 运行仿真

1. **Flow Navigator → SIMULATION → Run Simulation**
2. 选择 **Run Behavioral Simulation**
3. 等待编译和仿真启动

---

### 5. 查看波形

仿真启动后会自动打开波形窗口。

**添加关键信号到波形**：
1. 在 **Scope** 窗口中展开 `tb_day14_full_integration`
2. 选择感兴趣的信号
3. 右键 → **Add to Wave Window**
4. 点击工具栏的 **Run All** 或 **Run for 10us**

---

## 🐛 常见问题排查

### 问题 1: "ERROR: File not found"
**解决**: 检查文件路径，确保使用正斜杠 `/` 而不是反斜杠 `\`

### 问题 2: "Top module not set"
**解决**: 
- 仿真时必须设置 testbench 为 top
- 右键 testbench 文件 → Set as Top

### 问题 3: "Compilation failed"
**解决**: 
1. 查看 **Messages** 窗口的错误信息
2. 确认所有依赖文件都已添加
3. 确认 `pkg_axi_stream.sv` 在最先编译（package 文件）

### 问题 4: 仿真卡住不动
**解决**:
- 检查 testbench 是否有 `$finish;` 语句
- 设置仿真时间限制：**Simulation Settings → xsim.simulate.runtime = 10us**

---

## ✅ 验证仿真成功的标志

### Day 14 测试应该看到：
```verilog
[INFO] Starting Day 14 Full Integration Test
[INFO] DMA Write Transaction Started
[INFO] Crypto Engine Processing
[INFO] TX Stack Checksum Calculated
[PASS] Payload Encrypted Correctly
[PASS] Checksum Valid
[PASS] No Malformed Packets
```

### 波形检查要点：
- ✅ AXI 握手信号正常（valid & ready）
- ✅ 数据流按预期传输
- ✅ 状态机转换正确
- ✅ 加密前后数据发生变化

---

## 📁 仿真输出文件

仿真运行后会生成：
- `xsim.dir/` - 编译输出
- `*.wdb` - 波形数据库文件
- `*.log` - 仿真日志
- `*.vcd` - VCD 波形文件（如果 testbench 中启用）

---

## 🚀 快速开始命令

**最简单的方式（推荐）**：

```cmd
# 1. 打开命令提示符
cd D:\FPGAhanjia\Hetero_SoC_2026

# 2. 启动 Vivado
D:\Xilinx\Vivado\2021.2\bin\vivado.bat

# 3. 在 Vivado 的 Tcl Console 输入：
cd D:/FPGAhanjia/Hetero_SoC_2026
source sim/scripts/run_day14_sim.tcl
```

---

**祝仿真成功！** 🎉

有任何问题请告诉我。
