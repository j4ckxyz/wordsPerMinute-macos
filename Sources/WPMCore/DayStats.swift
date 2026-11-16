import Foundation

/// Aggregated counts for one local calendar day. Never contains typed text.
public struct DayStats: Codable, Sendable, Equatable, Identifiable {
    /// Local date, "yyyy-MM-dd".
    public var day: String
    public var characters = 0
    public var separators = 0
    public var words = 0
    public var keystrokes = 0
    public var backspaces = 0
    public var activeSeconds: TimeInterval = 0
    public var peakWPM: Double = 0
    public var sessions = 0

    public var id: String { day }

    public init(day: String) { self.day = day }

    public var typed: Int { characters + separators }

    /// Average WPM over active typing time only (pauses excluded).
    public var averageWPM: Double { standardWPM(typed: typed, seconds: activeSeconds) }

    /// Share of keystrokes that weren't backspaces, 0...1. 1 when nothing typed.
    public var accuracy: Double {
        keystrokes == 0 ? 1 : 1 - Double(backspaces) / Double(keystrokes)
    }

    public static func key(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

public enum Format {
    /// "1:05" or "1:02:05".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "1,234,567" (locale-independent grouping, matches the original app).
    public static func number(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }

    public static func percent(_ fraction: Double) -> String {
        String(format: "%.1f%%", fraction * 100)
    }
}
