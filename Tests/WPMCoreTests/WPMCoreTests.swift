import Foundation
import Testing
@testable import WPMCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

/// Types `text` as key kinds only (the engine never sees characters).
private func type(_ text: String, into e: inout WPMEngine, from start: Date, every dt: TimeInterval) -> Date {
    var t = start
    for ch in text {
        let kind: KeyKind = ch == " " || ch == "\n" ? .separator : (ch == "⌫" ? .backspace : .character)
        e.register(kind, at: t)
        t = t.addingTimeInterval(dt)
    }
    return t
}

@Suite("Key classification")
struct ClassifierTests {
    @Test func lettersDigitsPunctuationAreCharacters() {
        for code: UInt16 in [0, 1, 11, 18, 29, 41, 43, 47, 50, 10, 83] {
            #expect(KeyClassifier.classify(keyCode: code) == .character, "keyCode \(code)")
        }
    }

    @Test func separators() {
        for code: UInt16 in [49, 36, 76, 48] {
            #expect(KeyClassifier.classify(keyCode: code) == .separator)
        }
    }

    @Test func backspace() {
        #expect(KeyClassifier.classify(keyCode: 51) == .backspace)
    }

    @Test func navigationAndFunctionKeysIgnored() {
        for code: UInt16 in [123, 124, 125, 126, 122, 120, 53, 117, 56, 55, 57] {
            #expect(KeyClassifier.classify(keyCode: code) == nil, "keyCode \(code)")
        }
    }

    @Test func shortcutsIgnoredButOptionAndShiftCount() {
        #expect(KeyClassifier.classify(keyCode: 8, modifiers: .command) == nil)
        #expect(KeyClassifier.classify(keyCode: 0, modifiers: .control) == nil)
        #expect(KeyClassifier.classify(keyCode: 14, modifiers: .option) == .character)
        #expect(KeyClassifier.classify(keyCode: 0, modifiers: .shift) == .character)
    }

    @Test func autoRepeatIgnored() {
        #expect(KeyClassifier.classify(keyCode: 0, isAutoRepeat: true) == nil)
    }
}

@Suite("Word detection")
struct WordTests {
    @Test func countsWordsAtSeparators() {
        var e = WPMEngine(calendar: utc, now: t0)
        _ = type("hello world ", into: &e, from: t0, every: 0.1)
        #expect(e.session?.words == 2)
        #expect(e.session?.typed == 12)
        #expect(e.today.words == 2)
    }

    @Test func trailingWordWithoutSeparatorCountsInSession() {
        var e = WPMEngine(calendar: utc, now: t0)
        _ = type("one two", into: &e, from: t0, every: 0.1)
        #expect(e.session?.words == 2)
        // Today only counts completed words, so it never double counts.
        #expect(e.today.words == 1)
    }

    @Test func repeatedSeparatorsDoNotCreateEmptyWords() {
        var e = WPMEngine(calendar: utc, now: t0)
        _ = type("a   b\n\n", into: &e, from: t0, every: 0.1)
        #expect(e.session?.words == 2)
        #expect(e.today.separators == 5)
    }

    @Test func backspacesAreCountedButNotTyped() {
        var e = WPMEngine(calendar: utc, now: t0)
        _ = type("helo⌫⌫lo ", into: &e, from: t0, every: 0.1)
        #expect(e.session?.typed == 7)
        #expect(e.session?.backspaces == 2)
        #expect(e.today.keystrokes == 9)
        #expect(abs(e.today.accuracy - 7.0 / 9.0) < 1e-9)
    }
}

@Suite("Rolling window")
struct RollingWindowTests {
    @Test func steadySixtyWPM() {
        // 60 WPM = 300 chars/min = 5 chars/s = one key every 0.2 s.
        var e = WPMEngine(calendar: utc, now: t0)
        var t = t0
        for i in 0..<150 { // 30 s of typing
            e.register(i % 5 == 4 ? .separator : .character, at: t)
            t = t.addingTimeInterval(0.2)
            if i % 5 == 0 { e.tick(now: t) }
        }
        #expect(abs(e.liveWPM(now: t) - 60) < 2)
        #expect(abs(e.today.averageWPM - 60) < 1)
        #expect(e.today.peakWPM >= 58 && e.today.peakWPM <= 62)
    }

    @Test func earlyInSessionUsesElapsedTime() {
        var e = WPMEngine(calendar: utc, now: t0)
        let end = type("aaaaaaaaaaaaaaaaaaaa", into: &e, from: t0, every: 0.2) // 20 chars over 4 s
        // 20 chars / 5 / (4 s / 60) = 60 WPM, not diluted by the 10 s window.
        #expect(abs(e.liveWPM(now: end) - 60) < 1)
    }

    @Test func liveWPMDecaysAfterTypingStops() {
        var e = WPMEngine(calendar: utc, now: t0)
        let end = type(String(repeating: "abcd ", count: 20), into: &e, from: t0, every: 0.2)
        let before = e.liveWPM(now: end)
        #expect(before > 50)
        e.tick(now: end.addingTimeInterval(5))
        let mid = e.liveWPM(now: end.addingTimeInterval(5))
        #expect(mid < before && mid > 0)
        e.tick(now: end.addingTimeInterval(11))
        #expect(e.liveWPM(now: end.addingTimeInterval(11)) == 0)
        #expect(e.isIdle(now: end.addingTimeInterval(11)))
    }

    @Test func keysStampedSlightlyAfterNowStillCount() {
        var e = WPMEngine(calendar: utc, now: t0)
        let end = type(String(repeating: "abcd ", count: 20), into: &e, from: t0, every: 0.2)
        // Reading "now" a few ms before the last key's timestamp must not zero the WPM.
        #expect(e.liveWPM(now: end.addingTimeInterval(-0.25)) > 50)
    }

    @Test func peakIgnoresBurstsBeforeWindowFills() {
        var e = WPMEngine(calendar: utc, now: t0)
        let end = type("abcdefgh", into: &e, from: t0, every: 0.02) // absurd burst
        e.tick(now: end)
        #expect(e.today.peakWPM == 0)
    }

    @Test func samplesAreTakenAtInterval() {
        var e = WPMEngine(calendar: utc, now: t0)
        var t = t0
        for _ in 0..<60 { e.register(.character, at: t); e.tick(now: t); t = t.addingTimeInterval(0.5) }
        // 30 s with a 3 s interval ≈ 10 samples.
        #expect((9...11).contains(e.samples.count))
    }
}

@Suite("Idle handling")
struct IdleTests {
    @Test func activeTimeExcludesLongPauses() {
        var e = WPMEngine(calendar: utc, now: t0)
        e.register(.character, at: t0)
        e.register(.character, at: t0.addingTimeInterval(1))
        e.register(.character, at: t0.addingTimeInterval(30)) // 29 s pause > 5 s gap
        e.register(.character, at: t0.addingTimeInterval(31))
        #expect(abs(e.today.activeSeconds - 2) < 1e-9)
        #expect(e.session != nil) // still under the 60 s idle timeout
    }

    @Test func idleTimeoutEndsSessionOnTick() {
        var e = WPMEngine(calendar: utc, now: t0)
        let end = type(String(repeating: "word ", count: 10), into: &e, from: t0, every: 0.2)
        e.tick(now: end.addingTimeInterval(61))
        #expect(e.session == nil)
        #expect(e.today.sessions == 1)
        #expect(e.liveWPM(now: end.addingTimeInterval(61)) == 0)
        #expect(e.sessionDuration(now: end.addingTimeInterval(61)) == 0)
    }

    @Test func keyAfterIdleStartsNewSession() {
        var e = WPMEngine(calendar: utc, now: t0)
        let end = type(String(repeating: "word ", count: 10), into: &e, from: t0, every: 0.2)
        let later = end.addingTimeInterval(120)
        e.register(.character, at: later)
        #expect(e.session?.start == later)
        #expect(e.session?.characters == 1)
        #expect(e.today.sessions == 1)
    }

    @Test func shortSessionsDoNotCountAsSessions() {
        var e = WPMEngine(calendar: utc, now: t0)
        let end = type("hi ", into: &e, from: t0, every: 0.2)
        e.tick(now: end.addingTimeInterval(61))
        #expect(e.today.sessions == 0)
        #expect(e.today.words == 1) // ...but the words still count
    }
}

@Suite("Daily stats")
struct DailyStatsTests {
    @Test func rollsOverAtMidnight() {
        let lateNight = utc.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 23, minute: 59, second: 50))!
        var e = WPMEngine(calendar: utc, now: lateNight)
        let end = type(String(repeating: "abcd ", count: 6), into: &e, from: lateNight, every: 0.2)
        #expect(e.today.day == "2027-01-01")
        e.register(.character, at: end.addingTimeInterval(10)) // after midnight
        #expect(e.today.day == "2027-01-02")
        #expect(e.today.keystrokes == 1)
        #expect(e.history.count == 1)
        #expect(e.history[0].words == 6)
        #expect(e.history[0].sessions == 1)
        #expect(e.recentDays(7).map(\.day) == ["2027-01-01", "2027-01-02"])
    }

    @Test func resumesTodayFromSavedHistory() {
        var saved = DayStats(day: DayStats.key(for: t0, calendar: utc))
        saved.words = 42
        var old = DayStats(day: "2020-01-01")
        old.words = 7
        let e = WPMEngine(calendar: utc, now: t0, history: [saved, old])
        #expect(e.today.words == 42)
        #expect(e.history.map(\.day) == ["2020-01-01"])
    }

    @Test func resetTodayKeepsHistory() {
        var old = DayStats(day: "2020-01-01"); old.words = 7
        var e = WPMEngine(calendar: utc, now: t0, history: [old])
        _ = type("abc def ", into: &e, from: t0, every: 0.2)
        e.resetToday()
        #expect(e.today.keystrokes == 0)
        #expect(e.session == nil)
        #expect(e.history.count == 1)
        e.resetAll()
        #expect(e.history.isEmpty)
    }

    @Test func averageUsesActiveTimeOnly() {
        var d = DayStats(day: "x")
        d.characters = 250; d.separators = 50; d.activeSeconds = 60
        #expect(d.averageWPM == 60)
        #expect(DayStats(day: "x").averageWPM == 0)
        #expect(DayStats(day: "x").accuracy == 1)
    }

    @Test func storeRoundTrips() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = StatsStore(url: dir.appendingPathComponent("days.json"))
        var d = DayStats(day: "2027-01-01"); d.words = 3; d.peakWPM = 88.5
        try store.save([d])
        #expect(store.load() == [d])
        // Privacy: file contains only counts.
        let json = try String(contentsOf: store.url, encoding: .utf8)
        #expect(!json.contains("text"))
        try? FileManager.default.removeItem(at: dir)
    }
}

@Suite("Formatting")
struct FormatTests {
    @Test func formats() {
        #expect(Format.number(0) == "0")
        #expect(Format.number(1_234_567) == "1,234,567")
        #expect(Format.duration(65) == "1:05")
        #expect(Format.duration(3725) == "1:02:05")
        #expect(Format.percent(0.9876) == "98.8%")
        #expect(standardWPM(typed: 10, seconds: 1) == 0)
    }
}
