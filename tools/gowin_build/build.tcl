# build.tcl -- headless Gowin build: synthesis + place & route + bitstream.
#
# Usage (from a shell with the Gowin environment set, see run_gowin.sh):
#   NAME=myproj TOP=my_top SRC=top.v:other.v:pins.cst:timing.sdc gw_sh build.tcl
#
# The project is created in ./$NAME/; the bitstream lands in
# ./$NAME/impl/pnr/$NAME.fs.  SRC is a ':'-separated list; .cst and .sdc
# files go in the same list.  Paths are normalized to absolute first because
# create_project changes directory.
#
# Set SYNTH_ONLY=1 to stop after synthesis (fast; gives a netlist in
# ./$NAME/impl/gwsynthesis/$NAME.vg for gate-level simulation).
set here [file normalize [pwd]]

proc envdef {key def} {
    if {[info exists ::env($key)] && $::env($key) ne ""} { return $::env($key) }
    return $def
}

set name   [envdef NAME   "proj"]
set part   [envdef PART   "GW5AST-LV138PG484AC1/I0"]
set devver [envdef DEVVER "C"]
set top    [envdef TOP    "top"]
set srcenv [envdef SRC    ""]
set synth_only [envdef SYNTH_ONLY "0"]

# normalize BEFORE create_project: it changes directory into ./$name
set files {}
foreach s [split $srcenv ":"] {
    if {$s eq ""} { continue }
    lappend files [file normalize $s]
}
create_project -name $name -dir $here -pn $part -device_version $devver -force
foreach f $files { add_file $f }
set_option -top_module $top
set_option -verilog_std sysv2017
set_option -synthesis_tool gowinsynthesis
if {$synth_only ne "0"} {
    run syn
} else {
    run all
}
puts "BUILD_DONE"
