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

puts "NET_CFG0=0x[format %08X [mrd -value 0x43C00090]]"
puts "INJ_CTRL=0x[format %08X [mrd -value 0x43C000A0]]"
puts "INJ_STATUS=0x[format %08X [mrd -value 0x43C000A8]]"
puts "TXCAP_CTRL=0x[format %08X [mrd -value 0x43C000AC]]"
puts "TXCAP_STATUS=0x[format %08X [mrd -value 0x43C000B0]]"
puts "TXCAP_DATA=0x[format %08X [mrd -value 0x43C000B4]]"
