// A session keeps the Mac awake until a guardrail stops it: a time limit, a battery floor or a heat limit.
//
// Lid open:   an IOKit power assertion, the same call that /usr/bin/caffeinate makes.
// Lid closed: `pmset -a disablesleep 1`, through a sudoers rule for that one command.
// The Caffeinate switch is separate: it runs `/usr/bin/caffeinate -dimsu` with no limits.

import AppKit
import IOKit.ps
import IOKit.pwr_mgt
import ServiceManagement

final class Session: ObservableObject {
    static let shared = Session()

    @Published var active = false
    @Published var config: Config?
    @Published var startedBy = "panel"
    @Published var startedAt = Date()
    @Published var endsAt: Date?
    @Published var now = Date()
    @Published var battery: Int?
    @Published var onAC = true
    @Published var thermal = 0
    @Published var lidPermission = false
    @Published var lastStop: String?
    @Published var error: String?
    @Published var caffeinated = false
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled
    @Published var appsToReopen: [URL] = []

    private var assertions: [IOPMAssertionID] = []
    private var activity: NSObjectProtocol?
    private var changedSleep = false        // true when this session set SleepDisabled = 1
    private var savedBrightness: Float?
    private var watchdog: Process?
    private var caffeinate: Process?
    private var wakeObserver: NSObjectProtocol?
    private var timer: Timer?

    init() {
        Pref.register()
        lidPermission = Lid.canDisableSleep()
        // A crash during a lid-closed session leaves sleep disabled. Undo it at launch.
        if UserDefaults.standard.bool(forKey: Lid.flag) {
            Lid.setDisableSleep(false)
            UserDefaults.standard.set(false, forKey: Lid.flag)
            Log.write("Restored lid sleep that an earlier run left disabled")
        }
        readSensors()
        // .common: the guardrail check also runs while a menu or a picker is open.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    var summary: String { config.map(Self.describe) ?? "" }

    static func describe(_ c: Config) -> String {
        var parts: [String] = []
        parts.append(c.endsAfter.map { "stops after \(shortDuration($0))" } ?? "no time limit")
        parts.append(c.batteryFloor.map { "below \($0)%" } ?? "no battery limit")
        parts.append(c.thermalLimit.map { "at \(thermalName($0))" } ?? "no heat limit")
        parts.append(c.lidClosed ? "lid may close" : "lid open")
        return parts.joined(separator: ", ")
    }

    /// Starts a session. Returns an error message, or nil on success.
    @discardableResult
    func start(_ c: Config, by source: String = "panel") -> String? {
        guard !active else { return fail("A session is already active. Stop it first.") }
        error = nil
        changedSleep = false
        if c.lidClosed {
            guard lidPermission else { return fail("Lid permission missing. Open Lidless Settings > Lid to grant it.") }
            // Restore the previous setting at the end: touch SleepDisabled only if it was off.
            if !Lid.sleepDisabled() {
                guard Lid.setDisableSleep(true) else { return fail("Could not run pmset -a disablesleep 1.") }
                changedSleep = true
                UserDefaults.standard.set(true, forKey: Lid.flag)
                startWatchdog()
            }
        }
        assertions = [Self.hold(kIOPMAssertionTypePreventUserIdleSystemSleep)]
            + (c.keepDisplay ? [Self.hold(kIOPMAssertionTypePreventUserIdleDisplaySleep)] : [])
        // A menu bar app with no visible window can get App Nap, which slows the guardrail timer.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "Lidless guardrails")
        config = c
        startedBy = source
        startedAt = Date()
        endsAt = c.endsAfter.map { Date().addingTimeInterval($0) }
        active = true

        appsToReopen = c.cleanupApps.isEmpty ? [] : AppCleanup.quit(c.cleanupApps)
        if !c.reopenApps { appsToReopen = [] }
        if c.minBrightness, let b = Brightness.get(), Brightness.set(0) { savedBrightness = b }
        if c.sleepDisplay && !c.keepDisplay {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Shell.run(Lid.pmset, ["displaysleepnow"]) }
        }
        if c.stopOnWake {
            // Wait until the display is asleep, so the start itself does not count as a wake.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, self.active else { return }
                self.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
                ) { [weak self] _ in self?.stop("Display woke") }
            }
        }
        Log.write("Session started by \(source): \(summary)")
        Notifier.post("Lidless session started", summary.prefix(1).uppercased() + summary.dropFirst() + ".")
        Control.shared.writeState()
        return nil
    }

    /// Ends the session and undoes everything that start did. Returns false if none was active.
    @discardableResult
    func stop(_ reason: String) -> Bool {
        guard active else { return false }
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions.removeAll()
        if let a = activity { ProcessInfo.processInfo.endActivity(a) }
        activity = nil
        if changedSleep {
            Lid.setDisableSleep(false)
            UserDefaults.standard.set(false, forKey: Lid.flag)
            changedSleep = false
        }
        watchdog?.terminate()
        watchdog = nil
        if let o = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        wakeObserver = nil
        if let b = savedBrightness { Brightness.set(b) }
        savedBrightness = nil
        AppCleanup.reopen(appsToReopen)
        appsToReopen = []
        active = false
        let f = DateFormatter()
        f.timeStyle = .short
        lastStop = "\(reason) at \(f.string(from: Date()))"
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

    private func tick() {
        now = Date()
        readSensors()
        if Control.shared.stale { Control.shared.writeState() }
        guard active, let c = config else { return }
        if let end = endsAt, now >= end { stop("Time limit reached") }
        else if let floor = c.batteryFloor, !onAC, let b = battery, b <= floor { stop("Battery at \(b)%") }
        else if let limit = c.thermalLimit, thermal >= limit { stop("Mac too hot (\(thermalName(thermal)))") }
    }

    private func readSensors() {
        thermal = ProcessInfo.processInfo.thermalState.rawValue
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

    private static func hold(_ type: String) -> IOPMAssertionID {
        var id = IOPMAssertionID(0)
        IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "Lidless session" as CFString, &id)
        return id
    }

    // If this app dies during a lid-closed session, the shell restores lid sleep.
    private func startWatchdog() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 5; done; /usr/bin/sudo -n \(Lid.pmset) -a disablesleep 0"]
        try? p.run()
        watchdog = p
    }

    // MARK: Caffeinate switch: the real `caffeinate -dimsu`, no limits.
    // `-w` ends caffeinate when Lidless exits, also after a crash.

    func setCaffeinated(_ on: Bool) {
        guard on != caffeinated || (on && caffeinate == nil) else { return }
        caffeinate?.terminate()
        caffeinate = nil
        if on {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            p.arguments = ["-dimsu", "-w", String(ProcessInfo.processInfo.processIdentifier)]
            p.terminationHandler = { [weak self] proc in
                DispatchQueue.main.async {
                    guard let self, self.caffeinate === proc else { return }
                    self.caffeinate = nil
                    self.caffeinated = false
                    Control.shared.writeState()
                }
            }
            do { try p.run(); caffeinate = p } catch { self.error = "caffeinate: \(error.localizedDescription)" }
        }
        caffeinated = caffeinate != nil
        Log.write("Caffeinate \(caffeinated ? "on" : "off")")
        Control.shared.writeState()
    }

    // MARK: Settings actions

    func grantPermission() {
        lidPermission = Lid.grant()
        error = lidPermission ? nil : "The lid permission was not installed."
        Log.write(lidPermission ? "Lid permission granted" : "Lid permission not granted")
        Control.shared.writeState()
    }

    func revokePermission() {
        Lid.revoke()
        lidPermission = Lid.canDisableSleep()
        Log.write("Lid permission removed")
        Control.shared.writeState()
    }

    // Open at login also makes sure that a crash during a lid-closed session gets cleaned up at the next boot.
    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = "Open at login: \(error.localizedDescription)"
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
}
