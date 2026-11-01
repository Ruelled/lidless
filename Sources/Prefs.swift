// Saved settings. The panel and the settings window bind to the same keys with @AppStorage.

import Foundation

struct Config {
    var endsAfter: TimeInterval?
    var batteryFloor: Int?
    var thermalLimit: Int?      // ProcessInfo.ThermalState raw value: 1 fair, 2 serious, 3 critical
    var lidClosed: Bool
    var keepDisplay: Bool
    var sleepDisplay: Bool
    var stopOnWake: Bool
    var minBrightness: Bool
    var cleanupApps: [String]   // bundle identifiers
    var reopenApps: Bool

    /// Go Dark: a night session. Every display sleeps at once. The Mac screen keeps its brightness,
    /// so any key (F2 too) wakes it at full light. The battery, heat and lid settings stay the same.
    var dark = false

    func dark(apps: [String], reopen: Bool, endsAfter: TimeInterval?, stopOnWake: Bool) -> Config {
        var c = self
        c.dark = true
        c.keepDisplay = false
        c.sleepDisplay = true
        c.minBrightness = false
        c.stopOnWake = stopOnWake
        c.cleanupApps = apps
        c.reopenApps = reopen
        c.endsAfter = endsAfter
        return c
    }
}

enum Pref {
    static let useDuration = "useDuration"
    static let minutes = "minutes"
    static let useBattery = "useBattery"
    static let floor = "floor"
    static let useThermal = "useThermal"
    static let thermalLimit = "thermalLimit"
    static let allowLid = "allowLidClosed"
    static let keepDisplay = "keepDisplay"
    static let sleepDisplay = "sleepDisplayOnStart"
    static let stopOnWake = "stopOnWake"
    static let minBrightness = "minBrightness"
    static let cleanupApps = "cleanupApps"
    static let reopenApps = "reopenApps"
    static let notifications = "notifications"
    static let autoUpdate = "autoUpdateCheck"
    static let caffeinateFlags = "caffeinateFlags"
    static let caffeinateMinutes = "caffeinateMinutes"
    static let darkCleanupApps = "darkCleanupApps"
    static let darkReopenApps = "darkReopenApps"
    static let darkUseDuration = "darkUseDuration"
    static let darkMinutes = "darkMinutes"
    static let darkStopOnWake = "darkStopOnWake"
    static let darkQuitApps = "darkQuitApps"

    static let durations = [30, 60, 120, 240, 480]
    static let floors = [10, 15, 20, 25, 30, 40, 50]

    static func register() {
        UserDefaults.standard.register(defaults: [
            useDuration: true, minutes: 120, useBattery: true, floor: 20, useThermal: true, thermalLimit: 2,
            allowLid: false, keepDisplay: false, sleepDisplay: false, stopOnWake: false, minBrightness: false,
            cleanupApps: [String](), reopenApps: true, notifications: true, autoUpdate: true,
            caffeinateFlags: "dimsu", caffeinateMinutes: 0,
            darkReopenApps: true, darkUseDuration: false, darkMinutes: 480, darkStopOnWake: false, darkQuitApps: true,
        ])
        // Go Dark starts with the App Cleanup list, once. After that the two lists are separate.
        let d = UserDefaults.standard
        if d.object(forKey: darkCleanupApps) == nil { d.set(d.stringArray(forKey: cleanupApps) ?? [], forKey: darkCleanupApps) }
    }

    /// The session that the panel's Start button would start.
    static func config() -> Config {
        let d = UserDefaults.standard
        return Config(
            endsAfter: d.bool(forKey: useDuration) ? TimeInterval(d.integer(forKey: minutes) * 60) : nil,
            batteryFloor: d.bool(forKey: useBattery) ? d.integer(forKey: floor) : nil,
            thermalLimit: d.bool(forKey: useThermal) ? d.integer(forKey: thermalLimit) : nil,
            lidClosed: d.bool(forKey: allowLid),
            keepDisplay: d.bool(forKey: keepDisplay),
            sleepDisplay: d.bool(forKey: sleepDisplay),
            stopOnWake: d.bool(forKey: stopOnWake),
            minBrightness: d.bool(forKey: minBrightness),
            cleanupApps: d.stringArray(forKey: cleanupApps) ?? [],
            reopenApps: d.bool(forKey: reopenApps))
    }

    /// The session that the panel's Go Dark button would start.
    static func darkConfig() -> Config {
        let d = UserDefaults.standard
        return config().dark(
            apps: d.bool(forKey: darkQuitApps) ? d.stringArray(forKey: darkCleanupApps) ?? [] : [],
            reopen: d.bool(forKey: darkReopenApps),
            endsAfter: d.bool(forKey: darkUseDuration) ? TimeInterval(d.integer(forKey: darkMinutes) * 60) : nil,
            stopOnWake: d.bool(forKey: darkStopOnWake))
    }
}
