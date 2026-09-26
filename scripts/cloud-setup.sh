#!/bin/bash
#---------------------------------------------------------------------------
# cloud-setup.sh
#
# Setup script for Claude Code cloud sessions (Ubuntu 24.04, x86_64, root).
# Put this into the environment's "Setup script" field at claude.ai/code:
#
#   curl -fsSL https://raw.githubusercontent.com/munetomo-maruyama/mmRISC-2-GF180MCU/main/scripts/cloud-setup.sh -o /tmp/cloud-setup.sh && bash /tmp/cloud-setup.sh
#
# (Not "curl | bash": when curl is blocked, bash reads nothing and the setup
# "succeeds" without installing anything.)
#
# It installs Nix, fills the Nix store with the LibreLane dev shell of this
# repository, and fetches the gf180mcuD PDK into /opt/gf180mcu. The
# SessionStart hook (.claude/hooks/session-start.sh) links that PDK into the
# checkout and puts nix on PATH.
#
# The environment needs "Custom" network access that allows these hosts
# (the default list covers the GitHub and nixos.org ones, if included):
#   raw.githubusercontent.com          this script
#   artifacts.nixos.org, releases.nixos.org, channels.nixos.org,
#   cache.nixos.org                    Nix installer, nixpkgs, binaries
#   nix-cache.fossi-foundation.org     LibreLane binaries; without it
#                                      OpenROAD etc. build from source (hours)
#   github.com, api.github.com, codeload.github.com
#                                      the flake inputs
#   fossi-foundation.github.io, release-assets.githubusercontent.com,
#   objects.githubusercontent.com      the PDK (ciel)
#---------------------------------------------------------------------------
set -euo pipefail

# git+https, not github: - the github: form asks api.github.com for the
# head commit, and unauthenticated API calls from the shared cloud IPs hit
# GitHub's rate limit (403). Locked github: inputs in flake.lock are fetched
# from github.com/<owner>/<repo>/archive/<rev>.tar.gz, not the API.
REPO=git+https://github.com/munetomo-maruyama/mmRISC-2-GF180MCU
PDK_COMMIT=f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7    # same as the Makefile
PDK_ROOT=/opt/gf180mcu
export PATH=/nix/var/nix/profiles/default/bin:$PATH

# Nix, without a daemon (no systemd in the VM)
if ! command -v nix > /dev/null; then
    curl --proto '=https' --tlsv1.2 -fsSL https://artifacts.nixos.org/nix-installer \
    | sh -s -- install linux --init none --no-confirm --extra-conf "
        extra-substituters = https://nix-cache.fossi-foundation.org
        extra-trusted-public-keys = nix-cache.fossi-foundation.org:3+K59iFwXqKsL7BNu6Guy0v+uTlwsxYQxjspXzqLYQs=
        extra-experimental-features = nix-command flakes
    "
fi

# LibreLane dev shell into the Nix store
nix develop "$REPO" --command true

# PDK: only the libraries the flow uses (all of them is ~4 GB). The tarballs
# are GitHub release assets of another repository, which the cloud GitHub
# proxy may refuse; do not fail the session over it; the SessionStart hook
# reports a missing PDK.
if [ ! -d "$PDK_ROOT/ciel/gf180mcu/versions/$PDK_COMMIT/gf180mcuD" ]; then
    nix develop "$REPO" --command \
        ciel enable "$PDK_COMMIT" --pdk-root "$PDK_ROOT" --pdk-family gf180mcu \
            -l gf180mcu_fd_pr \
            -l gf180mcu_fd_sc_mcu7t5v0 \
            -l gf180mcu_fd_io \
            -l gf180mcu_fd_ip_sram \
    || { echo "WARNING: PDK download failed"; rm -rf "$PDK_ROOT"; }
fi
