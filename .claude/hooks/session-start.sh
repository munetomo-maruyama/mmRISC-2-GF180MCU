#!/bin/bash
#---------------------------------------------------------------------------
# session-start.sh
#
# SessionStart hook. Only acts in Claude Code cloud sessions, where
# scripts/cloud-setup.sh has installed Nix and the PDK into /opt/gf180mcu.
#---------------------------------------------------------------------------
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

cd "$CLAUDE_PROJECT_DIR" || exit 0

# the CPU RTL
git submodule update --init --recursive || true

# the PDK, if the setup script did not get it (or the environment was cached
# before it did)
[ -d /opt/gf180mcu ] || bash scripts/fetch-pdk.sh /opt/gf180mcu > /dev/null 2>&1 || true

# the PDK, where the Makefile expects it (PDK_ROOT = ./gf180mcu)
if [ -d /opt/gf180mcu ]; then
    [ -e gf180mcu ] || ln -sfn /opt/gf180mcu gf180mcu
else
    [ -L gf180mcu ] && rm -f gf180mcu
fi

# nix on PATH for the Bash tool
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo 'export PATH=/nix/var/nix/profiles/default/bin:$PATH' >> "$CLAUDE_ENV_FILE"
fi

# stdout goes into Claude's context: say so if the setup script did not run
missing=""
[ -x /nix/var/nix/profiles/default/bin/nix ] || missing="$missing Nix"
[ -d /opt/gf180mcu ] || missing="$missing PDK(/opt/gf180mcu)"
if [ -n "$missing" ]; then
    echo "WARNING: cloud setup incomplete, missing:$missing."
    echo "The environment's setup script (scripts/cloud-setup.sh) did not finish;"
    echo "check its network allowlist (see the header of scripts/cloud-setup.sh)."
fi
exit 0
