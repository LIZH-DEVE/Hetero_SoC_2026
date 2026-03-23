# ============================================================
# 完整修复版 — 新增 FPU/VFP 使能，解决 Undefined Instruction 异常
# PC=0x100004 = UndefinedException handler → FPU 指令在 VFP 使能前执行
# ============================================================
puts "========== 上电初始化 (含 FPU 修复) =========="

# [1] 连接
puts "\n[1] 连接..."
connect
targets -set -nocase -filter {name =~ "arm*#0"}

# [2] 编程 FPGA
puts "\n[2] 编程 FPGA..."
fpga -f D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit

# [3] PS 初始化
puts "\n[3] PS 初始化..."
source D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/platform/hw/ps7_init.tcl
ps7_init
ps7_post_config
after 200

# [4] UART 时钟修复 (APER + CLK_CTRL + MIO)
puts "\n[4] 使能 UART 时钟..."
mwr -force 0xF8000008 0x0000DF0D
mwr -force 0xF800012C [expr {[mrd -value 0xF800012C] | 0x00300000}]
mwr -force 0xF8000154 0x00001003
mwr -force 0xF80007C0 0x000016E0
mwr -force 0xF80007C4 0x000016E1
mwr -force 0xF8000738 0x000016E0
mwr -force 0xF800073C 0x000016E1
mwr -force 0xF8000004 0x0000767B
after 50

# [5] 初始化 UART1 — 100MHz, BRGR=124, BDIV=6
puts "\n[5] 初始化 UART1..."
mwr 0xE0001000 0x00000003
after 20
mwr 0xE0001004 0x00000020
mwr 0xE0001018 124
mwr 0xE000101C 6
mwr 0xE0001000 0x00000114
after 20
puts [format "    SR=0x%08x BRGR=%d" [mrd -value 0xE000102C] [mrd -value 0xE0001018]]

# [6] 下载 ELF (先不 con)
puts "\n[6] 下载 ELF..."
dow D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/build/crypto_test_app.elf

# [7] ★ 关键修复: 在 CPU 运行前手动使能 VFP/FPU ★
# Cortex-A9 默认 FPU 关闭，若 BSP crt0 �� VFP 指令会触发 Undefined Instruction
# CPACR: 设置 CP10/CP11 = 11 (Full access)
puts "\n[7] 使能 VFP/FPU (避免 Undefined Instruction @ 0x100004)..."
# 写 CPACR: 让 CP10(bit21:20)=11, CP11(bit23:22)=11 → 0x00F00000
mwr -force 0xF8F02000 0x00F00000   ;# CPUECTLR (尝试通过 SCU 访问)

# 通过写寄存器方式使能 (XSDB writereg 方式)
# 使用 XSDB 的 mwr 无法直接写协处理器寄存器
# 改用: 在 PC 处注入使能 FPU 的代码片段
# 方案：在 DDR 空闲区写一小段 FPU 使能代码，跳转执行后再跳回 main 入口
puts "    注入 FPU 使能代码到 0x10F000..."
# ARM 指令: MRC p15,0,R0,c1,c0,2 → ORR R0,R0,#(0xF<<20) → MCR p15,0,R0,c1,c0,2 → ISB
# FMRX R0,FPEXC → ORR R0,R0,#(1<<30) → FMXR FPEXC,R0
# 最后: BX 到 ELF 入口 0x100000

# 指令 (Little Endian ARM 32-bit):
# E10F0F10 = MRC p15,0,r0,c1,c0,2  (读 CPACR)
# E3800A0F = ORR r0,r0,#(0xF<<20)  (使能CP10/CP11)
# E0CF0F10 = MCR p15,0,r0,c1,c0,2  (写 CPACR)
# F57FF06F = ISB
# EEF10A10 = VMRS r0,FPEXC          (读 FPEXC)
# E3800201 = ORR r0,r0,#(1<<30)     (使能 FPU EN 位)
# EEE10A10 = VMSR FPEXC,r0          (写 FPEXC)
# E3A00000 = MOV r0,#0
# E59FF000 = LDR PC,[PC,#0]         (跳到 ELF 入口)
# 00100000 = 0x00100000 (ELF 入口地址)

mwr 0x0010F000 0xE10F0F10
mwr 0x0010F004 0xE3800A0F
mwr 0x0010F008 0xEE010F10
mwr 0x0010F00C 0xF57FF06F
mwr 0x0010F010 0xEEF10A10
mwr 0x0010F014 0xE3800201
mwr 0x0010F018 0xEEE10A10
mwr 0x0010F01C 0xE59FF000
mwr 0x0010F020 0x00100000

# 设置 PC 跳到我们注入的代码
rwr pc 0x0010F000

puts "    PC 已设置到 FPU 使能代码 @ 0x10F000"
puts "    执行后将自动跳入 ELF 入口 0x100000"

# [8] 直写 HELLO 测试
puts "\n[8] 直写 'HELLO' 到 UART1..."
foreach b {0x48 0x45 0x4C 0x4C 0x4F 0x0D 0x0A} { mwr 0xE0001030 $b }
after 300

# [9] 启动
puts "\n[9] 运行 (含 FPU 使能)..."
con

puts "\n✓ 完成！PuTTY 应出现 HELLO 然后 ABC + banner"
puts "  若仍只有 HELLO → 贴出 'mrd 0x100000 8' 的结果"
puts "============================================="
