#!/usr/bin/env bash
# Shared paths and config for the usage gate. Sourced by gate.sh and refresh.sh.
# Runtime state lives in the user config dir (not the plugin dir, so it survives
# plugin updates and is shared with the /usage:check skill).

GATE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage-gate"
CONFIG="$GATE_DIR/config"      # SOFT= / HARD= percentages (single source of truth)
CACHE="$GATE_DIR/cache"        # last-known 5-hour utilization percent
OFF="$GATE_DIR/off"            # kill switch: gate is disabled while this exists
WARN="$GATE_DIR/soft-warned"   # rate-limits repeated soft nudges
CRED="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"

TTL=300         # seconds: refresh re-fetches the API only when cache is older than this
STALE=900       # seconds: gate ignores cache older than this and fails open
SOFT_REPEAT=60  # seconds: minimum gap between soft nudges

mkdir -p "$GATE_DIR" 2>/dev/null
[ -f "$CONFIG" ] || printf 'SOFT=80\nHARD=90\n' > "$CONFIG"

SOFT=; HARD=
. "$CONFIG" 2>/dev/null
