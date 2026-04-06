# Simple UART Debug Script
# Date: 2026-03-15

puts "Step 1: Check MIO config"
puts [mrd 0xF80007C0]
puts [mrd 0xF80007C4]

puts "Step 2: Unlock SLCR"
mwr 0xF8000008 0x0000DF0D

puts "Step 3: Enable UART1 clock"
mwr 0xF800012C 0x016C004D

puts "Step 4: Configure MIO48/49"
mwr 0xF80007C0 0x00001607
mwr 0xF80007C4 0x00001607

puts "Step 5: Lock SLCR"
mwr 0xF8000004 0x0000767B

after 100

puts "Step 6: Configure UART1"
mwr 0xE0001000 0x00000000
after 10
mwr 0xE0001018 0x0000007B
mwr 0xE0001004 0x00000020
mwr 0xE0001000 0x00000014

after 100

puts "Step 7: Verify config"
puts [mrd 0xF80007C0]
puts [mrd 0xF80007C4]
puts [mrd 0xE0001000]

puts "Step 8: Send test char"
mwr 0xE0001030 0x00000041

puts "Step 9: Download and run"
dow "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/BACKUP_UART_WORKING_20260315/crypto_test_app.elf"
con

puts "Done"
