# Area estimate of mmRISC-2 CPU_TOP or CPU_CORE in GF180MCU (synthesis only, no P&R).
#
# Run through run_synth.sh, which sets the environment:
#   CFG      name of the configuration (output goes to out/$CFG)
#   TOP      top module (CPU_TOP or CPU_CORE)
#   FILELIST list of RTL files (files.f for CPU_TOP, files_core.f for CPU_CORE)
#   GPARAMS  top-level parameter overrides, e.g. "-G USE_BFM=0 -G IC_SETS=16"
#   LIB      liberty file of gf180mcu_fd_sc_mcu7t5v0 (tt corner)
#
# - The RTL of the mmRISC-2 submodule is read unmodified.
# - For CPU_TOP, USE_BFM=0 (in GPARAMS) selects the real CPU core instead of
#   the simulation BFM.
# - CACHE_DATA_ARRAY and CACHE_TAG_ARRAY are blackboxed: their area comes
#   from the SRAM macros (sram_area.py), not from standard cells.
# - The hierarchy is kept, so that stat reports every instance separately
#   (yosys-slang gives each instance its own module, named by its path).

yosys -import

set cfg     $::env(CFG)
set lib     $::env(LIB)
set gparams $::env(GPARAMS)
set top     $::env(TOP)
set out     "out/$cfg"
file mkdir $out

set fp [open $::env(FILELIST)]
set files {}
foreach line [split [read $fp] "\n"] {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} continue
    lappend files "../$line"
}
close $fp

plugin -i slang
# --allow-use-before-declare: CORE_FPU.sv uses prod_sign (line 565) before
#   its declaration (line 571). Accepted by the simulators and Vivado, an
#   error in slang.
yosys read_slang --top $top {*}$gparams \
    --keep-hierarchy --allow-use-before-declare \
    --blackboxed-module CACHE_DATA_ARRAY \
    --blackboxed-module CACHE_TAG_ARRAY \
    {*}$files

hierarchy -check -top $top
synth -top $top

# Power-up values from initial blocks / declaration initialisers (FPGA INIT)
# do not exist in ASIC flops; drop them before mapping.
attrmap -remove init

dfflibmap -liberty $lib
abc -liberty $lib
opt_clean -purge

tee -o $out/stat.txt  stat -liberty $lib -top $top
tee -q -o $out/stat.json stat -json -liberty $lib -top $top
write_verilog -noattr $out/${top}_netlist.v
