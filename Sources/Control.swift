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
    var startedAt: Date?
    var endsAt: Date?
    var batteryFloor: Int?
    var thermalStop: String?
    var lidClosed: Bool
    var caffeinated: Bool
    var battery: Int?
    var onAC: Bool
    var thermal: String
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

    var stale: Bool { Date().timeIntervalSince(lastWrite) > 30 }

    func listen() {
        DistributedNotificationCenter.default().addObserver(forName: commandNotification, object: nil, queue: .main) {
            [weak self] n in self?.handle(n.userInfo ?? [:])
        }
        writeState()   // the CLI waits for this file: it means the app listens
    }

    private func handle(_ info: [AnyHashable: Any]) {
        guard let id = info["id"] as? String, let cmd = info["cmd"] as? String else { return }
        let s = Session.shared
        var reply = Reply(id: id, ok: true, message: "")
        switch cmd {
        case "start":
            var c = Pref.config()
            if let v = info["duration"] as? Int { c.endsAfter = v > 0 ? TimeInterval(v) : nil }
            if let v = info["battery"] as? Int { c.batteryFloor = v > 0 ? v : nil }
            if let v = info["thermal"] as? Int { c.thermalLimit = v > 0 ? v : nil }
            if let v = info["lid"] as? Bool { c.lidClosed = v }
            if let e = s.start(c, by: info["by"] as? String ?? "cli") {
                reply.ok = false
                reply.message = e
            } else {
                reply.message = "Session started: \(s.summary)."
            }
        case "stop":
            reply.message = s.stop(info["reason"] as? String ?? "Stopped from the command line")
                ? "Session stopped." : "No session was active."
        case "caffeinate":
            let on = info["on"] as? Bool ?? false
            s.setCaffeinated(on)
            reply.ok = s.caffeinated == on
            reply.message = s.caffeinated ? "Caffeinate on (caffeinate -dimsu)." : "Caffeinate off."
        default:
            reply.ok = false
            reply.message = "Unknown command: \(cmd)"
        }
        lastReply = reply
        writeState()
    }

    func writeState(running: Bool = true) {
        let s = Session.shared
        let c = s.active ? s.config : nil
        let state = LidlessState(
            running: running, pid: ProcessInfo.processInfo.processIdentifier, active: s.active,
            startedBy: c == nil ? nil : s.startedBy, startedAt: c == nil ? nil : s.startedAt, endsAt: s.endsAt.flatMap { c == nil ? nil : $0 },
            batteryFloor: c?.batteryFloor, thermalStop: c?.thermalLimit.map { thermalName($0).lowercased() },
            lidClosed: c?.lidClosed ?? false, caffeinated: s.caffeinated, battery: s.battery, onAC: s.onAC,
            thermal: thermalName(s.thermal).lowercased(), lidPermission: s.lidPermission,
            sleepDisabled: Lid.sleepDisabled(), lastStop: s.lastStop, lastCommand: lastReply, updatedAt: Date())
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if let data = try? LidlessState.encoder.encode(state) { try? data.write(to: Paths.state, options: .atomic) }
        lastWrite = Date()
    }
}

// MARK: - Command line

enum CLI {
    static let commands: Set<String> = ["start", "stop", "status", "caffeinate", "version", "help", "--help", "-h", "--version"]

    static let usage = """
    Usage: lidless <command> [options]

    Commands:
      start [options]        Start a session with guardrails.
        --duration <t>         30m, 2h, 1h30m, or none. Default: the saved panel setting.
        --battery-floor <n>    Stop below n percent on battery (5-95), or none.
        --thermal-stop <s>     warm, hot, critical, or none.
        --lid / --no-lid       Allow the lid to close (needs the lid permission).
        --by <name>            Who started it, for example codex or claude.
      stop                   Stop the session.
      status                 Show the state. Add --json for machine output.
      caffeinate on|off      Switch caffeinate -dimsu on or off (no limits).
      version                Show the version.

    Add --json to any command to print the full state as JSON.
    Exit codes: 0 success, 1 failure, 2 usage error.
    """

    static func run(_ args: [String]) -> Int32 {
        let json = args.contains("--json")
        let rest = Array(args.dropFirst()).filter { $0 != "--json" }
        switch args[0] {
        case "start":
            guard var info = parseStart(rest) else { return 2 }
            info["cmd"] = "start"
            return send(info, json: json)
        case "stop":
            return send(["cmd": "stop"], json: json)
        case "caffeinate":
            guard let v = rest.first, v == "on" || v == "off" else { return usageError("caffeinate needs on or off") }
            return send(["cmd": "caffeinate", "on": v == "on"], json: json)
        case "status":
            return status(json: json)
        case "version", "--version":
            let info = Bundle.main.infoDictionary ?? [:]
            print("lidless \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["LidlessCommit"] as? String ?? "unknown"))")
            return 0
        default:
            print(usage)
            return 0
        }
    }

    private static func parseStart(_ a: [String]) -> [String: Any]? {
        var info: [String: Any] = [:]
        var i = 0
        func value() -> String? { i += 1; return i < a.count ? a[i].lowercased() : nil }
        while i < a.count {
            switch a[i] {
            case "--duration":
                guard let v = value(), let secs = parseDuration(v) else { usageError("bad --duration"); return nil }
                info["duration"] = secs
            case "--battery-floor":
                guard let v = value() else { usageError("bad --battery-floor"); return nil }
                if v == "none" { info["battery"] = 0 }
                else if let n = Int(v.trimmingCharacters(in: CharacterSet(charactersIn: "%"))), (5...95).contains(n) { info["battery"] = n }
                else { usageError("bad --battery-floor"); return nil }
            case "--thermal-stop":
                guard let v = value(), let n = ["none": 0, "warm": 1, "hot": 2, "critical": 3][v] else {
                    usageError("bad --thermal-stop"); return nil
                }
                info["thermal"] = n
            case "--lid": info["lid"] = true
            case "--no-lid": info["lid"] = false
            case "--by":
                guard let v = value() else { usageError("bad --by"); return nil }
                info["by"] = String(v.prefix(40))
            default:
                usageError("unknown option \(a[i])"); return nil
            }
            i += 1
        }
        return info
    }

    /// "30m", "2h", "1h30m", "45s", "90" (minutes), "none"/"0" → seconds (0 = no limit).
    static func parseDuration(_ s: String) -> Int? {
        if s == "none" || s == "0" { return 0 }
        if let m = Int(s) { return m > 0 ? m * 60 : nil }
        var total = 0, num = ""
        for ch in s {
            if ch.isNumber { num.append(ch); continue }
            guard let n = Int(num), let unit = ["h": 3600, "m": 60, "s": 1][String(ch)] else { return nil }
            total += n * unit
            num = ""
        }
        return num.isEmpty && total > 0 ? total : nil
    }

    @discardableResult
    private static func usageError(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("lidless: \(message)\n\n\(usage)\n".utf8))
        return 2
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("lidless: \(message)\n".utf8))
        return 1
    }

    private static func alive(_ pid: Int32) -> Bool { pid > 0 && kill(pid, 0) == 0 }

    private static func liveState() -> LidlessState? {
        guard let s = LidlessState.read(), s.running, alive(s.pid) else { return nil }
        return s
    }

    private static func ensureRunning() -> Bool {
        if liveState() != nil { return true }
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app" else { return false }
        let launched = Date().addingTimeInterval(-1)
        Shell.run("/usr/bin/open", ["-g", app.path])
        for _ in 0..<100 {
            if let s = liveState(), s.updatedAt >= launched { return true }
            usleep(100_000)
        }
        return false
    }

    private static func send(_ info: [String: Any], json: Bool) -> Int32 {
        guard ensureRunning() else { return fail("Lidless is not running and did not start. Open ~/Applications/Lidless.app.") }
        let id = UUID().uuidString
        var payload = info
        payload["id"] = id
        DistributedNotificationCenter.default().postNotificationName(
            commandNotification, object: nil, userInfo: payload, deliverImmediately: true)
        for _ in 0..<100 {
            if let s = LidlessState.read(), let r = s.lastCommand, r.id == id {
                if json { printJSON(s) } else { print(r.message) }
                return r.ok ? 0 : 1
            }
            usleep(100_000)
        }
        return fail("No answer from Lidless within 10 seconds.")
    }

    private static func printJSON(_ s: LidlessState) {
        if let d = try? LidlessState.encoder.encode(s) { print(String(decoding: d, as: UTF8.self)) }
    }

    private static func status(json: Bool) -> Int32 {
        guard var s = LidlessState.read() else {
            if json { print("{\"running\": false}") } else { print("Lidless: not running") }
            return 0
        }
        s.running = s.running && alive(s.pid)
        if json { printJSON(s); return 0 }
        guard s.running else { print("Lidless: not running"); return 0 }
        let t = DateFormatter()
        t.timeStyle = .short
        print("Lidless: running (pid \(s.pid))")
        if s.active {
            var line = "Session: active, started by \(s.startedBy ?? "?")"
            if let a = s.startedAt { line += " at \(t.string(from: a))" }
            if let e = s.endsAt { line += ", \(clock(e.timeIntervalSinceNow)) left" }
            print(line)
            print("Limits: battery \(s.batteryFloor.map { "below \($0)%" } ?? "none"), "
                  + "heat \(s.thermalStop ?? "none"), lid \(s.lidClosed ? "may close" : "open")")
        } else {
            print("Session: none" + (s.lastStop.map { " (last: \($0))" } ?? ""))
        }
        print("Battery: \(s.battery.map { "\($0)%" } ?? "?")\(s.onAC ? " on mains power" : " on battery")"
              + ", temperature: \(s.thermal)")
        print("Caffeinate: \(s.caffeinated ? "on" : "off")")
        print("Lid permission: \(s.lidPermission ? "granted" : "not granted"), SleepDisabled: \(s.sleepDisabled ? 1 : 0)")
        return 0
    }
}
