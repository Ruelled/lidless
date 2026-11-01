// Unit tests for the pure functions. Run: ./test.sh
// Compiled with every source file except App.swift, so this file is the entry point.

import Foundation

var failures = 0
var checks = 0

func check<T: Equatable>(_ actual: T, _ expected: T, _ what: String, line: Int = #line) {
    checks += 1
    if actual != expected {
        failures += 1
        print("FAIL line \(line): \(what): got \(actual), want \(expected)")
    }
}

// Durations for --duration and --for.
check(CLI.parseDuration("30m"), 1800, "30m")
check(CLI.parseDuration("2h"), 7200, "2h")
check(CLI.parseDuration("1h30m"), 5400, "1h30m")
check(CLI.parseDuration("45s"), 45, "45s")
check(CLI.parseDuration("90"), 5400, "plain number means minutes")
check(CLI.parseDuration("none"), 0, "none")
check(CLI.parseDuration("0"), 0, "0")
check(CLI.parseDuration("24h"), 86400, "24h is the maximum")
check(CLI.parseDuration("25h"), nil, "more than 24h")
check(CLI.parseDuration("1441"), nil, "more than 24h in minutes")
check(CLI.parseDuration("banana"), nil, "text")
check(CLI.parseDuration("5x"), nil, "unknown unit")
check(CLI.parseDuration("h"), nil, "unit without number")
check(CLI.parseDuration("30m5"), nil, "number without unit at the end")
check(CLI.parseDuration("-5"), nil, "negative")

// caffeinate flags.
check(Caffeinate.normalize("dimsu"), "dimsu", "all flags")
check(Caffeinate.normalize("usd"), "dsu", "canonical order")
check(Caffeinate.normalize("dd"), "d", "duplicate")
check(Caffeinate.normalize(""), nil, "empty")
check(Caffeinate.normalize("dx"), nil, "unknown letter")
check(Caffeinate.args(flags: "di", seconds: 1800), ["-di", "-t", "1800"], "args with a time limit")
check(Caffeinate.args(flags: "dimsu", seconds: 0), ["-dimsu"], "args without a time limit")

// Settings tabs, also the names for `lidless settings <tab>`.
check(SettingsTab(rawValue: "safety"), .safety, "tab by name")
check(SettingsTab(rawValue: "nope"), nil, "unknown tab")

// Formatting.
check(shortDuration(1800), "30m", "30m")
check(shortDuration(7200), "2h", "2h")
check(shortDuration(5400), "1h30m", "1h30m")
check(clock(3661), "01:01:01", "clock")
check(clock(-5), "00:00:00", "negative clock")
check(thermalName(-1), "Normal", "thermal below range")
check(thermalName(2), "Hot", "thermal")
check(thermalName(9), "Critical", "thermal above range")
check(sentence("stops after 2h"), "Stops after 2h.", "sentence")
check(degrees(57.6), "58 °C", "degrees")
check(degrees(nil), "—", "degrees without a sensor")
check(temperatures(.init(chip: 61.2, battery: 34.4)), "chip 61 °C, battery 34 °C", "temperatures")
check(temperatures(.init(chip: nil, battery: 34)), "battery 34 °C", "temperatures, battery only")
check(temperatures(.init()), nil, "temperatures, no sensors")
// A Mac without the sensors (Intel, a CI virtual machine) gives nil. A Mac with them gives a sane value.
let now = Temperature.read()
check([now.chip, now.battery].allSatisfy { $0 == nil || (1..<130).contains($0!) }, true, "sensor values in range")

// Session summary.
let c = Config(endsAfter: 7200, batteryFloor: 20, thermalLimit: 2, lidClosed: true, keepDisplay: false,
               sleepDisplay: false, stopOnWake: false, minBrightness: false, cleanupApps: [], reopenApps: true)
check(Session.describe(c), "stops after 2h, below 20%, at Hot, lid may close", "summary")
var open = c
open.endsAfter = nil; open.batteryFloor = nil; open.thermalLimit = nil; open.lidClosed = false
check(Session.describe(open), "no time limit, no battery limit, no heat limit, lid open", "summary without limits")

// Go Dark keeps the battery, heat and lid limits, uses its own apps and time limit, and never dims.
var awake = c
awake.keepDisplay = true; awake.minBrightness = true; awake.cleanupApps = ["com.apple.Music"]
let dark = awake.dark(apps: ["com.apple.Safari"], reopen: false, endsAfter: nil, stopOnWake: false)
check(dark.dark && dark.sleepDisplay && !dark.keepDisplay && !dark.stopOnWake, true, "dark display settings")
check(dark.minBrightness, false, "dark never dims, so a key wakes the Mac screen at full light")
check(dark.cleanupApps, ["com.apple.Safari"], "dark uses its own apps")
check(dark.reopenApps, false, "dark uses its own reopen setting")
check([dark.batteryFloor, dark.thermalLimit], [20, 2], "dark keeps the battery and heat limits")
check(dark.lidClosed, true, "dark keeps the lid setting")
check(Session.describe(dark), "no time limit, below 20%, at Hot, lid may close, Go Dark", "dark summary")
// Go Dark with a setting for each display: no display sleeps, the Mac screen never goes off.
let each = c.dark(apps: [], reopen: true, endsAfter: nil, stopOnWake: false,
                  screens: DarkScreens(mac: 0, externals: ["A": -1, "B": 0.4, "C": 2]))
check(each.sleepDisplay, false, "per display: no display sleeps")
check(each.darkScreens?.mac, DarkScreens.macFloor, "per display: the Mac screen keeps one brightness step")
check(each.darkScreens?.externals, ["A": 0, "B": 0.4, "C": 1], "per display: levels stay between 0 and 1")
check(Session.describe(each), "no time limit, below 20%, at Hot, lid may close, Go Dark per display",
      "per display summary")

// The "Quit apps" switch. register(defaults:) keeps the values in memory, so the test writes nothing.
// Do not call Pref.register() here: it stores a copy of the App Cleanup list.
UserDefaults.standard.register(defaults: [Pref.darkCleanupApps: ["com.apple.Music"], Pref.darkQuitApps: true])
check(Pref.darkConfig().cleanupApps, ["com.apple.Music"], "Go Dark quits its apps")
UserDefaults.standard.register(defaults: [Pref.darkQuitApps: false])
check(Pref.darkConfig().cleanupApps, [], "Go Dark with Quit apps off keeps every app open")
UserDefaults.standard.register(defaults: [Pref.cleanupApps: ["com.apple.Music"], Pref.quitApps: false])
check(Pref.config().cleanupApps, [], "Go Lidless with Quit apps off keeps every app open")

print(failures == 0 ? "All \(checks) checks passed." : "\(failures) of \(checks) checks failed.")
exit(failures == 0 ? 0 : 1)
