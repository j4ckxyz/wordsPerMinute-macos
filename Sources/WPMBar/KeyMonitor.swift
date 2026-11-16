import AppKit
import CoreGraphics
import WPMCore

/// Input Monitoring permission (needed for a listen-only event tap).
/// Accessibility is *not* required: we never modify or inject events.
enum InputPermission {
    static var isGranted: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt once and adds the app to the Input Monitoring list.
    @discardableResult
    static func request() -> Bool { CGRequestListenEventAccess() }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}

/// System-wide, listen-only keyboard tap.
///
/// Privacy: the callback reads only the virtual key code, modifier flags and
/// the auto-repeat flag, classifies them into a `KeyKind`, and drops the event.
/// No characters are ever decoded, so typed text cannot be reconstructed.
/// Secure text fields (passwords) are hidden from event taps by macOS anyway.
final class KeyMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let onKey: (KeyKind) -> Void

    init(onKey: @escaping (KeyKind) -> Void) { self.onKey = onKey }

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Returns false if the tap couldn't be created (usually: no permission yet).
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables slow taps; just turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            // Don't count typing inside this app (e.g. in Settings).
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                return
            }
            let flags = event.flags
            var mods: KeyModifiers = []
            if flags.contains(.maskCommand) { mods.insert(.command) }
            if flags.contains(.maskControl) { mods.insert(.control) }
            if flags.contains(.maskAlternate) { mods.insert(.option) }
            if flags.contains(.maskShift) { mods.insert(.shift) }
            let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let repeating = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if let kind = KeyClassifier.classify(keyCode: code, modifiers: mods, isAutoRepeat: repeating) {
                onKey(kind)
            }
        default:
            break
        }
    }
}
