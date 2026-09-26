#!/usr/bin/env python3
"""Area report of CPU_TOP from `stat -json -liberty` (hierarchy kept).

yosys-slang names every instance's module <MODULE>$<instance path>, so the
hierarchy is recovered from the names: the inclusive area of an instance is
the sum over every module whose path is the instance path or below it.

Usage: report.py out/<cfg>/stat.json  (Markdown on stdout)
"""
import json
import sys

CELL_PREFIX = "gf180mcu_fd_sc_mcu7t5v0__"

# Groups for the summary: (label, instance path prefixes).
# A module is counted in the first group whose prefix matches its path.
GROUPS = [
    ("CORE_FPU (FPU)",              ["CPU_TOP.g_core.u_cpu_core.u_fpu"]),
    ("CORE_MMU (TLB/PMP/PTW)",      ["CPU_TOP.g_core.u_cpu_core.u_mmu"]),
    ("CPU_CORE (FPU/MMU 以外)",     ["CPU_TOP.g_core.u_cpu_core"]),
    ("CPU_CACHE 制御部 (I$/D$)",    ["CPU_TOP.u_cpu_cache"]),
    ("CPU_DBG: DBG_HART_STUB",      ["CPU_TOP.u_cpu_dbg.u_hart"]),
    ("CPU_DBG (HART_STUB 以外)",    ["CPU_TOP.u_cpu_dbg"]),
    ("CPU_MMIO (CLINT/PLIC)",       ["CPU_TOP.u_mmio"]),
    ("DMA_CACHE",                   ["CPU_TOP.u_dma"]),
    ("CPU_TOP 直下 (BUS_ARB x2, P2 ARB, glue)", ["CPU_TOP"]),
]


def path_of(mod):
    name = mod.lstrip("\\")
    return name.split("$", 1)[1] if "$" in name else name


def type_of(mod):
    return mod.lstrip("\\").split("$", 1)[0]


def is_ff(cell):
    c = cell[len(CELL_PREFIX):]
    return c.startswith("dff") or c.startswith("sdff")


def is_latch(cell):
    return cell[len(CELL_PREFIX):].startswith("lat")


def under(path, prefix):
    return path == prefix or path.startswith(prefix + ".")


def main():
    with open(sys.argv[1]) as f:
        data = json.load(f)

    mods = {}
    for name, m in data["modules"].items():
        by_type = m.get("num_cells_by_type", {})
        cells = sum(n for t, n in by_type.items() if t.startswith(CELL_PREFIX))
        ffs = sum(n for t, n in by_type.items() if t.startswith(CELL_PREFIX) and is_ff(t))
        lats = sum(n for t, n in by_type.items() if t.startswith(CELL_PREFIX) and is_latch(t))
        bbs = {t: n for t, n in by_type.items()
               if not t.startswith(CELL_PREFIX) and not t.startswith("$")
               and t.lstrip("\\").split("$", 1)[0] in ("CACHE_DATA_ARRAY", "CACHE_TAG_ARRAY")}
        mods[path_of(name)] = dict(type=type_of(name), area=float(m.get("area", 0.0)),
                                   cells=cells, ffs=ffs, lats=lats, bbs=bbs)

    def incl(prefix):
        a = c = f = l = 0
        for p, m in mods.items():
            if under(p, prefix):
                a += m["area"]; c += m["cells"]; f += m["ffs"]; l += m["lats"]
        return a, c, f, l

    total_a, total_c, total_f, total_l = incl("CPU_TOP")

    out = []
    out.append(f"Total (standard cells only, SRAM arrays blackboxed): "
               f"{total_a/1e6:.3f} mm2, {total_c} cells, {total_f} flip-flops, {total_l} latches\n")

    # summary by group
    out.append("| グループ | 面積 [mm2] | 割合 | セル数 | FF 数 |")
    out.append("|---|---:|---:|---:|---:|")
    seen = set()
    for label, prefixes in GROUPS:
        a = c = f = 0
        for p, m in mods.items():
            if p in seen:
                continue
            if any(under(p, px) for px in prefixes):
                seen.add(p)
                a += m["area"]; c += m["cells"]; f += m["ffs"]
        out.append(f"| {label} | {a/1e6:.3f} | {100*a/total_a:.1f}% | {c} | {f} |")
    out.append(f"| **合計** | **{total_a/1e6:.3f}** | 100% | {total_c} | {total_f} |")
    out.append("")

    # every instance, in hierarchy order
    out.append("| インスタンス | モジュール | 面積 (配下含む) [mm2] | 自身の面積 [mm2] | セル数 (配下含む) | FF 数 (配下含む) |")
    out.append("|---|---|---:|---:|---:|---:|")
    for p in sorted(mods):
        m = mods[p]
        a, c, f, _ = incl(p)
        depth = p.count(".")
        name = p.split(".")[-1] if depth else p
        indent = "&nbsp;&nbsp;" * depth
        out.append(f"| {indent}{name} | {m['type']} | {a/1e6:.4f} | {m['area']/1e6:.4f} | {c} | {f} |")
    out.append("")

    # largest leaves (own area)
    out.append("面積の大きい順 (インスタンス自身のセルのみ、上位 15):\n")
    out.append("| 順位 | インスタンス | 面積 [mm2] | 割合 | FF 数 |")
    out.append("|---:|---|---:|---:|---:|")
    for i, (p, m) in enumerate(sorted(mods.items(), key=lambda x: -x[1]["area"])[:15], 1):
        out.append(f"| {i} | {p} | {m['area']/1e6:.3f} | {100*m['area']/total_a:.1f}% | {m['ffs']} |")
    out.append("")

    bb_lines = [f"{p}: {', '.join(f'{t.lstrip(chr(92))} x{n}' for t, n in m['bbs'].items())}"
                for p, m in sorted(mods.items()) if m["bbs"]]
    if bb_lines:
        out.append("Blackboxes: " + "; ".join(bb_lines) + "\n")

    print("\n".join(out))


if __name__ == "__main__":
    main()
