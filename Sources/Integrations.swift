// Things outside the app: open at login, the update check, the `lidless` command in ~/.local/bin,
// and agent skills.

import AppKit
import ServiceManagement

// MARK: - Open at login (also cleans up after a crash during a lid session, at the next login)

final class LoginItem: ObservableObject {
    static let shared = LoginItem()
    @Published private(set) var enabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var error: String?

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Updates (compare the built commit with the newest commit on GitHub)

final class Updates: ObservableObject {
    static let shared = Updates()
    static let repo = "Ruelled/lidless"

    @Published var status = "Not checked yet"
    @Published var available = false
    @Published var checking = false
    private var timer: Timer?

    var commit: String { Bundle.main.object(forInfoDictionaryKey: "LidlessCommit") as? String ?? "unknown" }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    var sourceDir: String { Bundle.main.object(forInfoDictionaryKey: "LidlessSource") as? String ?? "lidless" }
    var updateCommand: String { "cd \"\(sourceDir)\" && git pull && ./build.sh" }

    func startAutoCheck() {
        let t = Timer(timeInterval: 24 * 3600, repeats: true) { [weak self] _ in self?.autoCheck() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        autoCheck()
    }

    private func autoCheck() {
        if UserDefaults.standard.bool(forKey: Pref.autoUpdate) { check() }
    }

    func check() {
        guard commit.count == 40 else { status = "This build has no git commit, so it cannot compare."; return }
        checking = true
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/commits/main")!)
        req.setValue("application/vnd.github.sha", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let sha = data.map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                self.checking = false
                guard code == 200, sha.count == 40 else { self.status = "Check failed (HTTP \(code))."; return }
                self.available = sha != self.commit
                self.status = (self.available ? "A newer version is on GitHub." : "Up to date.")
                    + " Checked at \(shortTime(Date()))."
            }
        }.resume()
    }
}

// MARK: - The `lidless` command (a small shell wrapper around the app binary)

enum CommandInstall {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/lidless")

    static var script: String {
        "#!/bin/sh\n# Installed by Lidless. Runs the command line of the Lidless app.\n"
            + "exec \"\(Bundle.main.executablePath ?? "")\" \"$@\"\n"
    }

    static var installed: Bool { (try? String(contentsOf: url, encoding: .utf8)) == script }

    static func install() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    static func remove() { try? FileManager.default.removeItem(at: url) }
}

// MARK: - Agent skills (SKILL.md copied into each agent's skill folder)

struct SkillTarget: Identifiable {
    let id: String
    let name: String
    let folder: String      // relative to the home folder

    static let all = [
        SkillTarget(id: "claude", name: "Claude Code", folder: ".claude/skills/lidless"),
        SkillTarget(id: "codex", name: "Codex", folder: ".codex/skills/lidless"),
        SkillTarget(id: "agents", name: "Other agents (~/.agents)", folder: ".agents/skills/lidless"),
    ]

    var file: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(folder).appendingPathComponent("SKILL.md") }
}

enum Skills {
    static var bundled: URL? { Bundle.main.url(forResource: "SKILL", withExtension: "md") }
    static var text: String { bundled.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "" }

    enum Status { case missing, outdated, current }

    static func status(_ t: SkillTarget) -> Status {
        guard let installed = try? String(contentsOf: t.file, encoding: .utf8) else { return .missing }
        return installed == text ? .current : .outdated
    }

    static func install(_ t: SkillTarget) throws {
        try FileManager.default.createDirectory(at: t.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: t.file, atomically: true, encoding: .utf8)
    }

    static func remove(_ t: SkillTarget) {
        try? FileManager.default.removeItem(at: t.file.deletingLastPathComponent())
    }

    static var setupPrompt: String {
        "Lidless is installed on this Mac. Use the `lidless` command as this skill describes:\n\n" + text
    }
}
