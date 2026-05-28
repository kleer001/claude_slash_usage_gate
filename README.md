# usage — Claude Code usage gate

A Claude Code plugin that watches your Claude.ai rate-limit usage and **gates work on the
5-hour window**: a *soft* "wrap up and save" nudge at one threshold, and a *hard* tool-call
block at a higher one. Ships a `/usage:check` skill to report usage and control the gate.

## Install

```
/plugin marketplace add kleer001/claude_slash_usage_gate
/plugin install usage@usage-gate
```

Then `/reload-plugins` (or restart Claude Code) to activate the hooks.

Local development:

```
claude --plugin-dir /path/to/claude_slash_usage_gate
```

## Commands

| Command | Action |
|---|---|
| `/usage:check` | Show 5-hour and 7-day usage (with reset countdowns) + effective gate status |
| `/usage:check on` / `off` | Enable / disable the gate for this project |
| `/usage:check soft N` / `soft off` | Set / clear the soft (nudge) limit for this project |
| `/usage:check hard N` / `hard off` | Set / clear the hard (block) limit for this project |
| add `--global` to any control | Set the global fallback instead of the current project |

Defaults: `soft 80`, `hard 90`, enabled.

Full reference — every command, the status fields, state files, the escape hatch, and gotchas:
[`skills/check/MANUAL.md`](skills/check/MANUAL.md).

## Scope: per-project gates, global usage

The 5-hour usage figure is account-wide, so the cached percentage is **global**. The gate
**policy** — the soft/hard thresholds and the on/off kill switch — is **per project**, so a
`hard 70` you set while focused on one repo does not block your work in another.

Resolution, most specific first:

```
soft / hard / off :  <this project>  →  <global default>  →  built-in (soft 80, hard 90)
5-hour usage %    :  always global
```

The gate is disabled if *either* the project or the global kill switch is present. `/usage:check`
control commands write the **current project's** policy by default; add `--global` to write the
fallback. The project is identified by `$CLAUDE_PROJECT_DIR` (else the working directory), so run
the command from inside the project you mean to configure.

## How it works

- A `PostToolUse` hook (async, non-blocking) refreshes a cached 5-hour percentage from the
  OAuth usage API at most once per 5 minutes — under the API's rate-limit window.
- A `PreToolUse` hook reads that cache before each tool call: at/above the **hard** limit it
  blocks the call (`exit 2`); at/above the **soft** limit it injects a non-blocking "wrap up
  and save" reminder; otherwise it allows. It fails **open** — missing/stale cache, no token,
  or the kill switch all allow work to proceed.

When hard-blocked, *all* tool calls are blocked (including the gate's own controls), so the
escape hatch is a plain file — the block message prints the exact path. A project kill switch
lives at `~/.claude/usage-gate/projects/<slug>/off`; `touch`ing it (or the global
`~/.claude/usage-gate/off`) re-enables work immediately.

State lives in `~/.claude/usage-gate/` — outside the plugin, so it survives plugin updates:

```
~/.claude/usage-gate/
  cache                      # global: last-known 5-hour utilization %
  config                     # global default policy (SOFT=/HARD=)
  off                        # global kill switch
  projects/<slug-of-path>/
    config                   # this project's SOFT/HARD (overrides global)
    off                      # this project's kill switch
```

The hook gets the project path from `${CLAUDE_PROJECT_DIR}` (passed in `hooks.json`); the
`/usage:check` skill, which does not receive that variable, falls back to the working directory.

## Requirements

- A Claude.ai subscription (Pro/Max) — the usage API only returns data for those accounts.
- `jq` and `curl` on `PATH`.
- The OAuth token in `~/.claude/.credentials.json` (written by Claude Code at login).

## License

MIT
