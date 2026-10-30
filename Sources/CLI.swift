// The `lidless` command line. It runs in the same binary as the app (see App.swift), sends each command
// to the running app, and reads the reply from the state file (see Control.swift).

import AppKit

enum CLI {
    static let commands: Set<String> = ["start", "stop", "status", "caffeinate", "settings", "install", "version",
                                        "help", "--help", "-h", "--version"]

    static let usage = """
    Usage: lidless <command> [options]

    Commands:
      start [options]        Start a session with guardrails, or join the active one.
        --duration <t>         30m, 2h, 1h30m, or none. Default: the saved panel setting.
        --battery-floor <n>    Stop below n percent on battery (5-95), or none.
        --thermal-stop <s>     warm, hot, critical, or none.
        --lid / --no-lid       Allow the lid to close (needs the lid permission).
        --by <name>            Who holds it, for example codex or claude.
      stop [--by <name>]     With --by: leave the session; it ends when no holder is left.
                             Without --by: stop the session for everyone.
      status                 Show the state. Add --json for machine output.
      caffeinate on|off      Switch caffeinate on or off. No battery or heat limits.
        --flags <letters>      For this run only: any of d i m s u. Default: Settings > Caffeinate.
        --for <t>              For this run only: stop after t (30m, 2h), or none.
      settings [tab]         Open Settings: \(SettingsTab.allCases.map(\.rawValue).joined(separator: ", ")).
      install                Install this command in ~/.local/bin and update installed agent skills.
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
            info["protect"] = callerApps()
            return send(info, json: json)
        case "stop":
            if rest.isEmpty { return send(["cmd": "stop"], json: json) }
            guard rest.count == 2, rest[0] == "--by" else { return usageError("stop takes only --by <name>") }
            return send(["cmd": "stop", "by": String(rest[1].lowercased().prefix(40))], json: json)
        case "caffeinate":
            guard var info = parseCaffeinate(rest) else { return 2 }
            info["cmd"] = "caffeinate"
            return send(info, json: json)
        case "settings":
            return send(["cmd": "settings", "tab": rest.first ?? SettingsTab.general.rawValue], json: json)
        case "install":
            return install()
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
                guard let v = value(), let secs = parseDuration(v) else { usageError("bad --duration (at most 24h)"); return nil }
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

    static let maxDuration = 24 * 3600

    private static func parseCaffeinate(_ a: [String]) -> [String: Any]? {
        guard let v = a.first, v == "on" || v == "off" else { usageError("caffeinate needs on or off"); return nil }
        var info: [String: Any] = ["on": v == "on"]
        var i = 1
        while i < a.count {
            let opt = a[i]
            guard i + 1 < a.count else { usageError("\(opt) needs a value"); return nil }
            let val = a[i + 1].lowercased()
            switch opt {
            case "--flags":
                guard let f = Caffeinate.normalize(val.trimmingCharacters(in: CharacterSet(charactersIn: "-"))) else {
                    usageError("--flags takes letters from dimsu, for example dimsu or di"); return nil
                }
                info["flags"] = f
            case "--for":
                guard let secs = parseDuration(val) else { usageError("bad --for (at most 24h)"); return nil }
                info["seconds"] = secs
            default:
                usageError("unknown option \(opt)"); return nil
            }
            i += 2
        }
        return info
    }

    /// Run by build.sh from the installed app, so that the wrapper points at that app.
    private static func install() -> Int32 {
        do {
            try CommandInstall.install()
            print("Installed \(CommandInstall.url.path)")
        } catch {
            return fail("Could not install the command: \(error.localizedDescription)")
        }
        for t in SkillTarget.all where Skills.status(t) == .outdated {
            if (try? Skills.install(t)) != nil { print("Updated \(t.file.path)") }
        }
        return 0
    }

    /// "30m", "2h", "1h30m", "45s", "90" (minutes), "none"/"0" → seconds (0 = no limit). At most 24 hours.
    static func parseDuration(_ s: String) -> Int? {
        if s == "none" || s == "0" { return 0 }
        if let m = Int(s) { return m > 0 && m * 60 <= maxDuration ? m * 60 : nil }
        var total = 0, num = ""
        for ch in s {
            if ch.isNumber { num.append(ch); continue }
            guard let n = Int(num), let unit = ["h": 3600, "m": 60, "s": 1][String(ch)] else { return nil }
            total += n * unit
            num = ""
        }
        return num.isEmpty && total > 0 && total <= maxDuration ? total : nil
    }

    /// Bundle identifiers of the apps above this process, for example Terminal or the editor of an agent.
    static func callerApps() -> [String] {
        var ids: [String] = []
        var pid = getppid()
        for _ in 0..<32 where pid > 1 {
            if let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier { ids.append(id) }
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { break }
            pid = pid_t(info.pbi_ppid)
        }
        return ids
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

    /// True if the process exists and is Lidless. After a crash, macOS can give the old pid to another process.
    private static func alive(_ pid: Int32) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 else { return false }
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return true }
        return String(cString: path).hasSuffix("/Contents/MacOS/Lidless")
    }

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
        print("Lidless: running (pid \(s.pid))")
        if s.active {
            var line = "Session: active, held by \((s.holders ?? []).joined(separator: ", "))"
            if let a = s.startedAt { line += ", started at \(shortTime(a))" }
            if let e = s.endsAt { line += ", \(clock(e.timeIntervalSinceNow)) left" }
            print(line)
            print("Limits: battery \(s.batteryFloor.map { "below \($0)%" } ?? "none"), "
                  + "heat \(s.thermalStop ?? "none"), lid \(s.lidClosed ? "may close" : "open")")
        } else {
            print("Session: none" + (s.lastStop.map { " (last: \($0))" } ?? ""))
        }
        print("Battery: \(s.battery.map { "\($0)%" } ?? "?")\(s.onAC ? " on mains power" : " on battery")"
              + ", temperature: \(s.thermal)"
              + (temperatures(.init(chip: s.chipTemp, battery: s.batteryTemp)).map { " (\($0))" } ?? ""))
        print("Caffeinate: \(s.caffeinated ? "on" : "off")")
        print("Lid permission: \(s.lidPermission ? "granted" : "not granted"), SleepDisabled: \(s.sleepDisabled ? 1 : 0)")
        return 0
    }
}
