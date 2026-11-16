import Charts
import SwiftUI
import WPMCore

struct PopoverView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.page {
            case .stats: StatsView(model: model)
            case .settings: SettingsView(model: model)
            }
        }
        .frame(width: 316)
        .animation(.smooth(duration: 0.2), value: model.page)
    }
}

// MARK: - Stats

struct StatsView: View {
    let model: AppModel
    @Environment(\.offscreenRender) private var offscreen

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.permissionGranted && !model.monitorRunning {
                PermissionCard(model: model)
            }
            hero
            RecentChart(samples: model.samples, now: model.now)
            grid
            footer
        }
        .padding(20)
    }

    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(model.liveWPM)")
                .font(.hero(60))
                .foregroundStyle(model.isIdle ? AnyShapeStyle(.secondary) : AnyShapeStyle(Palette.accent))
                .contentTransition(offscreen ? .identity : .numericText(value: Double(model.liveWPM)))
                .animation(.snappy, value: model.liveWPM)
            Text("wpm")
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(model.isIdle ? Color.secondary.opacity(0.5) : Palette.accent)
                    .frame(width: 6, height: 6)
                Text(model.isIdle ? "idle" : "typing")
                    .font(.statLabel)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var grid: some View {
        let d = model.today
        return VStack(alignment: .leading, spacing: 8) {
            Text("today")
                .font(.statLabel)
                .foregroundStyle(.tertiary)
            GlassGroup {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        StatTile(label: "avg", value: "\(Int(d.averageWPM.rounded()))")
                        StatTile(label: "peak", value: "\(Int(d.peakWPM.rounded()))")
                        StatTile(label: "acc", value: d.keystrokes == 0 ? "–" : Format.percent(d.accuracy))
                    }
                    GridRow {
                        StatTile(label: "words", value: Format.number(d.words))
                        StatTile(label: "keys", value: Format.number(d.keystrokes))
                        StatTile(label: "session", value: Format.duration(model.sessionDuration))
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("typing time \(Format.duration(model.today.activeSeconds))")
                .font(.statLabel)
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                model.page = .settings
            } label: {
                Image(systemName: "gearshape")
            }
            .quietButton()
            .help("Settings")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .quietButton()
            .help("Quit WPM")
        }
        .controlSize(.small)
    }
}

struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.statLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.statValue)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .tile()
    }
}

struct RecentChart: View {
    let samples: [WPMSample]
    let now: Date

    var body: some View {
        let window: TimeInterval = 5 * 60
        let start = now.addingTimeInterval(-window)
        let points = samples.filter { $0.date >= start }
        let top = max(60, (points.map(\.wpm).max() ?? 0) * 1.15)
        ZStack(alignment: .topLeading) {
            if points.count < 2 {
                Text("start typing anywhere…")
                    .font(.statLabel)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(points) { p in
                    AreaMark(x: .value("time", p.date), y: .value("wpm", p.wpm))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Palette.accent.opacity(0.28), Palette.accent.opacity(0.0)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("time", p.date), y: .value("wpm", p.wpm))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .foregroundStyle(Palette.accent)
                }
                .chartXScale(domain: start...now)
                .chartYScale(domain: 0...top)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            }
            Text("last 5 min")
                .font(.statLabel)
                .foregroundStyle(.tertiary)
        }
        .frame(height: 64)
        .accessibilityLabel("Recent words per minute chart")
    }
}

struct PermissionCard: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Input Monitoring needed", systemImage: "hand.raised")
                .font(.system(size: 12, weight: .semibold))
            Text("Allow WPM to see key presses so it can count your speed. It never sees or stores what you type.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Set up…") { OnboardingWindow.shared.show(model: model) }
                .quietButton(prominent: true)
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
    }
}
