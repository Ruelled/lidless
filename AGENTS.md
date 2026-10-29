# Lidless — notes for coding agents

Lidless is a macOS menu bar app (one Swift file, no dependencies) that keeps a
Mac awake, also with the lid closed, with time, battery and heat limits.

- Source: `Lidless.swift`. Build and install: `./build.sh`. Build only: `./build.sh --no-install`.
- Requires macOS 13+, Xcode Command Line Tools. No Xcode project, no packages.
- The user controls it from the menu bar. There is no CLI.

Check the state from a shell:

```sh
pgrep -lf Lidless.app                          # is it running?
pmset -g assertions | grep Lidless             # "Lidless session" or "Lidless caffeinate" = active
pmset -g | grep SleepDisabled                  # 1 = lid-closed mode active
```

If `SleepDisabled` is `1` and no Lidless session is active, restore normal
sleep with `sudo pmset -a disablesleep 0`.

Do not use `pmset displaysleepnow` on a desktop setup: it locks the screen and
can reset USB devices behind a dock.
