set workspace_root [file normalize [file dirname [info script]]]
set repo_root [file normalize [file dirname $workspace_root]]
set project_file [file join $workspace_root "HCS_SOC.xpr"]
set source_bd [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" "system" "system.bd"]
set raw_bd_name "raw_copy_dma"
set raw_bd [file normalize [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" $raw_bd_name "${raw_bd_name}.bd"]]
set out_xsa [file join $workspace_root "raw_copy_dma_wrapper.xsa"]
set fifo_ip_name "dma_raw_copy_axis_data_fifo"
set vendor_ps_config [file normalize [file join $workspace_root ".." ".." "AX7020_2023.1" "course_s2_vitis" "08_ps_uart" "Vivado" "auto_create_project" "ps_config.tcl"]]
set dry_run 0

if {[info exists ::env(RAW_COPY_EXPORT_DRY_RUN)] && $::env(RAW_COPY_EXPORT_DRY_RUN) eq "1"} {
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
    set open_projects [get_projects -quiet]
    if {[llength $open_projects] == 0} {
        error "No projects are currently open."
    }

    set project_obj [lindex $open_projects 0]
    current_project $project_obj
    set_property source_mgmt_mode All $project_obj
    update_compile_order -fileset sources_1
}

proc wait_for_run_terminal {run_name timeout_secs} {
    set run_obj [get_runs -quiet $run_name]
    if {[llength $run_obj] == 0} {
        error "Run not found: $run_name"
    }

    set deadline [expr {[clock seconds] + $timeout_secs}]
    set last_status ""
    while {1} {
        set status [get_property STATUS $run_obj]
        if {$status ne $last_status} {
            puts "$run_name status: $status"
            set last_status $status
        }

        if {[string match "*Complete*" $status] || $status eq "Up-to-date" || $status eq "Using cached IP results"} {
            return $status
        }
        if {[string match "*Fail*" $status] || [string match "*Error*" $status] || [string match "*Cancel*" $status]} {
            error "$run_name failed: $status"
        }
        if {[clock seconds] >= $deadline} {
            error "$run_name timed out after ${timeout_secs}s (last status: $status)"
        }

        after 5000
        set run_obj [get_runs -quiet $run_name]
    }
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
    {"rtl/core/dma/dma_raw_copy_engine.sv" "SystemVerilog"}
    {"rtl/top/dma_raw_copy_subsystem.sv" "SystemVerilog"}
    {"rtl/top/dma_raw_copy_board_wrapper.v" "Verilog"}
} {
    ensure_design_source [file join $repo_root [lindex $src_info 0]] [lindex $src_info 1]
}

# Keep the raw-copy hardware export on the self-contained RTL BRAM FIFO path.
# The Xilinx axis_data_fifo IP remains available for other flows, but forcing
# the macro here leaves the module-reference OOC checkpoint incomplete and
# breaks fresh raw_copy_dma XSA export at impl stitch time.
set current_defs [get_property verilog_define [current_fileset]]
set filtered_defs {}
foreach def $current_defs {
    if {$def ne "USE_XILINX_AXIS_DATA_FIFO_IP"} {
        lappend filtered_defs $def
    }
}
if {$filtered_defs ne $current_defs} {
    set_property verilog_define $filtered_defs [current_fileset]
}

if {[llength [get_ips -quiet $fifo_ip_name]] == 0} {
    create_ip -name axis_data_fifo -vendor xilinx.com -library ip -module_name $fifo_ip_name
}
set_property -dict [list \
    CONFIG.FIFO_DEPTH {512} \
    CONFIG.FIFO_MEMORY_TYPE {block} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.HAS_TREADY {1} \
    CONFIG.TDATA_NUM_BYTES {4} \
    CONFIG.IS_ACLK_ASYNC {0} \
] [get_ips $fifo_ip_name]
generate_target all [get_ips $fifo_ip_name]
update_compile_order -fileset sources_1

if {[llength [get_files -quiet $raw_bd]] != 0} {
    set raw_designs [get_bd_designs -quiet $raw_bd_name]
    if {[llength $raw_designs] != 0} {
        catch {close_bd_design $raw_designs}
    }
    catch {remove_files [get_files -quiet $raw_bd]}
}
foreach stale_path [list [file dirname $raw_bd] [file join $workspace_root "HCS_SOC.gen" "sources_1" "bd" $raw_bd_name]] {
    if {[file exists $stale_path]} {
        if {[catch {file delete -force $stale_path} delete_err]} {
            puts "Warning: failed to delete stale raw-copy artifact $stale_path: $delete_err"
        }
    }
}

force_auto_compile_order
open_bd_design [get_files $source_bd]
save_bd_design_as $raw_bd_name
close_bd_design [current_bd_design]

if {![file exists $raw_bd]} {
    error "raw-copy BD clone was not created: $raw_bd"
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
create_bd_cell -type module -reference dma_raw_copy_board_wrapper dma_raw_copy_subsystem_0

connect_bd_net [get_bd_pins dma_raw_copy_subsystem_0/clk] [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net [get_bd_pins dma_raw_copy_subsystem_0/rst_n] [get_bd_pins rst_ps7_0_100M/peripheral_aresetn]
connect_bd_intf_net [get_bd_intf_pins dma_raw_copy_subsystem_0/s_axil] [get_bd_intf_pins ps7_0_axi_periph/M00_AXI]
connect_bd_intf_net [get_bd_intf_pins dma_raw_copy_subsystem_0/m_axi_dma_wr] [get_bd_intf_pins axi_mem_intercon/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins dma_raw_copy_subsystem_0/m_axi_fetcher] [get_bd_intf_pins axi_mem_intercon/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins dma_raw_copy_subsystem_0/m_axi_s2mm] [get_bd_intf_pins axi_mem_intercon/S02_AXI]

assign_bd_address [get_bd_addr_segs dma_raw_copy_subsystem_0/s_axil/reg0]
set raw_seg [get_bd_addr_segs processing_system7_0/Data/SEG_dma_raw_copy_subsystem_0_reg0]
set_property offset 0x40000000 $raw_seg
set_property range 1G $raw_seg

source $vendor_ps_config
if {![llength [info procs set_ps_config]]} {
    error "vendor ps_config.tcl did not define set_ps_config"
}
puts "Applying vendor PS preset from: $vendor_ps_config"
set_ps_config processing_system7_0
set_property CONFIG.PCW_USE_S_AXI_HP0 {1} [get_bd_cells processing_system7_0]
foreach intf_pin [list [get_bd_intf_pins axi_mem_intercon/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]] {
    catch {disconnect_bd_intf_net -objects $intf_pin}
}
connect_bd_intf_net [get_bd_intf_pins axi_mem_intercon/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]
connect_bd_net [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK] [get_bd_pins processing_system7_0/FCLK_CLK0]
foreach addr_space {m_axi_dma_wr m_axi_fetcher m_axi_s2mm} {
    assign_bd_address -offset 0x00000000 -range 512M \
        -target_address_space [get_bd_addr_spaces dma_raw_copy_subsystem_0/$addr_space] \
        [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] -force
}

validate_bd_design
save_bd_design
close_bd_design [current_bd_design]

force_auto_compile_order
generate_target all $raw_bd_obj`r`nexport_ip_user_files -of_objects $raw_bd_obj -sync -force -quiet
set module_ref_synth_wrapper [file join $workspace_root "HCS_SOC.gen" "sources_1" "bd" $raw_bd_name "ip" "raw_copy_dma_dma_raw_copy_subsystem_0_0" "synth" "raw_copy_dma_dma_raw_copy_subsystem_0_0.v"]
if {![file exists $module_ref_synth_wrapper]} {
    error "raw-copy module-ref synth wrapper was not generated: $module_ref_synth_wrapper"
}
if {[llength [get_files -quiet $module_ref_synth_wrapper]] == 0} {
    add_files -norecurse $module_ref_synth_wrapper
}
set_property file_type Verilog [get_files -quiet $module_ref_synth_wrapper]
set wrapper_files [make_wrapper -files $raw_bd_obj -top -force]
foreach wrapper_file $wrapper_files {
    if {[llength [get_files -quiet $wrapper_file]] == 0} {
        add_files -norecurse $wrapper_file
    }
}
update_compile_order -fileset sources_1
set_property top raw_copy_dma_wrapper [current_fileset]
puts "Wrapper files: $wrapper_files"
puts "Top set to: [get_property top [current_fileset]]"

if {$dry_run} {
    puts "Dry-run complete. Raw-copy hardware graph and wrapper generated without launching synth/impl."
    close_project
    return
}

reset_run synth_1
reset_run impl_1

launch_runs synth_1 -jobs 8
set synth_status [wait_for_run_terminal synth_1 7200]
puts "synth_1 terminal status: $synth_status"

launch_runs impl_1 -to_step write_bitstream -jobs 8
set impl_status [wait_for_run_terminal impl_1 7200]
puts "impl_1 terminal status: $impl_status"

set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set bit_file [file join $impl_dir "raw_copy_dma_wrapper.bit"]
if {![file exists $bit_file]} {
    error "bitstream not found after impl: $bit_file"
}
puts "raw-copy bitstream: $bit_file"

write_hw_platform -fixed -include_bit -force -file $out_xsa
puts "Exported XSA: $out_xsa"

close_project

