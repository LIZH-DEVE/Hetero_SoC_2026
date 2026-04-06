# 超简化 UART 测试 - 逐行执行
# 请手动复制每行命令到 XSDB 执行

# 步骤 1: 设置 UART1 基地址
set UART1_BASE 0xE0001000

# 步骤 2: 使能 UART 时钟 (解锁 SLCR)
mwr 0xF8000008 0x0000DF0D
mwr 0xF8000154 0x00003F03
mwr 0xF8000004 0x0000767B

# 步骤 3: 配置 UART1
mwr $UART1_BASE 0x00000000
mwr [expr $UART1_BASE + 0x18] 0x0000007B
mwr [expr $UART1_BASE + 0x34] 0x00000006
mwr [expr $UART1_BASE + 0x04] 0x00000020
mwr $UART1_BASE 0x00000014

# 步骤 4: 检查状态
mrd $UART1_BASE
mrd [expr $UART1_BASE + 0x2C]

# 步骤 5: 发送字符
mwr [expr $UART1_BASE + 0x30] 0x00000041
mwr [expr $UART1_BASE + 0x30] 0x00000042
mwr [expr $UART1_BASE + 0x30] 0x00000043
mwr [expr $UART1_BASE + 0x30] 0x0000000A

# 步骤 6: 再次检查状态
mrd [expr $UART1_BASE + 0x2C]
