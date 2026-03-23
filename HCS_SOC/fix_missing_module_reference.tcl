# ============================================================
# FIX MISSING MODULE REFERENCE SCRIPT
# ============================================================
puts "\n============================================"
puts "  FIX MISSING MODULE REFERENCE"
puts "============================================"
puts "Restoring dma_subsystem_wrapper.v reference"
puts "============================================\n"

# ============================================================
# Step 1: Locate the missing file
# ============================================================
puts "[1/6] Locating dma_subsystem_wrapper.v..."

set missing_file_path "D:/FPGAhanjia/Hetero_SoC_2026/rtl/core/dma/dma_subsystem_wrapper.v"

if {[file exists $missing_file_path]} {
    puts "   ✓ Found file on disk: $missing_file_path"
} else {
    puts "   ✗ ERROR: File not found at: $missing_file_path"
    puts "   Searching for file in project directory..."

    set proj_dir [get_property DIRECTORY [current_project]]
    set found_files [glob -nocomplain "${proj_dir}/**/dma_subsystem_wrapper.v"]

    if {[llength $found_files] > 0} {
        set missing_file_path [lindex $found_files 0]
        puts "   ✓ Found file at: $missing_file_path"
    } else {
        puts "   ✗ ERROR: File not found anywhere in project"
        return -code error "Critical file missing: dma_subsystem_wrapper.v"
    }
}

# ============================================================
# Step 2: Check if file is already in project
# ============================================================
puts "\n[2/6] Checking if file is in project..."

set existing_file [get_files -quiet *dma_subsystem_wrapper.v]
if {$existing_file ne ""} {
    puts "   File already in project: $existing_file"

    # Check if it's enabled
    set is_enabled [get_property is_enabled $existing_file]
    if {!$is_enabled} {
        puts "   File is disabled, enabling it..."
        set_property is_enabled true $existing_file
        puts "   ✓ File enabled"
    } else {
        puts "   ✓ File is already enabled"
    }
} else {
    puts "   File not in project, adding it..."
    add_files -norecurse $missing_file_path
    puts "   ✓ File added to project"
}

# ============================================================
# Step 3: Set file properties
# ============================================================
puts "\n[3/6] Setting file properties..."

set wrapper_file [get_files *dma_subsystem_wrapper.v]
set_property is_enabled true $wrapper_file
set_property used_in {synthesis implementation simulation} $wrapper_file
puts "   ✓ File properties set"

# ============================================================
# Step 4: Update Block Design module reference
# ============================================================
puts "\n[4/6] Updating Block Design module reference..."

set bd_file [get_files -quiet *system.bd]
if {$bd_file ne ""} {
    puts "   Opening Block Design..."
    open_bd_design $bd_file

    # Find the dma_subsystem_wrapper cell
    set wrapper_cell [get_bd_cells -quiet dma_subsystem_wrapper_0]
    if {$wrapper_cell ne ""} {
        puts "   Found cell: $wrapper_cell"

        # Update module reference
        set result [catch {
            update_module_reference $wrapper_cell
            puts "   ✓ Module reference updated"
        } err]

        if {$result != 0} {
            puts "   WARNING: update_module_reference failed: $err"
            puts "   Trying to refresh the cell..."

            # Alternative: refresh the cell
            catch {
                refresh_bd_cell $wrapper_cell
                puts "   ✓ Cell refreshed"
            }
        }

        # Validate design
        puts "   Validating Block Design..."
        set val_result [catch {validate_bd_design} val_msg]
        if {$val_result == 0} {
            puts "   ✓ Block Design validation passed"
        } else {
            puts "   WARNING: Validation messages: $val_msg"
        }

        # Save design
        puts "   Saving Block Design..."
        save_bd_design
        puts "   ✓ Block Design saved"

    } else {
        puts "   WARNING: dma_subsystem_wrapper_0 cell not found in Block Design"
        puts "   Available cells:"
        set all_cells [get_bd_cells]
        foreach cell $all_cells {
            puts "      - $cell"
        }
    }
} else {
    puts "   WARNING: Block Design file not found"
}

# ============================================================
# Step 5: Verify Top Module setting
# ============================================================
puts "\n[5/6] Verifying Top Module setting..."

set current_top [get_property top [current_fileset]]
puts "   Current Top: $current_top"

if {$current_top ne "system_wrapper"} {
    puts "   Setting Top to system_wrapper..."
    set_property top system_wrapper [current_fileset]
    puts "   ✓ Top module set"
} else {
    puts "   ✓ Top module is correct"
}

# Update compile order
puts "   Updating compile order..."
update_compile_order -fileset sources_1
puts "   ✓ Compile order updated"

# ============================================================
# Step 6: Reset and Launch Synthesis
# ============================================================
puts "\n[6/6] Resetting and launching synthesis..."

puts "   Resetting synthesis run..."
reset_run synth_1

puts "   Launching synthesis (8 jobs)..."
launch_runs synth_1 -jobs 8

puts "   Waiting for synthesis to complete..."
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]

puts "\n============================================"
puts "  SYNTHESIS RESULT"
puts "============================================"
puts "Status: $synth_status"
puts "Progress: $synth_progress"

if {[string match "*Complete*" $synth_status] || [string match "*100%*" $synth_progress]} {
    puts "\n✓✓✓ SYNTHESIS SUCCESSFUL ✓✓✓"
    puts "\nNext step: Launch implementation"
    puts "   launch_runs impl_1 -to_step write_bitstream -jobs 8"
} else {
    puts "\n✗✗✗ SYNTHESIS FAILED ✗✗✗"
    set synth_log "[get_property DIRECTORY [get_runs synth_1]]/runme.log"
    puts "Check log: $synth_log"
    return -code error "Synthesis failed"
}

puts "============================================"
