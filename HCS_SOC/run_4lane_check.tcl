open_project D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr
update_compile_order -fileset sources_1
reset_run system_dma_subsystem_v2_wra_0_0_synth_1
reset_run synth_1
reset_run impl_1
launch_runs impl_1 -to_step place_design -jobs 8
wait_on_run impl_1
set placed_dcp D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/system_wrapper_placed.dcp
if {[catch {open_run impl_1} err]} {
    puts "open_run impl_1 failed: $err"
    if {[file exists $placed_dcp]} {
        open_checkpoint $placed_dcp
    } else {
        error "Neither open_run nor placed DCP is available"
    }
}
report_utilization -file D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/util_4lane_impl.rpt
report_timing_summary -file D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/timing_4lane_impl.rpt
close_project
exit
