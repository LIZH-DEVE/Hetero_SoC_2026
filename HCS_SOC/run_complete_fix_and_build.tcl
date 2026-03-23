# ============================================================================
# Complete Fix and Build Script
# Combines Task 1 (Fix IO) and Task 2 (Build Bitstream)
# ============================================================================

puts "============================================"
puts "  Complete Fix and Build Workflow"
puts "============================================"
puts "This script will:"
puts "  1. Fix IO over-utilization"
puts "  2. Build complete bitstream"
puts "============================================\n"

# Execute Task 1: Fix IO
puts ">>> Executing Task 1: Fix IO Over-utilization"
source fix_io.tcl

# Small delay to ensure file system sync
after 1000

# Execute Task 2: Build Bitstream
puts "\n>>> Executing Task 2: Build Bitstream"
source build_bitstream.tcl

puts "\n============================================"
puts "  All Tasks Complete!"
puts "============================================"
