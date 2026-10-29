// Thin wrappers around macOS: shell commands, brightness, apps, notifications, log.

import AppKit
import CoreGraphics
import Darwin
import UserNotifications

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

// MARK: - Brightness of the built-in display (private DisplayServices, loaded at run time)

enum Brightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getFn: GetFn? = symbol("DisplayServicesGetBrightness")
    private static let setFn: SetFn? = symbol("DisplayServicesSetBrightness")

    private static func symbol<T>(_ name: String) -> T? {
        guard let h = handle, let s = dlsym(h, name) else { return nil }
        return unsafeBitCast(s, to: T.self)
    }

    private static var builtIn: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var available: Bool { getFn != nil && setFn != nil && builtIn != nil }

    static func get() -> Float? {
        guard let f = getFn, let d = builtIn else { return nil }
        var v: Float = 0
        return f(d, &v) == 0 ? v : nil
    }

    @discardableResult
    static func set(_ v: Float) -> Bool {
        guard let f = setFn, let d = builtIn else { return false }
        return f(d, v) == 0
    }
}

// MARK: - App Cleanup

struct RunningApp: Identifiable {
    let id: String          // bundle identifier
    let name: String
    let icon: NSImage?
    let memory: UInt64      // physical footprint in bytes
}

enum AppCleanup {
    static func candidates() -> [RunningApp] {
        let me = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app -> RunningApp? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != me,
                  seen.insert(id).inserted else { return nil }
            return RunningApp(id: id, name: app.localizedName ?? id, icon: app.icon,
                              memory: footprint(app.processIdentifier))
        }.sorted { $0.memory > $1.memory }
    }

    /// Asks the selected apps to quit (they can still ask to save). Returns what to reopen later.
    static func quit(_ ids: [String]) -> [URL] {
        var urls: [URL] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, ids.contains(id), app.terminate() else { continue }
            if let u = app.bundleURL, !urls.contains(u) { urls.append(u) }
        }
        return urls
    }

    static func reopen(_ urls: [URL]) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        urls.forEach { NSWorkspace.shared.openApplication(at: $0, configuration: cfg) }
    }

    static func footprint(_ pid: pid_t) -> UInt64 {
        var info = rusage_info_v2()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        return r == 0 ? info.ri_phys_footprint : 0
    }
}

final class CleanupList: ObservableObject {
    static let shared = CleanupList()
    @Published var ids: [String] = UserDefaults.standard.stringArray(forKey: Pref.cleanupApps) ?? [] {
        didSet { UserDefaults.standard.set(ids, forKey: Pref.cleanupApps) }
    }

    func toggle(_ id: String) {
        if let i = ids.firstIndex(of: id) { ids.remove(at: i) } else { ids.append(id) }
    }
}

// MARK: - Notifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    static var enabled: Bool { UserDefaults.standard.bool(forKey: Pref.notifications) }

    static func setUp() {
        UNUserNotificationCenter.current().delegate = shared
        if enabled { requestPermission() }
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ title: String, _ body: String) {
        guard enabled else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // A menu bar app counts as "in front", so ask macOS to show the banner anyway.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}

// MARK: - Log

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Lidless/lidless.log")

    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = .current   // local time, so the log matches the clock on the wall
        return f
    }()

    static func write(_ message: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
            try? fm.removeItem(at: url)
        }
        let line = Data("\(stamp.string(from: Date())) \(message)\n".utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(line)
            try? h.close()
        } else {
            try? line.write(to: url)
        }
    }
}
