# `/usage:check` — manual

Reports Claude.ai rate-limit usage and controls the **usage gate**: a soft "wrap up and save"
nudge and a hard tool-call block, both keyed to the rolling 5-hour window.

## Mental model: global usage, per-project policy

There are two separable things:

- **Usage** — how much of your 5-hour (and 7-day) window you've spent. This is one number for
  your whole Claude.ai account. It is the same in every repo. **Global.**
- **Policy** — *when* the gate should nudge (soft) and *when* it should block (hard), and whether
  it's on at all. This is set **per project**, so a strict `hard 70` you want while focused on one
  repo does not freeze your work in another.

A project's policy is resolved most-specific-first:

```
soft / hard / on-off :  this project  →  global default  →  built-in (soft 80, hard 90)
5-hour usage %       :  always global
```

The gate is **disabled** if *either* the project or the global kill switch is set.

## Commands

| Command | Effect |
|---|---|
| `/usage:check` | Show 5-hour + 7-day usage with reset countdowns, and the gate status for the current project |
| `/usage:check soft N` | Set this project's soft (nudge) threshold to N% (1–100) |
| `/usage:check hard N` | Set this project's hard (block) threshold to N% (1–100) |
| `/usage:check soft off` / `hard off` | Clear this project's threshold (falls back to global, then built-in) |
| `/usage:check off` | Disable the gate for this project |
| `/usage:check on` | Re-enable the gate for this project |
| add `--global` to any of the above | Act on the global fallback instead of the current project |

Control commands act on the **current project** by default. The project is whichever directory you
run the command from (the skill reads the working directory), so run it from inside the repo you
mean to configure.

### Examples

```
/usage:check                 # status for the current project
/usage:check hard 70         # block this project at 70%
/usage:check soft 60         # ...and nudge at 60% (keep soft below hard, see Gotchas)
/usage:check off             # stop gating this project
/usage:check hard 90 --global  # set the default that unconfigured projects inherit
/usage:check hard off        # this project reverts to the global/built-in hard limit
```

## Reading the status output

```
Usage:
  5-hour   41%  (resets in 2h 3m)
  7-day     5%  (resets in 13h 13m)
Gate:  ENABLED   soft=60  hard=70  (policy: project)
       project: /home/you/code/myrepo
       -> not gating (5h 41% below limits)
```

- `(policy: project | global | builtin)` — which layer supplied the soft/hard values.
- `project:` — the path used as the per-project key.
- The last line says what the gate is doing right now: `not gating`, `soft nudging`, or
  `HARD BLOCKING`.
- `DISABLED` lines also report whether a project, global, or both kill switches are responsible.

## State files

Everything lives under `~/.claude/usage-gate/` (outside the plugin, so it survives updates):

```
~/.claude/usage-gate/
  cache                      # global: last-known 5-hour utilization %
  config                     # global default policy (SOFT=/HARD=)
  off                        # global kill switch (a file's presence = disabled)
  soft-warned                # internal: rate-limits repeated soft nudges
  projects/<slug>/
    config                   # this project's SOFT/HARD (overrides global)
    off                      # this project's kill switch
```

`<slug>` is the project's absolute path with every `/` turned into `-`
(e.g. `/home/you/code/myrepo` → `-home-you-code-myrepo`).

## The hard-block escape hatch

When the hard limit is hit, **every** tool call is blocked — including the skill's own `off`
command. So the only way out is to create the kill-switch file by hand. The block message prints
the exact path; it is one of:

```
touch ~/.claude/usage-gate/projects/<slug>/off    # disable just this project
touch ~/.claude/usage-gate/off                    # disable everywhere
```

Then work resumes immediately (the next tool call passes).

## Gotchas

- **Keep soft below hard.** The soft nudge only fires in the band `soft ≤ usage < hard`. If soft
  ≥ hard, the block triggers first and you never get the warning.
- **Run control commands from the project.** The skill identifies the project by the working
  directory. Running it from a subdirectory or elsewhere keys a different project.
- **`hooks.json` edits need a reload.** Changing the hook wiring (not the thresholds) requires
  `/reload-plugins` or a restart to take effect. Threshold/on-off changes are picked up live.
- **Fails open.** A missing or stale (>15 min) cache, a missing OAuth token, or a kill switch all
  let work proceed. The gate never blocks on its own malfunction.
- **Requires a Pro/Max subscription** — the usage API only returns data for those accounts. A line
  beginning `check:` (e.g. `HTTP 401` expired token, `HTTP 429` rate-limited) is reported as-is.
