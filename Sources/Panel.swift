// The menu bar panel: set up and start a session, or watch the running one.

import SwiftUI
import AppKit

/// Finds the NSWindow that hosts a SwiftUI view.
struct WindowReader: NSViewRepresentable {
    let found: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { found(v.window) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) { DispatchQueue.main.async { found(v.window) } }
}

/// The panel floats above normal windows, so close it before another window of this app opens.
enum MenuPanel {
    static weak var window: NSWindow?

    static func close() {
        guard let w = window, w.isVisible else { return }
        // Click our own menu bar icon, so that SwiftUI closes the panel and keeps its open/closed state right.
        statusButton()?.performClick(nil)
        if w.isVisible { w.orderOut(nil) }
    }

    private static func statusButton() -> NSButton? {
        for win in NSApp.windows where win.className.contains("StatusBarWindow") {
            if let b = firstButton(in: win.contentView) { return b }
        }
        return nil
    }

    private static func firstButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let b = view as? NSButton { return b }
        for sub in view.subviews { if let b = firstButton(in: sub) { return b } }
        return nil
    }
}

struct Panel: View {
    @ObservedObject var s: Session
    @ObservedObject private var cleanup = CleanupList.shared
    @ObservedObject private var updates = Updates.shared
    @AppStorage(Pref.useDuration) private var useDuration = true
    @AppStorage(Pref.minutes) private var minutes = 120
    @AppStorage(Pref.useBattery) private var useBattery = true
    @AppStorage(Pref.floor) private var floor = 20
    @AppStorage(Pref.useThermal) private var useThermal = true
    @AppStorage(Pref.thermalLimit) private var thermalLimit = 2
    @AppStorage(Pref.allowLid) private var lidClosed = false
    @AppStorage(Pref.keepDisplay) private var keepDisplay = false
    @AppStorage(Pref.sleepDisplay) private var sleepDisplay = false
    @AppStorage(Pref.stopOnWake) private var stopOnWake = false
    @AppStorage(Pref.minBrightness) private var minBrightness = false
    @AppStorage(Pref.reopenApps) private var reopenApps = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if s.active { running } else { setup }
        }
        .padding(16)
        .frame(width: 400)
        .background(WindowReader { MenuPanel.window = $0 })
    }

    private var header: some View {
        HStack {
            Image(systemName: "figure.walk")
            Text("Lidless").font(.title3.bold())
            Spacer()
            Toggle("Caffeinate", isOn: Binding(get: { s.caffeinated }, set: { s.setCaffeinated($0) }))
                .toggleStyle(.switch).controlSize(.small)
                .help("Runs caffeinate \(Session.savedCaffeinateArgs().joined(separator: " ")). "
                      + "Change it in Settings > Caffeinate.")
            Button { SettingsWindow.show() } label: {
                Image(systemName: updates.available ? "gearshape.arrow.triangle.2.circlepath" : "gearshape")
            }
            .buttonStyle(.borderless).help(updates.available ? "Settings (update available)" : "Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.borderless).help("Quit (ends the session)")
        }
    }

    private var batteryNow: String { s.battery.map { "\($0)%" + (s.onAC ? " ⚡︎" : "") } ?? "—" }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Duration")
                    Toggle("Stop after", isOn: $useDuration)
                    Picker("", selection: $minutes) {
                        ForEach(Pref.durations, id: \.self) { Text(durationName($0)).tag($0) }
                    }.labelsHidden().disabled(!useDuration)
                    Text("")
                }
                GridRow {
                    Text("Battery")
                    Toggle("Stop below", isOn: $useBattery)
                    Picker("", selection: $floor) {
                        ForEach(Pref.floors, id: \.self) { Text("\($0)%").tag($0) }
                    }.labelsHidden().disabled(!useBattery)
                    Text("Now: \(batteryNow)").foregroundStyle(.secondary)
                }
                GridRow {
                    HStack(spacing: 4) {
                        Text("Temperature")
                        Button { SettingsWindow.show(.safety) } label: { Image(systemName: "info.circle") }
                            .buttonStyle(.borderless).help("What the heat levels mean")
                    }
                    Toggle("Stop at", isOn: $useThermal)
                    Picker("", selection: $thermalLimit) {
                        ForEach(1...3, id: \.self) { Text(thermalName($0)).tag($0) }
                    }.labelsHidden().disabled(!useThermal)
                    Text("Now: \(thermalName(s.thermal))").foregroundStyle(.secondary)
                }
            }
            if !useThermal {
                Text("No heat limit. Not recommended.").font(.caption).foregroundStyle(.red)
            }
            Divider()
            Button { SettingsWindow.show(.cleanup) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App Cleanup")
                        Text(cleanup.ids.isEmpty ? "No apps selected"
                             : "\(cleanup.ids.count) app\(cleanup.ids.count == 1 ? "" : "s") selected"
                               + (reopenApps ? " · Reopen after session" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Keep display awake", isOn: $keepDisplay)
                    Toggle("Put display to sleep on start", isOn: $sleepDisplay).disabled(keepDisplay)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Set brightness to minimum", isOn: $minBrightness).disabled(!Brightness.available)
                        .help(Brightness.available ? "Built-in display only. Restored when the session stops."
                                                   : "No built-in display found.")
                    Toggle("Stop when display wakes", isOn: $stopOnWake)
                }
            }

            if let e = s.error { Text(e).font(.caption).foregroundStyle(.red) }
            if let l = s.lastStop { Text("Last session: \(l)").font(.caption).foregroundStyle(.secondary) }

            Button { s.start(Pref.config()) } label: {
                Text("Start Session").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
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
                if !s.appsToReopen.isEmpty {
                    GridRow {
                        Text("Apps to reopen").foregroundStyle(.secondary)
                        Text("\(s.appsToReopen.count)")
                        Text(s.appsToReopen.map { $0.deletingPathExtension().lastPathComponent }.joined(separator: ", "))
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if s.startedBy != "panel" {
                    GridRow {
                        Text("Started by").foregroundStyle(.secondary)
                        Text(s.startedBy)
                        Text("")
                    }
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
