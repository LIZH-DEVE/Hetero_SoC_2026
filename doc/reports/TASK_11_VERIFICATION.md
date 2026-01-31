# Task 11.1/11.2/11.3 完成验证清单

## 已修改的文件

### 1. CSR 模块
- **文件路径**: `D:\FPGAhanjia\Hetero_SoC_2026\rtl\core\axil_csr.sv`
- **修改内容**:
  - 添加 S2MM/MM2S 控制位（Bit 4: S2MM Enable, Bit 5: MM2S Enable）
  - 添加 S2MM/MM2S 寄存器（0x20: S2MM Addr, 0x24: S2MM Data）
  - 添加 Loopback Mode 寄存器（0x48）
  - 移动 Key 寄存器到 0x28-0x34
  - 添加输出信号：
    - `o_s2mm_en`: S2MM 使能
    - `o_mm2s_en`: MM2S 使能
    - `o_s2mm_addr`: S2MM 地址
    - `o_s2mm_data`: S2MM 数据
    - `o_loopback_mode[1:0]`: Loopback 模式（00=Normal, 01=DDR Loopback, 10=PBM Passthrough）

### 2. S2MM/MM2S Engine
- **文件路径**: `D:\FPGAhanjia\Hetero_SoC_2026\rtl\core\dma\dma_s2mm_mm2s_engine.sv`
- **功能**: 支持直接读写 DDR
- **状态机**:
  - IDLE → S2MM_WRITE_ADDR → S2MM_WRITE_DATA → S2MM_WAIT_RESP → DONE
  - IDLE → MM2S_READ_ADDR → MM2S_READ_DATA → MM2S_WAIT_DATA → DONE
- **接口**: 
  - AXI4 Master（读和写）
  - 控制接口（S2MM Enable, MM2S Enable）

### 3. DMA 子系统
- **文件路径**: `D:\FPGAhanjia\Hetero_SoC_2026\rtl\top\crypto_dma_subsystem.sv`
- **修改内容**:
  - 添加 TX 输出接口（PBM Passthrough）
  - 添加 S2MM/MM2S 实例化
  - 添加 Loopback Mux 逻辑（3 种模式）
  - AXI Master 接口多路复用（Fetcher / S2MM / DMA）

### 4. 测试台
- **S2MM/MM2S 测试**: `D:\FPGAhanjia\Hetero_SoC_2026\tb\tb_dma_s2mm_mm2s.sv`
- **Loopback 测试**: `D:\FPGAhanjia\Hetero_SoC_2026\tb\tb_dma_loopback.sv`

## CSR 寄存器映射（更新）

| 地址 | 名称 | 功能 |
|------|------|------|
| 0x00 | Control | Bit 0: DMA Start<br>Bit 1: HW Init<br>Bit 2: Algo Sel<br>**Bit 4: S2MM Enable**<br>**Bit 5: MM2S Enable** |
| 0x04 | Status | Bit 0: Done<br>Bit 1: Error |
| 0x08 | Base Addr | DMA 某地址 |
| 0x0C | Length | DMA 长度 |
| **0x20** | **S2MM Addr** | **S2MM 目标地址** |
| **0x24** | **S2MM Data** | **S2MM 数据** |
| 0x28-0x34 | Keys | 加密密钥（已移动） |
| 0x40 | Cache | 缓存控制 |
| 0x44 | ACL Count | ACL 计数 |
| **0x48** | **Loopback Mode** | **Bit[1:0]: 00=Normal, 01=DDR Loopback, 10=PBM Passthrough** |
| 0x50 | Ring Base | 环基地址 |
| 0x54 | Ring Head | 硬件头指针 |
| 0x58 | Ring Tail | 软件尾指针 |
| 0x5C | Ring Size | 环大小 |

## Vivado 集成步骤

### 步骤 1: 在 Vivado 项目中添加文件

#### 添加 S2MM/MM2S Engine
1. 在 Vivado GUI 中打开项目
2. 右键点击 `Design Sources` → `Add Sources`
3. 选择 `D:\FPGAhanjia\Hetero_SoC_2026\rtl\core\dma\dma_s2mm_mm2s_engine.sv`
4. 选择 "Copy into project"
5. 在 `Design Sources` 中找到该文件，右键选择 "Add to simulation sourceset"

#### 添加测试台
1. 右键点击 `Simulation Sources` → `Add Sources`
2. 选择 `D:\FPGAhanjia\Hetero_SoC_2026\tb\tb_dma_s2mm_mm2s.sv`
3. 选择 "Copy into project"
4. 设置为顶层测试台：
   - 右键点击该文件 → "Set as Top"
   - 或者在 Vivado Tcl Console 运行：`set_property top tb_dma_s2mm_mm2s [get_filesets -filter {sim_1} -top]`

5. 重复步骤 2-4 添加 `tb_dma_loopback.sv`

### 步骤 2: 编译项目

1. 在 Vivado Tcl Console 运行：
   ```tcl
   update_compile_order -fileset sim_1 -top
   launch_simulation
   ```

## 运行测试

### 测试 1: S2MM/MM2S 功能测试

1. **在 Vivado 中运行**:
   - 右键点击 `tb_dma_s2mm_mm2s.sv` → "Run Simulation"
   - 或者在 Tcl Console 运行：
     ```tcl
     launch_simulation
     ```

2. **预期输出**:
   ```
   [TB] ========================================================
   [TB] Test 1: 配置 S2MM/MM2S
   [TB] ========================================================
   [TB] Write CSR Addr: 00000020, Data: 20000000
   [TB] Write CSR Addr: 00000024, Data: 12345678
   [TB] Write CSR Addr: 00000000, Data: 00000020
   [TB] ========================================================
   [TB] Test 2: 测试 MM2S（读取 S2MM 数据寄存器）
   [TB] ========================================================
   [TB] Read CSR Addr: 00000024, Data: 12345678
   ```

3. **验证点**:
   - [ ] S2MM 地址配置正确
   - [ ] S2MM 数据写入正确
   - [ ] MM2S 读取数据正确

### 测试 2: Loopback 模式测试

1. **在 Vivado 中运行**:
   - 右键点击 `tb_dma_loopback.sv` → "Run Simulation"
   - 或设置该测试台为顶层后运行仿真

2. **预期输出**:
   ```
   [TB] ========================================================
   [TB] Test 1: 配置 DMA (Normal 模式)
   [TB] ========================================================
   [TB] PBM Write: Data=DEADCAFE, Last=0
   ...
   [TB] DMA Write to DDR: Addr=20000000, Data=XXXXXXXX
   ```

3. **验证点**:
   - [ ] Normal 模式：PBM → Crypto → DMA → DDR
   - [ ] DDR Loopback 模式：DDR → Crypto → DMA → DDR（暂不支持）
   - [ ] PBM Passthrough 模式：PBM → Crypto → TX 输出

## 常见问题排查

### 问题 1: 编译错误
**症状**: Vivado 报告语法错误或找不到模块
**解决**:
- 检查所有文件是否正确添加到仿真源集
- 运行 `update_compile_order -fileset sim_1`
- 确认顶层模块设置正确

### 问题 2: 仿真超时
**症状**: 测试台在等待信号时超时
**解决**:
- 在波形窗口查看关键信号：
  ```tcl
  add_wave /tb_dma_s2mm_mm2s/u_dut/state
  add_wave /tb_dma_s2mm_mm2s/u_dut/loopback_mode
  ```
- 检查状态机是否正确跳转
- 检查寄存器读写是否成功

### 问题 3: AXI 握手失败
**症状**: AXI valid/ready 信号无法握手
**解决**:
- 检查地址对齐（必须是 4 字节对齐）
- 检查 AXI 协议信号时序
- 在波形窗口查看 valid/ready 信号

## 完成标准

✅ **验证清单**：

- [ ] CSR 模块编译无错误
- [ ] S2MM/MM2S Engine 编译无错误
- [ ] DMA 子系统编译无错误
- [ ] 测试台编译无错误
- [ ] S2MM/MM2S 仿真通过
- [ ] Loopback 模式 Normal 测试通过
- [ ] Loopback 模式 PBM Passthrough 测试通过
- [ ] Vivado 综合（Synthesis）无警告或只有可忽略的警告

## 日志记录

### 编译日志位置
- Xilinx 日志: `D:\FPGAhanjia\Hetero_SoC_2026\HCS_SOC.runs\`

### 仿真日志位置
- 仿真输出: `D:\FPGAhanjia\Hetero_SoC_2026\HCS_SOC.sim\sim_1\behav\xsim\`

### 调试建议

1. **使用波形窗口**:
   - Vivado 会自动打开波形窗口
   - 添加关键信号到波形窗口：
     - CSR 寄存器：`reg_ctrl`, `reg_s2mm_addr`, `reg_s2mm_data`, `reg_loopback_mode`
     - S2MM/MM2S 状态机：`state`, `s2mm_awvalid`, `mm2s_en`
     - DMA 子系统：`loopback_mode`, `dma_awvalid`

2. **使用 $display 输出**:
   - 查看 Tcl Console 的文本输出
   - 跟踪状态机转换和数据流

3. **逐步调试**:
   - 先测试 S2MM/MM2S 功能
   - 确认通过后再测试 Loopback 模式
   - 最后测试完整的数据流

## 下一步

1. 将新文件添加到 Vivado 项目
2. 运行仿真测试 S2MM/MM2S 功能
3. 运行仿真测试 Loopback 模式
4. 查看波形验证数据流
5. 解决发现的问题
6. 所有测试通过后进行硬件验证
