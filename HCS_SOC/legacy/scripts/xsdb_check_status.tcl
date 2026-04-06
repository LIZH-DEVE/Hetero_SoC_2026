proc select_first_matching {patterns} {
    foreach pattern $patterns {
        if {![catch {targets -set -filter [format {name =~ "%s"} $pattern]}]} {
            return $pattern
        }
    }
    error [format "no targets found for patterns: %s" [join $patterns ", "]]
}

connect
select_first_matching [list "*Cortex-A9 MPCore #0*" "*APU*"]
catch {stop}
configparams force-mem-access 1

puts "\n===== Read STATUS Register (0x43C00008) ====="
set status [mrd -value 0x43C00008]
puts "STATUS = 0x[format %08X $status]"

set fingerprint [expr {($status >> 20) & 0xFFF}]
puts "Hardware Fingerprint = 0x[format %03X $fingerprint]"

if {$fingerprint == 0xACE} {
    puts "\nPASS: hardware fingerprint matches 0xACE"
} else {
    puts "\nINFO: fingerprint 0xACE not present at 0x43C00008. Checking Stage1 control window..."
    set net_cfg0 [mrd -value 0x40000090]
    set net_applied_cfg0 [mrd -value 0x400000BC]
    set net_applied_ip [mrd -value 0x400000C0]
    puts "NET_CFG0          = 0x[format %08X $net_cfg0]"
    puts "NET_APPLIED_CFG0  = 0x[format %08X $net_applied_cfg0]"
    puts "NET_APPLIED_IP    = 0x[format %08X $net_applied_ip]"
    if {$net_applied_cfg0 == $net_cfg0 && $net_applied_ip != 0} {
        puts "PASS: Stage1 control path is present (system_wrapper mode)."
    } else {
        puts "FAIL: neither ACE fingerprint nor valid Stage1 applied controls detected."
    }
}
