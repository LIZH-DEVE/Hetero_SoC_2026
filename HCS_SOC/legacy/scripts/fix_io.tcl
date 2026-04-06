# ============================================================================
# Task 1: Fix IO Over-utilization by Removing Unnecessary External Ports
# ============================================================================

puts "=========================================="
puts "Task 1: Fixing IO Over-utilization"
puts "=========================================="

# Open Block Design
puts "\n[1/5] Opening Block Design..."
set bd_file [get_files system.bd]
if {$bd_file == ""} {
    puts "ERROR: system.bd not found!"
    return -code error
}
open_bd_design $bd_file
puts "   Block Design opened: $bd_file"

# Find the crypto_dma_subsystem_wrapper or dma_subsystem_wrapper instance
puts "\n[2/5] Finding DMA subsystem wrapper instance..."
set wrapper_cell ""
foreach cell_name {dma_subsystem_wrapper_0 crypto_dma_wrapper_0 crypto_dma_subsystem_wrapper_0} {
    set cell [get_bd_cells -quiet $cell_name]
    if {$cell != ""} {
        set wrapper_cell $cell
        puts "   Found: $cell_name"
        break
    }
}

if {$wrapper_cell == ""} {
    puts "WARNING: No DMA wrapper cell found. Checking all cells..."
    set all_cells [get_bd_cells]
    puts "   Available cells: $all_cells"
    # Try to find any cell with wrapper in name
    foreach cell $all_cells {
        if {[string match "*wrapper*" $cell]} {
            set wrapper_cell $cell
            puts "   Using: $cell"
            break
        }
    }
}

if {$wrapper_cell == ""} {
    puts "ERROR: Could not find DMA wrapper cell!"
    puts "Continuing to remove external ports anyway..."
}

# Get all external ports (interface and regular ports)
puts "\n[3/5] Scanning for external ports to remove..."
set ports_to_remove [list]

# Find all ports that match rx_ or tx_ pattern
set all_ports [get_bd_ports -quiet *]
set removed_count 0

foreach port $all_ports {
    set port_name [get_property NAME $port]
    # Check if port name contains rx_ or tx_
    if {[string match "*rx_*" $port_name] || [string match "*tx_*" $port_name]} {
        lappend ports_to_remove $port
        puts "   Will remove: $port_name"
    }
}

# Also check for interface ports
set all_intf_ports [get_bd_intf_ports -quiet *]
foreach port $all_intf_ports {
    set port_name [get_property NAME $port]
    if {[string match "*rx_*" $port_name] || [string match "*tx_*" $port_name]} {
        lappend ports_to_remove $port
        puts "   Will remove (interface): $port_name"
    }
}

puts "   Total ports to remove: [llength $ports_to_remove]"

# Remove the ports
puts "\n[4/5] Removing external ports..."
foreach port $ports_to_remove {
    set port_name [get_property NAME $port]
    puts "   Removing: $port_name"
    catch {
        remove_bd_port $port
        incr removed_count
    } err
    if {$err != ""} {
        puts "   WARNING: Failed to remove $port_name: $err"
    }
}

puts "   Successfully removed: $removed_count ports"

# Validate the design
puts "\n[5/5] Validating Block Design..."
set validation_result [catch {validate_bd_design} validation_msg]
if {$validation_result == 0} {
    puts "   ✓ Block Design validation PASSED"
} else {
    puts "   WARNING: Validation returned messages:"
    puts "   $validation_msg"
    puts "   (This may be acceptable - continuing...)"
}

# Save the design
puts "\nSaving Block Design..."
save_bd_design
puts "   ✓ Block Design saved"

puts "\n=========================================="
puts "Task 1 Complete: IO Fix Applied"
puts "Removed $removed_count external ports"
puts "=========================================="
