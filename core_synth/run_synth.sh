#!/usr/bin/env bash
# Synthesise CPU_TOP or CPU_CORE for one configuration and write the area report.
#
#   core_synth/run_synth.sh default   # I$/D$ 64 sets x 4 ways x 64 B (RTL default)
#   core_synth/run_synth.sh small     # I$/D$ 16 sets x 2 ways x 64 B
#   core_synth/run_synth.sh trim      # small + the other size parameters reduced
#                                     # (BTB 16, ITLB/DTLB 4, PMP 4, MSHR/WB 1, PQ 8)
#   core_synth/run_synth.sh core      # CPU_CORE alone (no caches), RTL defaults
#   core_synth/run_synth.sh core_trim # CPU_CORE alone, BTB 16, ITLB/DTLB 4, PMP 4, PQ 8
#
# Run inside the Nix dev shell (nix develop -c core_synth/run_synth.sh ...).
# Output: core_synth/out/<cfg>/{synth.log,stat.txt,stat.json,report.md}
set -euo pipefail
cd "$(dirname "$0")"

CFG=${1:-default}
TOP=CPU_TOP
FILELIST=files.f
TOP_PARAMS="-G USE_BFM=0"
case "$CFG" in
    core|core_trim)
        TOP=CPU_CORE
        FILELIST=files_core.f
        TOP_PARAMS="" ;;
esac
case "$CFG" in
    default|core) GPARAMS="" ;;
    core_trim) GPARAMS="-G BTB_ENTRIES=16 -G ITLB_ENTRIES=4 -G DTLB_ENTRIES=4 -G PMP_ENTRIES=4 -G PQ_DEPTH=8" ;;
    small)   GPARAMS="-G IC_SETS=16 -G IC_WAYS=2 -G DC_SETS=16 -G DC_WAYS=2" ;;
    trim)    GPARAMS="-G IC_SETS=16 -G IC_WAYS=2 -G DC_SETS=16 -G DC_WAYS=2 -G DC_NUM_MSHR=1 -G DC_NUM_WB=1 -G BTB_ENTRIES=16 -G ITLB_ENTRIES=4 -G DTLB_ENTRIES=4 -G PMP_ENTRIES=4 -G PQ_DEPTH=8" ;;
    *) echo "unknown configuration: $CFG" >&2; exit 1 ;;
esac

PDK_ROOT_DIR=${PDK_ROOT_DIR:-../gf180mcu}
LIB=${LIB:-$PDK_ROOT_DIR/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/lib/gf180mcu_fd_sc_mcu7t5v0__tt_025C_5v00.lib}

mkdir -p "out/$CFG"
CFG=$CFG TOP=$TOP FILELIST=$FILELIST GPARAMS="$TOP_PARAMS $GPARAMS" LIB=$LIB yosys -c synth.tcl -l "out/$CFG/synth.log" > /dev/null
python3 report.py "out/$CFG/stat.json" > "out/$CFG/report.md"
cat "out/$CFG/report.md"
