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
set direct_script_flow 1
set expose_fastpath_tx_ports 0

if {[info exists ::env(UDP_GATEWAY_SHADOW_MIRROR_EXPORT_DRY_RUN)] && $::env(UDP_GATEWAY_SHADOW_MIRROR_EXPORT_DRY_RUN) eq "1"} {
    set dry_run 1
}
if {[info exists ::env(UDP_GATEWAY_SHADOW_MIRROR_DIRECT_SCRIPT_FLOW)]} {
    set direct_script_flow [expr {$::env(UDP_GATEWAY_SHADOW_MIRROR_DIRECT_SCRIPT_FLOW) eq "1"}]
}
if {[info exists ::env(UDP_GATEWAY_SHADOW_MIRROR_EXPOSE_FASTPATH_TX_PORTS)]} {
    set expose_fastpath_tx_ports [expr {$::env(UDP_GATEWAY_SHADOW_MIRROR_EXPOSE_FASTPATH_TX_PORTS) eq "1"}]
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

proc reopen_shadow_project {project_file} {
    catch {close_project}
    puts "Reopening project after direct OOC runs: $project_file"
    if {[catch {open_project $project_file} open_err]} {
        error "failed to reopen project after direct OOC runs: $project_file: $open_err"
    }
    set open_projects [get_projects -quiet]
    if {[llength $open_projects] == 0} {
        error "failed to reopen project after direct OOC runs: $project_file"
    }
}

proc find_single_run_tcl {run_dir} {
    set run_tcls [glob -nocomplain [file join $run_dir "*.tcl"]]
    if {[llength $run_tcls] != 1} {
        error "expected exactly one run tcl in $run_dir, got [llength $run_tcls]"
    }
    return [lindex $run_tcls 0]
}

proc run_direct_vivado_run {run_name run_dir} {
    set run_tcl [find_single_run_tcl $run_dir]
    set vivado_exec [info nameofexecutable]
    set run_base [file rootname [file tail $run_tcl]]
    set run_log [file join $run_dir "${run_base}.vds"]
    set msg_db [file join $run_dir "vivado.pb"]
    set prev_dir [pwd]

    catch {file delete -force $run_log}
    catch {file delete -force $msg_db}

    puts "Direct-flow executing $run_name"
    set cmd [list $vivado_exec -log $run_log -product Vivado -mode batch -messageDb $msg_db -notrace -source $run_tcl]
    cd $run_dir
    set run_failed [catch {exec {*}$cmd} run_output run_opts]
    cd $prev_dir
    if {$run_failed} {
        if {$run_output ne ""} {
            puts $run_output
        }
        error "direct-flow run failed for $run_name: $run_opts"
    }
    if {$run_output ne ""} {
        puts $run_output
    }
}

proc run_manual_shadow_top_flow {workspace_root runs_root out_xsa} {
    set top_name [get_property top [get_filesets sources_1]]
    set part_name [get_property PART [current_project]]
    set synth_dir [file join $runs_root "synth_1"]
    set impl_dir [file join $runs_root "impl_1"]
    set synth_dcp [file join $synth_dir "${top_name}.dcp"]
    set routed_dcp [file join $impl_dir "${top_name}_routed.dcp"]
    set bit_path [file join $impl_dir "${top_name}.bit"]
    set root_bit [file join $workspace_root "${top_name}.bit"]
    set skip_timing_reports [expr {[info exists ::env(SHADOW_SKIP_TIMING_REPORTS)] && $::env(SHADOW_SKIP_TIMING_REPORTS) ne "" && $::env(SHADOW_SKIP_TIMING_REPORTS) ne "0"}]

    if {$top_name eq ""} {
        error "manual top flow requires a locked top module"
    }

    foreach run_dir [list $synth_dir $impl_dir] {
        if {![file exists $run_dir]} {
            file mkdir $run_dir
        }
    }

    foreach stale_path [list \
        $synth_dcp \
        $routed_dcp \
        $bit_path \
        $root_bit \
        $out_xsa \
    ] {
        catch {file delete -force $stale_path}
    }

    puts "Manual top flow synth start: $top_name"
    update_compile_order -fileset sources_1
    synth_design \
        -top $top_name \
        -part $part_name \
        -flatten_hierarchy rebuilt \
        -control_set_opt_threshold 1 \
        -directive AreaOptimized_high
    write_checkpoint -force $synth_dcp
    catch {report_utilization -file [file join $synth_dir "${top_name}_utilization_synth.rpt"]}
    if {!$skip_timing_reports} {
        catch {report_timing_summary -file [file join $synth_dir "${top_name}_timing_summary_synth.rpt"] -warn_on_violation}
    } else {
        puts "Skipping timing summary reports because SHADOW_SKIP_TIMING_REPORTS is set."
    }

    puts "Manual top flow impl start: $top_name"
    opt_design -directive Explore
    power_opt_design
    place_design -directive Explore
    catch {report_utilization -file [file join $impl_dir "${top_name}_utilization_place.rpt"]}
    if {!$skip_timing_reports} {
        catch {report_timing_summary -file [file join $impl_dir "${top_name}_timing_summary_place.rpt"] -warn_on_violation}
    }
    phys_opt_design -directive Explore
    route_design -directive Explore -tns_cleanup
    phys_opt_design -directive Explore
    catch {report_drc -file [file join $impl_dir "${top_name}_drc_routed.rpt"] -pb [file join $impl_dir "${top_name}_drc_routed.pb"]}
    catch {report_methodology -file [file join $impl_dir "${top_name}_methodology_routed.rpt"] -pb [file join $impl_dir "${top_name}_methodology_routed.pb"]}
    catch {report_power -file [file join $impl_dir "${top_name}_power_routed.rpt"] -pb [file join $impl_dir "${top_name}_power_routed.pb"]}
    catch {report_utilization -file [file join $impl_dir "${top_name}_utilization_routed.rpt"] -pb [file join $impl_dir "${top_name}_utilization_routed.pb"]}
    if {!$skip_timing_reports} {
        catch {report_timing_summary -file [file join $impl_dir "${top_name}_timing_summary_routed.rpt"] -warn_on_violation}
    }
    write_checkpoint -force $routed_dcp
    write_bitstream -force $bit_path
    file copy -force $bit_path $root_bit
    write_hw_platform -fixed -force -file $out_xsa
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

proc ensure_shadow_tx_tready_default_ready {} {
    set tready_pin [get_bd_pins -quiet dma_gateway_hybrid_0/i_tx_axis_tready]
    if {[llength $tready_pin] == 0} {
        error "ZERO_COPY_FASTPATH_EGRESS_STEP1 missing refreshed BD pin dma_gateway_hybrid_0/i_tx_axis_tready"
    }

    set existing_nets [get_bd_nets -quiet -of_objects $tready_pin]
    if {[llength $existing_nets] != 0} {
        puts "Shadow TX tready already connected: [lindex $existing_nets 0]"
        return
    }

    set const_cell [get_bd_cells -quiet shadow_tx_tready_const]
    if {[llength $const_cell] == 0} {
        set const_cell [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 shadow_tx_tready_const]
    }
    set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] $const_cell

    set const_pin [get_bd_pins shadow_tx_tready_const/dout]
    set const_nets [get_bd_nets -quiet -of_objects $const_pin]
    if {[llength $const_nets] == 0} {
        connect_bd_net $const_pin $tready_pin
    } else {
        connect_bd_net [lindex $const_nets 0] $tready_pin
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
    {"rtl/inc/pkg_axi_stream.sv" "SystemVerilog"}
    {"rtl/if/axi_stream_if.sv" "SystemVerilog"}
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

if {$expose_fastpath_tx_ports} {
    # ZERO_COPY_FASTPATH_EGRESS_STEP1: refresh module_ref ports after wrapper TX egress exposure
    ensure_shadow_fastpath_tx_pins_external
} else {
    # o_tx_axis advertises HAS_TREADY=0 in the generated BD interface. When the
    # scalar ready pin is not exposed, Vivado ties the disconnected input low;
    # drive it high so the diagnostic PBM passthrough sink behaves as always-ready.
    ensure_shadow_tx_tready_default_ready
    puts "Skipping fastpath TX external port exposure for board export; tying shadow TX ready high."
}
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
#
# Force local run scheduling. In this environment, the default vrs/cluster
# path can leave OOC runs stuck at "Running synth_design..." without producing
# worker logs or DCP outputs.
set_param runs.enableClusterConf 0
set_param runs.monitorLSFJobs 0
# Clear stale scheduler metadata left by interrupted runs so launch_runs can
# regenerate a clean local dispatch plan.
set jobs_dir [file join $runs_root ".jobs"]
if {[file exists $jobs_dir]} {
    catch {file delete -force $jobs_dir}
}
foreach run_dir [glob -nocomplain [file join $runs_root "*"]] {
    if {![file isdirectory $run_dir]} {
        continue
    }
    foreach stale_marker [concat \
        [glob -nocomplain [file join $run_dir ".vivado*.rst"]] \
        [glob -nocomplain [file join $run_dir ".Vivado*.rst"]] \
    ] {
        catch {file delete -force $stale_marker}
    }
}
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
lock_shadow_wrapper_top
update_compile_order -fileset sources_1
if {$direct_script_flow} {
    set direct_ooc_runs [create_ip_run $raw_bd_obj]
    if {[llength $direct_ooc_runs] == 0} {
        error "create_ip_run did not return any shadow-mirror OOC runs"
    }
    foreach shadow_run_name $direct_ooc_runs {
        launch_runs $shadow_run_name -scripts_only
        set run_script [find_single_run_tcl [file join $runs_root $shadow_run_name]]
        if {![file exists $run_script]} {
            error "required OOC run script missing after -scripts_only generation: $run_script"
        }
    }
    close_project

    foreach shadow_run_name $direct_ooc_runs {
        run_direct_vivado_run $shadow_run_name [file join $runs_root $shadow_run_name]
    }

    reopen_shadow_project $project_file
    set_property source_mgmt_mode All [current_project]
    keep_shadow_inactive_sources_disabled
    foreach support_src_info {
        {"rtl/inc/pkg_axi_stream.sv" "SystemVerilog"}
        {"rtl/if/axi_stream_if.sv" "SystemVerilog"}
        {"rtl/inc/dma_csr_pkg.sv" "SystemVerilog"}
    } {
        ensure_design_source [file join $repo_root [lindex $support_src_info 0]] [lindex $support_src_info 1]
    }
    if {[llength [get_files -quiet $raw_bd]] == 0} {
        add_files -norecurse $raw_bd
    }
    open_bd_design $raw_bd
    lock_shadow_wrapper_top
    update_compile_order -fileset sources_1
    run_manual_shadow_top_flow $workspace_root $runs_root $out_xsa
} else {
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
}
puts "Exported XSA: $out_xsa"
close_project
