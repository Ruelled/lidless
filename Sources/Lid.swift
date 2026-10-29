// Lid sleep: `pmset -a disablesleep 1` keeps a Mac awake with the lid closed, also on battery.
// It needs root, so Lidless uses a sudoers rule for exactly that command and `disablesleep 0`.

import AppKit

enum Lid {
    static let pmset = "/usr/bin/pmset"
    static let sudoersFile = "/etc/sudoers.d/lidless"
    private static let ownedKey = "lidSleepDisabledByLidless"

    static var rule: String {
        "\(NSUserName()) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 0, \(pmset) -a disablesleep 1"
    }

    /// True while Lidless set SleepDisabled = 1 and must set it back. Saved, so that the next launch
    /// can undo it after a crash or a failed restore.
    static var ownsSleepDisabled: Bool {
        get { UserDefaults.standard.bool(forKey: ownedKey) }
        set { UserDefaults.standard.set(newValue, forKey: ownedKey) }
    }

    @discardableResult
    static func setDisableSleep(_ on: Bool) -> Bool {
        Shell.run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", on ? "1" : "0"]).status == 0
    }

    static func canDisableSleep() -> Bool {
        Shell.run("/usr/bin/sudo", ["-n", "-l", pmset, "-a", "disablesleep", "1"]).status == 0
    }

    static func sleepDisabled() -> Bool {
        Shell.run(pmset, ["-g"]).output.split(separator: "\n").contains {
            $0.contains("SleepDisabled") && $0.trimmingCharacters(in: .whitespaces).hasSuffix("1")
        }
    }

    /// A shell that waits for this process to exit and then restores lid sleep. Covers a crash or a force quit.
    static func startWatchdog() -> Process? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 5; done; "
                       + "/usr/bin/sudo -n \(pmset) -a disablesleep 0"]
        return (try? p.run()) == nil ? nil : p
    }

    /// Installs the sudoers rule after macOS asks for an admin password. Returns whether it works.
    static func grant() -> Bool {
        let shell = "t=$(mktemp) && echo '\(rule)' > $t && /usr/sbin/visudo -cf $t && "
            + "/usr/bin/install -m 0440 -o root -g wheel $t \(sudoersFile); rc=$?; rm -f $t; exit $rc"
        admin(shell)
        return canDisableSleep()
    }

    static func revoke() {
        admin("rm -f \(sudoersFile)")
    }

    private static func admin(_ shell: String) {
        var err: NSDictionary?
        NSAppleScript(source: "do shell script \"\(shell)\" with administrator privileges")?.executeAndReturnError(&err)
    }
}
