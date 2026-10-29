// Lidless: a menu bar app that keeps the Mac awake, with the lid open or closed,
// and stops by itself at a time limit, a battery floor or a heat limit.
//
// Lid open:   an IOKit power assertion, the same call that /usr/bin/caffeinate makes.
// Lid closed: `pmset -a disablesleep 1`, through a sudoers rule for that one command.

import SwiftUI
import AppKit
import IOKit.ps
import IOKit.pwr_mgt
import ServiceManagement

// MARK: - Session

struct Config {
    var endsAfter: TimeInterval?
    var batteryFloor: Int?
    var thermalLimit: Int?      // ProcessInfo.ThermalState raw value: 1 fair, 2 serious, 3 critical
    var lidClosed: Bool
    var keepDisplay: Bool
    var sleepDisplay: Bool
    var stopOnWake: Bool
}

final class Session: ObservableObject {
    static let shared = Session()

    @Published var active = false
    @Published var config: Config?
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

    private var assertions: [IOPMAssertionID] = []
    private var caffeinate: Process?
    private var watchdog: Process?
    private var wakeObserver: NSObjectProtocol?
    private var timer: Timer?
    private var activity: NSObjectProtocol?

    private static let pmset = "/usr/bin/pmset"
    private static let sudoersFile = "/etc/sudoers.d/lidless"
    private static let lidFlag = "lidSleepDisabledByLidless"

    init() {
        lidPermission = Self.canDisableSleep()
        // A crash during a lid-closed session leaves sleep disabled. Undo it at launch.
        if UserDefaults.standard.bool(forKey: Self.lidFlag) {
            Self.setDisableSleep(false)
            UserDefaults.standard.set(false, forKey: Self.lidFlag)
        }
        readSensors()
        // .common: the guardrail check also runs while a menu or a picker is open.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func start(_ c: Config) {
        error = nil
        if c.lidClosed {
            guard lidPermission, Self.setDisableSleep(true) else {
                error = "Could not disable lid sleep. Grant the permission first."
                return
            }
            UserDefaults.standard.set(true, forKey: Self.lidFlag)
            startWatchdog()
        }
        assertions.append(contentsOf: [Self.hold(kIOPMAssertionTypePreventUserIdleSystemSleep, "Lidless session")]
            + (c.keepDisplay ? [Self.hold(kIOPMAssertionTypePreventUserIdleDisplaySleep, "Lidless session")] : []))

        config = c
        startedAt = Date()
        endsAt = c.endsAfter.map { Date().addingTimeInterval($0) }
        active = true
        // A menu bar app with no visible window can get App Nap, which slows the guardrail timer.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "Lidless guardrails")

        if c.sleepDisplay && !c.keepDisplay {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Self.run(Self.pmset, ["displaysleepnow"]) }
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
    }

    func stop(_ reason: String) {
        guard active else { return }
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions.removeAll()
        if config?.lidClosed == true {
            Self.setDisableSleep(false)
            UserDefaults.standard.set(false, forKey: Self.lidFlag)
        }
        watchdog?.terminate()
        watchdog = nil
        if let o = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        wakeObserver = nil
        active = false
        if let a = activity { ProcessInfo.processInfo.endActivity(a) }
        activity = nil
        let f = DateFormatter()
        f.timeStyle = .short
        lastStop = "\(reason) at \(f.string(from: Date()))"
    }

    private func tick() {
        now = Date()
        readSensors()
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

    // Open at login also makes sure that a crash during a lid-closed session gets cleaned up at the next boot.
    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = "Open at login: \(error.localizedDescription)"
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    // Caffeinate switch: runs the real `caffeinate -dimsu`, no limits. Separate from a session.
    // `-w` ends caffeinate when Lidless exits, also after a crash.
    func setCaffeinated(_ on: Bool) {
        caffeinate?.terminate()
        caffeinate = nil
        if on {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            p.arguments = ["-dimsu", "-w", String(ProcessInfo.processInfo.processIdentifier)]
            p.terminationHandler = { [weak self] proc in
                DispatchQueue.main.async { if self?.caffeinate === proc { self?.caffeinate = nil; self?.caffeinated = false } }
            }
            do { try p.run(); caffeinate = p } catch { self.error = "caffeinate: \(error.localizedDescription)" }
        }
        caffeinated = caffeinate != nil
    }

    private static func hold(_ type: String, _ name: String) -> IOPMAssertionID {
        var id = IOPMAssertionID(0)
        IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), name as CFString, &id)
        return id
    }

    // If this app dies during a lid-closed session, the shell restores lid sleep.
    private func startWatchdog() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 5; done; /usr/bin/sudo -n \(Self.pmset) -a disablesleep 0"]
        try? p.run()
        watchdog = p
    }

    // MARK: Lid permission (sudoers rule for one command)

    @discardableResult
    static func setDisableSleep(_ on: Bool) -> Bool {
        run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", on ? "1" : "0"]) == 0
    }

    static func canDisableSleep() -> Bool {
        run("/usr/bin/sudo", ["-n", "-l", pmset, "-a", "disablesleep", "1"]) == 0
    }

    func grantPermission() {
        let rule = "\(NSUserName()) ALL=(root) NOPASSWD: \(Self.pmset) -a disablesleep 0, \(Self.pmset) -a disablesleep 1"
        let shell = "t=$(mktemp) && echo '\(rule)' > $t && /usr/sbin/visudo -cf $t && "
            + "/usr/bin/install -m 0440 -o root -g wheel $t \(Self.sudoersFile); rc=$?; rm -f $t; exit $rc"
        admin(shell)
        lidPermission = Self.canDisableSleep()
        if !lidPermission { error = "The permission was not installed." }
    }

    func revokePermission() {
        admin("rm -f \(Self.sudoersFile)")
        lidPermission = Self.canDisableSleep()
    }

    private func admin(_ shell: String) {
        var err: NSDictionary?
        NSAppleScript(source: "do shell script \"\(shell)\" with administrator privileges")?
            .executeAndReturnError(&err)
    }

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}

func thermalName(_ v: Int) -> String { ["Normal", "Warm", "Hot", "Critical"][max(0, min(3, v))] }

func durationName(_ m: Int) -> String { m < 60 ? "\(m) minutes" : (m == 60 ? "1 hour" : "\(m / 60) hours") }

func clock(_ t: TimeInterval) -> String {
    let s = max(0, Int(t))
    return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
}

// MARK: - Panel

struct Panel: View {
    @ObservedObject var s: Session
    @AppStorage("useDuration") private var useDuration = true
    @AppStorage("minutes") private var minutes = 120
    @AppStorage("useBattery") private var useBattery = true
    @AppStorage("floor") private var floor = 20
    @AppStorage("useThermal") private var useThermal = true
    @AppStorage("thermalLimit") private var thermalLimit = 2
    @AppStorage("allowLidClosed") private var lidClosed = false
    @AppStorage("keepDisplay") private var keepDisplay = false
    @AppStorage("sleepDisplayOnStart") private var sleepDisplay = false
    @AppStorage("stopOnWake") private var stopOnWake = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "figure.walk")
                Text("Lidless").font(.title3.bold())
                Spacer()
                Toggle("Caffeinate", isOn: Binding(get: { s.caffeinated }, set: { s.setCaffeinated($0) }))
                    .toggleStyle(.switch).controlSize(.small)
                    .help("Runs caffeinate -dimsu until you switch it off.")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.borderless).help("Quit (ends the session)")
            }
            Divider()
            if s.active { running } else { setup }
        }
        .padding(16)
        .frame(width: 400)
    }

    private var batteryNow: String { s.battery.map { "\($0)%" + (s.onAC ? " ⚡︎" : "") } ?? "—" }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Duration")
                    Toggle("Stop after", isOn: $useDuration)
                    Picker("", selection: $minutes) {
                        ForEach([30, 60, 120, 240, 480], id: \.self) { Text(durationName($0)).tag($0) }
                    }.labelsHidden().disabled(!useDuration)
                    Text("")
                }
                GridRow {
                    Text("Battery")
                    Toggle("Stop below", isOn: $useBattery)
                    Picker("", selection: $floor) {
                        ForEach([10, 15, 20, 30, 40, 50], id: \.self) { Text("\($0)%").tag($0) }
                    }.labelsHidden().disabled(!useBattery)
                    Text("Now: \(batteryNow)").foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Temperature")
                    Toggle("Stop at", isOn: $useThermal)
                    Picker("", selection: $thermalLimit) {
                        ForEach(1...3, id: \.self) { Text(thermalName($0)).tag($0) }
                    }.labelsHidden().disabled(!useThermal)
                    Text("Now: \(thermalName(s.thermal))").foregroundStyle(.secondary)
                }
            }
            Divider()
            Toggle("Allow the lid to close (also on battery)", isOn: $lidClosed)
            if lidClosed {
                Text("A closed Mac in a bag can get hot. Keep the battery and time limits on.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if lidClosed && !s.lidPermission {
                HStack(alignment: .top) {
                    Text("Needs a one-time admin permission. It writes /etc/sudoers.d/lidless, which lets "
                         + "only you run only `pmset -a disablesleep 0` and `1` with no password.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Grant…") { s.grantPermission() }.controlSize(.small)
                }
            }
            Toggle("Keep display awake", isOn: $keepDisplay)
            Toggle("Put display to sleep on start", isOn: $sleepDisplay).disabled(keepDisplay)
            Toggle("Stop session when display wakes", isOn: $stopOnWake)

            if let e = s.error { Text(e).font(.caption).foregroundStyle(.red) }
            if let l = s.lastStop { Text("Last session: \(l)").font(.caption).foregroundStyle(.secondary) }

            Button {
                s.start(Config(
                    endsAfter: useDuration ? TimeInterval(minutes * 60) : nil,
                    batteryFloor: useBattery ? floor : nil,
                    thermalLimit: useThermal ? thermalLimit : nil,
                    lidClosed: lidClosed, keepDisplay: keepDisplay,
                    sleepDisplay: sleepDisplay, stopOnWake: stopOnWake))
            } label: {
                Text("Start Session").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)

            HStack {
                Toggle("Open at login", isOn: Binding(get: { s.openAtLogin }, set: { s.setOpenAtLogin($0) }))
                    .font(.caption)
                Spacer()
                if s.lidPermission {
                    Button("Remove lid permission") { s.revokePermission() }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
        .toggleStyle(.checkbox)
    }

    private var running: some View {
        let c = s.config
        return VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 2) {
                Text(clock(s.endsAt.map { $0.timeIntervalSince(s.now) } ?? s.now.timeIntervalSince(s.startedAt)))
                    .font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit()
                Text(s.endsAt == nil ? "Elapsed" : "Remaining").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Battery").foregroundStyle(.secondary)
                    Text(batteryNow)
                    Text(c?.batteryFloor.map { "Stop below \($0)%" } ?? "No limit").foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Temperature").foregroundStyle(.secondary)
                    Text(thermalName(s.thermal))
                    Text(c?.thermalLimit.map { "Stop at \(thermalName($0))" } ?? "No limit").foregroundStyle(.secondary)
                }
            }
            Text(c?.lidClosed == true ? "Lidless is running. You can close the lid."
                                      : "Lidless is running. Keep the lid open.")
                .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Button { s.stop("Stopped by you") } label: {
                Text("Stop Session").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        Session.shared.stop("App quit")
        Session.shared.setCaffeinated(false)
    }
}

@main
struct LidlessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var s = Session.shared

    var body: some Scene {
        MenuBarExtra {
            Panel(s: s)
        } label: {
            Image(systemName: s.active ? "figure.walk" : (s.caffeinated ? "cup.and.saucer.fill" : "figure.stand"))
        }
        .menuBarExtraStyle(.window)
    }
}
