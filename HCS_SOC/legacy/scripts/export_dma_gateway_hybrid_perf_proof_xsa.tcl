set workspace_root [file normalize [file dirname [info script]]]
set repo_root [file normalize [file dirname $workspace_root]]
set project_file [file join $workspace_root "HCS_SOC.xpr"]
set source_bd [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" "system" "system.bd"]
set raw_bd_name "dma_gateway_hybrid_perf_proof"
set raw_bd [file normalize [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" $raw_bd_name "${raw_bd_name}.bd"]]
set raw_bd_dir [file dirname $raw_bd]
set out_xsa [file join $workspace_root "dma_gateway_hybrid_perf_proof_wrapper.xsa"]
set vendor_ps_config [file normalize [file join $workspace_root ".." ".." "AX7020_2023.1" "course_s2_vitis" "08_ps_uart" "Vivado" "auto_create_project" "ps_config.tcl"]]
set dry_run 0

if {[info exists ::env(DMA_GATEWAY_HYBRID_PERF_PROOF_EXPORT_DRY_RUN)] && $::env(DMA_GATEWAY_HYBRID_PERF_PROOF_EXPORT_DRY_RUN) eq "1"} {
    set dry_run 1
}

proc ensure_design_source {abs_path file_type} {
    if {![file exists $abs_path]} {
        error "Required design source not found: $abs_path"
    }
    set existing [get_files -quiet $abs_path]
    if {[llength $existing] == 0} {
        add_files -norecurse $abs_path
        set existing [get_files -quiet $abs_path]
    }
    if {$file_type ne ""} {
        set_property file_type $file_type $existing
    }
}

proc force_auto_compile_order {} {
    set project_obj [lindex [get_projects -quiet] 0]
    current_project $project_obj
    set_property source_mgmt_mode All $project_obj
    update_compile_order -fileset sources_1
}

if {![file exists $project_file]} {
    error "project file not found: $project_file"
}
if {![file exists $source_bd]} {
    error "system.bd not found: $source_bd"
}
if {![file exists $vendor_ps_config]} {
    error "vendor ps_config.tcl not found: $vendor_ps_config"
}

open_project -quiet $project_file
force_auto_compile_order

foreach src_info {
    {"rtl/inc/dma_csr_pkg.sv" "SystemVerilog"}
    {"rtl/core/axil_csr.sv" "SystemVerilog"}
    {"rtl/core/dma/dma_desc_fetcher.sv" "SystemVerilog"}
    {"rtl/core/dma/axis_packet_fifo_bram.sv" "SystemVerilog"}
    {"rtl/core/dma/dma_axis_fifo_wrapper.sv" "SystemVerilog"}
    {"rtl/core/dma/dma_crypto_source_reader.sv" "SystemVerilog"}
    {"rtl/core/dma/dma_master_engine.sv" "SystemVerilog"}
    {"rtl/core/dma/dma_s2mm_mm2s_engine.sv" "SystemVerilog"}
    {"rtl/core/pbm/pbm_controller.sv" "SystemVerilog"}
    {"rtl/core/crypto/crypto_bridge_top.sv" "SystemVerilog"}
    {"rtl/top/crypto_dma_subsystem.sv" "SystemVerilog"}
    {"rtl/top/dma_gateway_hybrid_perf_proof_core.v" "Verilog"}
} {
    ensure_design_source [file join $repo_root [lindex $src_info 0]] [lindex $src_info 1]
}

if {[llength [get_files -quiet $raw_bd]] != 0} {
    catch {close_bd_design [get_bd_designs -quiet $raw_bd_name]}
    catch {remove_files [get_files -quiet $raw_bd]}
}
if {[file exists $raw_bd_dir]} {
    file delete -force $raw_bd_dir
}

force_auto_compile_order
open_bd_design [get_files $source_bd]
save_bd_design_as -force $raw_bd_name
close_bd_design [current_bd_design]

if {![file exists $raw_bd]} {
    error "hybrid perf proof BD clone was not created: $raw_bd"
}
if {[llength [get_files -quiet $raw_bd]] == 0} {
    add_files -norecurse $raw_bd
}

force_auto_compile_order
open_bd_design $raw_bd
set raw_bd_obj [lindex [get_files -quiet [file tail $raw_bd]] 0]
if {$raw_bd_obj eq ""} {
    set raw_bd_obj $raw_bd
}

delete_bd_objs [get_bd_cells dma_subsystem_v2_wra_0]
set_property -dict [list CONFIG.NUM_MI {2}] [get_bd_cells ps7_0_axi_periph]
connect_bd_net [get_bd_pins ps7_0_axi_periph/M01_ACLK] [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net [get_bd_pins ps7_0_axi_periph/M01_ARESETN] [get_bd_pins rst_ps7_0_100M/peripheral_aresetn]
create_bd_cell -type module -reference dma_gateway_hybrid_perf_proof_core dma_gateway_hybrid_perf_proof_0

connect_bd_net [get_bd_pins dma_gateway_hybrid_perf_proof_0/clk] [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net [get_bd_pins dma_gateway_hybrid_perf_proof_0/rst_n] [get_bd_pins rst_ps7_0_100M/peripheral_aresetn]
connect_bd_intf_net [get_bd_intf_pins dma_gateway_hybrid_perf_proof_0/s_axil_ctrl] [get_bd_intf_pins ps7_0_axi_periph/M00_AXI]
connect_bd_intf_net [get_bd_intf_pins dma_gateway_hybrid_perf_proof_0/s_axil_dma] [get_bd_intf_pins ps7_0_axi_periph/M01_AXI]
connect_bd_intf_net [get_bd_intf_pins dma_gateway_hybrid_perf_proof_0/m_axi_dma_wr] [get_bd_intf_pins axi_mem_intercon/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins dma_gateway_hybrid_perf_proof_0/m_axi_fetcher] [get_bd_intf_pins axi_mem_intercon/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins dma_gateway_hybrid_perf_proof_0/m_axi_s2mm] [get_bd_intf_pins axi_mem_intercon/S02_AXI]

assign_bd_address -offset 0x40000000 -range 4K \
    -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs dma_gateway_hybrid_perf_proof_0/s_axil_ctrl/reg0] -force
assign_bd_address -offset 0x40001000 -range 4K \
    -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs dma_gateway_hybrid_perf_proof_0/s_axil_dma/reg0] -force

source $vendor_ps_config
set_ps_config processing_system7_0
set_property CONFIG.PCW_USE_S_AXI_HP0 {1} [get_bd_cells processing_system7_0]
foreach intf_pin [list [get_bd_intf_pins axi_mem_intercon/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]] {
    catch {disconnect_bd_intf_net -objects $intf_pin}
}
connect_bd_intf_net [get_bd_intf_pins axi_mem_intercon/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]
foreach addr_space {m_axi_dma_wr m_axi_fetcher m_axi_s2mm} {
    assign_bd_address -offset 0x00000000 -range 512M \
        -target_address_space [get_bd_addr_spaces dma_gateway_hybrid_perf_proof_0/$addr_space] \
        [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] -force
}
connect_bd_net [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK] [get_bd_pins processing_system7_0/FCLK_CLK0]

validate_bd_design
save_bd_design
close_bd_design [current_bd_design]

force_auto_compile_order
generate_target all $raw_bd_obj
export_ip_user_files -of_objects $raw_bd_obj -sync -force -quiet
set wrapper_files [make_wrapper -files $raw_bd_obj -top -force]
foreach wrapper_file $wrapper_files {
    if {[llength [get_files -quiet $wrapper_file]] == 0} {
        add_files -norecurse $wrapper_file
    }
}
update_compile_order -fileset sources_1
set_property top dma_gateway_hybrid_perf_proof_wrapper [current_fileset]

if {$dry_run} {
    puts "Dry-run complete. Hybrid perf proof hardware graph and wrapper generated without synth/impl."
    close_project
    return
}

reset_run synth_1
reset_run impl_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
write_hw_platform -fixed -include_bit -force -file $out_xsa
puts "Exported XSA: $out_xsa"
close_project
