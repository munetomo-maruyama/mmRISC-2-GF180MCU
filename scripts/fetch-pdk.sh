#!/bin/bash
#---------------------------------------------------------------------------
# fetch-pdk.sh [PDK_ROOT]
#
# Fetches the gf180mcuD PDK subset for cloud sessions into PDK_ROOT
# (default /opt/gf180mcu): libs.tech and the four libraries the flow uses
# (gf180mcu_fd_pr, gf180mcu_fd_sc_mcu7t5v0, gf180mcu_fd_io,
# gf180mcu_fd_ip_sram), in ciel's layout.
#
# It comes from a release of this repository, because the cloud GitHub proxy
# refuses release assets of other repositories, which is where ciel gets
# them. Locally, use "make clone-pdk" instead.
#
# Called by scripts/cloud-setup.sh and, when the PDK is missing (e.g. a
# cached environment from before), by .claude/hooks/session-start.sh.
#---------------------------------------------------------------------------
set -euo pipefail

PDK_ROOT=${1:-/opt/gf180mcu}
PDK_COMMIT=f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7    # same as the Makefile
PDK_URL=https://github.com/munetomo-maruyama/mmRISC-2-GF180MCU/releases/download/pdk-gf180mcuD-f6eeac7
PDK_TAR=gf180mcuD-f6eeac7-subset.tar.zst

[ -d "$PDK_ROOT/ciel/gf180mcu/versions/$PDK_COMMIT/gf180mcuD" ] && exit 0

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
curl -fsSL -o "$PDK_TAR"        "$PDK_URL/$PDK_TAR"
curl -fsSL -o "$PDK_TAR.sha256" "$PDK_URL/$PDK_TAR.sha256"
sha256sum -c --quiet "$PDK_TAR.sha256"
command -v zstd > /dev/null || apt-get install -y -qq zstd > /dev/null
mkdir -p "$PDK_ROOT"
zstd -dc "$PDK_TAR" | tar xf - -C "$PDK_ROOT" || { rm -rf "$PDK_ROOT"; exit 1; }
