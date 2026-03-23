# Fix IP references and regenerate IP
puts "=== Fixing IP References ==="

# Report IP status
puts "\n=== Reporting IP Status ==="
report_ip_status

# Reset IP runs
puts "\n=== Resetting IP Runs ==="
reset_run system_dma_subsystem_wrapper_0_0_synth_1
reset_run system_processing_system7_0_0_synth_1
reset_run system_rst_ps7_0_100M_0_synth_1
reset_run system_auto_pc_0_synth_1
reset_run system_auto_pc_1_synth_1
reset_run system_auto_us_0_synth_1

# Upgrade IPs
puts "\n=== Upgrading IPs ==="
upgrade_ip [get_ips]

# Generate all IP outputs
puts "\n=== Generating IP Outputs ==="
generate_target all [get_files system.bd]

# Export hardware
puts "\n=== Exporting Hardware Definition ==="
export_ip_user_files -of_objects [get_files system.bd] -no_script -sync -force -quiet

# Report final status
puts "\n=== Final IP Status ==="
report_ip_status

puts "\n=== Done! You can now try synthesis again ==="
