#!/usr/bin/env python3
"""Make a LibreLane initial state from a synthesis result, for resuming P&R
without running Yosys again (Yosys.Synthesis of CPU_CORE takes ~40 min).

The synthesis directory holds what the state after Yosys.Synthesis refers
to, with any directory layout:
    cpu_core_wrap.nl.v     netlist        (06-yosys-synthesis/)
    cpu_core_wrap.h.json   JSON header    (05-yosys-jsonheader/)
    state_after_synth.json the state, only its "metrics" are used (optional)

It can be a run directory of this machine or a bundle made elsewhere
(the state files of LibreLane hold absolute paths, so a run copied from
another machine cannot be resumed as it is).

Usage:
    core_pnr/from_synth.py SYNTH_DIR OUT_STATE_JSON
then
    librelane core_pnr/config.yaml ... -i OUT_STATE_JSON --from OpenROAD.CheckSDCFiles
(`make core-pnr-from-synth SYNTH_DIR=...` does both.)

The netlist must come from the same RTL and the same synthesis settings as
core_pnr/config.yaml; after changing either, run the full flow again.
"""
import json
import os
import sys


def find(root, name):
    for d, _, files in os.walk(root):
        if name in files:
            return os.path.abspath(os.path.join(d, name))
    sys.exit(f"{name} not found under {root}")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    root, out = sys.argv[1], sys.argv[2]
    state = {
        "json_h": find(root, "cpu_core_wrap.h.json"),
        "nl": find(root, "cpu_core_wrap.nl.v"),
        "metrics": {},
    }
    for d, _, files in os.walk(root):
        if "state_after_synth.json" in files:
            with open(os.path.join(d, "state_after_synth.json")) as f:
                state["metrics"] = json.load(f).get("metrics", {})
            break
    with open(out, "w") as f:
        json.dump(state, f, indent=2)
    print(f"{out}: nl={state['nl']}")


if __name__ == "__main__":
    main()
