// The settings window. An NSWindow that we own, so it opens reliably from a menu bar app.

import SwiftUI
import AppKit

enum SettingsTab: Hashable { case general, safety, caffeinate, lid, cleanup, agents }

final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var tab = SettingsTab.general
}

enum SettingsWindow {
    private static var window: NSWindow?

    static func show(_ tab: SettingsTab = .general) {
        MenuPanel.close()
        SettingsRouter.shared.tab = tab
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Lidless Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

struct SettingsView: View {
    @ObservedObject private var router = SettingsRouter.shared

    var body: some View {
        TabView(selection: $router.tab) {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            SafetyTab().tabItem { Label("Safety", systemImage: "thermometer.medium") }.tag(SettingsTab.safety)
            CaffeinateTab().tabItem { Label("Caffeinate", systemImage: "cup.and.saucer") }.tag(SettingsTab.caffeinate)
            LidTab().tabItem { Label("Lid", systemImage: "laptopcomputer") }.tag(SettingsTab.lid)
            CleanupTab().tabItem { Label("App Cleanup", systemImage: "xmark.app") }.tag(SettingsTab.cleanup)
            AgentsTab().tabItem { Label("Agents", systemImage: "terminal") }.tag(SettingsTab.agents)
        }
        .padding(20)
        .frame(width: 580, height: 560)
    }
}

private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject private var s = Session.shared
    @ObservedObject private var u = Updates.shared
    @AppStorage(Pref.notifications) private var notifications = true
    @AppStorage(Pref.autoUpdate) private var autoUpdate = true

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open at login", isOn: Binding(get: { s.openAtLogin }, set: { s.setOpenAtLogin($0) }))
                Text("Also cleans up after a crash, at the next login.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Notifications") {
                Toggle("Notify when a session starts or stops", isOn: $notifications)
                    .onChange(of: notifications) { on in if on { Notifier.requestPermission() } }
            }
            Section("Updates") {
                Toggle("Check GitHub for updates every day", isOn: $autoUpdate)
                HStack {
                    Text(u.status).foregroundStyle(u.available ? .orange : .secondary)
                    Spacer()
                    Button(u.checking ? "Checking…" : "Check Now") { u.check() }.disabled(u.checking)
                }
                if u.available {
                    HStack {
                        Text(u.updateCommand).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Spacer()
                        Button("Copy") { copy(u.updateCommand) }
                    }
                }
            }
            Section("About") {
                LabeledContent("Version", value: "\(u.version) (\(String(u.commit.prefix(7))))")
                HStack {
                    Button("Reveal Logs in Finder") {
                        if !FileManager.default.fileExists(atPath: Log.url.path) { Log.write("Log opened") }
                        NSWorkspace.shared.activateFileViewerSelecting([Log.url])
                    }
                    Button("Open on GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/\(Updates.repo)")!) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Safety (the heat limit and why it exists)

private struct SafetyTab: View {
    @ObservedObject private var s = Session.shared
    @AppStorage(Pref.useThermal) private var useThermal = true
    @AppStorage(Pref.thermalLimit) private var thermalLimit = 2
    @State private var confirmOff = false

    private static let levels: [(name: String, meaning: String)] = [
        ("Normal", "No action. The Mac runs at full speed."),
        ("Warm", "Fans speed up and macOS cuts background work."),
        ("Hot", "macOS slows the processor down to cool the Mac."),
        ("Critical", "macOS cuts speed as far as it can. Next step: emergency shutdown."),
    ]

    var body: some View {
        Form {
            Section("Heat limit") {
                Toggle("Stop the session at a heat level", isOn: Binding(
                    get: { useThermal },
                    set: { on in if on { useThermal = true } else { confirmOff = true } }))
                Picker("Stop at", selection: $thermalLimit) {
                    Text("Warm — conservative").tag(1)
                    Text("Hot — recommended").tag(2)
                    Text("Critical — last resort").tag(3)
                }
                .disabled(!useThermal)
                if !useThermal {
                    Text("No heat limit. Only the time and battery limits protect the Mac. Not recommended.")
                        .font(.caption).foregroundStyle(.red)
                } else if thermalLimit == 3 {
                    Text("At Critical the Mac is already as hot as macOS permits. Use Hot unless you have a reason.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("This limit is also a ceiling for agents: `lidless start --thermal-stop` can make it "
                     + "stricter, not weaker.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Now", value: thermalName(s.thermal))
            }
            Section("What the levels mean") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    ForEach(Array(Self.levels.enumerated()), id: \.offset) { i, level in
                        GridRow {
                            Text(level.name).bold().foregroundStyle(i == s.thermal ? Color.accentColor : .primary)
                            Text(level.meaning).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text("Lidless reads the level that macOS reports (ProcessInfo.thermalState), not a temperature "
                     + "in degrees. macOS slows the Mac down before it reports Hot, so set a battery limit "
                     + "and a time limit too.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("When heat is a risk") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• A closed Mac in a bag, a sleeve, on a bed or under a blanket: no air flows, so heat builds up.")
                    Text("• Heavy work for a long time: builds, tests, local AI models, video export.")
                    Text("• Charging while hot: heat together with a full charge wears the battery fastest.")
                    Text("• A hot room, a car or direct sun. Apple gives 10–35 °C as the range to use a Mac in.")
                    Text("• A MacBook Air has no fan, so it slows down sooner and stays warm longer.")
                }
                .fixedSize(horizontal: false, vertical: true)
                Text("macOS protects the Mac itself: it slows down and, at the end, shuts down. The main risk of "
                     + "repeated heat is faster battery wear. Damage or a swollen battery is rare, but it is not "
                     + "worth the risk.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .alert("Turn off the heat limit?", isPresented: $confirmOff) {
            Button("Turn Off", role: .destructive) { useThermal = false }
            Button("Keep It On", role: .cancel) {}
        } message: {
            Text("A session will then continue while the Mac is hot, for example in a closed bag. "
                 + "Only the time and battery limits will stop it.")
        }
    }
}

// MARK: - Caffeinate (which flags the switch passes to /usr/bin/caffeinate)

private struct CaffeinateTab: View {
    @ObservedObject private var s = Session.shared
    @AppStorage(Pref.caffeinateFlags) private var flags = "dimsu"
    @AppStorage(Pref.caffeinateMinutes) private var minutes = 0

    private static let options: [(letter: Character, name: String, meaning: String)] = [
        ("d", "Display", "Keep the display on."),
        ("i", "Idle sleep", "Stop the Mac from sleeping when nobody uses it. The caffeinate default."),
        ("m", "Disk sleep", "Keep the disks spinning. Almost no effect on an SSD."),
        ("s", "System sleep", "Stop all system sleep on mains power, also with the lid closed. No effect on battery."),
        ("u", "User active", "Tell macOS that a user is present, which wakes the display. "
                             + "Without a time limit, macOS drops this after 5 seconds."),
    ]
    private static let presets = [("dimsu", "Everything"), ("dims", "No wake"), ("di", "Display and idle"), ("i", "Idle only")]

    private var command: String {
        "caffeinate " + Session.savedCaffeinateArgs().joined(separator: " ") + " -w <Lidless pid>"
    }

    private func binding(_ letter: Character) -> Binding<Bool> {
        Binding(get: { flags.contains(letter) }, set: { on in
            let next = on ? flags + String(letter) : flags.replacingOccurrences(of: String(letter), with: "")
            if let f = normalizedFlags(next) { flags = f; s.restartCaffeinateIfOn() }
        })
    }

    var body: some View {
        Form {
            Section("What the Caffeinate switch runs") {
                ForEach(Self.options, id: \.letter) { o in
                    Toggle(isOn: binding(o.letter)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("-\(String(o.letter))  \(o.name)").font(.body.monospaced())
                            Text(o.meaning).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .disabled(flags == String(o.letter))   // keep at least one flag
                }
                HStack {
                    Text("Presets").foregroundStyle(.secondary)
                    ForEach(Self.presets, id: \.0) { p in
                        Button("\(p.1) (-\(p.0))") { flags = p.0; s.restartCaffeinateIfOn() }
                            .controlSize(.small)
                    }
                }
            }
            Section("Time limit") {
                Picker("Switch off after", selection: $minutes) {
                    Text("Never").tag(0)
                    ForEach(Pref.durations, id: \.self) { Text(durationName($0)).tag($0) }
                }
                .onChange(of: minutes) { _ in s.restartCaffeinateIfOn() }
            }
            Section("Command") {
                Text(command).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Text("`-w` ends caffeinate when Lidless quits or crashes. "
                     + (s.caffeinated ? "Caffeinate is on: changes apply at once." : "Caffeinate is off."))
                    .font(.caption).foregroundStyle(.secondary)
                Text("The switch has no battery or heat limits. For a Mac in a bag, use a session.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Lid

private struct LidTab: View {
    @ObservedObject private var s = Session.shared
    @State private var sleepDisabled = Lid.sleepDisabled()

    var body: some View {
        Form {
            Section("Lid access") {
                Text("macOS sleeps when you close the lid on battery. To prevent that, Lidless runs "
                     + "`pmset -a disablesleep 1` during a session and `0` after it. That needs one sudoers rule:")
                    .fixedSize(horizontal: false, vertical: true)
                Text(Lid.rule).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                LabeledContent("Permission", value: s.lidPermission ? "Granted" : "Not granted")
                HStack {
                    if s.lidPermission {
                        Button("Remove Permission…") { s.revokePermission() }
                    } else {
                        Button("Grant Permission…") { s.grantPermission() }
                    }
                }
            }
            Section("Current state") {
                LabeledContent("SleepDisabled", value: sleepDisabled ? "1 (lid sleep off)" : "0 (normal)")
                HStack {
                    Button("Refresh") { sleepDisabled = Lid.sleepDisabled() }
                    if sleepDisabled && !s.active && s.lidPermission {
                        Button("Restore Normal Sleep") {
                            Lid.setDisableSleep(false)
                            sleepDisabled = Lid.sleepDisabled()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - App Cleanup

private struct CleanupTab: View {
    @ObservedObject private var list = CleanupList.shared
    @AppStorage(Pref.reopenApps) private var reopenApps = true
    @State private var apps = AppCleanup.candidates()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quit these apps when a session starts, to save battery. They can still ask you to save.")
            Text("Do not select the app that runs your agent, for example your terminal.")
                .font(.caption).foregroundStyle(.orange)
            Toggle("Reopen these apps when the session stops", isOn: $reopenApps)
            List {
                ForEach(apps) { app in
                    HStack {
                        Toggle("", isOn: Binding(get: { list.ids.contains(app.id) }, set: { _ in list.toggle(app.id) }))
                            .labelsHidden()
                        if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                        Text(app.name)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(app.memory), countStyle: .memory))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                ForEach(list.ids.filter { id in !apps.contains { $0.id == id } }, id: \.self) { id in
                    HStack {
                        Toggle("", isOn: Binding(get: { true }, set: { _ in list.toggle(id) })).labelsHidden()
                        Text(id).foregroundStyle(.secondary)
                        Spacer()
                        Text("not running").foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Text("Memory column: physical footprint now.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { apps = AppCleanup.candidates() }
            }
        }
        .toggleStyle(.checkbox)
    }
}

// MARK: - Agents

private struct AgentsTab: View {
    @State private var commandInstalled = CommandInstall.installed
    @State private var refresh = 0
    @State private var message: String?

    var body: some View {
        Form {
            Section("Command line") {
                LabeledContent("lidless", value: commandInstalled ? "Installed in ~/.local/bin" : "Not installed")
                HStack {
                    Button(commandInstalled ? "Reinstall" : "Install") {
                        do { try CommandInstall.install(); message = nil } catch { message = error.localizedDescription }
                        commandInstalled = CommandInstall.installed
                    }
                    if commandInstalled {
                        Button("Remove") { CommandInstall.remove(); commandInstalled = CommandInstall.installed }
                    }
                }
                Text("lidless start --duration 2h --battery-floor 20 --thermal-stop hot\nlidless status --json\nlidless stop")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            Section("Agent skills") {
                ForEach(SkillTarget.all) { t in
                    let st = Skills.status(t)
                    HStack {
                        Text(t.name)
                        Spacer()
                        Text(st == .current ? "Installed" : (st == .outdated ? "Update available" : "Not installed"))
                            .foregroundStyle(st == .outdated ? .orange : .secondary)
                        Button(st == .missing ? "Install" : (st == .outdated ? "Update" : "Reinstall")) {
                            do { try Skills.install(t); message = nil } catch { message = error.localizedDescription }
                            refresh += 1
                        }
                        if st != .missing {
                            Button("Remove") { Skills.remove(t); refresh += 1 }
                        }
                    }
                }
                .id(refresh)
            }
            Section("Other agents") {
                HStack {
                    Button("Copy Setup Prompt") { copy(Skills.setupPrompt) }
                    Button("Open SKILL.md") { if let u = Skills.bundled { NSWorkspace.shared.open(u) } }
                }
            }
            if let m = message { Text(m).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
    }
}
