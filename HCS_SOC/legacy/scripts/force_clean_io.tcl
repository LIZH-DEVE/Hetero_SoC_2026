# ============================================================================
# Force Clean IO - Aggressive External Port Removal
# ============================================================================
# This script removes ALL external ports except whitelisted ones
# to fix IO over-utilization issues
# ============================================================================

puts "\n============================================"
puts "  FORCE CLEAN IO - Aggressive Mode"
puts "============================================"
puts "This will remove ALL external ports except:"
puts "  - DDR"
puts "  - FIXED_IO"
puts "  - Ports containing 'clk' or 'clock'"
puts "  - Ports containing 'rst' or 'reset'"
puts "============================================\n"

# ============================================================================
# Step 1: Open Block Design
# ============================================================================
puts "[1/7] Opening Block Design..."
set bd_file [get_files system.bd]
if {$bd_file == ""} {
    puts "ERROR: system.bd not found!"
    return -code error "Block Design not found"
}
open_bd_design $bd_file
puts "   ✓ Block Design opened: $bd_file"

# ============================================================================
# Step 2: Define Whitelist Function
# ============================================================================
proc is_whitelisted {port_name} {
    # Convert to lowercase for case-insensitive matching
    set name_lower [string tolower $port_name]

    # Whitelist patterns
    set whitelist_patterns {
        "ddr"
        "fixed_io"
        "clk"
        "clock"
        "rst"
        "reset"
    }

    foreach pattern $whitelist_patterns {
        if {[string match "*${pattern}*" $name_lower]} {
            return 1
        }
    }

    return 0
}

# ============================================================================
# Step 3: Collect All External Ports
# ============================================================================
puts "\n[2/7] Scanning all external ports..."

# Get regular ports
set all_ports [get_bd_ports -quiet *]
set all_intf_ports [get_bd_intf_ports -quiet *]

puts "   Found [llength $all_ports] regular ports"
puts "   Found [llength $all_intf_ports] interface ports"

# ============================================================================
# Step 4: Categorize Ports (Whitelist vs Remove)
# ============================================================================
puts "\n[3/7] Categorizing ports..."

set ports_to_keep [list]
set ports_to_remove [list]
set intf_ports_to_keep [list]
set intf_ports_to_remove [list]

# Process regular ports
foreach port $all_ports {
    set port_name [get_property NAME $port]
    if {[is_whitelisted $port_name]} {
        lappend ports_to_keep $port_name
    } else {
        lappend ports_to_remove $port
    }
}

# Process interface ports
foreach port $all_intf_ports {
    set port_name [get_property NAME $port]
    if {[is_whitelisted $port_name]} {
        lappend intf_ports_to_keep $port_name
    } else {
        lappend intf_ports_to_remove $port
    }
}

puts "\n   === WHITELIST (Will Keep) ==="
puts "   Regular ports to keep: [llength $ports_to_keep]"
foreach name $ports_to_keep {
    puts "      ✓ $name"
}
puts "   Interface ports to keep: [llength $intf_ports_to_keep]"
foreach name $intf_ports_to_keep {
    puts "      ✓ $name"
}

puts "\n   === TO BE REMOVED ==="
puts "   Regular ports to remove: [llength $ports_to_remove]"
puts "   Interface ports to remove: [llength $intf_ports_to_remove]"

# ============================================================================
# Step 5: Remove Regular Ports
# ============================================================================
puts "\n[4/7] Removing regular external ports..."
set removed_regular_count 0

foreach port $ports_to_remove {
    set port_name [get_property NAME $port]
    puts "   Removing: $port_name"
    set result [catch {
        remove_bd_port $port
        incr removed_regular_count
    } err]

    if {$result != 0} {
        puts "      WARNING: Failed to remove $port_name: $err"
    }
}

puts "   ✓ Removed $removed_regular_count regular ports"

# ============================================================================
# Step 6: Remove Interface Ports
# ============================================================================
puts "\n[5/7] Removing interface external ports..."
set removed_intf_count 0

foreach port $intf_ports_to_remove {
    set port_name [get_property NAME $port]
    puts "   Removing: $port_name"
    set result [catch {
        remove_bd_intf_port $port
        incr removed_intf_count
    } err]

    if {$result != 0} {
        puts "      WARNING: Failed to remove $port_name: $err"
    }
}

puts "   ✓ Removed $removed_intf_count interface ports"

# ============================================================================
# Step 7: Validate and Save Design
# ============================================================================
puts "\n[6/7] Validating Block Design..."
set validation_result [catch {validate_bd_design} validation_msg]

if {$validation_result == 0} {
    puts "   ✓ Block Design validation PASSED"
} else {
    puts "   WARNING: Validation messages:"
    puts "   $validation_msg"
    puts "   (Continuing anyway...)"
}

puts "\n[7/7] Saving Block Design..."
save_bd_design
puts "   ✓ Block Design saved"

# ============================================================================
# Summary
# ============================================================================
puts "\n============================================"
puts "  IO Cleanup Complete!"
puts "============================================"
puts "Total ports removed: [expr $removed_regular_count + $removed_intf_count]"
puts "  - Regular ports: $removed_regular_count"
puts "  - Interface ports: $removed_intf_count"
puts "Total ports kept: [expr [llength $ports_to_keep] + [llength $intf_ports_to_keep]]"
puts "  - Regular ports: [llength $ports_to_keep]"
puts "  - Interface ports: [llength $intf_ports_to_keep]"
puts "============================================\n"

# ============================================================================
# Step 8: Immediate Rebuild
# ============================================================================
puts "\n============================================"
puts "  Starting Immediate Rebuild"
puts "============================================"

# Reset Block Design outputs
puts "\n[1/5] Resetting Block Design outputs..."
reset_target all $bd_file
puts "   ✓ Reset complete"

# Generate all outputs
puts "\n[2/5] Generating Block Design outputs..."
generate_target all $bd_file
export_ip_user_files -of_objects $bd_file -no_script -sync -force -quiet
puts "   ✓ Generation complete"

# Reset synthesis run
puts "\n[3/5] Resetting synthesis run..."
reset_run synth_1
puts "   ✓ Synthesis reset"

# Launch synthesis
puts "\n[4/5] Launching synthesis (8 jobs)..."
launch_runs synth_1 -jobs 8
puts "   Waiting for synthesis to complete..."
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]
puts "   Synthesis Status: $synth_status ($synth_progress)"

if {![string match "*Complete*" $synth_status] && ![string match "*100%*" $synth_progress]} {
    puts "   ✗ Synthesis FAILED"
    puts "   Check logs: [get_property DIRECTORY [get_runs synth_1]]/runme.log"
    return -code error "Synthesis failed"
}
puts "   ✓ Synthesis PASSED"

# Launch implementation and bitstream
puts "\n[5/5] Launching implementation and bitstream generation (8 jobs)..."
puts "   This may take 10-30 minutes..."
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]

puts "\n============================================"
puts "  BUILD COMPLETE"
puts "============================================"
puts "Implementation Status: $impl_status"
puts "Implementation Progress: $impl_progress"

if {[string match "*Complete*" $impl_status] || [string match "*100%*" $impl_progress]} {
    puts "\n✓✓✓ BITSTREAM GENERATION SUCCESSFUL ✓✓✓"

    # Find bitstream file
    set bit_file "[get_property DIRECTORY [get_runs impl_1]]/system_wrapper.bit"
    if {[file exists $bit_file]} {
        puts "\nBitstream location:"
        puts "   $bit_file"
        puts "   Size: [expr [file size $bit_file] / 1024] KB"
    }

    # Generate reports
    puts "\nGenerating reports..."
    catch {
        open_run impl_1
        report_timing_summary -file timing_summary.rpt
        report_utilization -file utilization.rpt
        puts "   ✓ Reports saved: timing_summary.rpt, utilization.rpt"
    }

} else {
    puts "\n✗✗✗ BUILD FAILED ✗✗✗"
    puts "Check logs:"
    puts "   Synthesis: [get_property DIRECTORY [get_runs synth_1]]/runme.log"
    puts "   Implementation: [get_property DIRECTORY [get_runs impl_1]]/runme.log"
    return -code error "Implementation failed"
}

puts "\n============================================"
puts "  ALL DONE!"
puts "============================================"
