create_project -in_memory tmp xc7z020clg400-1
proc max_site {pattern} {
  set sites [lsort [get_sites -quiet $pattern]]
  if {[llength $sites] == 0} {
    puts "$pattern=<none>"
  } else {
    puts "$pattern first=[lindex $sites 0] last=[lindex $sites end] count=[llength $sites]"
  }
}
max_site SLICE_*
max_site DSP48_*
max_site RAMB18_*
max_site RAMB36_*
close_project
exit
