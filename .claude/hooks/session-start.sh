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

# the PDK, where the Makefile expects it (PDK_ROOT = ./gf180mcu)
[ -e gf180mcu ] || ln -s /opt/gf180mcu gf180mcu

# nix on PATH for the Bash tool
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo 'export PATH=/nix/var/nix/profiles/default/bin:$PATH' >> "$CLAUDE_ENV_FILE"
fi
exit 0
