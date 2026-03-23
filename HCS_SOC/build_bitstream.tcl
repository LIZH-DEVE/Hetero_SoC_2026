# ============================================================================
# Task 2: Force Generate Bitstream (Build Firmware)
# ============================================================================

puts "\n=========================================="
puts "Task 2: Building Bitstream"
puts "=========================================="

# Reset Block Design outputs
puts "\n[1/6] Resetting Block Design outputs..."
set bd_file [get_files system.bd]
if {$bd_file == ""} {
    puts "ERROR: system.bd not found!"
    return -code error
}
reset_target all $bd_file
puts "   ✓ Block Design reset complete"

# Generate all outputs
puts "\n[2/6] Generating Block Design outputs..."
generate_target all $bd_file
puts "   ✓ Block Design outputs generated"

# Export IP user files
puts "\n[3/6] Exporting IP user files..."
export_ip_user_files -of_objects $bd_file -no_script -sync -force -quiet
puts "   ✓ IP user files exported"

# Reset synthesis run
puts "\n[4/6] Resetting synthesis run..."
reset_run synth_1
puts "   ✓ Synthesis run reset"

# Launch synthesis
puts "\n[5/6] Launching synthesis (8 jobs)..."
launch_runs synth_1 -jobs 8
puts "   Synthesis started. Waiting for completion..."
wait_on_run synth_1

# Check synthesis status
set synth_status [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]
puts "   Synthesis Status: $synth_status"
puts "   Synthesis Progress: $synth_progress"

if {[string match "*Complete*" $synth_status] || [string match "*100%*" $synth_progress]} {
    puts "   ✓ Synthesis PASSED"
} else {
    puts "   ✗ Synthesis FAILED or INCOMPLETE"
    puts "   Please check synthesis logs for errors"
    return -code error "Synthesis failed"
}

# Launch implementation and bitstream generation
puts "\n[6/6] Launching implementation and bitstream generation (8 jobs)..."
launch_runs impl_1 -to_step write_bitstream -jobs 8
puts "   Implementation started. Waiting for completion..."
puts "   (This may take 10-30 minutes depending on design complexity)"

# Wait for implementation to complete
wait_on_run impl_1

# Check implementation status
set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]
puts "\n=========================================="
puts "Build Complete!"
puts "=========================================="
puts "Implementation Status: $impl_status"
puts "Implementation Progress: $impl_progress"

if {[string match "*Complete*" $impl_status] || [string match "*100%*" $impl_progress]} {
    puts "\n✓✓✓ BITSTREAM GENERATION SUCCESSFUL ✓✓✓"

    # Find and report bitstream location
    set bit_file [get_property DIRECTORY [get_runs impl_1]]
    append bit_file "/system_wrapper.bit"
    if {[file exists $bit_file]} {
        puts "\nBitstream file location:"
        puts "   $bit_file"
        puts "\nFile size: [file size $bit_file] bytes"
    }

    # Report timing summary
    puts "\n--- Timing Summary ---"
    catch {
        open_run impl_1
        report_timing_summary -file timing_summary.rpt
        puts "Timing report saved to: timing_summary.rpt"
    }

    # Report utilization
    puts "\n--- Resource Utilization ---"
    catch {
        report_utilization -file utilization.rpt
        puts "Utilization report saved to: utilization.rpt"
    }

} else {
    puts "\n✗✗✗ BITSTREAM GENERATION FAILED ✗✗✗"
    puts "\nPlease check the following logs:"
    puts "   - Synthesis log: [get_property DIRECTORY [get_runs synth_1]]/runme.log"
    puts "   - Implementation log: [get_property DIRECTORY [get_runs impl_1]]/runme.log"
    return -code error "Implementation failed"
}

puts "\n=========================================="
