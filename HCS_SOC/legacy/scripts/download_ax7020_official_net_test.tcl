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
        if {![catch {ps7_init} err]} {
            if {![catch {ps7_post_config} post_err]} {
                set init_ok 1
                break
            } else {
                puts "ps7_post_config failed: $post_err"
            }
        } else {
            puts "ps7_init failed: $err"
        }
    }
    if {!$init_ok} {
        error "ps7_init failed after retry"
    }
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

connect

set workspace_root [file normalize [file dirname [info script]]]
set ref_root [file normalize [file join $workspace_root ".." ".." "AX7020_2023.1" "course_s2_vitis" "06_net_test"]]
set build_root [file normalize [file join $workspace_root "ax7020_official_net_test"]]
set bit_file [file normalize [file join $ref_root "Vivado" "design_1_wrapper.bit"]]
set ps7_init_file [file normalize [file join $build_root "design_1_wrapper" "hw" "ps7_init.tcl"]]
set elf_file [file normalize [file join $workspace_root "ax7020_official_net_test_app" "build" "ax7020_official_net_test_app.elf"]]
set uart1_base 0xE0001000
set ddr_probe_addr 0x00100000

if {![file exists $bit_file]} {
    error "missing official bitstream: $bit_file"
}
if {![file exists $ps7_init_file]} {
    error "missing built ps7_init.tcl: $ps7_init_file (run build_ax7020_official_net_test.ps1 first)"
}
if {![file exists $elf_file]} {
    error "missing official net_test ELF: $elf_file (run build_ax7020_official_net_test_app.ps1 first)"
}

select_first_matching [list "*xc7z020*" "*7z020*" "*xc7z*"]
fpga -f $bit_file

select_ps_access_target
source $ps7_init_file
run_ps_init_with_retry

mwr 0xF8000008 0x0000DF0D
mwr -force 0xF800012C [expr {[mrd -value 0xF800012C] | 0x00300000}]
mwr 0xF8000004 0x0000767B
mwr $uart1_base 0x00000003
mwr [expr $uart1_base + 0x04] 0x00000020
mwr [expr $uart1_base + 0x18] 62
mwr [expr $uart1_base + 0x34] 0x00000006
mwr $uart1_base 0x00000114

prepare_ddr_and_cpu_for_download $ddr_probe_addr

select_cpu_target
catch {stop}
dow $elf_file
con
puts "PROGRAM_DONE"
