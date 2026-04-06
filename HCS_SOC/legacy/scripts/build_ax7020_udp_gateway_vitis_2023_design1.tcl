set script_dir [file normalize [file dirname [info script]]]
set workspace_dir [file normalize "$script_dir/vitis_2023_udp_gateway_ws_design1"]
set app_src_dir [file normalize "$script_dir/ax7020_official_net_test_app/src"]
set xsa_path [file normalize "$script_dir/platform/export/platform/hw/design_1_wrapper.xsa"]
set vitis_root "D:/Xilinx/Vitis/2023.1"
set ws2_bsp_include_dir [file normalize "$script_dir/vitis_2023_udp_gateway_ws_2/ax7020_udp_gateway_platform/ps7_cortexa9_0/standalone_domain/bsp/ps7_cortexa9_0/include"]
set standalone_common_dir [file normalize "$vitis_root/data/embeddedsw/lib/bsp/standalone_v8_1/src/common"]
set standalone_arm_common_dir [file normalize "$vitis_root/data/embeddedsw/lib/bsp/standalone_v8_1/src/arm/common"]

set platform_name ax7020_udp_gateway_platform_design1
set app_name ax7020_udp_gateway_app

proc copy_tree_contents {src_dir dst_dir} {
    file mkdir $dst_dir
    foreach entry [glob -nocomplain -directory $src_dir *] {
        set dst [file join $dst_dir [file tail $entry]]
        if {[file isdirectory $entry]} {
            copy_tree_contents $entry $dst
        } else {
            file copy -force $entry $dst
        }
    }
}

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

set bsp_include_dir [file normalize "$workspace_dir/$platform_name/ps7_cortexa9_0/standalone_domain/bsp/ps7_cortexa9_0/include"]
set generated_standalone_src_dir [file normalize "$workspace_dir/$platform_name/ps7_cortexa9_0/standalone_domain/bsp/ps7_cortexa9_0/libsrc/standalone_v8_1/src"]
set pseudo_asm_src_dir [file normalize "$vitis_root/data/embeddedsw/lib/bsp/standalone_v8_1/src/arm/cortexa9"]
foreach header_dir [list $generated_standalone_src_dir $standalone_common_dir $standalone_arm_common_dir $pseudo_asm_src_dir] {
    foreach src [glob -nocomplain -directory $header_dir *.h] {
        file copy -force $src [file join $bsp_include_dir [file tail $src]]
    }
}

foreach header {xpseudo_asm_gcc.h} {
    set src [file join $ws2_bsp_include_dir $header]
    set dst [file join $bsp_include_dir $header]
    if {![file exists $src]} {
        error "Missing required generated Cortex-A9 header: $src"
    }
    file copy -force $src $dst
}

platform generate

set bsp_include_src_dir [file normalize "$workspace_dir/$platform_name/ps7_cortexa9_0/standalone_domain/bsp/ps7_cortexa9_0/include"]
set export_bsp_include_dir [file normalize "$workspace_dir/$platform_name/export/$platform_name/sw/$platform_name/standalone_domain/bspinclude/include"]
copy_tree_contents $bsp_include_src_dir $export_bsp_include_dir

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

set app_debug_subdir_mk [file normalize "$app_proj_dir/Debug/src/subdir.mk"]
if {[file exists $app_debug_subdir_mk]} {
    set fh [open $app_debug_subdir_mk r]
    set subdir_mk_data [read $fh]
    close $fh
    set export_include_quoted [file nativename $export_bsp_include_dir]
    set bsp_include_quoted [file nativename $bsp_include_src_dir]
    set subdir_mk_data [string map [list $export_include_quoted $bsp_include_quoted] $subdir_mk_data]
    set fh [open $app_debug_subdir_mk w]
    puts -nonewline $fh $subdir_mk_data
    close $fh
}

platform generate

sysproj build -name ${app_name}_system

puts "BUILD_DONE"
exit
