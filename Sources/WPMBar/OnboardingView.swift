import AppKit
import SwiftUI

struct OnboardingView: View {
    let model: AppModel
    var close: () -> Void = {}
    @State private var asked = false

    private var granted: Bool { model.permissionGranted || model.monitorRunning }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("wpm")
                    .font(.hero(40))
                    .foregroundStyle(Palette.accent)
                Text("your typing speed, in the menu bar")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text("To count words per minute while you type in any app, WPM needs **Input Monitoring** permission. It doesn't need Accessibility.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                bullet("eye.slash", "Never sees what you type. Only “a key”, “a space” or “a delete” and when it happened.")
                bullet("internaldrive", "Stores daily counts on this Mac only. No text, no network.")
                bullet("lock", "Password fields are hidden from it by macOS.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tile(cornerRadius: 14)

            VStack(alignment: .leading, spacing: 8) {
                step(1, "Click **Open System Settings** below.")
                step(2, "In Privacy & Security → Input Monitoring, switch **WPM** on.")
                step(3, "Come back here. WPM starts counting right away.")
            }

            HStack(spacing: 10) {
                status
                Spacer()
                if granted {
                    Button("Done") { close() }
                        .quietButton(prominent: true)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Later") { close() }
                        .quietButton()
                    Button("Open System Settings") {
                        if !asked { InputPermission.request(); asked = true }
                        InputPermission.openSystemSettings()
                    }
                    .quietButton(prominent: true)
                    .keyboardShortcut(.defaultAction)
                }
            }
            if model.permissionGranted && !model.monitorRunning {
                HStack {
                    Text("Permission is on, but macOS wants WPM restarted.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Relaunch") { model.relaunch() }.quietButton().controlSize(.small)
                }
            }
        }
        .padding(28)
        .frame(width: 480)
    }

    @ViewBuilder private var status: some View {
        if granted {
            Label("All set. Start typing.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 12, weight: .medium))
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("waiting…")
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).frame(width: 16).foregroundStyle(Palette.accent)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text).font(.system(size: 12.5))
        }
    }
}

/// A plain AppKit window for onboarding: a MenuBarExtra app has no scene to open at launch.
@MainActor
final class OnboardingWindow {
    static let shared = OnboardingWindow()
    private(set) var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: OnboardingView(model: model) { [weak self] in
                self?.window?.close()
            })
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
