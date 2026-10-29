// Saved settings. The panel binds to the same keys with @AppStorage.

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

    static let durations = [30, 60, 120, 240, 480]
    static let floors = [10, 15, 20, 25, 30, 40, 50]

    static func register() {
        UserDefaults.standard.register(defaults: [
            useDuration: true, minutes: 120, useBattery: true, floor: 20, useThermal: true, thermalLimit: 2,
            allowLid: false, keepDisplay: false, sleepDisplay: false, stopOnWake: false, minBrightness: false,
            cleanupApps: [String](), reopenApps: true, notifications: true, autoUpdate: true,
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

func thermalName(_ v: Int) -> String { ["Normal", "Warm", "Hot", "Critical"][max(0, min(3, v))] }

func durationName(_ m: Int) -> String { m < 60 ? "\(m) minutes" : (m == 60 ? "1 hour" : "\(m / 60) hours") }

func clock(_ t: TimeInterval) -> String {
    let s = max(0, Int(t))
    return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
}

func shortDuration(_ t: TimeInterval) -> String {
    let m = Int(t) / 60
    return m % 60 == 0 ? "\(m / 60)h" : (m < 60 ? "\(m)m" : "\(m / 60)h\(m % 60)m")
}
