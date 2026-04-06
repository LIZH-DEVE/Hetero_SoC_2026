# Force fix compile order and save project
puts "=== Force Fixing Compile Order ==="

# Close Block Design if open
puts "\n1. Closing Block Design..."
catch {close_bd_design [get_bd_designs system]}

# Set compile order to automatic and save
puts "\n2. Setting compile order to automatic..."
set_property source_mgmt_mode All [current_project]
set_property source_mgmt_mode DisplayOnly [current_project]
set_property source_mgmt_mode All [current_project]

# Save project
puts "\n3. Saving project..."
save_project_as -force HCS_SOC [get_property DIRECTORY [current_project]]

# Check current setting
puts "\n4. Current compile order mode: [get_property source_mgmt_mode [current_project]]"

# List all design files
puts "\n5. Checking dma_subsystem_wrapper.v status..."
set wrapper_files [get_files -filter {NAME =~ "*dma_subsystem_wrapper.v"}]
if {[llength $wrapper_files] > 0} {
    foreach f $wrapper_files {
        puts "   File: $f"
        puts "   Enabled: [get_property is_enabled $f]"
        puts "   Used in: [get_property used_in $f]"
    }
} else {
    puts "   ERROR: dma_subsystem_wrapper.v not found!"
}

# Update compile order
puts "\n6. Updating compile order..."
update_compile_order -fileset sources_1

puts "\n=== Done! Close and reopen Vivado, then try synthesis ==="
