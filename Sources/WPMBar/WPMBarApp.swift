import AppKit
import SwiftUI

@main
struct WPMBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let args = ProcessInfo.processInfo.arguments
    lazy var model = AppModel(demo: args.contains("--demo"))

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement already hides the Dock icon in the bundle; this covers `swift run`.
        NSApp.setActivationPolicy(.accessory)

        if let i = args.firstIndex(of: "--render-snapshots"), i + 1 < args.count {
            SnapshotRenderer.renderAll(model: model, to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }

        model.start()
        if args.contains("--debug-hooks") { DebugHooks.install(model: model) }
        if !model.monitorRunning || args.contains("--onboarding") {
            OnboardingWindow.shared.show(model: model)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}

/// Opt-in (`--debug-hooks`) remote control used by scripts/screenshots.sh:
/// `DistributedNotificationCenter` messages named "local.wpmbar.debug".
/// (Opening the MenuBarExtra itself is left to a real click: on macOS 26+
/// status items are hosted out of process, so there's no button to poke.)
@MainActor
enum DebugHooks {
    static func install(model: AppModel) {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("local.wpmbar.debug"), object: nil, queue: .main
        ) { note in
            let action = note.object as? String ?? ""
            MainActor.assumeIsolated {
                switch action {
                case "settings": model.page = .settings
                case "stats": model.page = .stats
                case "onboarding": OnboardingWindow.shared.show(model: model)
                case "close-onboarding": OnboardingWindow.shared.window?.close()
                default: break
                }
            }
        }
    }
}

/// Renders each screen offscreen to PNG (light and dark) with `--render-snapshots DIR`.
/// Used when the session can't take real screenshots (e.g. the screen is locked).
/// Liquid Glass can't be drawn offscreen, so tiles use their macOS 15 look here.
@MainActor
enum SnapshotRenderer {
    static func renderAll(model: AppModel, to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // A model that reflects the real permission state, for onboarding.
        let fresh = AppModel(demo: false)
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            model.page = .stats
            write(StatsView(model: model).frame(width: 316), scheme, dir, "2-popover-\(suffix)")
            write(SettingsView(model: model).frame(width: 316), scheme, dir, "3-settings-\(suffix)")
            write(OnboardingView(model: fresh), scheme, dir, "4-onboarding-\(suffix)")
            write(StatsView(model: fresh).frame(width: 316), scheme, dir, "5-popover-no-permission-\(suffix)")
            write(MenuBarStrip(), scheme, dir, "1-menubar-\(suffix)", background: false)
        }
    }

    /// The label in each state, as it sits at the right end of a menu bar.
    private struct MenuBarStrip: View {
        @Environment(\.colorScheme) private var scheme
        var body: some View {
            VStack(spacing: 0) {
                row(.typing(wpm: 92), "typing")
                row(.idle, "idle")
                row(.needsPermission, "needs permission")
            }
        }

        private func row(_ state: MenuBarState, _ caption: String) -> some View {
            HStack(spacing: 14) {
                Text(caption).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                MenuBarStateLabel(state: state, style: .iconNumberUnit)
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .frame(width: 380, height: 30)
            .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.93))
        }
    }

    private static func write<V: View>(_ view: V, _ scheme: ColorScheme, _ dir: URL, _ name: String, background: Bool = true) {
        let content = view
            .background(background ? Color(nsColor: .windowBackgroundColor) : .clear)
            .environment(\.offscreenRender, true)
            .transaction { $0.disablesAnimations = true }
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        // An offscreen window gives AppKit-backed controls (switches, spinners) a real backing.
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.display()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
        window.contentView = nil
    }
}
