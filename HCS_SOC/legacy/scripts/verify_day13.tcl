# Vivado Simulation Script for Day 1-13 Verification
# Run from: D:\FPGAhanjia\Hetero_SoC_2026\HCS_SOC

puts "=========================================="
puts "Day 1-13 Verification Simulation"
puts "=========================================="

# Set project directory
set proj_dir "D:/FPGAhanjia/Hetero_SoC_2026/HCS_SOC"
set rtl_dir "D:/FPGAhanjia/Hetero_SoC_2026/rtl"
set tb_dir "D:/FPGAhanjia/Hetero_SoC_2026/tb"

cd $proj_dir

# Open project (suppress GUI)
open_project HCS_SOC.xpr

# Refresh compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "\n\[1\] Checking file compilation..."
puts "=========================================="

# Check key files
set key_files [list \
    "$rtl_dir/core/dma/dma_s2mm_mm2s_engine.sv" \
    "$rtl_dir/top/crypto_dma_subsystem.sv" \
    "$rtl_dir/core/parser/rx_parser.sv" \
    "$rtl_dir/core/axil_csr.sv" \
    "$rtl_dir/core/crypto/crypto_bridge_top.sv" \
]

foreach f $key_files {
    if {[file exists $f]} {
        puts "OK Found: $f"
    } else {
        puts "ERROR Missing: $f"
    }
}

puts "\n\[2\] Checking module names..."
puts "=========================================="

# Check module name in dma_s2mm_mm2s_engine.sv
set fh [open "$rtl_dir/core/dma/dma_s2mm_mm2s_engine.sv" r]
set content [read $fh]
close $fh

if {[regexp {module\s+dma_s2mm_mm2s_engine} $content]} {
    puts "OK Module name: dma_s2mm_mm2s_engine (Correct)"
} else {
    puts "ERROR Module name mismatch!"
}

puts "\n\[3\] Checking key fixes..."
puts "=========================================="

# Check rx_parser alignment
set fh [open "$rtl_dir/core/parser/rx_parser.sv" r]
set content [read $fh]
close $fh

if {[regexp {Alignment check} $content]} {
    puts "OK rx_parser: Alignment check found"
} else {
    puts "ERROR rx_parser: Alignment check NOT found"
}

# Check crypto_dma_subsystem m_axis_wvalid
set fh [open "$rtl_dir/top/crypto_dma_subsystem.sv" r]
set content [read $fh]
close $fh

if {[regexp {m_axis_wvalid\s*=} $content]} {
    puts "OK crypto_dma_subsystem: m_axis_wvalid connection found"
} else {
    puts "ERROR crypto_dma_subsystem: m_axis_wvalid connection MISSING"
}

puts "\n\[4\] Compilation check..."
puts "=========================================="

# Try to compile the design files
puts "Compiling rtl/core/dma/dma_s2mm_mm2s_engine.sv..."
exec "\"D:/Xilinx/Vivado/2024.1/bin/xvlog.exe\" -sv \"$rtl_dir/core/dma/dma_s2mm_mm2s_engine.sv\" 2>@1

puts "\n=========================================="
puts "Verification Complete!"
puts "=========================================="
