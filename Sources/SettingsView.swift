// The settings window. An NSWindow that we own, so it opens reliably from a menu bar app.

import SwiftUI
import AppKit

enum SettingsTab: Hashable { case general, lid, cleanup, agents }

final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var tab = SettingsTab.general
}

enum SettingsWindow {
    private static var window: NSWindow?

    static func show(_ tab: SettingsTab = .general) {
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
    }
}

struct SettingsView: View {
    @ObservedObject private var router = SettingsRouter.shared

    var body: some View {
        TabView(selection: $router.tab) {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            LidTab().tabItem { Label("Lid", systemImage: "laptopcomputer") }.tag(SettingsTab.lid)
            CleanupTab().tabItem { Label("App Cleanup", systemImage: "xmark.app") }.tag(SettingsTab.cleanup)
            AgentsTab().tabItem { Label("Agents", systemImage: "terminal") }.tag(SettingsTab.agents)
        }
        .padding(20)
        .frame(width: 560, height: 440)
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
