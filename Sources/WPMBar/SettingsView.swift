import SwiftUI
import WPMCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var confirmReset: ResetKind?

    enum ResetKind: Identifiable {
        case today, all
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    model.page = .stats
                } label: {
                    Image(systemName: "chevron.left")
                }
                .quietButton()
                .controlSize(.small)
                Text("settings")
                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                Spacer()
            }

            section("general") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                if let err = model.loginItemError {
                    Text(err).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text("Menu bar shows")
                    Spacer()
                    Picker("", selection: $model.menuBarStyle) {
                        ForEach(MenuBarStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                }
            }

            section("permission") {
                HStack(spacing: 6) {
                    Image(systemName: model.monitorRunning ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(model.monitorRunning ? Color.green : Palette.accent)
                    Text(model.monitorRunning ? "Input Monitoring allowed" : "Input Monitoring not allowed")
                    Spacer()
                    if !model.monitorRunning {
                        Button("Set up…") { OnboardingWindow.shared.show(model: model) }
                            .quietButton()
                            .controlSize(.small)
                    }
                }
            }

            section("data") {
                HStack(spacing: 8) {
                    Button("Reset today") { confirmReset = .today }
                    Button("Reset all") { confirmReset = .all }
                    Spacer()
                }
                .quietButton()
                .controlSize(.small)
                Text("Only counts are stored (keys, words, time). What you type is never read, logged or saved.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("wpm \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .font(.statLabel)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit WPM") { NSApp.terminate(nil) }
                    .quietButton()
                    .controlSize(.small)
                    .keyboardShortcut("q")
            }
        }
        .font(.system(size: 12))
        .padding(20)
        .confirmationDialog(confirmReset == .all ? "Reset all stats?" : "Reset today's stats?",
                            isPresented: Binding(get: { confirmReset != nil }, set: { if !$0 { confirmReset = nil } }),
                            presenting: confirmReset) { kind in
            Button("Reset", role: .destructive) {
                kind == .all ? model.resetAll() : model.resetToday()
            }
        } message: { kind in
            Text(kind == .all ? "This clears every saved day." : "Today's counts go back to zero.")
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.statLabel).foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tile()
        }
    }
}
