set workspace_root [file normalize [file dirname [info script]]]
set repo_root [file normalize [file dirname $workspace_root]]
set project_file [file join $workspace_root "HCS_SOC.xpr"]
set source_bd_name "dma_gateway_hybrid"
set source_bd [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" $source_bd_name "${source_bd_name}.bd"]
set raw_bd_name "udp_gateway_shadow_mirror"
set raw_bd [file normalize [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" $raw_bd_name "${raw_bd_name}.bd"]]
set raw_bd_dir [file dirname $raw_bd]
set runs_root [file join $workspace_root "HCS_SOC.runs"]
set crypto_ref_synth_wrapper_pattern [file join $workspace_root "HCS_SOC.gen" "sources_1" "bd" $raw_bd_name "ip" "*crypto_accel_axi_0_0*" "synth" "${raw_bd_name}_crypto_accel_axi_0_0.v"]
set out_xsa [file join $workspace_root "udp_gateway_shadow_mirror_wrapper.xsa"]
set dry_run 0

if {[info exists ::env(UDP_GATEWAY_SHADOW_MIRROR_EXPORT_DRY_RUN)] && $::env(UDP_GATEWAY_SHADOW_MIRROR_EXPORT_DRY_RUN) eq "1"} {
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

proc ensure_constraint_source {abs_path} {
    if {![file exists $abs_path]} {
        error "Required constraint source not found: $abs_path"
    }

    set existing [get_files -quiet $abs_path]
    if {[llength $existing] == 0} {
        add_files -fileset constrs_1 -norecurse $abs_path
        set existing [get_files -quiet $abs_path]
    }

    set_property file_type XDC $existing
    set_property used_in_synthesis false $existing
    set_property used_in_implementation true $existing
}

proc remove_orphan_project_file {abs_path} {
    if {[file exists $abs_path]} {
        return
    }
    set existing [get_files -quiet $abs_path]
    if {[llength $existing] != 0} {
        catch {remove_files $existing}
    }
}

proc lock_shadow_wrapper_top {} {
    set src_fileset [get_filesets sources_1]
    set_property top_auto_set 0 $src_fileset
    set_property top udp_gateway_shadow_mirror_wrapper $src_fileset
}

proc mark_shadow_wrapper_sources {wrapper_files} {
    foreach wrapper_file $wrapper_files {
        set wrapper_obj [get_files -all -quiet [file normalize $wrapper_file]]
        if {[llength $wrapper_obj] != 0} {
            set_property used_in_synthesis true $wrapper_obj
            set_property used_in_implementation true $wrapper_obj
        }
    }
}

proc ensure_shadow_fastpath_tx_pins_external {} {
    set wrapper_cell [get_bd_cells -quiet dma_gateway_hybrid_0]
    if {[llength $wrapper_cell] == 0} {
        error "dma_gateway_hybrid_0 not found while exposing zero-copy fastpath egress pins"
    }

    catch {update_module_reference $wrapper_cell}

    set axis_intf_pin [get_bd_intf_pins -quiet dma_gateway_hybrid_0/o_tx_axis]
    if {[llength $axis_intf_pin] == 0} {
        error "ZERO_COPY_FASTPATH_EGRESS_STEP1 missing refreshed BD interface pin dma_gateway_hybrid_0/o_tx_axis"
    }

    if {[llength [get_bd_intf_ports -quiet o_tx_axis]] == 0} {
        set before_ports [get_bd_intf_ports]
        make_bd_intf_pins_external $axis_intf_pin

        set new_ports {}
        foreach intf_port [get_bd_intf_ports] {
            if {[lsearch -exact $before_ports $intf_port] < 0} {
                lappend new_ports $intf_port
            }
        }

        if {[llength $new_ports] != 1} {
            error "ZERO_COPY_FASTPATH_EGRESS_STEP1 expected exactly one new external AXIS port, got [llength $new_ports]"
        }

        set_property name o_tx_axis [lindex $new_ports 0]
    }

    set tready_pin [get_bd_pins -quiet dma_gateway_hybrid_0/i_tx_axis_tready]
    if {[llength $tready_pin] == 0} {
        error "ZERO_COPY_FASTPATH_EGRESS_STEP1 missing refreshed BD pin dma_gateway_hybrid_0/i_tx_axis_tready"
    }

    if {[llength [get_bd_ports -quiet i_tx_axis_tready]] == 0} {
        set before_ports [get_bd_ports]
        make_bd_pins_external $tready_pin

        set new_ports {}
        foreach bd_port [get_bd_ports] {
            if {[lsearch -exact $before_ports $bd_port] < 0} {
                lappend new_ports $bd_port
            }
        }

        if {[llength $new_ports] != 1} {
            error "ZERO_COPY_FASTPATH_EGRESS_STEP1 expected exactly one new scalar tready port, got [llength $new_ports]"
        }

        set_property name i_tx_axis_tready [lindex $new_ports 0]
    }
}

proc keep_shadow_inactive_sources_disabled {} {
    global repo_root

    foreach rel_path [list \
        "rtl/security/config_packet_auth.sv" \
        "rtl/security/key_vault.sv" \
        "rtl/core/crypto/crypto_engine.sv" \
        "rtl/security/five_tuple_extractor.sv" \
    ] {
        set abs_path [file normalize [file join $repo_root $rel_path]]
        set file_obj [get_files -all -quiet $abs_path]
        if {[llength $file_obj] != 0} {
            catch {set_property is_enabled false $file_obj}
            set_property used_in_synthesis false $file_obj
            set_property used_in_implementation false $file_obj
            catch {set_property used_in_simulation false $file_obj}
        }
    }
}

if {![file exists $project_file]} {
    error "project file not found: $project_file"
}
if {![file exists $source_bd]} {
    error "source bd not found: $source_bd"
}

open_project -quiet $project_file
set_property source_mgmt_mode All [current_project]
keep_shadow_inactive_sources_disabled
remove_orphan_project_file [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" "dma_gateway_hybrid_axi3_probe" "dma_gateway_hybrid_axi3_probe.bd"]
remove_orphan_project_file [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" "system" "system.bd"]
set stale_system_bd_files [get_files -quiet [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" "system" *]]
if {[llength $stale_system_bd_files] != 0} {
    catch {remove_files $stale_system_bd_files}
}
foreach stale_system_fileset [get_filesets -quiet "system_dma_subsystem_v2_wra_0_0*"] {
    catch {delete_fileset $stale_system_fileset}
}
foreach stale_system_run [get_runs -quiet "system_dma_subsystem_v2_wra_0_0*"] {
    catch {delete_run $stale_system_run}
}

if {[llength [get_files -quiet $raw_bd]] != 0} {
    set raw_designs [get_bd_designs -quiet $raw_bd_name]
    if {[llength $raw_designs] != 0} {
        catch {close_bd_design $raw_designs}
    }
    catch {remove_files [get_files -quiet $raw_bd]}
}
set stale_raw_project_files [concat \
    [get_files -quiet [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" $raw_bd_name *]] \
    [get_files -quiet [file join $workspace_root "HCS_SOC.gen" "sources_1" "bd" $raw_bd_name *]] \
]
if {[llength $stale_raw_project_files] != 0} {
    catch {remove_files $stale_raw_project_files}
}
foreach stale_raw_fileset [get_filesets -quiet "${raw_bd_name}_*"] {
    catch {delete_fileset $stale_raw_fileset}
}
foreach stale_raw_run [get_runs -quiet "${raw_bd_name}_*"] {
    catch {delete_run $stale_raw_run}
}
foreach stale_crypto_fileset [get_filesets -quiet "${raw_bd_name}_crypto_accel_axi_0_0*"] {
    catch {delete_fileset $stale_crypto_fileset}
}
set stale_crypto_ip_files [concat \
    [get_files -quiet [file join $workspace_root "HCS_SOC.gen" "sources_1" "bd" $raw_bd_name "ip" "${raw_bd_name}_crypto_accel_axi_0_0*" *]] \
    [get_files -quiet [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" $raw_bd_name "ip" "${raw_bd_name}_crypto_accel_axi_0_0*" *]] \
]
if {[llength $stale_crypto_ip_files] != 0} {
    catch {remove_files $stale_crypto_ip_files}
}
foreach stale_path [list $raw_bd_dir [file join $workspace_root "HCS_SOC.gen" "sources_1" "bd" $raw_bd_name]] {
    if {[file exists $stale_path]} {
        if {[catch {file delete -force $stale_path} delete_err]} {
            puts "Warning: failed to delete stale shadow-mirror artifact $stale_path: $delete_err"
        }
    }
}

close_project
open_project -quiet $project_file
set_property source_mgmt_mode All [current_project]
keep_shadow_inactive_sources_disabled

foreach src_info {
    {"rtl/inc/dma_csr_pkg.sv" "SystemVerilog"}
    {"rtl/core/axil_csr.sv" "SystemVerilog"}
    {"rtl/core/parser/rx_parser.sv" "SystemVerilog"}
    {"rtl/core/pbm/pbm_controller.sv" "SystemVerilog"}
    {"rtl/core/parser/arp_responder.sv" "SystemVerilog"}
    {"rtl/core/tx/arp_tx_framer.sv" "SystemVerilog"}
    {"rtl/core/tx/tx_stack.sv" "SystemVerilog"}
    {"rtl/top/network_stage1_path.sv" "SystemVerilog"}
    {"rtl/core/dma/dma_desc_fetcher.sv" "SystemVerilog"}
    {"rtl/core/dma/axis_packet_fifo_bram.sv" "SystemVerilog"}
    {"rtl/core/dma/dma_axis_fifo_wrapper.sv" "SystemVerilog"}
    {"rtl/core/dma/dma_raw_copy_engine.sv" "SystemVerilog"}
    {"rtl/core/dma/udp_dma_ingress_classifier.sv" "SystemVerilog"}
    {"rtl/top/dma_raw_copy_subsystem.sv" "SystemVerilog"}
    {"rtl/security/acl_match_engine.sv" "SystemVerilog"}
    {"rtl/security/acl_packet_filter.sv" "SystemVerilog"}
    {"rtl/security/device_dna_reader.sv" "SystemVerilog"}
    {"rtl/top/udp_gateway_shadow_ctrl_csr.sv" "SystemVerilog"}
    {"rtl/top/udp_gateway_shadow_inject_path.sv" "SystemVerilog"}
    {"rtl/top/dma_gateway_hybrid_board_wrapper.v" "Verilog"}
    {"rtl/core/crypto_axi/crypto_accel_axi.v" "Verilog"}
    {"rtl/core/crypto_axi/crypto_accel_axi_slave_lite_v1_0_S00_AXI.v" "Verilog"}
    {"rtl/top/crypto_accel_axi_design1_ref.v" "Verilog"}
} {
    ensure_design_source [file join $repo_root [lindex $src_info 0]] [lindex $src_info 1]
}

foreach xdc_src {
    "constraints/shadow_mirror_phasec_constraints.xdc"
} {
    ensure_constraint_source [file join $repo_root $xdc_src]
}

open_bd_design $source_bd
save_bd_design_as -force $raw_bd_name
catch {close_bd_design [current_bd_design]}

if {![file exists $raw_bd]} {
    error "shadow mirror bd clone was not created: $raw_bd"
}
if {[llength [get_files -quiet $raw_bd]] == 0} {
    add_files -norecurse $raw_bd
}
open_bd_design $raw_bd
set raw_bd_obj [lindex [get_files -quiet [file tail $raw_bd]] 0]
if {$raw_bd_obj eq ""} {
    set raw_bd_obj $raw_bd
}

set_property -dict [list CONFIG.SHADOW_INJECT_ONLY {1}] [get_bd_cells dma_gateway_hybrid_0]
set_property -dict [list CONFIG.NUM_MI {3}] [get_bd_cells ps7_0_axi_periph]
connect_bd_net [get_bd_pins ps7_0_axi_periph/M02_ACLK] [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net [get_bd_pins ps7_0_axi_periph/M02_ARESETN] [get_bd_pins rst_ps7_0_100M/peripheral_aresetn]

if {[llength [get_bd_cells -quiet crypto_accel_axi_0]] == 0} {
    create_bd_cell -type module -reference crypto_accel_axi_design1_ref crypto_accel_axi_0
}

connect_bd_net [get_bd_pins crypto_accel_axi_0/s00_axi_aclk] [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net [get_bd_pins crypto_accel_axi_0/s00_axi_aresetn] [get_bd_pins rst_ps7_0_100M/peripheral_aresetn]
connect_bd_intf_net [get_bd_intf_pins crypto_accel_axi_0/s00_axi] [get_bd_intf_pins ps7_0_axi_periph/M02_AXI]

assign_bd_address -offset 0x43C00000 -range 64K \
    -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs crypto_accel_axi_0/s00_axi/reg0] -force

# ZERO_COPY_FASTPATH_EGRESS_STEP1: refresh module_ref ports after wrapper TX egress exposure
ensure_shadow_fastpath_tx_pins_external
validate_bd_design
save_bd_design
catch {close_bd_design [current_bd_design]}
generate_target all $raw_bd_obj
export_ip_user_files -of_objects $raw_bd_obj -sync -force -quiet
catch {close_bd_design [current_bd_design]}
close_project
open_project -quiet $project_file
set_property source_mgmt_mode All [current_project]
keep_shadow_inactive_sources_disabled
lock_shadow_wrapper_top
set raw_bd_obj [lindex [get_files -quiet $raw_bd] 0]
if {$raw_bd_obj eq ""} {
    error "shadow mirror bd file disappeared after generate_target/export_ip_user_files: $raw_bd"
}
open_bd_design $raw_bd
set crypto_ref_synth_wrappers [glob -nocomplain $crypto_ref_synth_wrapper_pattern]
foreach crypto_ref_synth_wrapper $crypto_ref_synth_wrappers {
    if {[llength [get_files -quiet $crypto_ref_synth_wrapper]] == 0} {
        add_files -norecurse $crypto_ref_synth_wrapper
    }
}
set crypto_wrapper_files [get_files -all -quiet $crypto_ref_synth_wrapper_pattern]
if {[llength $crypto_wrapper_files] != 0} {
    set_property used_in_synthesis true $crypto_wrapper_files
    set_property used_in_implementation true $crypto_wrapper_files
    set_property used_in_simulation false $crypto_wrapper_files
}
set wrapper_files [make_wrapper -files $raw_bd_obj -top -force]
foreach wrapper_file $wrapper_files {
    if {[llength [get_files -quiet $wrapper_file]] == 0} {
        add_files -norecurse $wrapper_file
    }
}
mark_shadow_wrapper_sources $wrapper_files
update_compile_order -fileset sources_1
lock_shadow_wrapper_top
puts "Top set to: [get_property top [get_filesets sources_1]]"

if {$dry_run} {
    puts "Dry-run complete. Shadow mirror hardware graph and wrapper generated without synth/impl."
    close_project
    return
}

foreach stale_run_dir [glob -nocomplain [file join $runs_root "${raw_bd_name}_*"]] {
    if {[file isdirectory $stale_run_dir]} {
        if {[catch {file delete -force $stale_run_dir} delete_run_err]} {
            puts "Warning: failed to delete stale shadow-mirror run directory $stale_run_dir: $delete_run_err"
        }
    }
}

set_property strategy Flow_AreaOptimized_high [get_runs synth_1]
foreach shadow_run [get_runs -quiet "${raw_bd_name}_*"] {
    catch {reset_run $shadow_run}
}
reset_run synth_1
reset_run impl_1
lock_shadow_wrapper_top
lock_shadow_wrapper_top
launch_runs synth_1 -scripts_only
foreach required_run_name [list \
    "${raw_bd_name}_processing_system7_0_0_synth_1" \
    "${raw_bd_name}_dma_gateway_hybrid_0_0_synth_1" \
] {
    set required_run_name_no_step [string map {"_synth_1" ""} $required_run_name]
    set required_run_script [file join $runs_root $required_run_name "${required_run_name_no_step}.tcl"]
    if {![file exists $required_run_script]} {
        error "required OOC run script missing after -scripts_only generation: $required_run_script"
    }
}
reset_run synth_1
lock_shadow_wrapper_top
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
lock_shadow_wrapper_top
update_compile_order -fileset sources_1
foreach stale_impl_tcl [glob -nocomplain [file join $runs_root "impl_1" "*.tcl"]] {
    catch {file delete -force $stale_impl_tcl}
}
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
write_hw_platform -fixed -include_bit -force -file $out_xsa
puts "Exported XSA: $out_xsa"
close_project
