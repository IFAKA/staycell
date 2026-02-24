import SwiftUI

/// SwiftUI view shown in the menubar popover.
/// Mode picker, current status, and quick actions.
struct MenuBarPopover: View {
    @Bindable var appState: AppState
    let blockingEngine: BlockingEngine

    @State private var isSwitching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Focus")
                    .font(.headline)
                Spacer()
                if appState.hasError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .help(appState.lastError?.localizedDescription ?? "")
                }
            }

            Divider()

            // Current mode
            HStack {
                Circle()
                    .fill(colorForMode(appState.currentMode))
                    .frame(width: 10, height: 10)
                Text(appState.currentMode.displayName)
                    .font(.title3.weight(.medium))
                Spacer()
            }

            // Mode switcher
            VStack(alignment: .leading, spacing: 8) {
                Text("Switch Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(FocusMode.allCases, id: \.self) { mode in
                    Button {
                        switchMode(to: mode)
                    } label: {
                        HStack {
                            Circle()
                                .fill(colorForMode(mode))
                                .frame(width: 8, height: 8)
                            Text(mode.displayName)
                            Spacer()
                            if mode == appState.currentMode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        mode == appState.currentMode
                            ? Color.accentColor.opacity(0.1)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .disabled(isSwitching)
                }
            }

            Divider()

            // Blocked domains count
            let count = appState.currentMode.blockedDomains.count
            Text("\(count) domains blocked")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Quick actions
            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private func colorForMode(_ mode: FocusMode) -> Color {
        switch mode {
        case .deepWork: .red
        case .shallowWork: .orange
        case .personalTime: .green
        case .offline: .purple
        }
    }

    private func switchMode(to mode: FocusMode) {
        guard mode != appState.currentMode else { return }
        isSwitching = true
        appState.clearError()

        Task {
            do {
                try await blockingEngine.applyMode(mode)
                appState.currentMode = mode
            } catch let error as FocusError {
                appState.setError(error)
            } catch {
                appState.setError(.xpcConnectionFailed(underlying: error.localizedDescription))
            }
            isSwitching = false
        }
    }
}
