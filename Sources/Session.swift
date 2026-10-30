// A session keeps the Mac awake until a guardrail stops it: a time limit, a battery floor or a heat limit.
//
// Lid open:   an IOKit power assertion, the same call that /usr/bin/caffeinate makes.
// Lid closed: also `pmset -a disablesleep 1` (see Lid.swift).
//
// Several agents can share one session: each one is a holder. `stop --by <name>` removes one holder,
// and the session ends when no holder is left, or at once when a guardrail trips or the user stops it.

import AppKit
import IOKit.ps
import IOKit.pwr_mgt

final class Session: ObservableObject {
    static let shared = Session()

    @Published private(set) var active = false
    @Published private(set) var config: Config?
    @Published private(set) var holders: [String] = []
    @Published private(set) var startedAt = Date()
    @Published private(set) var endsAt: Date?
    @Published private(set) var appsToReopen: [URL] = []
    @Published private(set) var lastStop: String?
    @Published var error: String?

    // Sensors, also shown while no session runs.
    @Published private(set) var now = Date()
    @Published private(set) var battery: Int?
    @Published private(set) var onAC = true
    @Published private(set) var thermal = 0
    @Published private(set) var temps = Temperature.Reading()
    @Published private(set) var lidPermission = false

    private var assertions: [IOPMAssertionID] = []
    private var activity: NSObjectProtocol?
    private var savedBrightness: Float?
    private var watchdog: Process?
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var timer: Timer?
    private var lastSensorRead = Date.distantPast

    var startedBy: String { holders.first ?? "panel" }
    var holderList: String { holders.joined(separator: ", ") }
    var summary: String { config.map(Self.describe) ?? "" }
    /// "Hot, chip 98 °C, battery 41 °C"
    var heatNow: String { ([thermalName(thermal)] + [temperatures(temps)].compactMap { $0 }).joined(separator: ", ") }

    init() {
        Pref.register()
        lidPermission = Lid.canDisableSleep()
        if Lid.ownsSleepDisabled {   // a crash or a failed restore left lid sleep off
            if Lid.setDisableSleep(false) { Lid.ownsSleepDisabled = false }
            Log.write("Restored lid sleep that an earlier run left disabled")
        }
        readSensors()
        // .common: the guardrail check also runs while a menu or a picker is open.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.3   // let macOS group this wake-up with others to save energy
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // A Mac that sleeps during a session did not stay awake. Say so in the log, with the likely reason.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.active else { return }
            Log.write("The Mac goes to sleep during the session"
                      + (self.config?.lidClosed == true ? "" : ". Lid mode is off, so a closed lid sleeps the Mac"))
        }
    }

    static func describe(_ c: Config) -> String {
        [c.endsAfter.map { "stops after \(shortDuration($0))" } ?? "no time limit",
         c.batteryFloor.map { "below \($0)%" } ?? "no battery limit",
         c.thermalLimit.map { "at \(thermalName($0))" } ?? "no heat limit",
         c.lidClosed ? "lid may close" : "lid open"].joined(separator: ", ")
    }

    // MARK: Start, join, leave, stop

    /// Starts a session. Returns an error message, or nil on success.
    @discardableResult
    func start(_ c: Config, by source: String = "panel") -> String? {
        guard !active else { return fail("A session is already active. Stop it first.") }
        error = nil
        // A session that a guardrail would stop at once only confuses. Say why instead.
        readSensors()
        if let floor = c.batteryFloor, !onAC, let b = battery, b <= floor {
            return fail("The battery is at \(b)%, at or below the limit of \(floor)%. Connect power or lower the limit.")
        }
        if let limit = c.thermalLimit, thermal >= limit {
            return fail("The Mac is already \(thermalName(thermal)), at or above the heat limit. Let it cool down first.")
        }
        if c.lidClosed, let e = enableLidMode() { return fail(e) }

        assertions = [Self.hold(kIOPMAssertionTypePreventUserIdleSystemSleep)]
            + (c.keepDisplay ? [Self.hold(kIOPMAssertionTypePreventUserIdleDisplaySleep)] : [])
        // A menu bar app with no visible window can get App Nap, which slows the guardrail timer.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "Lidless guardrails")
        config = c
        holders = [source]
        startedAt = Date()
        endsAt = c.endsAfter.map { Date().addingTimeInterval($0) }
        active = true

        let quit = c.cleanupApps.isEmpty ? [] : AppCleanup.quit(c.cleanupApps)
        appsToReopen = c.reopenApps ? quit : []
        if c.minBrightness, let b = Brightness.get(), Brightness.set(0) { savedBrightness = b }
        if c.sleepDisplay && !c.keepDisplay {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Shell.run(Lid.pmset, ["displaysleepnow"]) }
        }
        if c.stopOnWake { watchDisplayWake() }

        Log.write("Session started by \(source): \(summary)")
        Notifier.post("Lidless session started", sentence(summary))
        Control.shared.writeState()
        return nil
    }

    /// Adds a holder to the active session. The end time can move later and lid mode can turn on.
    /// The battery and heat limits stay as they are.
    func join(_ c: Config, by source: String) -> String? {
        guard active, var cur = config else { return start(c, by: source) }
        error = nil
        if c.lidClosed && !cur.lidClosed {
            if let e = enableLidMode() { return fail(e) }
            cur.lidClosed = true
        }
        if let end = endsAt, let add = c.endsAfter, Date().addingTimeInterval(add) > end {
            endsAt = Date().addingTimeInterval(add)
        }
        config = cur
        if !holders.contains(source) { holders.append(source) }
        Log.write("\(source) joined the session. Holders: \(holderList)")
        Control.shared.writeState()
        return nil
    }

    /// Removes one holder. The session ends when no holder is left.
    func release(_ source: String) -> (ok: Bool, message: String) {
        guard active else { return (true, "No session was active.") }
        guard let i = holders.firstIndex(of: source) else {
            return (false, "\(source) does not hold the session. Holders: \(holderList).")
        }
        holders.remove(at: i)
        if holders.isEmpty {
            stop("Stopped by \(source)")
            return (true, "Session stopped.")
        }
        Log.write("\(source) left the session. Holders: \(holderList)")
        Control.shared.writeState()
        return (true, "\(source) left the session. It continues for \(holderList).")
    }

    /// Ends the session and undoes everything that start did. Returns false if none was active.
    @discardableResult
    func stop(_ reason: String) -> Bool {
        guard active else { return false }
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions.removeAll()
        if let a = activity { ProcessInfo.processInfo.endActivity(a) }
        activity = nil
        restoreLidSleep()
        if let o = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        wakeObserver = nil
        if let b = savedBrightness { Brightness.set(b) }
        savedBrightness = nil
        AppCleanup.reopen(appsToReopen)
        appsToReopen = []
        holders = []
        active = false
        lastStop = "\(reason) at \(shortTime(Date()))"
        Log.write("Session stopped: \(reason)")
        Notifier.post("Lidless session stopped", reason + ".")
        Control.shared.writeState()
        return true
    }

    private func fail(_ message: String) -> String {
        error = message
        Log.write("Start refused: \(message)")
        Control.shared.writeState()
        return message
    }

    // MARK: Lid mode

    /// Sets SleepDisabled = 1 if it is not set yet. Only that change is undone at the end,
    /// so a value of 1 that the user set before stays.
    private func enableLidMode() -> String? {
        guard lidPermission else { return "Lid permission missing. Open Lidless Settings > Lid to grant it." }
        if Lid.sleepDisabled() { return nil }
        guard Lid.setDisableSleep(true) else { return "Could not run pmset -a disablesleep 1." }
        Lid.ownsSleepDisabled = true
        watchdog = Lid.startWatchdog()
        return nil
    }

    private func restoreLidSleep() {
        watchdog?.terminate()
        watchdog = nil
        guard Lid.ownsSleepDisabled else { return }
        if Lid.setDisableSleep(false) {
            Lid.ownsSleepDisabled = false
        } else {   // keep ownership: the next launch tries again
            error = "Could not restore lid sleep. Run `sudo pmset -a disablesleep 0` in Terminal."
            Log.write("Could not restore lid sleep")
            Notifier.post("Lidless could not restore sleep", "Run: sudo pmset -a disablesleep 0")
        }
    }

    func grantPermission() {
        lidPermission = Lid.grant()
        error = lidPermission ? nil : "The lid permission was not installed."
        Log.write(lidPermission ? "Lid permission granted" : "Lid permission not granted")
        Control.shared.writeState()
    }

    func revokePermission() {
        // Without the rule, the end of a lid session could not restore sleep. End it first.
        if active && Lid.ownsSleepDisabled { stop("Lid permission removed") }
        Lid.revoke()
        lidPermission = Lid.canDisableSleep()
        Log.write("Lid permission removed")
        Control.shared.writeState()
    }

    // MARK: Guardrails and sensors

    private func tick() {
        now = Date()
        // Read the sensors every second only when someone looks or a session runs.
        if active || MenuPanel.window?.isVisible == true || now.timeIntervalSince(lastSensorRead) >= 30 {
            readSensors()
        }
        if Control.shared.isStale(busy: active || Caffeinate.shared.on) { Control.shared.writeState() }
        guard active, let c = config else { return }
        if let end = endsAt, now >= end { stop("Time limit reached") }
        else if let floor = c.batteryFloor, !onAC, let b = battery, b <= floor { stop("Battery at \(b)%") }
        else if let limit = c.thermalLimit, thermal >= limit { stop("Mac too hot (\(heatNow))") }
    }

    private func readSensors() {
        lastSensorRead = Date()
        let level = ProcessInfo.processInfo.thermalState.rawValue
        temps = Temperature.read()
        if level != thermal {
            thermal = level
            Log.write("Heat level: \(heatNow)")
        }
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            battery = cur * 100 / max
            onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return
        }
    }

    /// Stops the session when the display wakes. Starts after 5 seconds, so that the start itself does not count.
    private func watchDisplayWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.active else { return }
            self.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.stop("Display woke") }
        }
    }

    private static func hold(_ type: String) -> IOPMAssertionID {
        var id = IOPMAssertionID(0)
        IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "Lidless session" as CFString, &id)
        return id
    }
}
