# Lidless

A small macOS menu bar app that keeps your Mac awake, also with the lid closed,
and stops by itself before the battery runs out or the Mac gets too hot.

Use it when a coding agent (Claude Code, Codex, …) must keep working while the
laptop is in your bag. It is a free, open-source take on the idea behind
[SleepWalk](https://sleepwalk.app).

## Features

- **Caffeinate switch**: keep the Mac and the display awake until you switch it
  off. Lid open only. Works like `caffeinate -di`.
- **Sessions with guardrails**: stop after a time, below a battery percentage
  (on battery only), or at a thermal state (Warm, Hot, Critical).
- **Lid closed**: optional. Uses `pmset -a disablesleep 1` and turns it off
  again when the session ends, when the app quits, and when the app crashes.
- Display options: keep the display awake, put it to sleep on start, stop the
  session when the display wakes.
- Open at login.

## Install

Requires macOS 13 or later. Apple silicon and Intel.

```sh
git clone https://github.com/Ruelled/lidless.git
cd lidless
./build.sh            # builds and copies Lidless.app to ~/Applications
open ~/Applications/Lidless.app
```

You need the Xcode Command Line Tools (`xcode-select --install`). The app is
built on your Mac and signed ad hoc, so Gatekeeper does not block it.

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

To check by hand: `pmset -g | grep SleepDisabled` must show `0` when no
session is active. To fix it by hand: `sudo pmset -a disablesleep 0`.

## Warning

A closed laptop in a bag gets hot. Keep the battery and time limits on. The
temperature limit uses the macOS thermal state, and the Mac usually slows
itself down before it reports "Hot", so do not rely on that limit alone. Use
this software at your own risk; see the [license](LICENSE).

## License

MIT
