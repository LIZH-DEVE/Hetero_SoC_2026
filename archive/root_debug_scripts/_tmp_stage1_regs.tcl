proc select_first_matching {patterns} {
    foreach pattern $patterns {
        if {![catch {targets -set -filter [format {name =~ "%s"} $pattern]}]} {
            return $pattern
        }
    }
    error [format "no targets found for patterns: %s" [join $patterns ", "]]
}
connect
select_first_matching [list "*Cortex-A9 MPCore #0*" "*DAP*"]
configparams force-mem-access 1
foreach addr {0x43C00090 0x43C000A0 0x43C000A8 0x43C000B0 0x43C000B4} {
  puts [format "0x%08X = 0x%08X" $addr [mrd -value $addr]]
}
exit
