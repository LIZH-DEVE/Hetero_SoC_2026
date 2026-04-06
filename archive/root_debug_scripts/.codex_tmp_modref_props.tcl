set workspace_root {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC}
open_project [file join $workspace_root HCS_SOC.xpr]
set xci [get_files -all [file normalize [file join $workspace_root HCS_SOC.srcs sources_1 bd raw_copy_dma ip raw_copy_dma_dma_raw_copy_subsystem_0_0 raw_copy_dma_dma_raw_copy_subsystem_0_0.xci]]]
puts "=== XCI props containing checkpoint/module ==="
foreach p [lsort [list_property $xci]] {
  if {[regexp -nocase {checkpoint|module|synth} $p]} {
    catch {puts "$p = [get_property $p $xci]"}
  }
}
set ip [get_ips -quiet raw_copy_dma_dma_raw_copy_subsystem_0_0]
puts "=== IP object ==="
puts $ip
if {[llength $ip]} {
  foreach p [lsort [list_property $ip]] {
    if {[regexp -nocase {checkpoint|module|synth|output|file} $p]} {
      catch {puts "$p = [get_property $p $ip]"}
    }
  }
}
close_project
