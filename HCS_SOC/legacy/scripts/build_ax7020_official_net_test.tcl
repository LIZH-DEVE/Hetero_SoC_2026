set script_dir [file normalize [file dirname [info script]]]
set ref_root [file normalize [file join $script_dir ".." ".." "AX7020_2023.1" "course_s2_vitis" "06_net_test"]]
set workspace_dir [file normalize [file join $script_dir "ax7020_official_net_test"]]
set xsa_file [file normalize [file join $ref_root "Vitis" "design_1_wrapper.xsa"]]
set src_dir [file normalize [file join $ref_root "Vitis" "auto_create_vitis" "src" "net_test"]]

if {![file exists $xsa_file]} {
    error "missing official XSA: $xsa_file"
}
if {![file exists $src_dir]} {
    error "missing official net_test sources: $src_dir"
}

setws $workspace_dir

set platform_name "design_1_wrapper"
set app_name "net_test"

platform create -name $platform_name -hw $xsa_file -proc ps7_cortexa9_0 -os standalone -arch 32-bit -out $workspace_dir
platform active $platform_name
domain active standalone_domain

# Keep the board reachable on a direct host link without requiring DHCP.
bsp setlib -name lwip220
bsp config lwip_dhcp false
bsp regenerate

app create -name $app_name -platform $platform_name -domain standalone_domain -template "Empty Application"
importsources -name $app_name -path $src_dir -target-path ./

platform generate
sysproj build -name "${app_name}_system"

puts "OFFICIAL_NET_TEST_BUILD_DONE"
