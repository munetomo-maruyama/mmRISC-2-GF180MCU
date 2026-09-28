# Cell area of the block loaded in OpenROAD, by kind of cell.
#
#   read_db <run>/<step>/cpu_core_wrap.odb
#   source core_pnr/area_breakdown.tcl
#
# Kinds: tap (filltie), endcap, fill (fill_*/fillcap_*, not counted in the
# utilisation), antenna, clock (clkbuf/clkinv: CTS, and ABC maps inverters to clkinv too), buffer
# (buf/dly/inv, synthesis + repair_design), ff (dff/lat/icg), logic (the rest).

set block [ord::get_db_block]
set dbu   [$block getDbUnitsPerMicron]
set core  [$block getCoreArea]
set core_um2 [expr {double([$core dx]) * [$core dy] / $dbu / $dbu}]

array unset area
array unset count
foreach inst [$block getInsts] {
    set m    [$inst getMaster]
    set name [$m getName]
    regsub {^gf180mcu_fd_sc_mcu7t5v0__} $name {} name
    regsub {_[0-9]+$} $name {} base
    switch -glob -- $base {
        filltie              { set k tap }
        endcap               { set k endcap }
        fill*                { set k fill }
        antenna              { set k antenna }
        clkbuf* - clkinv*    { set k clock }
        buf* - dly* - inv*   { set k buffer }
        dff* - sdff* - lat* - icg* { set k ff }
        default              { set k logic }
    }
    set a [expr {double([$m getWidth]) * [$m getHeight] / $dbu / $dbu}]
    if {![info exists area($k)]} { set area($k) 0.0; set count($k) 0 }
    set area($k)  [expr {$area($k) + $a}]
    incr count($k)
}

set total 0.0
puts [format "%-8s %9s %12s %8s" kind count "area mm2" "of core"]
foreach k {logic ff buffer clock tap endcap antenna fill} {
    if {![info exists area($k)]} continue
    puts [format "%-8s %9d %12.4f %7.1f%%" $k $count($k) [expr {$area($k)/1e6}] [expr {100*$area($k)/$core_um2}]]
    if {$k ne "fill"} { set total [expr {$total + $area($k)}] }
}
puts [format "%-8s %9s %12.4f %7.1f%%   (core %.4f mm2, fill excluded)" total "" [expr {$total/1e6}] [expr {100*$total/$core_um2}] [expr {$core_um2/1e6}]]
