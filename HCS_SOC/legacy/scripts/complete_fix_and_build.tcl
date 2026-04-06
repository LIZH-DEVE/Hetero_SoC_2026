# ============================================================
# COMPLETE FIX AND BUILD WORKFLOW
# ============================================================
# This script combines all fixes and builds the bitstream:
# 1. Fix Top Module (system_wrapper)
# 2. Reset and regenerate Block Design
# 3. Build complete bitstream
# ============================================================

puts "\n============================================"
puts "  COMPLETE FIX AND BUILD WORKFLOW"
puts "============================================"
puts "This will:"
puts "  1. Fix Top Module setting"
puts "  2. Regenerate Block Design"
puts "  3. Build complete bitstream"
puts "============================================\n"

# ============================================================
# Step 1: Fix Top Module
# ============================================================
puts ">>> STEP 1: Fixing Top Module"
puts "============================================\n"
source fix_top_module.tcl

# Small delay for file system sync
after 1000

# ============================================================
# Step 2: Regenerate Block Design
# ============================================================
puts "\n>>> STEP 2: Regenerating Block Design"
puts "============================================\n"

set bd_file [get_files *system.bd]
if {$bd_file ne ""} {
    puts "Resetting Block Design targets..."
    reset_target all $bd_file

    puts "Generating Block Design outputs..."
    generate_target all $bd_file

    puts "Exporting IP user files..."
    export_ip_user_files -of_objects $bd_file -no_script -sync -force -quiet

    puts "✓ Block Design regeneration complete"
} else {
    puts "WARNING: Block Design file not found"
}

# ============================================================
# Step 3: Build Bitstream
# ============================================================
puts "\n>>> STEP 3: Building Bitstream"
puts "============================================\n"

# Reset synthesis
puts "[1/4] Resetting synthesis run..."
reset_run synth_1
puts "   ✓ Synthesis reset"

# Launch synthesis
puts "\n[2/4] Launching synthesis (8 jobs)..."
launch_runs synth_1 -jobs 8
puts "   Waiting for synthesis..."
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]
puts "   Status: $synth_status ($synth_progress)"

if {![string match "*Complete*" $synth_status] && ![string match "*100%*" $synth_progress]} {
    puts "   ✗ Synthesis FAILED"
    puts "   Log: [get_property DIRECTORY [get_runs synth_1]]/runme.log"
    return -code error "Synthesis failed"
}
puts "   ✓ Synthesis PASSED"

# Launch implementation
puts "\n[3/4] Launching implementation (8 jobs)..."
launch_runs impl_1 -to_step write_bitstream -jobs 8
puts "   Waiting for implementation and bitstream generation..."
puts "   (This may take 10-30 minutes)"
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]

# ============================================================
# Final Report
# ============================================================
puts "\n============================================"
puts "  BUILD COMPLETE"
puts "============================================"
puts "Implementation Status: $impl_status"
puts "Implementation Progress: $impl_progress"

if {[string match "*Complete*" $impl_status] || [string match "*100%*" $impl_progress]} {
    puts "\n✓✓✓ BITSTREAM GENERATION SUCCESSFUL ✓✓✓"

    # Find bitstream
    set bit_file "[get_property DIRECTORY [get_runs impl_1]]/system_wrapper.bit"
    if {[file exists $bit_file]} {
        puts "\nBitstream file:"
        puts "   Location: $bit_file"
        puts "   Size: [expr [file size $bit_file] / 1024] KB"
    }

    # Generate reports
    puts "\n[4/4] Generating reports..."
    catch {
        open_run impl_1
        report_timing_summary -file timing_summary.rpt
        report_utilization -file utilization.rpt
        report_io -file io_report.rpt
        puts "   ✓ Reports generated:"
        puts "      - timing_summary.rpt"
        puts "      - utilization.rpt"
        puts "      - io_report.rpt"
    }

} else {
    puts "\n✗✗✗ BUILD FAILED ✗✗✗"
    puts "\nCheck logs:"
    puts "   Synthesis: [get_property DIRECTORY [get_runs synth_1]]/runme.log"
    puts "   Implementation: [get_property DIRECTORY [get_runs impl_1]]/runme.log"
    return -code error "Implementation failed"
}

puts "\n============================================"
puts "  ALL TASKS COMPLETE!"
puts "============================================"
