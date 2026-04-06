set workspace_root [file normalize [file dirname [info script]]]
set project_file [file join $workspace_root "HCS_SOC.xpr"]
set xsa_file [file join $workspace_root "design_1_wrapper.xsa"]
set impl_bit [file join $workspace_root "HCS_SOC.runs" "impl_1" "design_1_wrapper.bit"]
set crypto_ip_run "design_1_crypto_accel_axi_0_1_synth_1"
set dma_stage1_run "system_dma_subsystem_v2_wra_0_0_synth_1"
set required_stage1_sources [list \
    [file join $workspace_root ".." "rtl" "core" "tx" "arp_tx_framer.sv"] \
    [file join $workspace_root ".." "rtl" "top" "network_stage1_path.sv"] \
]

proc fail {message} {
    puts "ERROR: $message"
    exit 1
}

proc require_run {run_name} {
    set run [get_runs -quiet $run_name]
    if {$run eq ""} {
        fail "required run is missing: $run_name"
    }
    return $run_name
}

proc ensure_source_present {src_path} {
    set normalized [file normalize $src_path]
    set existing [get_files -quiet $normalized]
    if {$existing eq ""} {
        puts "add_files -norecurse $normalized"
        add_files -norecurse $normalized
    } else {
        puts "source already present: $normalized"
    }
}

proc wait_and_assert_success {run_name} {
    wait_on_run $run_name
    set progress [get_property PROGRESS [get_runs $run_name]]
    set status [get_property STATUS [get_runs $run_name]]
    puts "run $run_name status: $status"
    if {$progress ne "100%"} {
        fail "run $run_name did not complete successfully (progress=$progress, status=$status)"
    }
}

puts "=========================================="
puts "Rebuild Authoritative Bitstream"
puts "=========================================="
puts "workspace: $workspace_root"
puts "project:   $project_file"

if {![file exists $project_file]} {
    fail "project file not found: $project_file"
}

open_project $project_file

puts ""
puts "Step 1/7: Ensure Stage 1 network RTL sources are in project"
foreach src_file $required_stage1_sources {
    if {![file exists $src_file]} {
        fail "required stage1 source is missing: $src_file"
    }
    ensure_source_present $src_file
}
update_compile_order -fileset sources_1

puts ""
puts "Step 2/7: Clear IP output repository cache"
config_ip_cache -clear_output_repo

puts ""
puts "Step 3/7: Refresh IP catalog"
update_ip_catalog -rebuild

puts ""
puts "Step 4/7: Force rebuild of $crypto_ip_run"
set crypto_ip_run [require_run $crypto_ip_run]
reset_run $crypto_ip_run
launch_runs $crypto_ip_run -jobs 8
wait_and_assert_success $crypto_ip_run

puts ""
puts "Step 5/7: Force rebuild of $dma_stage1_run"
set dma_stage1_run [require_run $dma_stage1_run]
reset_run $dma_stage1_run
launch_runs $dma_stage1_run -jobs 8
wait_and_assert_success $dma_stage1_run

puts ""
puts "Step 6/7: Regenerate block design targets"
set bd_files [get_files -quiet -filter {FILE_TYPE == "Block Designs"}]
foreach bd_file $bd_files {
    puts "generate_target all $bd_file"
    generate_target all $bd_file
}

puts ""
puts "Step 7/7: Rebuild top-level synthesis and implementation"
reset_run synth_1
reset_run impl_1
launch_runs synth_1 -jobs 8
wait_and_assert_success synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_and_assert_success impl_1

puts ""
puts "Export refreshed XSA"
write_hw_platform -fixed -include_bit -force -file $xsa_file

if {![file exists $impl_bit]} {
    fail "authoritative bitstream was not generated: $impl_bit"
}

set timestamp [clock format [file mtime $impl_bit] -format "%Y-%m-%d %H:%M:%S"]
puts ""
puts "=========================================="
puts "Authoritative bitstream ready"
puts "bit:  $impl_bit"
puts "time: $timestamp"
puts "xsa:  $xsa_file"
puts "=========================================="

close_project
exit 0
