# Fix module reference issue
puts "=== Fixing Module Reference Issue ==="

# 1. Set compile order to automatic
puts "\n1. Setting compile order to automatic..."
set_property source_mgmt_mode All [current_project]
puts "   Compile order set to: [get_property source_mgmt_mode [current_project]]"

# 2. Enable the dma_subsystem_wrapper.v file
puts "\n2. Enabling dma_subsystem_wrapper.v..."
set wrapper_file [get_files -of_objects [get_filesets sources_1] */dma_subsystem_wrapper.v]
if {$wrapper_file != ""} {
    set_property is_enabled true $wrapper_file
    set_property used_in {synthesis implementation simulation} $wrapper_file
    puts "   File enabled: $wrapper_file"
} else {
    puts "   WARNING: dma_subsystem_wrapper.v not found in project"
    puts "   Attempting to add it..."
    add_files -norecurse ../rtl/core/dma/dma_subsystem_wrapper.v
    set_property used_in {synthesis implementation simulation} [get_files */dma_subsystem_wrapper.v]
}

# 3. Refresh the file system
puts "\n3. Refreshing file system..."
update_compile_order -fileset sources_1

# 4. Reset and regenerate Block Design
puts "\n4. Resetting Block Design..."
reset_target all [get_files system.bd]
generate_target all [get_files system.bd]

# 5. Report IP status
puts "\n5. Checking IP status..."
report_ip_status

puts "\n=== Done! Try synthesis again ==="
puts "If you still see errors, the module might have synthesis issues."
