import Foundation

/// Tunables, with the same defaults as the original Windows app.
public struct WPMConfig: Sendable, Equatable {
    /// Window for the rolling "live" WPM.
    public var liveWindow: TimeInterval = 10
    /// A typing session ends after this long without a counted key.
    public var idleTimeout: TimeInterval = 60
    /// Gaps between keys longer than this don't count as active typing time.
    public var activeGap: TimeInterval = 5
    /// How often a point is added to the recent-WPM chart.
    public var sampleInterval: TimeInterval = 3
    /// How much chart history is kept.
    public var sampleHistory: TimeInterval = 5 * 60
    /// Sessions shorter than this many typed characters don't count as a session.
    public var minCharsForSession: Int = 25

    public init() {}
}

/// Standard WPM: one "word" is 5 typed characters (spaces included).
public func standardWPM(typed: Int, seconds: TimeInterval) -> Double {
    guard seconds >= 2 else { return 0 }
    return Double(typed) / 5 / (seconds / 60)
}

/// A point on the recent-WPM chart.
public struct WPMSample: Codable, Sendable, Equatable, Identifiable {
    public var date: Date
    public var wpm: Double
    public var id: Date { date }
    public init(date: Date, wpm: Double) { self.date = date; self.wpm = wpm }
}

/// One continuous stretch of typing, ended by `idleTimeout` of silence.
public struct LiveSession: Sendable, Equatable {
    public let start: Date
    public private(set) var lastKey: Date
    public private(set) var activeSeconds: TimeInterval = 0
    public private(set) var characters = 0
    public private(set) var separators = 0
    public private(set) var completedWords = 0
    public private(set) var keystrokes = 0
    public private(set) var backspaces = 0
    public internal(set) var peakWPM: Double = 0
    private var inWord = false
    /// Timestamps of recent typed (non-backspace) keys, for the rolling WPM.
    var recent: [Date] = []

    init(start: Date) { self.start = start; self.lastKey = start }

    public var typed: Int { characters + separators }
    public var words: Int { completedWords + (inWord ? 1 : 0) }
    public var averageWPM: Double { standardWPM(typed: typed, seconds: activeSeconds) }

    /// Registers a key. Returns the active-time delta and whether a word was completed.
    mutating func register(_ kind: KeyKind, at date: Date, activeGap: TimeInterval) -> (active: TimeInterval, wordCompleted: Bool) {
        var delta: TimeInterval = 0
        if keystrokes > 0 {
            let gap = max(0, date.timeIntervalSince(lastKey))
            if gap <= activeGap { delta = gap; activeSeconds += gap }
        }
        lastKey = max(lastKey, date)
        keystrokes += 1
        var completed = false
        switch kind {
        case .character:
            characters += 1
            inWord = true
            recent.append(date)
        case .separator:
            separators += 1
            if inWord { completedWords += 1; inWord = false; completed = true }
            recent.append(date)
        case .backspace:
            backspaces += 1
        }
        return (delta, completed)
    }

    /// Rolling WPM over the last `window` seconds. Early in a session the
    /// window isn't full yet, so the elapsed time is used instead.
    public func liveWPM(now: Date, window: TimeInterval) -> Double {
        let cutoff = now.addingTimeInterval(-window)
        // `recent` is chronological; count back from the newest key. Keys stamped a
        // hair after `now` (clock jitter between threads) still count.
        let n = recent.reversed().prefix { $0 >= cutoff }.count
        let span = max(2, min(window, now.timeIntervalSince(start)))
        return Double(n) / 5 / (span / 60)
    }

    mutating func prune(before cutoff: Date) {
        if let i = recent.firstIndex(where: { $0 >= cutoff }) {
            if i > 0 { recent.removeFirst(i) }
        } else {
            recent.removeAll()
        }
    }
}

/// The heart of the app: feed it key kinds and clock ticks, read stats back.
/// Deterministic and clock-injected so it is fully unit-testable.
public struct WPMEngine: Sendable {
    public var config: WPMConfig
    public var calendar: Calendar
    public private(set) var session: LiveSession?
    /// Stats for the current local day.
    public private(set) var today: DayStats
    /// Previous days, newest last.
    public private(set) var history: [DayStats]
    public private(set) var samples: [WPMSample] = []
    private var nextSample: Date?

    public init(config: WPMConfig = WPMConfig(),
                calendar: Calendar = .current,
                now: Date = Date(),
                history saved: [DayStats] = []) {
        self.config = config
        self.calendar = calendar
        let key = DayStats.key(for: now, calendar: calendar)
        var past = saved.sorted { $0.day < $1.day }
        if let last = past.last, last.day == key {
            today = past.removeLast()
        } else {
            today = DayStats(day: key)
        }
        history = past
    }

    // MARK: Input

    public mutating func register(_ kind: KeyKind, at date: Date) {
        rollDayIfNeeded(date)
        if let s = session, date.timeIntervalSince(s.lastKey) > config.idleTimeout {
            finishSession()
        }
        if session == nil {
            session = LiveSession(start: date)
            nextSample = date
        }
        let r = session!.register(kind, at: date, activeGap: config.activeGap)
        today.keystrokes += 1
        today.activeSeconds += r.active
        switch kind {
        case .character: today.characters += 1
        case .separator: today.separators += 1
        case .backspace: today.backspaces += 1
        }
        if r.wordCompleted { today.words += 1 }
    }

    /// Periodic update (≈ every second): idle timeout, peak tracking, chart sampling.
    public mutating func tick(now: Date) {
        rollDayIfNeeded(now)
        trimSamples(now: now)
        guard var s = session else { return }
        if now.timeIntervalSince(s.lastKey) > config.idleTimeout {
            finishSession()
            return
        }
        s.prune(before: now.addingTimeInterval(-config.liveWindow))
        let live = s.liveWPM(now: now, window: config.liveWindow)
        // Only trust peaks once the window is full; tiny bursts otherwise spike.
        if now.timeIntervalSince(s.start) >= config.liveWindow {
            s.peakWPM = max(s.peakWPM, live)
            today.peakWPM = max(today.peakWPM, live)
        }
        session = s
        if let next = nextSample, now >= next {
            samples.append(WPMSample(date: now, wpm: live))
            nextSample = now.addingTimeInterval(max(1, config.sampleInterval))
        }
    }

    // MARK: Output

    public func liveWPM(now: Date) -> Double {
        guard let s = session, now.timeIntervalSince(s.lastKey) <= config.idleTimeout else { return 0 }
        return s.liveWPM(now: now, window: config.liveWindow)
    }

    /// True when nothing has been typed within the live window.
    public func isIdle(now: Date) -> Bool {
        guard let s = session else { return true }
        return now.timeIntervalSince(s.lastKey) > config.liveWindow
    }

    /// Wall-clock length of the current session (0 when there is none).
    public func sessionDuration(now: Date) -> TimeInterval {
        guard let s = session, now.timeIntervalSince(s.lastKey) <= config.idleTimeout else { return 0 }
        return max(0, now.timeIntervalSince(s.start))
    }

    /// Up to `days` most recent days including today, oldest first.
    public func recentDays(_ days: Int) -> [DayStats] {
        Array((history + [today]).suffix(days))
    }

    /// Everything that should be persisted. Contains counts only.
    public var allDays: [DayStats] { history + [today] }

    // MARK: Maintenance

    public mutating func resetToday() {
        today = DayStats(day: today.day)
        session = nil
        samples = []
        nextSample = nil
    }

    public mutating func resetAll() {
        history = []
        resetToday()
    }

    /// Ends the current session now (e.g. on sleep or pause).
    public mutating func finishSession() {
        guard let s = session else { return }
        if s.typed >= config.minCharsForSession { today.sessions += 1 }
        session = nil
        nextSample = nil
        // Drop the chart to zero so it visibly shows the pause.
        if let last = samples.last, last.wpm > 0 {
            samples.append(WPMSample(date: s.lastKey.addingTimeInterval(config.liveWindow), wpm: 0))
        }
    }

    private mutating func trimSamples(now: Date) {
        let cutoff = now.addingTimeInterval(-config.sampleHistory)
        if let i = samples.firstIndex(where: { $0.date >= cutoff }) {
            if i > 0 { samples.removeFirst(i) }
        } else {
            samples.removeAll()
        }
    }

    private mutating func rollDayIfNeeded(_ date: Date) {
        let key = DayStats.key(for: date, calendar: calendar)
        guard key != today.day else { return }
        // A session spanning midnight is closed in the day it started.
        if session != nil { finishSession() }
        if today.keystrokes > 0 { history.append(today) }
        if history.count > 365 { history.removeFirst(history.count - 365) }
        today = DayStats(day: key)
    }
}
