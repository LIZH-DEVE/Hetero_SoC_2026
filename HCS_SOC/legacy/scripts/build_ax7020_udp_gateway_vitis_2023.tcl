set script_dir [file normalize [file dirname [info script]]]
set workspace_dir [file normalize "$script_dir/vitis_2023_udp_gateway_ws_2"]
set app_src_dir [file normalize "$script_dir/ax7020_official_net_test_app/src"]
set xsa_path [file normalize "$script_dir/platform/export/platform/hw/system_wrapper.xsa"]

set platform_name ax7020_udp_gateway_platform
set app_name ax7020_udp_gateway_app

puts "Workspace: $workspace_dir"
puts "XSA: $xsa_path"
puts "App sources: $app_src_dir"

setws $workspace_dir

platform create -name $platform_name -hw $xsa_path -proc ps7_cortexa9_0 -os standalone -arch 32-bit -out $workspace_dir
platform active $platform_name
domain active standalone_domain

bsp setlib -name lwip213 -ver 1.0
bsp config lwip_dhcp false
bsp regenerate

platform generate

app create -name $app_name -platform $platform_name -domain standalone_domain -template "Empty Application"

set app_proj_dir [file normalize "$workspace_dir/$app_name"]
set app_src_out_dir [file normalize "$app_proj_dir/src"]

if {[file exists "$app_src_out_dir/platform.c"]} {
    file delete -force "$app_src_out_dir/platform.c"
}
if {[file exists "$app_src_out_dir/platform.h"]} {
    file delete -force "$app_src_out_dir/platform.h"
}
if {[file exists "$app_src_out_dir/platform_config.h"]} {
    file delete -force "$app_src_out_dir/platform_config.h"
}

file copy -force "$app_src_dir/main.c" "$app_src_out_dir/main.c"
file copy -force "$app_src_dir/platform.h" "$app_src_out_dir/platform.h"
file copy -force "$app_src_dir/platform_config.h" "$app_src_out_dir/platform_config.h"
file copy -force "$app_src_dir/platform_zynq.c" "$app_src_out_dir/platform.c"
file copy -force "$app_src_dir/udp_crypto_gateway.c" "$app_src_out_dir/udp_crypto_gateway.c"
file copy -force "$app_src_dir/udp_crypto_gateway.h" "$app_src_out_dir/udp_crypto_gateway.h"

platform generate

sysproj build -name ${app_name}_system

puts "BUILD_DONE"
exit
