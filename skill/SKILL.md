---
name: lidless
description: Keep this Mac awake while you work, also with the lid closed, with a time limit, a battery floor and a heat limit. Use it when the user says "do not sleep", "keep the Mac awake", "I will close the lid", or before a long task that must continue while the user is away.
---

# Lidless

Lidless is a menu bar app on this Mac. Control it with the `lidless` command
(in `~/.local/bin`). Source: https://github.com/Ruelled/lidless

## Start a session

Start a session before a long task. Make the duration a little longer than the task.
Always give all three limits:

```sh
lidless start --duration 2h --battery-floor 20 --thermal-stop hot --by <your agent name>
```

- Add `--lid` only if the user says that they will close the lid. It needs the lid
  permission. If it is missing, the command fails and tells you so. Then tell the user
  to open Lidless Settings > Lid.
- Durations: `30m`, `2h`, `1h30m`. Thermal stops: `warm`, `hot`, `critical`.
- The user's heat limit is a ceiling. A weaker `--thermal-stop` (or `none`) is
  ignored, and the reply says so. Do not try to work around it.
- If a session is already active, `start` fails. Run `lidless status` and do not stop
  a session that the user or another agent started.

## Check

```sh
lidless status          # human-readable
lidless status --json   # active, startedBy, endsAt, battery, thermal, lidClosed, ...
```

## Stop

When your task is done, stop the session that you started:

```sh
lidless stop
```

## Rules

- Do not start a session without limits.
- Do not run `sudo pmset` yourself. Lidless restores sleep when the session ends.
- `lidless caffeinate on|off` runs `caffeinate -dimsu` with no limits. Use it only
  when the user asks for it.
- Exit codes: 0 success, 1 failure (the message says why), 2 usage error.
- If `lidless` is not found, try `~/.local/bin/lidless`. Otherwise tell the user to
  install Lidless from https://github.com/Ruelled/lidless.
