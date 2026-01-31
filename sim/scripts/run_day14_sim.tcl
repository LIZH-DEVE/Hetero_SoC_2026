# Day 14 Full Integration Simulation Script
# 验收标准:
# 1. Wireshark抓包
# 2. Payload加密正确
# 3. Checksum正确
# 4. 无Malformed Packet

set proj_dir "D:/FPGAhanjia/Hetero_SoC_2026"
cd $proj_dir

puts "=========================================="
puts "Day 14: Full Integration Simulation"
puts "=========================================="
puts ""

# ============================================================================
# Step 1: Compile all RTL files
# ============================================================================
puts "Step 1: Compiling RTL files..."
puts "----------------------------------------"

# Package files
xvlog -sv -prj day14_compile.prj -log compile.log
if {$::errorCode != 0} {
    puts "ERROR: Compilation failed!"
    exit 1
}
puts "✅ RTL compilation completed"
puts ""

# ============================================================================
# Step 2: Elaborate design
# ============================================================================
puts "Step 2: Elaborating design..."
puts "----------------------------------------"

xelab -debug typical -relax -snapshot tb_day14_full_integration_behav \
      xil_defaultlib.tb_day14_full_integration \
      xil_defaultlib.glbl -log elaborate.log

if {$::errorCode != 0} {
    puts "ERROR: Elaboration failed!"
    exit 1
}
puts "✅ Elaboration completed"
puts ""

# ============================================================================
# Step 3: Run simulation
# ============================================================================
puts "Step 3: Running simulation..."
puts "----------------------------------------"

xsim tb_day14_full_integration_behav -runall -log simulate.log

if {$::errorCode != 0} {
    puts "ERROR: Simulation failed!"
    exit 1
}
puts "✅ Simulation completed"
puts ""

# ============================================================================
# Step 4: Check results
# ============================================================================
puts "=========================================="
puts "Day 14 Simulation Complete!"
puts "=========================================="
puts ""

if {[file exists "tb_day14_full_integration.vcd"]} {
    puts "✅ VCD file generated: tb_day14_full_integration.vcd"
} else {
    puts "⚠️  VCD file not found"
}

if {[file exists "day14_capture.pcap"]} {
    puts "✅ Pcap file generated: day14_capture.pcap"
} else {
    puts "⚠️  Pcap file not found"
}

puts ""
puts "Use the following commands to view results:"
puts "  - GTKWave: gtkwave tb_day14_full_integration.vcd"
puts "  - Wireshark: wireshark day14_capture.pcap"
puts ""
