// Saved settings. The panel and the settings window bind to the same keys with @AppStorage.

import Foundation

/// Go Dark with a setting for each display, instead of display sleep.
struct DarkScreens: Equatable {
    /// Lowest Mac screen brightness: one step of the brightness key. The Mac screen never goes off.
    static let macFloor: Float = 1.0 / 16
    var mac: Float                    // brightness of the Mac screen, macFloor...1
    var externals: [String: Double]   // display UUID -> level: 0 black, 1 unchanged
}

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

    /// screens == nil: every display sleeps. Otherwise each display gets its own level and none sleeps.
    var darkScreens: DarkScreens? = nil

    func dark(apps: [String], reopen: Bool, endsAfter: TimeInterval?, stopOnWake: Bool,
              screens: DarkScreens? = nil) -> Config {
        var c = self
        c.dark = true
        c.darkScreens = screens.map { DarkScreens(mac: max(DarkScreens.macFloor, min(1, $0.mac)),
                                                  externals: $0.externals.mapValues { max(0, min(1, $0)) }) }
        c.keepDisplay = false
        c.sleepDisplay = screens == nil
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
    static let darkPerDisplay = "darkPerDisplay"
    static let darkMacBrightness = "darkMacBrightness"
    static let darkLevels = "darkDisplayLevels"
    static let quitApps = "quitApps"

    static let durations = [30, 60, 120, 240, 480]
    static let floors = [10, 15, 20, 25, 30, 40, 50]

    static func register() {
        UserDefaults.standard.register(defaults: [
            useDuration: true, minutes: 120, useBattery: true, floor: 20, useThermal: true, thermalLimit: 2,
            allowLid: false, keepDisplay: false, sleepDisplay: false, stopOnWake: false, minBrightness: false,
            cleanupApps: [String](), reopenApps: true, notifications: true, autoUpdate: true,
            caffeinateFlags: "dimsu", caffeinateMinutes: 0,
            darkReopenApps: true, darkUseDuration: false, darkMinutes: 480, darkStopOnWake: false, darkQuitApps: true,
            darkPerDisplay: false, darkMacBrightness: Double(DarkScreens.macFloor), quitApps: true,
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
            cleanupApps: d.bool(forKey: quitApps) ? d.stringArray(forKey: cleanupApps) ?? [] : [],
            reopenApps: d.bool(forKey: reopenApps))
    }

    /// The session that the panel's Go Dark button would start.
    static func darkConfig() -> Config {
        let d = UserDefaults.standard
        return config().dark(
            apps: d.bool(forKey: darkQuitApps) ? d.stringArray(forKey: darkCleanupApps) ?? [] : [],
            reopen: d.bool(forKey: darkReopenApps),
            endsAfter: d.bool(forKey: darkUseDuration) ? TimeInterval(d.integer(forKey: darkMinutes) * 60) : nil,
            stopOnWake: d.bool(forKey: darkStopOnWake) && !d.bool(forKey: darkPerDisplay),
            screens: d.bool(forKey: darkPerDisplay) ? darkScreens() : nil)
    }

    /// Level of an external display in Go Dark: 0 black (the default), 1 unchanged.
    static func darkLevel(_ uuid: String) -> Double {
        (UserDefaults.standard.dictionary(forKey: darkLevels) as? [String: Double])?[uuid] ?? 0
    }

    static func setDarkLevel(_ uuid: String, _ v: Double) {
        var all = UserDefaults.standard.dictionary(forKey: darkLevels) as? [String: Double] ?? [:]
        all[uuid] = v
        UserDefaults.standard.set(all, forKey: darkLevels)
    }

    static func darkScreens() -> DarkScreens {
        let ext = DisplayList.shared.displays.filter { !$0.builtIn }
        return DarkScreens(mac: Float(UserDefaults.standard.double(forKey: darkMacBrightness)),
                           externals: Dictionary(uniqueKeysWithValues: ext.map { ($0.uuid, darkLevel($0.uuid)) }))
    }
}
