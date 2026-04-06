proc select_first_matching {patterns} {
    foreach pattern $patterns {
        if {![catch {targets -set -filter [format {name =~ "%s"} $pattern]}]} {
            return $pattern
        }
    }
    error [format "no targets found for patterns: %s" [join $patterns ", "]]
}
proc select_ps_access_target {} {
    if {![catch {set chosen [select_first_matching [list "*DAP*" "*PS7*"]]}]} {
        return $chosen
    }
    return [select_first_matching [list "*APU*" "*Cortex-A9 MPCore #0*"]]
}
proc write_uart_string {base text} {
    foreach ch [split $text ""] {
        scan $ch %c value
        mwr [expr {$base + 0x30}] $value
    }
}
set uart0_base 0xE0000000
connect
select_ps_access_target
mwr 0xF8000008 0x0000DF0D
mwr -force 0xF800012C [expr {[mrd -value 0xF800012C] | 0x00300000}]
mwr 0xF8000004 0x0000767B
mwr $uart0_base 0x00000003
mwr [expr {$uart0_base + 0x04}] 0x00000020
mwr [expr {$uart0_base + 0x18}] 62
mwr [expr {$uart0_base + 0x34}] 0x00000006
mwr $uart0_base 0x00000114
after 200
write_uart_string $uart0_base "UART0_PROBE\\r\\n"
puts "UART0_PROBE_SENT"
exit 0
