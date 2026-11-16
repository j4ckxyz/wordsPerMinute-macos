import AppKit
import Observation
import ServiceManagement
import WPMCore

enum MenuBarStyle: String, CaseIterable, Identifiable {
    // Raw values kept from 0.1.0 so saved preferences carry over.
    case iconNumberUnit = "numberAndUnit"
    case iconNumber = "numberOnly"
    case iconOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .iconNumberUnit: "Icon + 72 wpm"
        case .iconNumber: "Icon + 72"
        case .iconOnly: "Icon only"
        }
    }
}

enum PopoverPage { case stats, settings }

@MainActor
@Observable
final class AppModel {
    private(set) var engine: WPMEngine
    /// Bumped by the clock so time-based values (live WPM, session time) refresh.
    private(set) var now = Date()
    private(set) var permissionGranted = InputPermission.isGranted
    private(set) var monitorRunning = false
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var loginItemError: String?
    var page: PopoverPage = .stats
    var menuBarStyle: MenuBarStyle {
        didSet { UserDefaults.standard.set(menuBarStyle.rawValue, forKey: "menuBarStyle") }
    }

    let isDemo: Bool
    private let store: StatsStore
    private var monitor: KeyMonitor?
    private var clock: Timer?
    private var dirty = false
    private var lastSave = Date()

    init(demo: Bool = false) {
        isDemo = demo
        // Demo mode never touches real stats.
        store = demo
            ? StatsStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("wpmbar-demo.json"))
            : StatsStore(url: StatsStore.defaultURL)
        engine = WPMEngine(history: demo ? [] : store.load())
        menuBarStyle = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: "menuBarStyle") ?? "") ?? .iconNumberUnit
        if demo { seedDemo() }
    }

    // MARK: Lifecycle

    func start() {
        startMonitorIfPossible()
        clock = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        clock?.tolerance = 0.1
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.engine.finishSession(); self?.save() }
        }
    }

    func stop() {
        engine.finishSession()
        save()
        monitor?.stop()
    }

    private func tick() {
        if isDemo { simulateDemoTyping() }
        now = Date()
        engine.tick(now: now)
        if !permissionGranted || !monitorRunning {
            let granted = InputPermission.isGranted
            if granted != permissionGranted { permissionGranted = granted }
            if granted { startMonitorIfPossible() }
        }
        if dirty && now.timeIntervalSince(lastSave) > 30 { save() }
    }

    func startMonitorIfPossible() {
        if monitor == nil {
            monitor = KeyMonitor { [weak self] kind in
                MainActor.assumeIsolated { self?.record(kind) }
            }
        }
        monitorRunning = monitor?.start() ?? false
        if monitorRunning { permissionGranted = true }
    }

    func record(_ kind: KeyKind) {
        let t = Date()
        engine.register(kind, at: t)
        now = t
        dirty = true
    }

    private func save() {
        guard dirty, !isDemo else { return }
        try? store.save(engine.allDays)
        dirty = false
        lastSave = Date()
    }

    // MARK: Derived values

    var liveWPM: Int { Int(engine.liveWPM(now: now).rounded()) }

    var menuBarState: MenuBarState {
        if !permissionGranted && !monitorRunning { return .needsPermission }
        let wpm = liveWPM
        return isIdle || wpm == 0 ? .idle : .typing(wpm: wpm)
    }
    var isIdle: Bool { engine.isIdle(now: now) }
    var today: DayStats { engine.today }
    var sessionDuration: TimeInterval { engine.sessionDuration(now: now) }
    var samples: [WPMSample] { engine.samples }

    // MARK: Settings actions

    func setLaunchAtLogin(_ on: Bool) {
        loginItemError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginItemError = error.localizedDescription
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            loginItemError = "Approve WPM in System Settings → General → Login Items."
        }
    }

    func resetToday() { engine.resetToday(); dirty = true; save() }
    func resetAll() { engine.resetAll(); dirty = true; save() }

    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: Demo data (for screenshots / trying the UI without permission)

    private var demoLastKey = Date()
    private var demoPhase = 0.0

    /// In demo mode, keeps feeding the engine ~75–95 WPM of synthetic key kinds.
    private func simulateDemoTyping() {
        let t = Date()
        demoPhase += 0.02
        let wpm = 85 + 10 * sin(demoPhase)
        let step = 60 / (wpm * 5)
        var k = demoLastKey
        while k.addingTimeInterval(step) <= t {
            k = k.addingTimeInterval(step)
            engine.register(Int.random(in: 0..<6) == 0 ? .separator : .character, at: k)
        }
        demoLastKey = k
        permissionGranted = true
        monitorRunning = true
    }

    /// Simulates ~4 minutes of typing through the real engine, ending now.
    private func seedDemo() {
        var rng = SystemRandomNumberGenerator()
        let end = Date()
        var t = end.addingTimeInterval(-240)
        let plan: [(TimeInterval, Double)] = [(70, 68), (8, 0), (60, 84), (5, 0), (97, 92)] // (seconds, wpm)
        for (secs, wpm) in plan {
            let stop = t.addingTimeInterval(secs)
            if wpm == 0 { t = stop; engine.tick(now: t); continue }
            var i = 0
            var nextTick = t
            while t < stop && t < end {
                let kind: KeyKind = i % 6 == 5 ? .separator : (Int.random(in: 0..<30, using: &rng) == 0 ? .backspace : .character)
                engine.register(kind, at: t)
                i += 1
                let base = 60 / (wpm * 5)
                t = t.addingTimeInterval(base * Double.random(in: 0.6...1.4, using: &rng))
                if t >= nextTick { engine.tick(now: t); nextTick = t.addingTimeInterval(1) }
            }
        }
        now = Date()
        engine.tick(now: now)
        demoLastKey = now
        permissionGranted = true
        monitorRunning = true
    }
}
