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
- `Sources/Session.swift`: sessions, guardrails, lid sleep, caffeinate switch.
- `Sources/Control.swift`: CLI, distributed-notification commands, `state.json`.
- `Sources/System.swift`: pmset/sudo, brightness, App Cleanup, notifications, log.
- `Sources/Integrations.swift`: update check, `lidless` wrapper, skill install.
- `Sources/Panel.swift`, `Sources/SettingsView.swift`: the UI.
- `Sources/Prefs.swift`: saved settings and their defaults.
- `skill/SKILL.md`: the agent skill, copied into the app bundle.

Build: `./build.sh` (installs) or `./build.sh --no-install` (CI). macOS 13+,
Xcode Command Line Tools, no Xcode project.

Test after each change:

```sh
./test.sh                              # unit tests (Tests/main.swift)
./build.sh && tests/integration.sh     # real sessions, lid mode, crash cleanup
```

Add a unit test in `Tests/main.swift` for each new pure function, and an
integration check in `tests/integration.sh` for each new command. Record each
change in `CHANGELOG.md`.

Do not use `pmset displaysleepnow` on a desktop setup: it locks the screen and
can reset USB devices behind a dock.
