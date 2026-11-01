# Changelog

## 0.9.1 — 2026-11-01

- Settings > Go Dark warns that "All displays sleep" can lock the screen and
  reset USB devices behind a dock.
- Internal, no other change in behavior: the display code moved to
  `Displays.swift`, and the Go Dark tab and the app list moved to
  `SettingsDark.swift`. The panel's display summary is a pure function with
  unit tests. `Tests/integration.sh` checks the hidden `displays-on` command.
- The README has a screenshot of the panel and a shorter feature list.

## 0.9.0 — 2026-11-01

- Go Dark, "A setting for each display": each external display has a
  **Turn off** checkbox, on by default. Lidless stops the signal to the
  monitor, the same as pulling its cable, and the monitor goes to standby.
  This works without DDC. Clear the checkbox to use the Black-to-Unchanged
  slider. If macOS refuses to turn a display off, Lidless makes it black.
- Lidless turns a display off only while the Mac screen is on, so one display
  always stays on. It never turns off the Mac screen.
- A test showed that macOS does not connect a display again when the app
  that turned it off crashes. So Lidless saves the displays that it turned
  off, runs a watchdog that turns them on again when Lidless dies, and turns
  them on again at the next launch. A logout also turns them on.

## 0.8.0 — 2026-11-01

- App Cleanup is now **Go Lidless**: the tab and the panel row have the new
  name. The Go Lidless row has a "Quit apps" switch, like the Go Dark row.
  With the switch off, a session keeps every app open. A session that an
  agent starts uses the same switch.
- Go Dark has a second display mode, "A setting for each display". No
  display sleeps. The Mac screen gets a brightness slider. Its lowest value
  is one step of the brightness key (6%), so the Mac screen never goes off
  and F2 makes it brighter at once. Each external display gets a slider from
  Black to Unchanged. Lidless uses the color table of the display, which
  works without DDC. macOS resets the table when Lidless quits or crashes.
  Every display comes back when Go Dark stops. "All displays sleep" stays
  the default.
- Settings > Safety: the heat levels no longer overlap the text below them.

## 0.7.0 — 2026-11-01

- The Go Dark row in the panel has a "Quit apps" switch. Switch it off, and
  Go Dark keeps every app open. The Go Dark tab has the same setting.
- The Go Dark tab lists the displays that go dark, with the name and the
  resolution of each. The panel row gives the number of displays.
- Each app list has a Deselect All button and shows how many apps are
  selected.

## 0.6.0 — 2026-11-01

- Settings has a Go Dark tab. Go Dark has its own list of apps to quit, its
  own reopen setting, its own time limit (none by default) and the option
  "Stop Go Dark when a display wakes" (off by default). At the first start,
  the Go Dark list is a copy of the App Cleanup list.
- Go Dark no longer sets the Mac screen to minimum brightness. Version 0.5.0
  did, so a key press woke the Mac screen at brightness 0. Now any key, F2
  too, wakes every display at its normal brightness.
- The panel has a Go Dark row, in the same style as the App Cleanup row.
- A selected app that does not run now shows its name and icon from the
  installed app, not its bundle identifier. An app that is not installed
  shows "not installed".
- The log records when the displays wake during Go Dark. `lidless settings
  dark` opens the new tab.

## 0.5.0 — 2026-11-01

- Two buttons replace Start Session: a blue **Go Lidless** button and a green
  **Go Dark** button. Go Dark is for the night. It starts the session with the
  limits and App Cleanup from the panel, closes the panel, puts every display
  to sleep and sets the built-in display to minimum brightness. A wake of a
  display does not stop a Go Dark session.
- The two buttons are solid blue and green with white text. The system tint
  on macOS 27 was too pale for white text.
- The panel is 440 points wide, and no label wraps onto two lines.
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
