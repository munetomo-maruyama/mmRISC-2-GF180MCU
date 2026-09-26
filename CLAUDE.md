# mmRISC-2 on GF180MCU

ASIC implementation of the mmRISC-2 CPU (RV64GC, `mmRISC-2/` submodule) in
GF180MCU for a wafer.space MPW, built on the wafer.space project template.
Current goal: trial synthesis and P&R of `CPU_TOP` alone, without the pad
ring, to see whether it fits a slot (1x1 core area is about 3.05 x 4.24 mm).

## Tools

- All tools come from the Nix dev shell: `nix develop -c <command>`
  (LibreLane, Yosys with the slang plugin, OpenROAD, Magic, KLayout, Netgen).
- PDK: gf180mcuD under `./gf180mcu` (not in git). Locally it holds all
  libraries; in cloud sessions it is a link to `/opt/gf180mcu` (or, in an
  environment cached before the setup script fetched it, a directory the
  SessionStart hook fetched; log in `/tmp/fetch-pdk.log`), which has only
  `gf180mcu_fd_pr`, `gf180mcu_fd_sc_mcu7t5v0`, `gf180mcu_fd_io` and
  `gf180mcu_fd_ip_sram`.
- The owner's local shell exports `PDK`, `PDK_ROOT` (for another project) and
  `LD_LIBRARY_PATH` (another KLayout build). The Makefile would pick up the
  first two, and the third breaks KLayout's Python module in the Nix shell.
  Locally, always run
  `nix develop -c env -u PDK -u PDK_ROOT -u LD_LIBRARY_PATH make ...`.

## Hosts

- Local: aarch64 Ubuntu under Parallels; the checkout is on the Parallels
  shared folder, which is case-insensitive and has 1-second mtimes.
- Cloud sessions: x86_64, set up by `scripts/cloud-setup.sh`, `scripts/fetch-pdk.sh` and
  `.claude/hooks/session-start.sh`. 4 vCPU / 16 GB, so large P&R runs are
  better done locally.

## Rules

- Do not edit the CPU RTL here; RTL changes belong in the mmRISC-2 repository.
  Bump the submodule to pick them up, and say in the commit which mmRISC-2
  commit a result was produced from.
- `librelane/runs/` and `final/` are not in git. Record the numbers that matter
  (area, utilization, timing, DRC/LVS) in the commit message or a doc.
