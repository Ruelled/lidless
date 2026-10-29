// Text for the UI, the log and the command line.

import Foundation

func thermalName(_ v: Int) -> String { ["Normal", "Warm", "Hot", "Critical"][max(0, min(3, v))] }

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
