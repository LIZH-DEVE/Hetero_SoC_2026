proc select_first_matching {patterns} {
    foreach pattern $patterns {
        if {![catch {targets -set -filter [format {name =~ "%s"} $pattern]}]} {
            return $pattern
        }
    }
    error [format "no targets found for patterns: %s" [join $patterns ", "]]
}

connect

set bitstream_file "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit"
set ps7_init_file "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/platform/export/platform/hw/sdt/ps7_init.tcl"
set uart1_base 0xE0001000
set uart1_baud_preferred 115200
set uart1_baud_fallback 230400

select_first_matching [list "*xc7z020*"]
fpga -f $bitstream_file

select_first_matching [list "*APU*" "*Cortex-A9 MPCore #0*" "*DAP*" "*PS7*"]
source $ps7_init_file
ps7_init
ps7_post_config

# Re-enable UART1 after PL programming so COM9 uses a single authoritative setup.
# Preferred host baud is 115200. Only use 230400 as a controlled fallback check.
mwr 0xF8000008 0x0000DF0D
mwr -force 0xF800012C [expr {[mrd -value 0xF800012C] | 0x00300000}]
mwr -force 0xF8000154 0x00002003
mwr -force 0xF80007C0 0x000016E0
mwr -force 0xF80007C4 0x000016E1
mwr 0xF8000004 0x0000767B
mwr $uart1_base 0x00000003
mwr [expr $uart1_base + 0x04] 0x00000020
mwr [expr $uart1_base + 0x18] 62
mwr [expr $uart1_base + 0x34] 0x00000006
mwr $uart1_base 0x00000114

select_first_matching [list "*Cortex-A9 MPCore #0*" "*APU*"]
catch {stop}
dow D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/build/crypto_test_app.elf
con
