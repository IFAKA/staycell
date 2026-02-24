import SwiftUI
import ServiceManagement
import GRDB

/// Settings view for the Focus app.
struct SettingsView: View {
    @Bindable var appState: AppState
    let dbPool: DatabasePool?

    @State private var showExportSuccess = false
    @State private var showUninstallConfirm = false

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

    // MARK: - Danger Zone

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Danger Zone")
                .font(.headline)
                .foregroundStyle(.red)

            Button("Uninstall Focus Completely") {
                showUninstallConfirm = true
            }
            .controlSize(.small)
            .foregroundStyle(.red)

            Text("Removes daemon, restores /etc/hosts, deletes all data.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .alert("Uninstall Focus?", isPresented: $showUninstallConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                performUninstall()
            }
        } message: {
            Text("This will remove the Focus helper daemon, restore your /etc/hosts file, delete all app data, and remove Focus from login items. This cannot be undone.")
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
        panel.nameFieldStringValue = "focus-export-\(ISO8601DateFormatter.dateOnly.string(from: Date())).json"

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
        Task { @MainActor in
            // 1. Restore /etc/hosts
            let xpcClient = XPCClient()
            _ = try? await xpcClient.uninstall()

            // 2. Remove login item
            try? await SMAppService.mainApp.unregister()

            // 3. Delete app data
            let appSupport = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!
            let focusDir = (appSupport as NSString).appendingPathComponent("Focus")
            try? FileManager.default.removeItem(atPath: focusDir)

            // 4. Delete logs
            let logDir = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first!
            let focusLogs = (logDir as NSString).appendingPathComponent("Logs/Focus")
            try? FileManager.default.removeItem(atPath: focusLogs)

            // 5. Delete preferences
            UserDefaults.standard.removePersistentDomain(forName: AppConstants.bundleIdentifier)

            // 6. Quit
            NSApplication.shared.terminate(nil)
        }
    }
}
