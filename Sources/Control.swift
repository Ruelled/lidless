// The command line and the app talk through two channels:
//   CLI → app:  a distributed notification with the command (local processes only; web pages cannot send it).
//   app → CLI:  ~/Library/Application Support/Lidless/state.json, which also carries the reply to each command.

import AppKit

let commandNotification = Notification.Name("io.github.ruelled.lidless.command")

enum Paths {
    static let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Lidless")
    static let state = support.appendingPathComponent("state.json")
}

struct Reply: Codable {
    var id: String
    var ok: Bool
    var message: String
}

struct LidlessState: Codable {
    var version = 1
    var running: Bool
    var pid: Int32
    var active: Bool
    var startedBy: String?
    var holders: [String]?
    var startedAt: Date?
    var endsAt: Date?
    var batteryFloor: Int?
    var thermalStop: String?
    var lidClosed: Bool
    var caffeinated: Bool
    var battery: Int?
    var onAC: Bool
    var thermal: String
    var chipTemp: Double?
    var batteryTemp: Double?
    var lidPermission: Bool
    var sleepDisabled: Bool
    var lastStop: String?
    var lastCommand: Reply?
    var updatedAt: Date

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static func read() -> LidlessState? {
        guard let data = try? Data(contentsOf: Paths.state) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(LidlessState.self, from: data)
    }
}

final class Control {
    static let shared = Control()
    private var lastWrite = Date.distantPast
    private var lastReply: Reply?

    /// The state file carries the battery and heat level for `lidless status`. Refresh it more often when busy.
    func isStale(busy: Bool) -> Bool { Date().timeIntervalSince(lastWrite) > (busy ? 30 : 120) }

    func listen() {
        DistributedNotificationCenter.default().addObserver(forName: commandNotification, object: nil, queue: .main) {
            [weak self] n in self?.handle(n.userInfo ?? [:])
        }
        writeState()   // the CLI waits for this file: it means the app listens
    }

    private func handle(_ info: [AnyHashable: Any]) {
        guard let id = info["id"] as? String, let cmd = info["cmd"] as? String else { return }
        let (ok, message): (Bool, String)
        switch cmd {
        case "start": (ok, message) = start(info)
        case "stop": (ok, message) = stop(info)
        case "caffeinate": (ok, message) = caffeinate(info)
        case "settings": (ok, message) = settings(info)
        default: (ok, message) = (false, "Unknown command: \(cmd)")
        }
        lastReply = Reply(id: id, ok: ok, message: message)
        writeState()
    }

    private func start(_ info: [AnyHashable: Any]) -> (Bool, String) {
        let s = Session.shared
        var c = Pref.config()
        var note = ""
        if let v = info["duration"] as? Int { c.endsAfter = v > 0 ? TimeInterval(v) : nil }
        if let v = info["battery"] as? Int { c.batteryFloor = v > 0 ? v : nil }
        if let v = info["thermal"] as? Int {
            // The user's heat limit is a ceiling: a command can make it stricter, not weaker.
            if let mine = c.thermalLimit, v == 0 || v > mine {
                note += " Heat limit kept at \(thermalName(mine)), the user's setting."
            } else {
                c.thermalLimit = v > 0 ? v : nil
            }
        }
        if let v = info["lid"] as? Bool { c.lidClosed = v }
        // Do not let App Cleanup quit the app that sent the command (the agent's terminal or editor).
        if let protect = info["protect"] as? [String] {
            let before = c.cleanupApps.count
            c.cleanupApps.removeAll { protect.contains($0) }
            if c.cleanupApps.count < before { note += " App Cleanup kept the app that sent this command open." }
        }
        let by = info["by"] as? String ?? "cli"
        if s.active {
            if let e = s.join(c, by: by) { return (false, e) }
            return (true, "Joined the active session. Holders: \(s.holderList)."
                    + (s.endsAt.map { " It ends at \(shortTime($0))." } ?? "") + note)
        }
        if let e = s.start(c, by: by) { return (false, e) }
        return (true, "Session started: \(s.summary)." + note)
    }

    private func stop(_ info: [AnyHashable: Any]) -> (Bool, String) {
        if let by = info["by"] as? String { return Session.shared.release(by) }
        return (true, Session.shared.stop("Stopped from the command line") ? "Session stopped." : "No session was active.")
    }

    private func caffeinate(_ info: [AnyHashable: Any]) -> (Bool, String) {
        let c = Caffeinate.shared
        let on = info["on"] as? Bool ?? false
        let custom = info["flags"] != nil || info["seconds"] != nil
        c.set(on, args: on && custom ? Caffeinate.args(flags: info["flags"] as? String, seconds: info["seconds"] as? Int) : nil)
        if c.on == on { return (true, on ? "Caffeinate on (\(c.command))." : "Caffeinate off.") }
        return (false, "Caffeinate did not start: \(c.error ?? "unknown error").")
    }

    private func settings(_ info: [AnyHashable: Any]) -> (Bool, String) {
        let name = info["tab"] as? String ?? SettingsTab.general.rawValue
        guard let tab = SettingsTab(rawValue: name) else {
            return (false, "Unknown tab \(name). Tabs: \(SettingsTab.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        SettingsWindow.show(tab)
        return (true, "Settings opened.")
    }

    func writeState(running: Bool = true) {
        let s = Session.shared
        let c = s.active ? s.config : nil
        let state = LidlessState(
            running: running, pid: ProcessInfo.processInfo.processIdentifier, active: s.active,
            startedBy: c == nil ? nil : s.startedBy, holders: c == nil ? nil : s.holders,
            startedAt: c == nil ? nil : s.startedAt, endsAt: c == nil ? nil : s.endsAt,
            batteryFloor: c?.batteryFloor, thermalStop: c?.thermalLimit.map { thermalName($0).lowercased() },
            lidClosed: c?.lidClosed ?? false, caffeinated: Caffeinate.shared.on, battery: s.battery, onAC: s.onAC,
            thermal: thermalName(s.thermal).lowercased(),
            chipTemp: s.temps.chip.map { ($0 * 10).rounded() / 10 }, batteryTemp: s.temps.battery.map { ($0 * 10).rounded() / 10 },
            lidPermission: s.lidPermission,
            sleepDisabled: Lid.sleepDisabled(), lastStop: s.lastStop, lastCommand: lastReply, updatedAt: Date())
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if let data = try? LidlessState.encoder.encode(state) { try? data.write(to: Paths.state, options: .atomic) }
        lastWrite = Date()
    }
}
