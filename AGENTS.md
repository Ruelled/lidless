# Lidless — notes for coding agents

Lidless is a macOS menu bar app that keeps a Mac awake, also with the lid
closed, with time, battery and heat limits. No dependencies.

## To use it

Read [skill/SKILL.md](skill/SKILL.md). In short:

```sh
lidless start --duration 2h --battery-floor 20 --thermal-stop hot --by <agent>
lidless status --json
lidless stop
```

If `SleepDisabled` is `1` (`pmset -g | grep SleepDisabled`) and no Lidless
session is active, restore normal sleep with `sudo pmset -a disablesleep 0`.

## To change it

- `Sources/App.swift`: entry point. A known command runs the CLI, else the app.
- `Sources/Session.swift`: sessions, holders, guardrails, sensors.
- `Sources/Lid.swift`: `pmset disablesleep`, the sudoers rule, the crash watchdog.
- `Sources/Caffeinate.swift`: the Caffeinate switch (`/usr/bin/caffeinate`).
- `Sources/Control.swift`: the app side of commands, and `state.json`.
- `Sources/CLI.swift`: the `lidless` command line.
- `Sources/System.swift`: shell, app lists (quit and reopen), notifications, log.
- `Sources/Displays.swift`: Mac screen brightness, the display list, the color
  table (black or dim) and the software disconnect (off) with its watchdog.
- `Sources/Integrations.swift`: open at login, update check, `lidless` wrapper, skills.
- `Sources/Panel.swift`, `Sources/SettingsView.swift`, `Sources/SettingsDark.swift`: the UI.
  The Go Lidless tab still has the internal name `cleanup` (`lidless settings cleanup`).
- `Sources/Prefs.swift`: saved settings and their defaults.
- `Sources/Format.swift`: text for the UI, the log and the command line.
- `skill/SKILL.md`: the agent skill, copied into the app bundle.

Build: `./build.sh` (installs) or `./build.sh --no-install` (CI). macOS 13+,
Xcode Command Line Tools, no Xcode project.

Test after each change:

```sh
./test.sh                              # unit tests (Tests/main.swift)
./build.sh && Tests/integration.sh     # real sessions, lid mode, crash cleanup
```

Add a unit test in `Tests/main.swift` for each new pure function, and an
integration check in `Tests/integration.sh` for each new command. Record each
change in `CHANGELOG.md`.

Do not use `pmset displaysleepnow` on a desktop setup: it locks the screen and
can reset USB devices behind a dock. Go Dark "All displays sleep" uses it and
says so in its tab; "A setting for each display" does not use it.

A display that Lidless turned off (`CGSConfigureDisplayEnabled`) stays off
when the app crashes, also with `.forAppOnly`; this was tested 2026-11-01.
Keep the saved list, the watchdog and the restore at launch. Never turn off
the built-in display, and turn off externals only while it is on.

Release: set `version` in `build.sh`, add a `## <version>` section to
`CHANGELOG.md`, commit, then push the tag `v<version>`. The `release` workflow
tests, builds with `LIDLESS_CHANNEL=release`, and publishes the zip.

Build with Command Line Tools 27: they have no SwiftUI macro plugin, so
`sdk.sh` selects a macOS 26 SDK.
