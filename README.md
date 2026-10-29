# Lidless

A small macOS menu bar app that keeps your Mac awake, also with the lid closed,
and stops by itself before the battery runs out or the Mac gets too hot.

Use it when a coding agent (Claude Code, Codex, …) must keep working while the
laptop is in your bag. It is a free, open-source take on the idea behind
[SleepWalk](https://sleepwalk.app).

## Features

- **Caffeinate switch**: runs `/usr/bin/caffeinate -dimsu` until you switch it
  off or quit Lidless. On mains power, `-s` also keeps the Mac awake with the
  lid closed. On battery, use a session with lid-closed mode.
- **Sessions with guardrails**: stop after a time, below a battery percentage
  (on battery only), or at a thermal state (Warm, Hot, Critical).
- **Lid closed**: optional. Uses `pmset -a disablesleep 1` and restores the
  previous setting when the session ends, when the app quits, and when the app
  crashes.
- **Command line and agent skill**: `lidless start/stop/status`, so a coding
  agent can start a session with limits and stop it when its work is done.
- **App Cleanup**: quit selected apps at the start of a session to save
  battery, and reopen them at the end.
- Display options: keep the display awake, set the built-in display to minimum
  brightness, put the display to sleep on start, stop when the display wakes.
- Notifications when a session starts or stops, with the reason.
- Settings window: open at login, lid permission, update check, logs, agents.

## Install

Requires macOS 13 or later. Apple silicon and Intel.

```sh
git clone https://github.com/Ruelled/lidless.git
cd lidless
./build.sh            # builds Lidless.app into ~/Applications and `lidless` into ~/.local/bin
open ~/Applications/Lidless.app
```

You need the Xcode Command Line Tools (`xcode-select --install`). The app is
built on your Mac and signed ad hoc, so Gatekeeper does not block it.

To update: `git pull && ./build.sh`, then quit Lidless and open it again.
Settings > General can check GitHub for a newer commit once a day. That is
the only network request Lidless makes.

## Command line

```sh
lidless start --duration 2h --battery-floor 20 --thermal-stop hot [--lid] [--by codex]
lidless status            # add --json for machine output
lidless stop
lidless caffeinate on|off
```

Options that you leave out come from the saved panel settings. `start` opens
Lidless if it is not running. Exit codes: 0 success, 1 failure, 2 usage error.

The command and the app talk through a distributed notification (local
processes only) and the state file
`~/Library/Application Support/Lidless/state.json`.

## Agent skill

[`skill/SKILL.md`](skill/SKILL.md) teaches an agent when and how to use
`lidless`. Install it for Claude Code, Codex or `~/.agents` in Settings >
Agents, or copy the setup prompt for any other agent. Then tell the agent
"do not let the Mac sleep" or "I will close the lid".

## How the lid-closed mode works

macOS always sleeps when you close the lid on battery power, unless sleep is
disabled for the whole system with `pmset -a disablesleep 1`. That command
needs root. When you click **Grant…** for the first time, Lidless asks for
your admin password once and writes `/etc/sudoers.d/lidless`:

```
<you> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

The rule lets only your user run only those two exact commands. Click
**Remove lid permission** in the panel, or run
`sudo rm /etc/sudoers.d/lidless`, to remove it.

Safety nets for `disablesleep`:

1. A session ends at its time, battery or heat limit, and sleep is enabled again.
2. When Lidless quits, it ends the session.
3. If Lidless crashes or is force-quit, a small background shell sees that the
   process is gone and runs `pmset -a disablesleep 0`.
4. At start, Lidless undoes a `disablesleep` that it left behind.

If `SleepDisabled` was already `1` before a session, Lidless leaves it at `1`.
Logs: `~/Library/Logs/Lidless/lidless.log`.

To check by hand: `pmset -g | grep SleepDisabled` must show `0` when no
session is active. To fix it by hand: `sudo pmset -a disablesleep 0`.

## Warning

A closed laptop in a bag gets hot. Keep the battery and time limits on. The
temperature limit uses the macOS thermal state, and the Mac usually slows
itself down before it reports "Hot", so do not rely on that limit alone. Use
this software at your own risk; see the [license](LICENSE).

## For agents

See [AGENTS.md](AGENTS.md) for build commands and shell checks of the state.

## License

MIT
