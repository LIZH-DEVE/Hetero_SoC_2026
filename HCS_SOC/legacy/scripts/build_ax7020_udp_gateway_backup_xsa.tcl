set script_dir [file normalize [file dirname [info script]]]
set workspace_dir [file normalize "$script_dir/vitis_2023_udp_gateway_backup_xsa_ws"]
set app_src_dir [file normalize "$script_dir/vitis_2023_udp_gateway_ws_2/ax7020_udp_gateway_app/src"]
set xsa_path [file normalize "$script_dir/../BACKUP_UART_WORKING_20260315/design_1_wrapper.xsa"]

set platform_name ax7020_udp_gateway_backup_platform

puts "Workspace: $workspace_dir"
puts "Backup XSA: $xsa_path"
puts "App sources: $app_src_dir"

set build_err ""
set rc [catch {
    setws $workspace_dir

    platform create -name $platform_name -hw $xsa_path -proc ps7_cortexa9_0 -os standalone -arch 32-bit -out $workspace_dir
    platform active $platform_name
    domain active standalone_domain

    bsp setlib -name lwip213 -ver 1.0
    bsp config lwip_dhcp false
    bsp regenerate

    platform generate
} build_err]

if {$rc != 0} {
    puts "BACKUP_XSA_BUILD_WARNING: $build_err"
}

set fsbl_path [file normalize "$workspace_dir/$platform_name/zynq_fsbl/fsbl.elf"]
set spec_path [file normalize "$workspace_dir/$platform_name/zynq_fsbl/Xilinx.spec"]
set xparam_path [file normalize "$workspace_dir/$platform_name/zynq_fsbl/zynq_fsbl_bsp/ps7_cortexa9_0/include/xparameters.h"]
set libxil_path [file normalize "$workspace_dir/$platform_name/zynq_fsbl/zynq_fsbl_bsp/ps7_cortexa9_0/lib/libxil.a"]

if {[file exists $fsbl_path] && [file exists $spec_path] && [file exists $xparam_path] && [file exists $libxil_path]} {
    puts "BACKUP_XSA_BUILD_DONE"
    exit 0
}

puts "BACKUP_XSA_BUILD_FAILED"
exit 1
