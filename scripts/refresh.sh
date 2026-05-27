#!/usr/bin/env bash
# PostToolUse hook (async). Refreshes the cached 5-hour utilization percent from
# the OAuth usage API, but only when the cache is older than TTL — so the API is
# hit at most once per TTL window, well under its rate limit. Never blocks.

SD="$(cd "$(dirname "$0")" && pwd)"; . "$SD/common.sh"

if [ -f "$CACHE" ]; then
  age=$(( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))
  [ "$age" -lt "$TTL" ] && exit 0
fi

TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' "$CRED" 2>/dev/null)
[ -z "$TOKEN" ] && exit 0

resp=$(curl -sS -m 5 https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "User-Agent: claude-code/2.1" 2>/dev/null)

pct=$(printf '%s' "$resp" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
case "$pct" in ''|*[!0-9.]*) exit 0;; esac

printf '%s\n' "$pct" > "$CACHE.tmp" 2>/dev/null && mv -f "$CACHE.tmp" "$CACHE"
exit 0
