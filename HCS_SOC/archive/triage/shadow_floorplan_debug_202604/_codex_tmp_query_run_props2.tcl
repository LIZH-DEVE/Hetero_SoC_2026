open_project -quiet {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr}
puts "FILESET_TOP=[get_property top [get_filesets sources_1]]"
puts "FILESET_TOP_AUTO_SET=[get_property top_auto_set [get_filesets sources_1]]"
foreach run [list [get_runs synth_1] [get_runs impl_1]] {
  puts "RUN=[get_property NAME $run]"
  foreach p {top srcset constrset strategy flow parent_run needs_refresh STATUS} {
    catch {puts "$p=[get_property $p $run]"}
  }
}
close_project
exit
