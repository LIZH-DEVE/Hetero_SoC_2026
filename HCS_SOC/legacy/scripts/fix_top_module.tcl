# ============================================================
# FIX TOP MODULE SCRIPT
# ============================================================
# This script fixes the "IO Placement failed" error caused by
# incorrect Top Module setting. It ensures system_wrapper
# (the Block Design wrapper) is set as the top module.
# ============================================================

puts "\n============================================"
puts "  FIX TOP MODULE"
puts "============================================"
puts "Fixing incorrect Top Module setting..."
puts "Target: system_wrapper (Block Design wrapper)"
puts "============================================\n"

# ============================================================
# Step 1: Get Block Design File
# ============================================================
puts "[1/8] Locating Block Design file..."
set bd_file [get_files -quiet *system.bd]
if {$bd_file eq ""} {
    puts "   ERROR: system.bd not found!"
    puts "   Searching in all filesets..."
    set bd_file [get_files -quiet -of_objects [get_filesets] *.bd]
    if {$bd_file eq ""} {
        return -code error "Error: No Block Design file found in project!"
    }
}
puts "   ✓ Found: $bd_file"

# ============================================================
# Step 2: Check Current Top Module
# ============================================================
puts "\n[2/8] Checking current Top Module..."
set current_top [get_property top [current_fileset]]
puts "   Current Top: $current_top"

if {$current_top eq "system_wrapper"} {
    puts "   INFO: Top is already system_wrapper, but may need regeneration"
}

# ============================================================
# Step 3: Remove Old Wrapper (if exists)
# ============================================================
puts "\n[3/8] Cleaning up old wrapper files..."
set old_wrappers [get_files -quiet *system_wrapper.v]
if {$old_wrappers ne ""} {
    foreach wrapper $old_wrappers {
        puts "   Removing old wrapper: $wrapper"
        catch {remove_files $wrapper}
    }
}
set old_wrappers_sv [get_files -quiet *system_wrapper.sv]
if {$old_wrappers_sv ne ""} {
    foreach wrapper $old_wrappers_sv {
        puts "   Removing old wrapper: $wrapper"
        catch {remove_files $wrapper}
    }
}
puts "   ✓ Cleanup complete"

# ============================================================
# Step 4: Generate HDL Wrapper
# ============================================================
puts "\n[4/8] Generating HDL Wrapper for Block Design..."
set result [catch {
    make_wrapper -files $bd_file -top
} err]

if {$result != 0} {
    puts "   WARNING: make_wrapper returned: $err"
    puts "   Continuing anyway..."
} else {
    puts "   ✓ Wrapper generation command executed"
}

# ============================================================
# Step 5: Locate Generated Wrapper File
# ============================================================
puts "\n[5/8] Locating generated wrapper file..."
set bd_dir [file dirname $bd_file]
set wrapper_path "${bd_dir}/hdl/system_wrapper.v"
set wrapper_path_sv "${bd_dir}/hdl/system_wrapper.sv"

set wrapper_file ""
if {[file exists $wrapper_path]} {
    set wrapper_file $wrapper_path
    puts "   ✓ Found Verilog wrapper: $wrapper_path"
} elseif {[file exists $wrapper_path_sv]} {
    set wrapper_file $wrapper_path_sv
    puts "   ✓ Found SystemVerilog wrapper: $wrapper_path_sv"
} else {
    puts "   WARNING: Wrapper file not found at expected location"
    puts "   Searching for wrapper in project..."
    set wrapper_file [get_files -quiet *system_wrapper.v]
    if {$wrapper_file eq ""} {
        set wrapper_file [get_files -quiet *system_wrapper.sv]
    }
    if {$wrapper_file ne ""} {
        puts "   ✓ Found existing wrapper in project: $wrapper_file"
    } else {
        puts "   ERROR: Cannot locate wrapper file!"
        return -code error "Wrapper file not found"
    }
}

# ============================================================
# Step 6: Add Wrapper to Project
# ============================================================
puts "\n[6/8] Adding wrapper to project..."
if {$wrapper_file ne ""} {
    set result [catch {
        add_files -norecurse $wrapper_file
        puts "   ✓ Wrapper added to project"
    } err]
    if {$result != 0} {
        puts "   INFO: $err (may already exist)"
    }
} else {
    puts "   ERROR: No wrapper file to add!"
    return -code error "No wrapper file available"
}

# ============================================================
# Step 7: Set Top Module
# ============================================================
puts "\n[7/8] Setting Top Module to system_wrapper..."
set result [catch {
    set_property top system_wrapper [current_fileset]
    puts "   ✓ Top module set to: system_wrapper"
} err]

if {$result != 0} {
    puts "   ERROR: Failed to set top module: $err"
    return -code error "Failed to set top module"
}

# Update compile order
puts "   Updating compile order..."
update_compile_order -fileset sources_1
puts "   ✓ Compile order updated"

# ============================================================
# Step 8: Verify and Report
# ============================================================
puts "\n[8/8] Verifying configuration..."
set final_top [get_property top [current_fileset]]
puts "   Final Top Module: $final_top"

if {$final_top eq "system_wrapper"} {
    puts "\n============================================"
    puts "  ✓✓✓ SUCCESS ✓✓✓"
    puts "============================================"
    puts "Top module correctly set to: system_wrapper"
    puts ""
    puts "Next steps:"
    puts "  1. Reset synthesis: reset_run synth_1"
    puts "  2. Launch synthesis: launch_runs synth_1 -jobs 8"
    puts "  3. Launch implementation: launch_runs impl_1 -to_step write_bitstream -jobs 8"
    puts "============================================\n"
} else {
    puts "\n============================================"
    puts "  ✗ WARNING ✗"
    puts "============================================"
    puts "Top module is: $final_top"
    puts "Expected: system_wrapper"
    puts "Please check project configuration manually."
    puts "============================================\n"
    return -code error "Top module verification failed"
}

# ============================================================
# Optional: Show all source files for verification
# ============================================================
puts "Current source files in project:"
set all_sources [get_files -of_objects [get_filesets sources_1]]
foreach src $all_sources {
    set is_top [get_property IS_TOP $src]
    if {$is_top} {
        puts "   [TOP] $src"
    } else {
        puts "         $src"
    }
}

puts "\n============================================"
puts "  FIX TOP MODULE - COMPLETE"
puts "============================================"
