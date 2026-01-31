# Hetero_SoC_2026: 异构加解密 SoC 开发实战

本项目记录了从金融工程向集成电路（IC）转型的深度进阶过程。目标是构建一个基于 FPGA 的高性能硬件加解密系统。

## 项目概述

**项目名称**: Hetero_SoC_2026  
**项目类型**: 智能网卡（SmartNIC）硬件加速加解密系统  
**开发平台**: Xilinx Zynq-7000 SoC  
**开发工具**: Vivado 2024.1, Vitis SDK  
**开发语言**: SystemVerilog, Verilog, C/C++, Python

## 项目结构

```
Hetero_SoC_2026/
├── rtl/                    # RTL源代码
│   ├── core/              # 核心模块
│   │   ├── crypto/        # 加密引擎（AES/SM4）
│   │   ├── dma/           # DMA引擎
│   │   ├── parser/        # 协议解析（RX/TX）
│   │   ├── tx/            # TX栈
│   │   └── pbm/           # 包缓冲管理
│   ├── security/          # 安全模块（HSM/ACL）
│   ├── flow/              # 流控模块
│   ├── if/                # 接口定义（AXI/AXI-Stream）
│   ├── inc/               # 包文件（pkg_axi_stream等）
│   ├── display/           # 显示模块
│   └── top/               # 顶层模块
├── tb/                    # 测试平台
├── sim/                   # 仿真相关
├── scripts/               # 构建和验证脚本
├── constraints/           # 约束文件（时序/引脚/ILA）
├── doc/                   # 文档（验证报告/优化报告）
├── sw/                    # 软件驱动
├── logs/                  # 运行日志
├── logs_backup/           # 备份日志
├── sim_build/             # 仿真构建产物
├── HCS_SOC/              # Vivado工程
└── crypto_test_app/      # 测试应用
```

## 核心功能

### Phase 1: 协议立法与总线基座 (Day 2-4)
- ✅ AXI4总线接口与拆包逻辑
- ✅ 4K边界自动拆包
- ✅ Burst限制（256 beats）
- ✅ 对齐错误检测

### Phase 2: 极速算力引擎 (Day 5-8)
- ✅ AES-128-CBC加密
- ✅ SM4-CBC加密（国密）
- ✅ CBC链式异或
- ✅ 双核并联
- ✅ 流控机制

### Phase 3: 智能网卡子系统 (Day 9-14)
- ✅ Ethernet帧解析
- ✅ IP/UDP协议解析
- ✅ ARP响应
- ✅ Checksum硬件计算
- ✅ 包缓冲管理（PBM）
- ✅ DMA子系统

### Phase 4: 独家高级特性与交付 (Day 15-21)
- ✅ 硬件安全模块（HSM）
  - Config包认证
  - Key Vault（DNA绑定防克隆）
- ✅ 硬件防火墙（ACL）
  - 五元组提取
  - 2-way Set Associative匹配
- ✅ 零拷贝快速通道（FastPath）
- ✅ 性能优化
  - Burst效率优化
  - Outstanding（Depth 4）
- ✅ 时序收敛
  - 流水线切割
  - CDC约束
  - Pblock物理区域约束
- ✅ ILA调试验证

## 技术亮点

1. **DNA绑定防克隆** - 利用FPGA芯片DNA实现硬件级别的防盗版
2. **2-way Set Associative ACL** - 抗碰撞的访问控制列表设计
3. **4K边界自动拆包** - 自动处理AXI总线的跨4K边界传输
4. **原子化PBM回滚** - 确保包缓冲管理的原子性和一致性
5. **Checksum硬件计算** - 硬件加速IP/UDP校验和计算
6. **零拷贝快速通道** - FastPath实现零拷贝传输，提升性能
7. **双商密支持** - 同时支持AES和SM4两种国密算法
8. **CDC安全处理** - 正确的跨时钟域处理，使用Gray code同步

## 开发进度索引

| 阶段 | 日期 | 核心任务 | 状态 | 详细技术日志 |
| :--- | :--- | :--- | :--- | :--- |
| **Day 1** | 2026-01-21 | AXI4 接口定义与 Git 环境闭环 | ✅ 已归档 | [查看 Day 1 日志](./doc/daily_logs/Day01.md) |
| **Day 2** | 2026-01-22 | 异步 FIFO 设计与格雷码同步 | ✅ 已归档 | [查看 Day 2 日志](./doc/daily_logs/Day02.md) |
| **Day 3** | 2026-01-23 | AXI4-Full 总线之王：4K 拆包与 Burst 逻辑 | ✅ 已归档 | [查看 Day 3 日志](./doc/daily_logs/Day03.md) |
| **Day 4** | 2026-01-24 | Core-Shell 架构封装与 SoC 拓扑闭合 | ✅ 已归档 | [查看 Day 4 日志](./doc/daily_logs/Day04.md) |
| **Day 5** | 2026-01-26 | 双商密引擎集成：AES/SM4 切换 | ✅ 已归档 | [查看 Day 5 日志](./doc/daily_logs/Day05.md) |
| **Day 6** | 2026-01-27 | 系统集成与 CDC：FIFO/Gearbox/DMA | ✅ 已归档 | [查看 Day 6 日志](./doc/daily_logs/Day06.md) |
| **Day 7** | 2026-01-28 | 双核分发器与自动化仿真验证 | ✅ 已归档 | [查看 Day 7 日志](./doc/daily_logs/Day07.md) |
| **Day 8** | 2026-01-28 | 统一包缓冲管理 (PBM) 与原子回滚机制 | ✅ 已归档 | [查看 Day 8 日志](./doc/daily_logs/Day08.md) |
| **Day 9** | 2026-01-29 | 协议感知解析器 (RX Parser) 与安检回滚 | ✅ 已归档 | [查看 Day 9 日志](./doc/daily_logs/Day09.md) |
| **Day 10** | 2026-01-30 | 全硬件 TX 发送栈与协议回显 (Echo) | ✅ 已归档 | [查看 Day 10 日志](./doc/daily_logs/Day10.md) |
| **Day 11** | 2026-01-30 | 描述符环形缓冲管理与加解密子系统闭环集成 | ✅ 已归档 | [查看 Day 11 日志](./doc/daily_logs/Day11.md) |

## 验证报告

| 报告名称 | 内容 | 状态 |
|----------|------|------|
| [Phase 1-4 完成报告](./doc/PHASE_1_4_COMPLETION_REPORT.md) | 所有Phase的功能实现详细说明 | ✅ |
| [完整功能验证报告](./doc/COMPLETE_FUNCTIONAL_VERIFICATION.md) | RTL编译、Elaboration、仿真验证 | ✅ |
| [项目优化报告](./doc/PROJECT_OPTIMIZATION_REPORT.md) | 文件结构优化、部署准备、下一步建议 | ✅ |
| [最终编译报告](./doc/FINAL_COMPILATION_REPORT.md) | 编译验证、BUG修复记录 | ✅ |
| [仿真验证报告](./doc/SIMULATION_VERIFICATION_REPORT.md) | 仿真执行、功能输出验证 | ✅ |
| [部署检查清单](./doc/DEPLOYMENT_CHECKLIST.md) | 部署前检查项和步骤 | ✅ |

## 快速开始

### 1. 环境准备

```bash
# 安装 Xilinx Vivado 2024.1 或更高版本
# 安装 Xilinx Vitis SDK

# 克隆项目
git clone https://github.com/yourusername/Hetero_SoC_2026.git
cd Hetero_SoC_2026
```

### 2. 编译RTL

```bash
# 使用提供的编译脚本
cd scripts
./compile_all.bat

# 或手动编译
vivado -mode batch -source run_compile.tcl
```

### 3. 运行仿真

```bash
# 运行完整功能仿真
cd scripts
./verify_day14.sh

# 运行加密引擎仿真
./COMPREHENSIVE_VERIFICATION.sh
```

### 4. 烧录到开发板

```bash
# 1. 打开Vivado项目
vivado HCS_SOC/HCS_SOC.xpr

# 2. 添加引脚约束
# 编辑 constraints/pin_assignment.xdc

# 3. 运行综合和实现
reset_run synth_1
launch_runs synth_1
wait_on_run synth_1

reset_run impl_1
launch_runs impl_1
wait_on_run impl_1

# 4. 生成比特流
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1

# 5. 烧录到开发板
open_hw_target
create_hw_device [get_hw_devices]
set_property PROGRAM.FILE {HCS_SOC/HCS_SOC.runs/impl_1/HCS_SOC_wrapper.bit} [get_hw_devices]
program_hw_devices [get_hw_devices]
```

## 部署状态

✅ **代码实现** - 100%完成  
✅ **文件结构** - 已优化  
⚠️ **引脚分配** - 需要根据目标开发板完成  
⚠️ **比特流生成** - 需运行综合和实现  
⚠️ **烧录** - 待完成引脚分配和比特流生成后进行

**部署就绪度**: 85%

详细的部署步骤和检查清单，请参考：
- [部署检查清单](./doc/DEPLOYMENT_CHECKLIST.md)
- [项目优化报告](./doc/PROJECT_OPTIMIZATION_REPORT.md)

## 软件驱动

项目包含Linux驱动和Python测试应用：

```bash
# 软件目录
cd sw/

# 查看驱动文档
cat smartnic_driver.py
cat COMPLETE_USER_MANUAL.md
```

## 脚本工具

项目提供多个构建和验证脚本：

- `compile_all.bat` - 批量编译所有RTL模块
- `verify_day14.sh` - 验证Day 14全系统集成
- `verify_day15.sh` - 验证HSM模块
- `verify_day16.sh` - 验证ACL模块
- `gen_vectors.py` - 生成加密测试向量
- `day21_performance_benchmark.py` - 性能基准测试

## 许可证

本项目遵循MIT许可证。

## 贡献指南

欢迎提交Issue和Pull Request。在提交代码前，请确保：
1. 代码通过编译
2. 仿真测试通过
3. 遵循项目的代码风格

## 联系方式

- 项目主页: https://github.com/yourusername/Hetero_SoC_2026
- 问题反馈: https://github.com/yourusername/Hetero_SoC_2026/issues

---

**本项目遵循像素级逻辑验证准则。**
