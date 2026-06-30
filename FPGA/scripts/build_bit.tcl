set root [file normalize [file dirname [info script]]/..]
set prj_dir $root/build/CaptainUSB
if {![file exists $prj_dir/CaptainUSB.xpr]} {
    source [file join [file dirname [info script]] create_project.tcl]
} else {
    open_project $prj_dir/CaptainUSB.xpr
}
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { puts "ERROR: synth failed"; exit 1 }
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { puts "ERROR: impl failed"; exit 1 }
set bit [file join [get_property DIRECTORY [get_runs impl_1]] captainusb_top.bit]
set tns [get_property STATS.TNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "=== BUILD SUMMARY ==="
puts "Bitstream: $bit"
puts "TNS: $tns  WHS: $whs"
if {$tns ne "" && $tns < 0.0} { puts "WARNING: setup violations" } else { puts "Timing: clean" }