connect
targets -set -nocase -filter {name =~ "arm*#0"}
rst -system
after 2000
mrd 0x43C00008 1
exit
