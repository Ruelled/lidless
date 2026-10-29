// Entry point. With a known command (`lidless start …`) the binary runs as a command line tool
// and exits. Without one it starts the menu bar app.

import SwiftUI
import AppKit

@main
enum Main {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if let first = args.first, CLI.commands.contains(first) {
            exit(CLI.run(args))
        }
        // One copy only: a second copy would add a second icon and fight over the state file.
        let me = ProcessInfo.processInfo.processIdentifier
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != me && $0.activationPolicy != .prohibited }) {
            exit(0)
        }
        LidlessApp.main()
    }
}

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.setUp()
        Control.shared.listen()
        Updates.shared.startAutoCheck()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Session.shared.stop("App quit")
        Session.shared.setCaffeinated(false)
        Control.shared.writeState(running: false)
    }
}
