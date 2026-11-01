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

/// A solid button with white text. The system tint is too pale on macOS 27 for white text.
struct BigButton: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold)).foregroundStyle(.white)
            .padding(.vertical, 9).frame(maxWidth: .infinity)
            .background(Capsule().fill(color.opacity(configuration.isPressed ? 0.75 : 1)))
            .contentShape(Capsule())
            .opacity(enabled ? 1 : 0.5)
    }
}

struct Panel: View {
    @ObservedObject var s: Session
    @ObservedObject private var caffeinate = Caffeinate.shared
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
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)   // the window takes the full height, bottom padding included
        .background(WindowReader { MenuPanel.window = $0 })
    }

    private var header: some View {
        HStack {
            Image(systemName: "figure.walk")
            Text("Lidless").font(.title3.bold())
            Spacer()
            Toggle("Caffeinate", isOn: Binding(get: { caffeinate.on }, set: { caffeinate.set($0) }))
                .toggleStyle(.switch).controlSize(.small)
                .help("Runs caffeinate \(Caffeinate.savedArgs().joined(separator: " ")). "
                      + "Change it in Settings > Caffeinate.")
            Button { SettingsWindow.show() } label: {
                Image(systemName: updates.available ? "gearshape.arrow.triangle.2.circlepath" : "gearshape")
            }
            .accessibilityLabel(updates.available ? "Settings, update available" : "Settings")
            .buttonStyle(.borderless).help(updates.available ? "Settings (update available)" : "Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .accessibilityLabel("Quit Lidless")
                .buttonStyle(.borderless).help("Quit (ends the session)")
        }
    }

    /// Warm or worse, or a battery at 40 °C or more: not the moment to close the Mac in a bag.
    private var tooWarmForBag: Bool { s.thermal >= 1 || (s.temps.battery ?? 0) >= 40 }

    /// "Chip 58 °C · Battery 34 °C", orange with a hint when the Mac is warm.
    @ViewBuilder private var temperatureLine: some View {
        if let t = temperatures(s.temps) {
            Text((t.prefix(1).uppercased() + t.dropFirst()).replacingOccurrences(of: ", ", with: " · ")
                 + (tooWarmForBag ? ". Too warm for a closed bag. Let it cool first." : ""))
                .font(.caption).foregroundStyle(tooWarmForBag ? Color.orange : .secondary)
                .help("Measured by the Mac's own sensors. The heat limit uses the level that macOS reports.")
        }
    }

    private var batteryNow: String { s.battery.map { "\($0)%" + (s.onAC ? " ⚡︎" : "") } ?? "—" }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Duration").fixedSize()
                    Toggle("Stop after", isOn: $useDuration).fixedSize()
                    Picker("", selection: $minutes) {
                        ForEach(Pref.durations, id: \.self) { Text(durationName($0)).tag($0) }
                    }.labelsHidden().disabled(!useDuration)
                    Text("")
                }
                GridRow {
                    Text("Battery").fixedSize()
                    Toggle("Stop below", isOn: $useBattery).fixedSize()
                    Picker("", selection: $floor) {
                        ForEach(Pref.floors, id: \.self) { Text("\($0)%").tag($0) }
                    }.labelsHidden().disabled(!useBattery)
                    Text("Now: \(batteryNow)").foregroundStyle(.secondary)
                }
                GridRow {
                    HStack(spacing: 4) {
                        Text("Temperature").fixedSize()
                        Button { SettingsWindow.show(.safety) } label: { Image(systemName: "info.circle") }
                            .accessibilityLabel("What the heat levels mean")
                            .buttonStyle(.borderless).help("What the heat levels mean")
                    }
                    Toggle("Stop at", isOn: $useThermal).fixedSize()
                    Picker("", selection: $thermalLimit) {
                        ForEach(1...3, id: \.self) { Text(thermalName($0)).tag($0) }
                    }.labelsHidden().disabled(!useThermal)
                    Text("Now: \(thermalName(s.thermal))").foregroundStyle(.secondary)
                }
            }
            temperatureLine
            if !useThermal {
                Text("No heat limit. Not recommended.").font(.caption).foregroundStyle(.red)
            }
            Divider()
            Button { SettingsWindow.show(.cleanup) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App Cleanup")
                        Text(cleanup.ids.isEmpty ? "No apps selected"
                             : "\(cleanup.ids.count) app\(cleanup.ids.count == 1 ? "" : "s") quit at session start"
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
                    Toggle("Put display to sleep on start", isOn: $sleepDisplay).disabled(keepDisplay).fixedSize()
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Set brightness to minimum", isOn: $minBrightness).disabled(!Brightness.available).fixedSize()
                        .help(Brightness.available ? "Built-in display only. Restored when the session stops."
                                                   : "No built-in display found.")
                    Toggle("Stop when display wakes", isOn: $stopOnWake)
                }
            }

            if let e = s.error ?? caffeinate.error { Text(e).font(.caption).foregroundStyle(.red) }
            if let l = s.lastStop { Text("Last session: \(l)").font(.caption).foregroundStyle(.secondary) }

            HStack(spacing: 10) {
                Button { s.start(Pref.config()) } label: {
                    Label("Go Lidless", systemImage: "figure.walk").frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButton(color: Color(red: 0.11, green: 0.42, blue: 0.93)))
                .help("Start a session with the settings above.")
                Button { goDark() } label: {
                    Label("Go Dark", systemImage: "moon.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButton(color: Color(red: 0.13, green: 0.58, blue: 0.27)))
                .help("Start a session with the settings above, then put every display to sleep. "
                      + "External monitors go to standby. Moving the mouse wakes them; the session continues.")
            }
            .padding(.bottom, 4)
        }
        .toggleStyle(.checkbox)
    }

    /// Start the night session, close the panel, and let the displays sleep.
    private func goDark() {
        let c = Pref.config().dark(brightnessAvailable: Brightness.available)
        if s.start(c, by: "panel") == nil { MenuPanel.close() }
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
                if s.holders != ["panel"] {
                    GridRow {
                        Text(s.holders.count > 1 ? "Held by" : "Started by").foregroundStyle(.secondary)
                        Text(s.holderList).lineLimit(1)
                        Text("")
                    }
                }
            }
            temperatureLine
            Text(c?.lidClosed == true ? "Lidless is running. You can close the lid."
                                      : "Lidless is running. Keep the lid open.")
                .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Button { s.stop("Stopped by you") } label: {
                Text("Stop Session").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
            .padding(.bottom, 4)
        }
    }
}
