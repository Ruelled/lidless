// The Caffeinate switch: runs the real /usr/bin/caffeinate with the user's flags. No battery or heat limits.
// `-w <pid>` ends caffeinate when Lidless exits, also after a crash.

import Foundation

final class Caffeinate: ObservableObject {
    static let shared = Caffeinate()

    @Published private(set) var on = false
    @Published private(set) var args: [String] = []
    @Published private(set) var error: String?
    private var process: Process?

    var command: String { "caffeinate " + args.joined(separator: " ") }

    /// Flags in canonical order, for example "usd" → "dsu". Nil if empty or with a letter outside d, i, m, s, u.
    static func normalize(_ flags: String) -> String? {
        let f = String("dimsu".filter { flags.contains($0) })
        return f.isEmpty || flags.contains(where: { !"dimsu".contains($0) }) ? nil : f
    }

    /// The saved choice from Settings > Caffeinate, for example ["-dimsu"] or ["-di", "-t", "7200"].
    static func savedArgs() -> [String] {
        args(flags: nil, seconds: nil)
    }

    /// Arguments with the saved choice as the default for each part. `seconds` 0 means no time limit.
    static func args(flags: String?, seconds: Int?) -> [String] {
        let d = UserDefaults.standard
        let f = flags ?? normalize(d.string(forKey: Pref.caffeinateFlags) ?? "") ?? "dimsu"
        let secs = seconds ?? d.integer(forKey: Pref.caffeinateMinutes) * 60
        return ["-\(f)"] + (secs > 0 ? ["-t", String(secs)] : [])
    }

    /// Switches caffeinate on (again, with new arguments) or off.
    func set(_ on: Bool, args a: [String]? = nil) {
        guard on || self.on else { return }
        process?.terminate()
        process = nil
        error = nil
        if on {
            let a = a ?? Self.savedArgs()
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            p.arguments = a + ["-w", String(ProcessInfo.processInfo.processIdentifier)]
            p.terminationHandler = { [weak self] proc in
                DispatchQueue.main.async { self?.ended(proc) }
            }
            do {
                try p.run()
                process = p
                args = a
            } catch {
                self.error = "caffeinate: \(error.localizedDescription)"
            }
        }
        self.on = process != nil
        Log.write(self.on ? "Caffeinate on: \(command)" : "Caffeinate off")
        Control.shared.writeState()
    }

    /// Applies a changed choice in Settings to a running caffeinate.
    func restartIfOn() {
        if on { set(true) }
    }

    /// Only a run that ends by itself, at its -t time limit, is still the current process here.
    private func ended(_ proc: Process) {
        guard process === proc else { return }
        process = nil
        on = false
        Log.write("Caffeinate ended: time limit reached")
        Notifier.post("Caffeinate ended", "Its time limit was reached.")
        Control.shared.writeState()
    }
}
