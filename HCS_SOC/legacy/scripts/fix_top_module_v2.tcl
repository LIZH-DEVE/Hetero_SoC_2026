# ============================================================
# ROBUST FIX TOP MODULE SCRIPT (V2)
# Enhanced version with comprehensive wrapper file search
# ============================================================

puts "\n============================================"
puts "  ROBUST TOP MODULE FIX (V2)"
puts "============================================"
puts "Enhanced search for wrapper files"
puts "Covers both .srcs and .gen directories"
puts "============================================\n"

# ============================================================
# Step 1: Locate Block Design
# ============================================================
puts "[1/7] Locating Block Design file..."
set bd_file [get_files -quiet *system.bd]
if {$bd_file eq ""} {
    puts "   ERROR: system.bd not found!"
    return -code error "system.bd missing"
}
puts "   ✓ Target BD: $bd_file"

# ============================================================
# Step 2: Force Generate Wrapper
# ============================================================
puts "\n[2/7] Forcing generation of HDL Wrapper..."
set result [catch {
    make_wrapper -files $bd_file -top -force
} err]

if {$result != 0} {
    puts "   WARNING: make_wrapper returned: $err"
    puts "   Continuing with search anyway..."
} else {
    puts "   ✓ Wrapper generation command executed"
}

# Small delay to ensure file system writes complete
after 500

# ============================================================
# Step 3: Comprehensive Wrapper File Search
# ============================================================
puts "\n[3/7] Searching for generated wrapper file..."

# Get project directory
set proj_dir [get_property DIRECTORY [current_project]]
puts "   Project directory: $proj_dir"

# Define wrapper file names
set wrapper_names [list "system_wrapper.v" "system_wrapper.sv"]

# Define search patterns (covering all possible locations)
set search_patterns [list]

# Pattern 1: .gen directory (Vivado 2020+)
lappend search_patterns "${proj_dir}/HCS_SOC.gen/sources_1/bd/system/hdl"
lappend search_patterns "${proj_dir}/*.gen/sources_1/bd/system/hdl"

# Pattern 2: .srcs directory (older Vivado)
lappend search_patterns "${proj_dir}/HCS_SOC.srcs/sources_1/bd/system/hdl"
lappend search_patterns "${proj_dir}/*.srcs/sources_1/bd/system/hdl"

# Pattern 3: Direct BD directory
set bd_dir [file dirname $bd_file]
lappend search_patterns "${bd_dir}/hdl"

puts "   Searching in multiple locations..."

set found_wrapper ""

# Search in each pattern
foreach pattern $search_patterns {
    # Expand glob patterns
    set dirs [glob -nocomplain -directory $proj_dir -type d *]

    # Try direct path first
    foreach wrapper_name $wrapper_names {
        set test_path "${pattern}/${wrapper_name}"
        if {[file exists $test_path]} {
            set found_wrapper $test_path
            puts "   ✓ Found: $test_path"
            break
        }
    }

    if {$found_wrapper ne ""} {
        break
    }
}

# If not found, try recursive search
if {$found_wrapper eq ""} {
    puts "   Standard search failed, trying recursive search..."

    foreach wrapper_name $wrapper_names {
        # Search in .gen directory
        set gen_files [glob -nocomplain "${proj_dir}/**/${wrapper_name}"]
        if {[llength $gen_files] > 0} {
            set found_wrapper [lindex $gen_files 0]
            puts "   ✓ Found via recursive search: $found_wrapper"
            break
        }
    }
}

# If still not found, check if already in project
if {$found_wrapper eq ""} {
    puts "   File not found on disk, checking if already in project..."
    set existing_wrapper [get_files -quiet *system_wrapper.v]
    if {$existing_wrapper eq ""} {
        set existing_wrapper [get_files -quiet *system_wrapper.sv]
    }

    if {$existing_wrapper ne ""} {
        set found_wrapper $existing_wrapper
        puts "   ✓ Found existing wrapper in project: $found_wrapper"
    }
}

# Final check
if {$found_wrapper eq ""} {
    puts "\n   ✗ ERROR: Wrapper file not found!"
    puts "\n   Attempted search locations:"
    foreach pattern $search_patterns {
        puts "      - $pattern"
    }
    puts "\n   Please manually locate 'system_wrapper.v' or 'system_wrapper.sv'"
    puts "   and add it to the project using: add_files -norecurse <path>"
    return -code error "Wrapper search failed"
}

# ============================================================
# Step 4: Remove Old Wrapper (if different)
# ============================================================
puts "\n[4/7] Checking for old wrapper files..."
set old_wrappers [get_files -quiet *system_wrapper.*]
set removed_count 0

foreach old_wrapper $old_wrappers {
    # Don't remove if it's the same file we just found
    if {[file normalize $old_wrapper] ne [file normalize $found_wrapper]} {
        puts "   Removing old wrapper: $old_wrapper"
        catch {remove_files $old_wrapper}
        incr removed_count
    }
}

if {$removed_count > 0} {
    puts "   ✓ Removed $removed_count old wrapper(s)"
} else {
    puts "   ✓ No old wrappers to remove"
}

# ============================================================
# Step 5: Add Wrapper to Project
# ============================================================
puts "\n[5/7] Adding wrapper to project..."
set result [catch {
    add_files -norecurse $found_wrapper
    puts "   ✓ Wrapper added: $found_wrapper"
} err]

if {$result != 0} {
    if {[string match "*already exists*" $err]} {
        puts "   ✓ Wrapper already in project"
    } else {
        puts "   WARNING: $err"
    }
}

# ============================================================
# Step 6: Set as Top Module
# ============================================================
puts "\n[6/7] Setting Top Module..."
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
# Step 7: Verify Configuration
# ============================================================
puts "\n[7/7] Verifying configuration..."

set final_top [get_property top [current_fileset]]
puts "   Current Top Module: $final_top"

# List wrapper files in project
set wrapper_files [get_files -quiet *system_wrapper.*]
if {[llength $wrapper_files] > 0} {
    puts "   Wrapper files in project:"
    foreach wf $wrapper_files {
        puts "      $wf"
    }
}

# Final verification
if {$final_top eq "system_wrapper"} {
    puts "\n============================================"
    puts "  ✓✓✓ SUCCESS ✓✓✓"
    puts "============================================"
    puts "Top module correctly set to: system_wrapper"
    puts "Wrapper file: $found_wrapper"
    puts ""
    puts "Next steps:"
    puts "  1. Reset runs:"
    puts "     reset_run synth_1"
    puts "     reset_run impl_1"
    puts ""
    puts "  2. Launch synthesis:"
    puts "     launch_runs synth_1 -jobs 8"
    puts "     wait_on_run synth_1"
    puts ""
    puts "  3. Launch implementation:"
    puts "     launch_runs impl_1 -to_step write_bitstream -jobs 8"
    puts "     wait_on_run impl_1"
    puts "============================================\n"
} else {
    puts "\n============================================"
    puts "  ✗ WARNING ✗"
    puts "============================================"
    puts "Top module is: $final_top"
    puts "Expected: system_wrapper"
    puts ""
    puts "Troubleshooting:"
    puts "  1. Check Sources window in Vivado GUI"
    puts "  2. Right-click system_wrapper.v and select 'Set as Top'"
    puts "  3. Or run: set_property top system_wrapper [current_fileset]"
    puts "============================================\n"
    return -code error "Top module verification failed"
}

# ============================================================
# Additional Information
# ============================================================
puts "Project source files:"
set all_sources [get_files -of_objects [get_filesets sources_1]]
set count 0
set top_module [get_property top [current_fileset]]
foreach src $all_sources {
    set file_type [get_property FILE_TYPE $src]
    set file_name [file tail $src]
    # Check if this file contains the top module
    if {[string match "*${top_module}*" $file_name]} {
        puts "   \[TOP\] $src ($file_type)"
    }
    incr count
}
puts "   Total source files: $count"

puts "\n============================================"
puts "  ROBUST TOP MODULE FIX - COMPLETE"
puts "============================================"
