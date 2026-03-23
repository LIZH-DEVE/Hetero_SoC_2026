connect
targets -set -nocase -filter {name =~ "arm*#0"}
puts "===== CPU PC Registry ====="
rrd pc
puts "===== UART Status (Tx Status) ====="
mrd 0xE000102C
puts "===== Crypto Status ====="
mrd -force 0x43C00000 4
puts "===== First Instructions ====="
mrd -force 0x00100000 4
