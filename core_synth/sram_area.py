#!/usr/bin/env python3
"""SRAM macro area of the mmRISC-2 L1 caches from the gf180mcu_fd_ip_sram LEFs.

The macros are single-port, 8 bits wide with a bit write mask, 64 to 512
words deep (gf180mcu_fd_ip_sram__sram{64,128,256,512}x8m8wm1).

Mapping of the RTL arrays (CACHE_DATA_ARRAY / CACHE_TAG_ARRAY):
  data : one 64-bit word per way is read per cycle, all ways in parallel,
         SETS * BLOCK_BYTES / 8 words per way
         -> per way 8 macros wide x ceil(words / 512) deep
  tag  : one entry per set and way, all ways of a set read in parallel,
         TAG_BITS = PADDR(40) - log2(BLOCK_BYTES) - log2(SETS)
         -> one row per set holding WAYS x TAG_BITS bits (bit write mask
            selects the way), ceil(WAYS * TAG_BITS / 8) macros of depth >= SETS
  valid / dirty bits stay flip-flops in both cases (not in this script).

Usage: sram_area.py [LEF_DIR]   (Markdown on stdout)
"""
import glob
import math
import os
import re
import sys

PADDR = 40
BLOCK = 64

# tag array entirely in flip-flops (real CACHE_TAG_ARRAY, run_est.sh), one cache, mm2
TAG_FF_SYNTH = {(64, 4): 0.9334, (16, 2): 0.1270}
TAG_FF_UM2_PER_BIT = 120.0   # ~ what the two runs above give per storage bit


def macro_sizes(lef_dir):
    sizes = {}
    for f in glob.glob(os.path.join(lef_dir, "*.lef")):
        txt = open(f).read()
        name = re.search(r"MACRO\s+(\S+)", txt).group(1)
        w, h = map(float, re.search(r"SIZE\s+([\d.]+)\s+BY\s+([\d.]+)", txt).groups())
        depth = int(re.search(r"sram(\d+)x8", name).group(1))
        sizes[depth] = (name, w, h)
    return dict(sorted(sizes.items()))


def pick(sizes, words):
    """smallest macro holding `words`, or the deepest one tiled"""
    for d in sizes:
        if d >= words:
            return d, 1
    d = max(sizes)
    return d, math.ceil(words / d)


def cache(sizes, sets, ways):
    tag_bits = PADDR - int(math.log2(BLOCK)) - int(math.log2(sets))
    words = sets * BLOCK // 8
    dd, dn = pick(sizes, words)
    data_n = ways * 8 * dn
    data_a = data_n * sizes[dd][1] * sizes[dd][2] / 1e6
    td, tn = pick(sizes, sets)
    tag_n = math.ceil(ways * tag_bits / 8) * tn
    tag_a = tag_n * sizes[td][1] * sizes[td][2] / 1e6
    tag_ff = TAG_FF_SYNTH.get((sets, ways))
    tag_ff_exact = tag_ff is not None
    if tag_ff is None:
        tag_ff = (sets * ways * (tag_bits + 2)) * TAG_FF_UM2_PER_BIT / 1e6
    return dict(sets=sets, ways=ways, kb=sets * ways * BLOCK / 1024, tag_bits=tag_bits,
                data_n=data_n, data_m=dd, data_a=data_a,
                tag_n=tag_n, tag_m=td, tag_a=tag_a, tag_ff=tag_ff, tag_ff_exact=tag_ff_exact)


def main():
    lef_dir = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(os.path.dirname(__file__), "..", "gf180mcu", "gf180mcuD", "libs.ref",
                     "gf180mcu_fd_ip_sram", "lef")
    sizes = macro_sizes(lef_dir)

    print("| マクロ | サイズ [um] | 面積 [mm2] |")
    print("|---|---|---:|")
    for d, (n, w, h) in sizes.items():
        print(f"| {n} | {w:.2f} x {h:.2f} | {w*h/1e6:.4f} |")
    print()

    print("I$ と D$ が同じ構成の場合、2 キャッシュ分の合計 (1 ブロック 64 B)。\n")
    print("| 構成 (sets x ways) | 容量/キャッシュ | データ SRAM | タグ SRAM | "
          "SRAM 合計 [mm2] (データ+タグ) | タグを FF にした場合のタグ [mm2] | "
          "データ SRAM + タグ FF [mm2] |")
    print("|---|---:|---|---|---:|---:|---:|")
    for sets, ways in [(64, 4), (64, 2), (32, 4), (32, 2), (16, 4), (16, 2), (64, 1), (16, 1)]:
        c = cache(sizes, sets, ways)
        mark = "" if c["tag_ff_exact"] else " (概算)"
        print(f"| {sets} x {ways} | {c['kb']:g} KB | "
              f"{2*c['data_n']} x {c['data_m']}x8 = {2*c['data_a']:.2f} mm2 | "
              f"{2*c['tag_n']} x {c['tag_m']}x8 = {2*c['tag_a']:.2f} mm2 | "
              f"{2*(c['data_a']+c['tag_a']):.2f} | {2*c['tag_ff']:.2f}{mark} | "
              f"{2*(c['data_a']+c['tag_ff']):.2f} |")


if __name__ == "__main__":
    main()
