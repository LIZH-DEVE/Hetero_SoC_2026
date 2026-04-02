if {[llength $argv] != 2} {
    puts stderr "Usage: export_udp_gateway_shadow_mirror_evidence_pack.tcl <checkpoint.dcp> <output_dir>"
    exit 2
}

set checkpoint_path [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]

if {![file exists $checkpoint_path]} {
    puts stderr "Checkpoint not found: $checkpoint_path"
    exit 3
}

file mkdir $output_dir

open_checkpoint $checkpoint_path

report_utilization -hierarchical -file [file join $output_dir "udp_gateway_shadow_mirror_wrapper_utilization_hierarchical.rpt"]
report_timing_summary -max_paths 10 -report_unconstrained -warn_on_violation -file [file join $output_dir "udp_gateway_shadow_mirror_wrapper_timing_summary_postroute_physopted.rpt"]
report_power -file [file join $output_dir "udp_gateway_shadow_mirror_wrapper_power_routed.rpt"]
report_clock_utilization -file [file join $output_dir "udp_gateway_shadow_mirror_wrapper_clock_utilization_routed.rpt"]
report_route_status -file [file join $output_dir "udp_gateway_shadow_mirror_wrapper_route_status.rpt"]
report_drc -file [file join $output_dir "udp_gateway_shadow_mirror_wrapper_drc_routed.rpt"]
report_methodology -file [file join $output_dir "udp_gateway_shadow_mirror_wrapper_methodology_drc_routed.rpt"]
report_cdc -details -file [file join $output_dir "udp_gateway_shadow_mirror_wrapper_cdc_routed.rpt"]
report_clock_interaction -file [file join $output_dir "udp_gateway_shadow_mirror_wrapper_clock_interaction_routed.rpt"]

set pblock_summary_path [file join $output_dir "udp_gateway_shadow_mirror_wrapper_pblock_summary.txt"]
set pblock_summary [open $pblock_summary_path "w"]
puts $pblock_summary "Pblock Summary"
set pblocks [lsort [get_pblocks]]
if {[llength $pblocks] == 0} {
    puts $pblock_summary "No pblocks found."
} else {
    foreach pblock $pblocks {
        puts $pblock_summary ""
        puts $pblock_summary "==== $pblock ===="
        puts $pblock_summary [report_property -return_string $pblock]
    }
}
close $pblock_summary

close_design
puts "Fresh engineering evidence reports exported to $output_dir"
exit
