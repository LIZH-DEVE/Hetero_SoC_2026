proc usage {} {
    puts stderr "Usage: xsct download_ax7020_udp_gateway_shadow_mirror_jtag.tcl -bitstream <bit> -ps7-init <ps7_init.tcl> -elf <app.elf> ?-validate-only? ?-skip-bitstream? ?-skip-run? ?-ddr-probe-addr <addr>?"
    exit 1
}

proc dump_visible_targets {} {
    set dump ""
    catch {set dump [string trim [targets]]}
    puts "JTAG_TARGET_DUMP_BEGIN"
    if {$dump eq ""} {
        puts "<none>"
    } else {
        puts $dump
    }
    puts "JTAG_TARGET_DUMP_END"
    return $dump
}

proc ensure_jtag_targets_visible {} {
    for {set attempt 0} {$attempt < 5} {incr attempt} {
        set dump ""
        catch {set dump [string trim [targets]]}
        if {$dump ne ""} {
            return
        }
        if {$attempt < 4} {
            puts "JTAG target discovery retry..."
            after 1000
        }
    }
    dump_visible_targets
    error "no JTAG targets visible to XSCT after retry; check board power, JTAG USB connection, and cable drivers"
}

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
        puts [format "selected ps-access target via %s" $chosen]
        return $chosen
    }
    set chosen [select_first_matching [list "*APU*" "*Cortex-A9 MPCore #0*"]]
    puts [format "selected ps-access fallback target via %s" $chosen]
    return $chosen
}

proc select_cpu_target {} {
    set chosen [select_first_matching [list "*Cortex-A9 MPCore #0*" "*APU*"]]
    puts [format "selected cpu target via %s" $chosen]
    return $chosen
}

proc run_ps_init_with_retry {} {
    set init_ok 0
    for {set attempt 0} {$attempt < 2} {incr attempt} {
        select_ps_access_target
        if {$attempt > 0} {
            puts "ps7_init retry after system reset..."
            catch {rst -system}
            after 500
            select_ps_access_target
        }
        if {![catch {ps7_init} init_err]} {
            if {![catch {ps7_post_config} post_err]} {
                set init_ok 1
                break
            } else {
                puts "ps7_post_config failed: $post_err"
            }
        } else {
            puts "ps7_init failed: $init_err"
        }
    }
    if {!$init_ok} {
        error "ps7_init failed after retry"
    }
}

proc configure_uart1_console {} {
    set uart1_base 0xE0001000

    select_ps_access_target
    mwr 0xF8000008 0x0000DF0D
    mwr -force 0xF800012C [expr {[mrd -value 0xF800012C] | 0x00300000}]
    mwr -force 0xF8000154 0x00002003
    mwr -force 0xF80007C0 0x000016E0
    mwr -force 0xF80007C4 0x000016E1
    mwr 0xF8000004 0x0000767B

    mwr $uart1_base 0x00000003
    mwr [expr {$uart1_base + 0x04}] 0x00000020
    mwr [expr {$uart1_base + 0x18}] 62
    mwr [expr {$uart1_base + 0x34}] 0x0000000D
    mwr $uart1_base 0x00000114
}

proc prepare_ddr_and_cpu_for_download {ddr_addr} {
    select_ps_access_target
    mwr -force $ddr_addr 0x12345678
    set probe_val [mrd -value $ddr_addr]
    if {$probe_val != 0x12345678} {
        error [format "DDR probe mismatch at 0x%08X: read 0x%08X" $ddr_addr $probe_val]
    }

    select_cpu_target
    catch {stop}
    catch {rst -processor}
    after 200
    catch {stop}
}

if {[llength $argv] < 6} {
    usage
}

set bitstream_file ""
set ps7_init_file ""
set elf_file ""
set validate_only 0
set skip_bitstream 0
set skip_run 0
set ddr_probe_addr 0x00100000

for {set idx 0} {$idx < [llength $argv]} {incr idx} {
    set arg [lindex $argv $idx]
    switch -- $arg {
        -bitstream {
            incr idx
            if {$idx >= [llength $argv]} { usage }
            set bitstream_file [file normalize [lindex $argv $idx]]
        }
        -ps7-init {
            incr idx
            if {$idx >= [llength $argv]} { usage }
            set ps7_init_file [file normalize [lindex $argv $idx]]
        }
        -elf {
            incr idx
            if {$idx >= [llength $argv]} { usage }
            set elf_file [file normalize [lindex $argv $idx]]
        }
        -validate-only {
            set validate_only 1
        }
        -skip-bitstream {
            set skip_bitstream 1
        }
        -skip-run {
            set skip_run 1
        }
        -ddr-probe-addr {
            incr idx
            if {$idx >= [llength $argv]} { usage }
            set ddr_probe_addr [expr {[lindex $argv $idx]}]
        }
        default {
            puts stderr [format "Unknown argument: %s" $arg]
            usage
        }
    }
}

if {$bitstream_file eq "" || $ps7_init_file eq "" || $elf_file eq ""} {
    usage
}

if {!$skip_bitstream && ![file exists $bitstream_file]} {
    error "missing bitstream: $bitstream_file"
}
if {![file exists $ps7_init_file]} {
    error "missing ps7_init.tcl: $ps7_init_file"
}
if {![file exists $elf_file]} {
    error "missing ELF: $elf_file"
}

puts "MODE=[expr {$validate_only ? "validate_only" : "run"}]"
puts "BITSTREAM=$bitstream_file"
puts "PS7_INIT=$ps7_init_file"
puts "ELF=$elf_file"
puts "SKIP_BITSTREAM=$skip_bitstream"
puts "SKIP_RUN=$skip_run"
puts [format "DDR_PROBE_ADDR=0x%08X" $ddr_probe_addr]

if {$validate_only} {
    puts "JTAG_VALIDATE_OK"
    exit 0
}

connect
ensure_jtag_targets_visible

if {!$skip_bitstream} {
    select_first_matching [list "*xc7z020*" "*7z020*" "*xc7z*"]
    fpga -f $bitstream_file
}

select_ps_access_target
source $ps7_init_file
run_ps_init_with_retry
configure_uart1_console
prepare_ddr_and_cpu_for_download $ddr_probe_addr

select_cpu_target
catch {stop}
dow $elf_file

if {!$skip_run} {
    con
}

puts "JTAG_RUN_DONE"
exit 0
