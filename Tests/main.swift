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

print(failures == 0 ? "All \(checks) checks passed." : "\(failures) of \(checks) checks failed.")
exit(failures == 0 ? 0 : 1)
