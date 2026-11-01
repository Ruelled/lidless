# Changelog

## 0.5.0 — 2026-11-01

- Two buttons replace Start Session: a blue **Go Lidless** button and a green
  **Go Dark** button. Go Dark is for the night. It starts the session with the
  limits and App Cleanup from the panel, closes the panel, puts every display
  to sleep and sets the built-in display to minimum brightness. A wake of a
  display does not stop a Go Dark session.
- The panel keeps its bottom padding. The button at the bottom no longer
  touches the edge of the panel.
- `build.sh` and `test.sh` use a macOS 26 SDK when the Command Line Tools have
  no SwiftUI macro plugin. Command Line Tools 27 cannot compile `@State` with
  the macOS 27 SDK.

## 0.4.0 — 2026-10-30

- The panel shows the chip and battery temperature in °C. The sensors are read
  without root through IOHIDEventSystem (Apple silicon only; other Macs show
  no value). When the heat level is Warm or worse, or the battery is at 40 °C
  or more, the panel says that the Mac is too warm for a closed bag.
- The log records each change of the heat level, with the temperatures. A stop
  for heat also gives the temperatures.
- The log records when the Mac goes to sleep during a session, and says when
  lid mode was off. A session with lid mode off ends in sleep when you close
  the lid.
- `lidless status` and `state.json` give `chipTemp` and `batteryTemp`.
- Settings > Safety has a section about temperatures in degrees, and says that
  a closed Mac in open air is safe.

## 0.3.1 — 2026-10-30

Internal refactor, no change in behavior:

- One file for each part: `Lid.swift` (lid sleep and its watchdog),
  `Caffeinate.swift` (the switch), `CLI.swift` (the command line) and
  `Format.swift` (text). `Session.swift` keeps only sessions and guardrails.
- One saved flag records that Lidless owns `SleepDisabled = 1`. A failed restore
  is now also retried at the next launch.
- The command handler has one method for each command.
- `lidless install` writes the `lidless` wrapper and updates installed skills.
  `build.sh` calls it, so the wrapper is defined in one place only.
- The settings tab names are the names for `lidless settings <tab>`.
- More unit tests (35 checks).

## 0.3.0 — 2026-10-30

- Several agents can share one session: `start` joins an active session, and
  `stop --by <name>` leaves it. The session ends when no holder is left.
- A session does not start when the battery is already at its floor or the Mac
  is already at its heat limit. The reply says why.
- App Cleanup never quits the app that sent a `lidless start` command.
- Removing the lid permission ends a lid session first, so sleep is restored.
- If sleep cannot be restored, Lidless says so and tries again at the next launch.
- Durations are at most 24 hours.
- Only one copy of the app runs at a time.
- The command line checks that a saved process ID still belongs to Lidless.
- Settings > Caffeinate: choose the flags and a time limit.
  `lidless caffeinate on --flags --for`, `lidless settings [tab]`.
- Settings > Safety: the heat limit, what the levels mean, and when heat is a
  risk. The heat limit is a ceiling for the command line.
- Settings open in front of the panel.
- Fewer wake-ups while idle. The log uses local time.
- Unit tests (`./test.sh`, also in CI) and integration tests (`Tests/integration.sh`).

## 0.2 — 2026-10-29

- `lidless` command line, agent skill, settings window, notifications,
  App Cleanup, minimum brightness, update check, log.
- The previous `SleepDisabled` value is restored after a session.
- The Caffeinate switch runs the real `caffeinate -dimsu`.

## 0.1 — 2026-10-29

- First version: menu bar panel, sessions with time, battery and heat limits,
  lid-closed mode, Caffeinate switch.
