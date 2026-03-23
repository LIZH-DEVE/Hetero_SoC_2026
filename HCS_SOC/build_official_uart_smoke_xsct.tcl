set scriptDir [file dirname [file normalize [info script]]]
set workspaceRoot [file join $scriptDir "ax7020_official_uart_smoke_xsct" "workspace_v2"]
set sourceRoot [file join $scriptDir "ax7020_official_uart_smoke_xsct" "src"]
set xsaPath "D:/FPGAhanjia/Hetero_SoC_2026_3/AX7020_2023.1/course_s2_vitis/06_net_test/Vitis/design_1_wrapper.xsa"
set platformName "design_1_wrapper"
set appName "official_uart_smoke"

if {![file exists $workspaceRoot]} {
    file mkdir $workspaceRoot
}

setws $workspaceRoot
platform create -name $platformName -hw $xsaPath -proc ps7_cortexa9_0 -os standalone -arch 32-bit -out $workspaceRoot
platform active $platformName
domain active standalone_domain

app create -name $appName -platform $platformName -domain standalone_domain -template "Empty Application"
importsources -name $appName -path $sourceRoot

platform generate
app build -name $appName

puts "WORKSPACE=$workspaceRoot"
puts "APP_ELF=$workspaceRoot/$appName/Debug/$appName.elf"
puts "FSBL_ELF=$workspaceRoot/$platformName/export/$platformName/sw/$platformName/zynq_fsbl/fsbl.elf"
