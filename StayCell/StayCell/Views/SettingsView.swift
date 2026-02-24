import SwiftUI
import ServiceManagement
import GRDB

/// Settings view for the StayCell app.
struct SettingsView: View {
    @Bindable var appState: AppState
    let dbPool: DatabasePool?

    @State private var showExportSuccess = false
    @State private var showUninstallConfirm = false
    @State private var isUninstalling = false
    @State private var uninstallStep = ""
    @State private var showErrorLogCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.title2.weight(.semibold))

                scheduleSettings
                Divider()
                keyboardShortcuts
                Divider()
                dataSection
                Divider()
                errorLogSection
                Divider()
                dangerZone
            }
            .padding(20)
        }
    }

    // MARK: - Schedule

    private var scheduleSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule")
                .font(.headline)

            HStack {
                Text("Workday start hour")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $appState.workdayStartHour) {
                    ForEach(5..<13, id: \.self) { hour in
                        Text("\(hour):00").tag(hour)
                    }
                }
                .frame(width: 80)
            }

            HStack {
                Text("Workday end hour")
                    .font(.subheadline)
                Spacer()
                Stepper("\(appState.workdayEndHour):00", value: $appState.workdayEndHour, in: 13...22)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Work days")
                    .font(.subheadline)
                HStack(spacing: 8) {
                    ForEach(dayNames, id: \.weekday) { day in
                        Toggle(day.name, isOn: Binding(
                            get: { appState.workDays.contains(day.weekday) },
                            set: { isOn in
                                if isOn {
                                    appState.workDays.insert(day.weekday)
                                } else {
                                    appState.workDays.remove(day.weekday)
                                }
                            }
                        ))
                        .toggleStyle(.button)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Keyboard Shortcuts

    private var keyboardShortcuts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keyboard Shortcuts")
                .font(.headline)

            Group {
                shortcutRow("Deep Work", keys: "^⌥⌘D")
                shortcutRow("Shallow Work", keys: "^⌥⌘S")
                shortcutRow("Personal", keys: "^⌥⌘P")
                shortcutRow("Offline", keys: "^⌥⌘O")
            }
        }
    }

    private func shortcutRow(_ label: String, keys: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(keys)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data")
                .font(.headline)

            HStack {
                Button("Export All Data (JSON)") {
                    exportData()
                }
                .controlSize(.small)

                if showExportSuccess {
                    Text("Exported!")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Text("Exports sessions, overrides, and FIRE data to a JSON file.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Error Log

    private var errorLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Error Log")
                .font(.headline)

            if appState.errorLog.isEmpty {
                Text("No errors recorded this session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Button("Copy for AI (\(appState.errorLog.count))") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(appState.errorLogForAI, forType: .string)
                        showErrorLogCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showErrorLogCopied = false
                        }
                    }
                    .controlSize(.small)

                    if showErrorLogCopied {
                        Text("Copied!")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    Button("Clear") {
                        appState.clearErrorLog()
                    }
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                }

                // Last error preview
                if let last = appState.errorLog.last {
                    Text(last.message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }

            Text("Captures errors during this session. Paste copied text into your AI agent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Danger Zone

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Danger Zone")
                .font(.headline)
                .foregroundStyle(.red)

            if isUninstalling {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(uninstallStep)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Uninstall StayCell Completely") {
                    showUninstallConfirm = true
                }
                .controlSize(.small)
                .foregroundStyle(.red)

                Text("Removes daemon, restores /etc/hosts, deletes all data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Uninstall StayCell?", isPresented: $showUninstallConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                performUninstall()
            }
        } message: {
            Text("This will remove the StayCell helper daemon, restore your /etc/hosts file, delete all app data, and remove StayCell from login items. This cannot be undone.")
        }
    }

    // MARK: - Helpers

    private struct DayInfo {
        let weekday: Int
        let name: String
    }

    private var dayNames: [DayInfo] {
        [
            DayInfo(weekday: 1, name: "Sun"),
            DayInfo(weekday: 2, name: "Mon"),
            DayInfo(weekday: 3, name: "Tue"),
            DayInfo(weekday: 4, name: "Wed"),
            DayInfo(weekday: 5, name: "Thu"),
            DayInfo(weekday: 6, name: "Fri"),
            DayInfo(weekday: 7, name: "Sat"),
        ]
    }

    private func exportData() {
        guard let dbPool else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "staycell-export-\(ISO8601DateFormatter.dateOnly.string(from: Date())).json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try DataExportService.exportJSON(from: dbPool, to: url)
            showExportSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                showExportSuccess = false
            }
        } catch {
            // Could show error alert
        }
    }

    private func performUninstall() {
        isUninstalling = true
        Task { @MainActor in
            // 1. Restore /etc/hosts + remove daemon files
            uninstallStep = "Restoring /etc/hosts and removing daemon…"
            let xpcClient = XPCClient()
            _ = try? await xpcClient.uninstall()

            // 2. Remove login item
            uninstallStep = "Removing login item…"
            try? await SMAppService.mainApp.unregister()

            // 3. Delete app data
            uninstallStep = "Deleting app data…"
            let appSupport = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!
            let focusDir = (appSupport as NSString).appendingPathComponent("StayCell")
            try? FileManager.default.removeItem(atPath: focusDir)

            // 4. Delete logs
            let logDir = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first!
            let focusLogs = (logDir as NSString).appendingPathComponent("Logs/StayCell")
            try? FileManager.default.removeItem(atPath: focusLogs)

            // 5. Delete preferences
            uninstallStep = "Clearing preferences…"
            UserDefaults.standard.removePersistentDomain(forName: AppConstants.bundleIdentifier)

            // 6. Quit
            uninstallStep = "Done. Quitting…"
            try? await Task.sleep(for: .milliseconds(600))
            NSApplication.shared.terminate(nil)
        }
    }
}
