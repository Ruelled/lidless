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

    static let durations = [30, 60, 120, 240, 480]
    static let floors = [10, 15, 20, 25, 30, 40, 50]

    static func register() {
        UserDefaults.standard.register(defaults: [
            useDuration: true, minutes: 120, useBattery: true, floor: 20, useThermal: true, thermalLimit: 2,
            allowLid: false, keepDisplay: false, sleepDisplay: false, stopOnWake: false, minBrightness: false,
            cleanupApps: [String](), reopenApps: true, notifications: true, autoUpdate: true,
            caffeinateFlags: "dimsu", caffeinateMinutes: 0,
        ])
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
}
