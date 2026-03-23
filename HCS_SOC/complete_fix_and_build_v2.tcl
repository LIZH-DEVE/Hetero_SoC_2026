# ============================================================
# COMPLETE FIX AND BUILD - V2
# Uses robust top module fix + full build
# ============================================================

puts "\n============================================"
puts "  COMPLETE FIX AND BUILD (V2)"
puts "============================================"
puts "Enhanced workflow with robust wrapper search"
puts "============================================\n"

# ============================================================
# Step 1: Fix Top Module (V2)
# ============================================================
puts ">>> STEP 1: Fixing Top Module (Enhanced)"
puts "============================================\n"

# Get the directory of this script
set script_dir [file dirname [info script]]
source "${script_dir}/fix_top_module_v2.tcl"

# Verify success before continuing
set current_top [get_property top [current_fileset]]
if {$current_top ne "system_wrapper"} {
    puts "\nERROR: Top module fix failed!"
    puts "Cannot proceed with build."
    return -code error "Top module is not system_wrapper"
}

puts "\n✓ Top module fix successful, proceeding with build..."
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
    puts "WARNING: Block Design file not found, skipping regeneration"
}

# ============================================================
# Step 3: Reset Runs
# ============================================================
puts "\n>>> STEP 3: Resetting Runs"
puts "============================================\n"

puts "Resetting synthesis run..."
reset_run synth_1

puts "Resetting implementation run..."
reset_run impl_1

puts "✓ Runs reset complete"

# ============================================================
# Step 4: Launch Synthesis
# ============================================================
puts "\n>>> STEP 4: Launching Synthesis"
puts "============================================\n"

puts "Starting synthesis (8 jobs)..."
launch_runs synth_1 -jobs 8
puts "Waiting for synthesis to complete..."
puts "(This typically takes 5-15 minutes)"

wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]

puts "\nSynthesis Results:"
puts "   Status: $synth_status"
puts "   Progress: $synth_progress"

if {![string match "*Complete*" $synth_status] && ![string match "*100%*" $synth_progress]} {
    puts "\n✗ Synthesis FAILED"
    set synth_log "[get_property DIRECTORY [get_runs synth_1]]/runme.log"
    puts "Check log: $synth_log"
    return -code error "Synthesis failed"
}

puts "✓ Synthesis PASSED"

# ============================================================
# Step 5: Launch Implementation
# ============================================================
puts "\n>>> STEP 5: Launching Implementation"
puts "============================================\n"

puts "Starting implementation and bitstream generation (8 jobs)..."
puts "This includes:"
puts "   - Opt Design"
puts "   - Place Design"
puts "   - Route Design"
puts "   - Write Bitstream"
puts "\n(This typically takes 15-30 minutes)"

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]

# ============================================================
# Step 6: Final Report
# ============================================================
puts "\n============================================"
puts "  BUILD COMPLETE"
puts "============================================"
puts "Implementation Status: $impl_status"
puts "Implementation Progress: $impl_progress"
puts "============================================\n"

if {[string match "*Complete*" $impl_status] || [string match "*100%*" $impl_progress]} {
    puts "✓✓✓ BITSTREAM GENERATION SUCCESSFUL ✓✓✓\n"

    # Locate bitstream file
    set impl_dir [get_property DIRECTORY [get_runs impl_1]]
    set bit_file "${impl_dir}/system_wrapper.bit"

    if {[file exists $bit_file]} {
        set bit_size [expr [file size $bit_file] / 1024]
        puts "Bitstream Information:"
        puts "   Location: $bit_file"
        puts "   Size: ${bit_size} KB"
        puts ""
    } else {
        puts "WARNING: Bitstream file not found at expected location"
        puts "   Expected: $bit_file"
    }

    # Generate reports
    puts "Generating reports..."
    set report_result [catch {
        open_run impl_1

        report_timing_summary -file timing_summary.rpt
        report_utilization -file utilization.rpt
        report_io -file io_report.rpt
        report_drc -file drc_report.rpt

        puts "   ✓ Reports generated:"
        puts "      - timing_summary.rpt"
        puts "      - utilization.rpt"
        puts "      - io_report.rpt"
        puts "      - drc_report.rpt"
    } report_err]

    if {$report_result != 0} {
        puts "   WARNING: Some reports failed to generate: $report_err"
    }

    # Show timing summary
    puts "\n--- Quick Timing Summary ---"
    catch {
        set wns [get_property STATS.WNS [get_runs impl_1]]
        set tns [get_property STATS.TNS [get_runs impl_1]]
        set whs [get_property STATS.WHS [get_runs impl_1]]
        set ths [get_property STATS.THS [get_runs impl_1]]

        puts "   WNS (Worst Negative Slack): $wns ns"
        puts "   TNS (Total Negative Slack): $tns ns"
        puts "   WHS (Worst Hold Slack): $whs ns"
        puts "   THS (Total Hold Slack): $ths ns"

        if {$wns >= 0 && $whs >= 0} {
            puts "   ✓ Timing constraints MET"
        } else {
            puts "   ✗ Timing constraints VIOLATED"
        }
    }

} else {
    puts "✗✗✗ BUILD FAILED ✗✗✗\n"

    set synth_log "[get_property DIRECTORY [get_runs synth_1]]/runme.log"
    set impl_log "[get_property DIRECTORY [get_runs impl_1]]/runme.log"

    puts "Check logs:"
    puts "   Synthesis: $synth_log"
    puts "   Implementation: $impl_log"

    return -code error "Implementation failed"
}

puts "\n============================================"
puts "  ALL TASKS COMPLETE!"
puts "============================================"
