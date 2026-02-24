import SwiftUI

/// SwiftUI view shown in the menubar popover.
/// Mode picker, timer display, session controls, and quick stats.
struct MenuBarPopover: View {
    @Bindable var appState: AppState
    let modeEngine: ModeEngine

    @State private var isSwitching = false
    @State private var showIntentionField = false
    @State private var intentionText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            if appState.timerIsRunning {
                timerDisplay
                Divider()
            }

            if showIntentionField {
                intentionPrompt
                Divider()
            }

            sessionControls
            Divider()
            modeList
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 280)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("Focus")
                .font(.headline)
            Spacer()
            if appState.sessionsCompletedToday > 0 {
                Text("\(appState.sessionsCompletedToday) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if appState.hasError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(appState.lastError?.localizedDescription ?? "")
            }
        }
    }

    private var timerDisplay: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(colorForMode(appState.currentMode))
                    .frame(width: 8, height: 8)
                Text(appState.currentMode.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                // Seconds-level display in popover
                Text(formatTime(appState.timerRemainingSeconds))
                    .font(.system(.title2, design: .monospaced).weight(.medium))
            }

            if let intention = appState.currentSessionIntention, !intention.isEmpty {
                Text(intention)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ProgressView(value: modeEngine.timerEngine.progress)
                .tint(colorForMode(appState.currentMode))

            Button("End Session") {
                modeEngine.endCurrentSession()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .font(.caption)
        }
    }

    private var intentionPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What are you working on?")
                .font(.subheadline.weight(.medium))

            TextField("e.g., Fix auth bug", text: $intentionText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    startSessionWithIntention()
                }

            HStack {
                Button("Skip") {
                    intentionText = ""
                    startSessionWithIntention()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Start") {
                    startSessionWithIntention()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var sessionControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !appState.timerIsRunning {
                Text("Start Session")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    showIntentionField = true
                } label: {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.red)
                        Text("Deep Work — \(TimerDurations.deepWorkMinutes) min")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)

                Button {
                    modeEngine.startShallowWork()
                } label: {
                    HStack {
                        Image(systemName: "tray.full.fill")
                            .foregroundStyle(.orange)
                        Text("Shallow Work — \(TimerDurations.deepWorkMinutes) min")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        }
    }

    private var modeList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Quick Switch")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(FocusMode.allCases, id: \.self) { mode in
                Button {
                    modeEngine.switchMode(to: mode)
                } label: {
                    HStack {
                        Circle()
                            .fill(colorForMode(mode))
                            .frame(width: 6, height: 6)
                        Text(mode.displayName)
                            .font(.caption)
                        Spacer()
                        if mode == appState.currentMode {
                            Image(systemName: "checkmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
                .disabled(isSwitching)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Dashboard") {
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.showDashboard()
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption2)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .font(.caption2)
        }
    }

    // MARK: - Helpers

    private func colorForMode(_ mode: FocusMode) -> Color {
        switch mode {
        case .deepWork: .red
        case .shallowWork: .orange
        case .personalTime: .green
        case .offline: .purple
        }
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startSessionWithIntention() {
        let intention = intentionText.isEmpty ? nil : intentionText
        showIntentionField = false
        appState.currentSessionIntention = intention

        // Call through ModeEngine's beginSession logic
        modeEngine.startDeepWork()
        intentionText = ""
    }
}
