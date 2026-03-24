if {[llength $argv] != 3} {
    puts stderr "Usage: xsct generate_ax7020_standalone_platform_xsct.tcl <workspace_root> <xsa_path> <platform_name>"
    exit 1
}

set workspaceRoot [file normalize [lindex $argv 0]]
set xsaPath [file normalize [lindex $argv 1]]
set platformName [lindex $argv 2]

if {![file exists $xsaPath]} {
    puts stderr "XSA not found: $xsaPath"
    exit 1
}

if {![file exists $workspaceRoot]} {
    file mkdir $workspaceRoot
}

setws $workspaceRoot
platform create -name $platformName -hw $xsaPath -proc ps7_cortexa9_0 -os standalone -arch 32-bit -out $workspaceRoot
platform active $platformName
domain active standalone_domain
platform generate

puts "WORKSPACE=$workspaceRoot"
puts "PLATFORM_NAME=$platformName"
exit
