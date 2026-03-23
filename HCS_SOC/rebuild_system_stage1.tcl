set workspace_root [file normalize [file dirname [info script]]]
set project_file [file join $workspace_root "HCS_SOC.xpr"]
set system_bd [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" "system" "system.bd"]
set out_xsa [file join $workspace_root "system_wrapper.xsa"]
set crypto_instances 2

if {[info exists ::env(CRYPTO_NUM_INSTANCES)]} {
    set crypto_instances $::env(CRYPTO_NUM_INSTANCES)
}

if {![file exists $project_file]} {
    error "project file not found: $project_file"
}

open_project $project_file

if {![file exists $system_bd]} {
    error "system.bd not found: $system_bd"
}

puts "Using BD: $system_bd"
open_bd_design [get_files $system_bd]
set bd_cell [get_bd_cells /dma_subsystem_v2_wra_0]
if {[llength $bd_cell] == 0} {
    error "cannot find /dma_subsystem_v2_wra_0 in system.bd"
}
set ps_cell [get_bd_cells /processing_system7_0]
if {[llength $ps_cell] == 0} {
    error "cannot find /processing_system7_0 in system.bd"
}
puts "Setting CRYPTO_NUM_INSTANCES to: $crypto_instances"
set_property -dict [list CONFIG.CRYPTO_NUM_INSTANCES $crypto_instances] $bd_cell

# Final integrated system should expose GEM0 through PS MIO and keep UART1 on MIO48/49.
set ps_config [list \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
    CONFIG.PCW_EN_ENET0 {1} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_ENET0_PERIPHERAL_FREQMHZ {1000 Mbps} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
    CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27} \
    CONFIG.PCW_ENET0_GRP_MDIO_IO {MIO 52 .. 53} \
    CONFIG.PCW_EN_EMIO_ENET0 {0} \
    CONFIG.PCW_EN_UART1 {1} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
    CONFIG.PCW_UART1_GRP_FULL_ENABLE {0} \
    CONFIG.PCW_EN_MODEM_UART1 {0} \
    CONFIG.PCW_EN_EMIO_UART1 {0} \
    CONFIG.PCW_EN_EMIO_MODEM_UART1 {0} \
]
puts "Applying PS7 peripheral configuration for GEM0/UART1"
set_property -dict $ps_config $ps_cell
validate_bd_design
foreach prop {
    CONFIG.PCW_PRESET_BANK1_VOLTAGE
    CONFIG.PCW_EN_ENET0
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE
    CONFIG.PCW_ENET0_PERIPHERAL_FREQMHZ
    CONFIG.PCW_ENET0_ENET0_IO
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE
    CONFIG.PCW_ENET0_GRP_MDIO_IO
    CONFIG.PCW_EN_UART1
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE
    CONFIG.PCW_UART1_UART1_IO
} {
    puts [format "%s = %s" $prop [get_property $prop $ps_cell]]
}
save_bd_design
close_bd_design [current_bd_design]
generate_target all [get_files $system_bd]
make_wrapper -files [get_files $system_bd] -top -force
update_compile_order -fileset sources_1
set_property top system_wrapper [current_fileset]
puts "Top set to: [get_property top [current_fileset]]"

reset_run synth_1
reset_run impl_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "synth_1 status: $synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "synth_1 failed: $synth_status"
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1 status: $impl_status"
if {![string match "*Complete*" $impl_status]} {
    error "impl_1 failed: $impl_status"
}

set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set bit_file [file join $impl_dir "system_wrapper.bit"]
if {![file exists $bit_file]} {
    error "bitstream not found after impl: $bit_file"
}
puts "Stage1 bitstream: $bit_file"

write_hw_platform -fixed -include_bit -force -file $out_xsa
puts "Exported XSA: $out_xsa"

close_project
