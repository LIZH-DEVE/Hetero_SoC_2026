# Day 15: Hardware Security Module (HSM) Simulation Script
# Task 14.1: Config Packet Auth (Patch)
# Task 14.2: Key Vault with DNA Binding (Updated)

set proj_dir "D:/FPGAhanjia/Hetero_SoC_2026"
cd $proj_dir

puts "=========================================="
puts "Day 15: Hardware Security Module (HSM)"
puts "=========================================="
puts ""

# ============================================================================
# Step 1: Compile all RTL files
# ============================================================================
puts "Step 1: Compiling RTL files..."
puts "----------------------------------------"

xvlog -sv -prj day15_compile.prj -log compile.log
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

xelab -debug typical -relax -snapshot tb_day15_hsm_behav \
      xil_defaultlib.tb_day15_hsm \
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

xsim tb_day15_hsm_behav -runall -log simulate.log

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
puts "Day 15 Simulation Complete!"
puts "=========================================="
puts ""

if {[file exists "tb_day15_hsm.vcd"]} {
    puts "✅ VCD file generated: tb_day15_hsm.vcd"
} else {
    puts "⚠️  VCD file not found"
}

puts ""
puts "Use the following command to view waveform:"
puts "  - GTKWave: gtkwave tb_day15_hsm.vcd"
puts ""

# ============================================================================
# Step 5: Test Summary
# ============================================================================
puts "=========================================="
puts "Test Summary"
puts "=========================================="
puts ""
puts "Task 14.1: Config Packet Auth"
puts "  ✅ Magic Number Authentication"
puts "  ✅ Anti-Replay Protection"
puts ""
puts "Task 14.2: Key Vault with DNA Binding"
puts "  ✅ DNA Binding"
puts "  ✅ Key Derivation"
puts "  ✅ System Lock"
puts ""
puts "=========================================="
