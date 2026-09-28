#!/usr/bin/env bash
# Stand-alone synthesis of the cache tag side, for the parts that the
# CPU_TOP run leaves out (CACHE_TAG_ARRAY is blackboxed there):
#   - TAG_VALID_DIRTY : valid / dirty flip-flops that stay in logic when the
#                       tags go into SRAM macros (est/TAG_VALID_DIRTY.sv)
#   - CACHE_TAG_ARRAY : the real RTL, tags included, all in flip-flops
#                       (alternative to tag SRAM macros for small caches)
# One cache each; I$ and D$ use the same parameters.
# Run inside the Nix dev shell. Output: core_synth/out/est/est.md
set -euo pipefail
cd "$(dirname "$0")"

PDK_ROOT_DIR=${PDK_ROOT_DIR:-../gf180mcu}
LIB=${LIB:-$PDK_ROOT_DIR/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/lib/gf180mcu_fd_sc_mcu7t5v0__tt_025C_5v00.lib}
TAG_RTL=../mmRISC-2/RTL/CPU/CPU_CACHE/CACHE_TAG_ARRAY/CACHE_TAG_ARRAY.sv
OUT=out/est
mkdir -p $OUT

# name  file  top  parameters   (PADDR 40 bit, 64 B blocks: TAG_BITS = 40 - 6 - log2(SETS))
RUNS=(
    "vd_64x4   est/TAG_VALID_DIRTY.sv TAG_VALID_DIRTY -G SETS=64 -G WAYS=4"
    "vd_16x2   est/TAG_VALID_DIRTY.sv TAG_VALID_DIRTY -G SETS=16 -G WAYS=2"
    "tagff_64x4 $TAG_RTL CACHE_TAG_ARRAY -G SETS=64 -G WAYS=4 -G TAG_BITS=28"
    "tagff_16x2 $TAG_RTL CACHE_TAG_ARRAY -G SETS=16 -G WAYS=2 -G TAG_BITS=30"
)

echo "| 対象 | 面積 [mm2] (1 キャッシュ分) | セル数 | FF 数 |" > $OUT/est.md
echo "|---|---:|---:|---:|" >> $OUT/est.md
for r in "${RUNS[@]}"; do
    set -- $r
    name=$1; file=$2; top=$3; shift 3
    yosys -q -l $OUT/$name.log -p "plugin -i slang; read_slang --top $top $* $file;
        hierarchy -top $top; synth -flatten -top $top; attrmap -remove init;
        dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean -purge;
        tee -q -o $OUT/$name.json stat -json -liberty $LIB" > /dev/null
    python3 - "$OUT/$name.json" "$name" >> $OUT/est.md <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = next(iter(d["modules"].values()))
bt = m["num_cells_by_type"]
ff = sum(n for t, n in bt.items() if "__dff" in t)
print(f"| {sys.argv[2]} | {float(m['area'])/1e6:.4f} | {sum(bt.values())} | {ff} |")
PY
done
cat $OUT/est.md
