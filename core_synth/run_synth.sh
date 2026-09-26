#!/usr/bin/env bash
# Synthesise CPU_TOP for one cache configuration and write the area report.
#
#   core_synth/run_synth.sh default   # I$/D$ 64 sets x 4 ways x 64 B (RTL default)
#   core_synth/run_synth.sh small     # I$/D$ 16 sets x 2 ways x 64 B
#   core_synth/run_synth.sh trim      # small + the other size parameters reduced
#                                     # (BTB 16, ITLB/DTLB 4, PMP 4, MSHR/WB 1, PQ 8)
#
# Run inside the Nix dev shell (nix develop -c core_synth/run_synth.sh ...).
# Output: core_synth/out/<cfg>/{synth.log,stat.txt,stat.json,report.md}
set -euo pipefail
cd "$(dirname "$0")"

CFG=${1:-default}
case "$CFG" in
    default) GPARAMS="" ;;
    small)   GPARAMS="-G IC_SETS=16 -G IC_WAYS=2 -G DC_SETS=16 -G DC_WAYS=2" ;;
    trim)    GPARAMS="-G IC_SETS=16 -G IC_WAYS=2 -G DC_SETS=16 -G DC_WAYS=2 -G DC_NUM_MSHR=1 -G DC_NUM_WB=1 -G BTB_ENTRIES=16 -G ITLB_ENTRIES=4 -G DTLB_ENTRIES=4 -G PMP_ENTRIES=4 -G PQ_DEPTH=8" ;;
    *) echo "unknown configuration: $CFG" >&2; exit 1 ;;
esac

PDK_ROOT_DIR=${PDK_ROOT_DIR:-../gf180mcu}
LIB=${LIB:-$PDK_ROOT_DIR/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/lib/gf180mcu_fd_sc_mcu7t5v0__tt_025C_5v00.lib}

mkdir -p "out/$CFG"
CFG=$CFG GPARAMS=$GPARAMS LIB=$LIB yosys -c synth.tcl -l "out/$CFG/synth.log" > /dev/null
python3 report.py "out/$CFG/stat.json" > "out/$CFG/report.md"
cat "out/$CFG/report.md"
