open_project -quiet D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr
set run [get_runs -quiet system_dma_subsystem_v2_wra_0_0_synth_1]
report_property $run
close_project
