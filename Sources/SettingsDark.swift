// Settings: the Go Dark tab, its display rows, and the app list that Go Lidless and Go Dark share.

import SwiftUI
import AppKit

/// The list of apps with a checkbox each. App Cleanup and Go Dark each have one.
struct AppPicker: View {
    @ObservedObject var list: CleanupList
    @State private var apps = AppCleanup.candidates()

    var body: some View {
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
                let app = AppCleanup.installed(id)
                HStack {
                    Toggle("", isOn: Binding(get: { true }, set: { _ in list.toggle(id) })).labelsHidden()
                    if let icon = app?.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                    Text(app?.name ?? id).foregroundStyle(app == nil ? .secondary : .primary)
                    Spacer()
                    Text(app == nil ? "not installed" : "not running").foregroundStyle(.secondary)
                }.help(id)
            }
        }
        .toggleStyle(.checkbox)
        HStack {
            Text("\(list.ids.count) selected. Memory column: physical footprint now.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Deselect All") { list.ids = [] }.disabled(list.ids.isEmpty)
            Button("Refresh") { apps = AppCleanup.candidates() }
        }
    }
}

// MARK: - Go Dark

struct DarkTab: View {
    @ObservedObject private var screens = DisplayList.shared
    @AppStorage(Pref.darkReopenApps) private var reopen = true
    @AppStorage(Pref.darkUseDuration) private var useDuration = false
    @AppStorage(Pref.darkMinutes) private var minutes = 480
    @AppStorage(Pref.darkStopOnWake) private var stopOnWake = false
    @AppStorage(Pref.darkQuitApps) private var quitApps = true
    @AppStorage(Pref.darkPerDisplay) private var perDisplay = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Go Dark is for the night. It starts a session, quits the apps below and makes the displays "
                 + "dark.").bold().fixedSize(horizontal: false, vertical: true)
            Text("The battery limit, the heat limit and \"Allow the lid to close\" come from the panel.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $perDisplay) {
                        Text("All displays sleep").tag(false)
                        Text("A setting for each display").tag(true)
                    }.pickerStyle(.segmented).labelsHidden()
                    ForEach(screens.displays) { d in DisplayRow(d: d, perDisplay: perDisplay) }
                    if screens.displays.isEmpty { Text("No display found.").foregroundStyle(.secondary) }
                    if !perDisplay {
                        Text("With a dock or a USB hub, display sleep can lock the screen and reset the USB "
                             + "devices behind the dock. Then use \"A setting for each display\".")
                            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(perDisplay
                         ? "The Mac screen stays on at its brightness, so F2 makes it brighter at once. It can "
                           + "never go off. \"Turn off\" stops the signal to a monitor, the same as pulling its "
                           + "cable, and the monitor goes to standby. macOS moves its windows to the other displays. "
                           + "Black or dim keeps the backlight on. Every display comes back when Go Dark stops."
                         : "All displays sleep and all wake together when you press a key. macOS cannot put "
                           + "only one to sleep. Choose \"A setting for each display\" to keep the Mac screen on.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } label: { Text("Displays: \(screens.displays.count) connected now") }
            HStack {
                Toggle("Stop after", isOn: $useDuration)
                Picker("", selection: $minutes) {
                    ForEach(Pref.durations, id: \.self) { Text(durationName($0)).tag($0) }
                }.labelsHidden().fixedSize().disabled(!useDuration)
                Text(useDuration ? "" : "No time limit: the session runs until you stop it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Stop Go Dark when a display wakes", isOn: $stopOnWake).disabled(perDisplay)
                .help(perDisplay ? "Only for \"All displays sleep\"." : "")
            HStack(spacing: 16) {
                Toggle("Quit the apps below", isOn: $quitApps)
                Toggle("Reopen them when Go Dark stops", isOn: $reopen).disabled(!quitApps)
            }
            Text("Do not select the app that runs your agent, for example your terminal.")
                .font(.caption).foregroundStyle(.orange)
            AppPicker(list: CleanupList.dark).disabled(!quitApps).opacity(quitApps ? 1 : 0.5)
        }
        .toggleStyle(.checkbox)
        .onAppear { screens.refresh() }
    }
}

/// One display in the Go Dark tab. The Mac screen has a brightness slider with a floor; an external
/// display has a level from Black to Unchanged.
private struct DisplayRow: View {
    let d: DisplayInfo
    let perDisplay: Bool
    @AppStorage(Pref.darkMacBrightness) private var mac = Double(DarkScreens.macFloor)
    @State private var level = 0.0
    @State private var off = true

    var body: some View {
        HStack {
            Image(systemName: d.builtIn ? "laptopcomputer" : "display").frame(width: 20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(d.name).lineLimit(1).truncationMode(.middle)
                Text((d.builtIn ? "Mac screen · " : "") + d.pixels).font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit()
            }.frame(width: 200, alignment: .leading)
            if !perDisplay {
                Spacer()
                Text("Sleeps").foregroundStyle(.secondary)
            } else if d.builtIn {
                Slider(value: $mac, in: Double(DarkScreens.macFloor)...1)
                Text("Brightness \(Int((mac * 100).rounded()))%").monospacedDigit().frame(width: 120, alignment: .trailing)
            } else {
                Toggle("Turn off", isOn: Binding(get: { off }, set: { off = $0; Pref.setDarkTurnOff(d.uuid, $0) }))
                    .disabled(!DisplayPower.available)
                Slider(value: Binding(get: { level }, set: { level = $0; Pref.setDarkLevel(d.uuid, $0) }), in: 0...1)
                    .disabled(off)
                Text(off ? "Off" : level <= 0.005 ? "Black" : level >= 0.995 ? "Unchanged"
                     : "Dim \(Int((level * 100).rounded()))%")
                    .monospacedDigit().frame(width: 90, alignment: .trailing)
            }
        }
        .onAppear { level = Pref.darkLevel(d.uuid); off = Pref.darkTurnOff(d.uuid) && DisplayPower.available }
    }
}
