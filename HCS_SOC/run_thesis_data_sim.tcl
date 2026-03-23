open_project D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr
set_property top tb_dma_subsystem_crypto_encdec [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set sec_files [glob -nocomplain D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/security/*.sv]
foreach f $sec_files {
  if {[llength [get_files -quiet $f]] == 0} {
    add_files -fileset sources_1 $f
  }
}
set_property -dict [list xsim.simulate.xsim.more_options {-testplusarg RUN_FUNC=1 -testplusarg RUN_TP_AES=1 -testplusarg RUN_TP_SM4=1 -testplusarg RUN_BACKPRESSURE=0 -testplusarg RUN_KEY_SWITCH=0 -testplusarg RUN_STABILITY=0 -testplusarg SM4_ONLY=0 -testplusarg THROUGHPUT_SIZE_COUNT=4 -testplusarg THROUGHPUT_REPEAT=3 -testplusarg THROUGHPUT_WARMUP=1 -testplusarg PBM_COMMIT_WORDS=256 -testplusarg RESET_EACH_TRANSFER=0}] [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
run all
close_sim
close_project
exit
