// Text for the UI, the log and the command line.

import Foundation

func thermalName(_ v: Int) -> String { ["Normal", "Warm", "Hot", "Critical"][max(0, min(3, v))] }

/// 57.6 → "58 °C", nil → "—".
func degrees(_ v: Double?) -> String { v.map { "\(Int($0.rounded())) °C" } ?? "—" }

/// "chip 58 °C, battery 34 °C", or nil if the Mac has neither sensor.
func temperatures(_ r: Temperature.Reading) -> String? {
    let parts = [r.chip.map { "chip \(degrees($0))" }, r.battery.map { "battery \(degrees($0))" }].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
}

func durationName(_ minutes: Int) -> String {
    minutes < 60 ? "\(minutes) minutes" : (minutes == 60 ? "1 hour" : "\(minutes / 60) hours")
}

/// 3661 → "01:01:01". Negative values show as zero.
func clock(_ t: TimeInterval) -> String {
    let s = max(0, Int(t))
    return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
}

/// 5400 → "1h30m", 7200 → "2h", 1800 → "30m".
func shortDuration(_ t: TimeInterval) -> String {
    let m = Int(t) / 60
    return m % 60 == 0 ? "\(m / 60)h" : (m < 60 ? "\(m)m" : "\(m / 60)h\(m % 60)m")
}

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    return f
}()

/// The clock time in the user's format, for example "11:58 PM".
func shortTime(_ date: Date) -> String { timeFormatter.string(from: date) }

/// "stops after 2h, …" → "Stops after 2h, ….".
func sentence(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() + "." }

/// The Go Dark display summary in the panel: "3 displays sleep", or "Mac 6% · 2 off · 1 dim".
/// externals: for each external display, nil when it turns off, else its level (0 black, 1 unchanged).
func darkDisplaySummary(perDisplay: Bool, displays: Int, mac: Double, externals: [Double?]) -> String {
    guard perDisplay else { return "\(displays) display\(displays == 1 ? "" : "s") sleep" }
    let off = externals.filter { $0 == nil }.count
    let levels = externals.compactMap { $0 }
    let black = levels.filter { $0 <= 0.005 }.count
    let dim = levels.filter { $0 > 0.005 && $0 < 0.995 }.count
    return (["Mac \(Int((mac * 100).rounded()))%"]
            + [off > 0 ? "\(off) off" : nil, black > 0 ? "\(black) black" : nil, dim > 0 ? "\(dim) dim" : nil]
              .compactMap { $0 })
        .joined(separator: " · ")
}
