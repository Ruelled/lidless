// Displays: the list of connected displays, and the two ways that Go Dark makes one dark:
// its color table (black or dim) and a software disconnect (off).

import AppKit

enum Brightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getFn: GetFn? = symbol("DisplayServicesGetBrightness")
    private static let setFn: SetFn? = symbol("DisplayServicesSetBrightness")

    private static func symbol<T>(_ name: String) -> T? {
        guard let h = handle, let s = dlsym(h, name) else { return nil }
        return unsafeBitCast(s, to: T.self)
    }

    private static var builtIn: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var available: Bool { getFn != nil && setFn != nil && builtIn != nil }

    static func get() -> Float? {
        guard let f = getFn, let d = builtIn else { return nil }
        var v: Float = 0
        return f(d, &v) == 0 ? v : nil
    }

    @discardableResult
    static func set(_ v: Float) -> Bool {
        guard let f = setFn, let d = builtIn else { return false }
        return f(d, v) == 0
    }
}

/// The displays that are on now. Go Dark puts all of them to sleep.
struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let builtIn: Bool
    let pixels: String   // "3024 × 1964"
    let uuid: String     // stays the same when the display reconnects
}

/// Dims or blacks out a display through its color table. Works on every display, also without DDC.
/// macOS resets the table when Lidless quits or crashes, so a display cannot stay black.
enum Gamma {
    static func set(_ id: CGDirectDisplayID, _ level: Double) {
        let v = CGGammaValue(max(0, min(1, level)))
        CGSetDisplayTransferByFormula(id, 0, v, 1, 0, v, 1, 0, v, 1)
    }

    static func restoreAll() { CGDisplayRestoreColorSyncSettings() }
}

/// Turns an external display off the same way as pulling its cable: macOS stops the signal and the
/// monitor goes to standby. Works without DDC.
/// A test on 2026-11-01 showed that macOS does NOT connect the display again when the app crashes,
/// also with the "app only" option. So Lidless saves what it turned off, runs a watchdog that turns it
/// on again when Lidless dies, and turns it on again at the next launch. A logout also connects it.
enum DisplayPower {
    private typealias EnableFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    private static let enableFn: EnableFn? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let sym = dlsym(h, "CGSConfigureDisplayEnabled") else { return nil }
        return unsafeBitCast(sym, to: EnableFn.self)
    }()
    private static let ownedKey = "displaysTurnedOffByLidless"

    static var available: Bool { enableFn != nil }

    /// The displays that Lidless turned off and must turn on again. Saved for the next launch.
    static var owned: [CGDirectDisplayID] {
        get { (UserDefaults.standard.array(forKey: ownedKey) as? [Int] ?? []).map { CGDirectDisplayID($0) } }
        set { UserDefaults.standard.set(newValue.map { Int($0) }, forKey: ownedKey) }
    }

    /// Returns true when macOS accepted the change. Never turns off the Mac screen.
    @discardableResult
    static func set(_ id: CGDirectDisplayID, on: Bool) -> Bool {
        guard let fn = enableFn, CGDisplayIsBuiltin(id) == 0 else { return false }
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
        guard fn(cfg, id, on) == .success else { CGCancelDisplayConfiguration(cfg); return false }
        return CGCompleteDisplayConfiguration(cfg, .forSession) == .success
    }

    /// Turns on every display that Lidless turned off. Returns how many it turned on.
    @discardableResult
    static func restoreOwned() -> Int {
        let ids = owned
        let back = ids.filter { set($0, on: true) }
        owned = ids.filter { !back.contains($0) }
        return back.count
    }

    /// A shell that waits for this process to exit and then turns the displays on again. Covers a crash
    /// or a force quit. It runs this same binary with the hidden `displays-on` command.
    static func startWatchdog(_ ids: [CGDirectDisplayID]) -> Process? {
        guard let exe = Bundle.main.executablePath, !ids.isEmpty else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 2; done; "
                       + "'\(exe)' displays-on " + ids.map(String.init).joined(separator: " ")]
        return (try? p.run()) == nil ? nil : p
    }
}

final class DisplayList: ObservableObject {
    static let shared = DisplayList()
    @Published private(set) var displays: [DisplayInfo] = []
    private var observer: NSObjectProtocol?

    private init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        displays = NSScreen.screens.compactMap { screen in
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            let id = CGDirectDisplayID(n.uint32Value)
            let mode = CGDisplayCopyDisplayMode(id)
            let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
            return DisplayInfo(id: id, name: screen.localizedName, builtIn: CGDisplayIsBuiltin(id) != 0,
                               pixels: mode.map { "\($0.pixelWidth) × \($0.pixelHeight)" } ?? "",
                               uuid: uuid.flatMap { CFUUIDCreateString(nil, $0) as String? } ?? "id-\(id)")
        }
        .sorted { ($0.builtIn ? 0 : 1, $0.name) < ($1.builtIn ? 0 : 1, $1.name) }
    }
}
