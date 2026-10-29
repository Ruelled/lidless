# Changelog

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
