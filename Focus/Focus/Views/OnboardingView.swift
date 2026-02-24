import SwiftUI

/// First-launch onboarding: install daemon, check DoH, set schedule.
struct OnboardingView: View {
    @Bindable var appState: AppState
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var isInstallingDaemon = false
    @State private var installError: String?
    @State private var workStartHour = 9
    @State private var selectedDays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var dohWarnings: [String] = []
    @State private var hasCheckedDoH = false

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            Spacer()

            // Step content
            Group {
                switch currentStep {
                case 0:
                    daemonInstallStep
                case 1:
                    dohCheckStep
                case 2:
                    scheduleStep
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                }
                Spacer()
                if currentStep < 2 {
                    Button("Next") {
                        currentStep += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentStep == 0 && !appState.isDaemonInstalled)
                } else {
                    Button("Start Focusing") {
                        appState.workdayStartHour = workStartHour
                        appState.workDays = selectedDays
                        appState.isOnboardingComplete = true
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 480, height: 400)
    }

    // MARK: - Step 1: Install Daemon

    private var daemonInstallStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Install Focus Helper")
                .font(.title2.weight(.semibold))

            Text("Focus needs a small helper service to manage website blocking. This requires a one-time administrator password — you won't be asked again.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if appState.isDaemonInstalled {
                Label("Helper installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(isInstallingDaemon ? "Installing..." : "Install Helper") {
                    installDaemon()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInstallingDaemon)
            }

            if let installError {
                Text(installError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Step 2: DoH Check

    private var dohCheckStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Browser DNS Check")
                .font(.title2.weight(.semibold))

            Text("Secure DNS (DoH) in your browser can bypass website blocking. Focus needs to check your browser settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if !hasCheckedDoH {
                Button("Check Browsers") {
                    checkDoHSettings()
                }
                .buttonStyle(.borderedProminent)
            } else if dohWarnings.isEmpty {
                Label("No DoH issues detected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(dohWarnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Step 3: Schedule

    private var scheduleStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Your Schedule")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                Text("What time does your workday usually start?")
                    .font(.subheadline)

                Picker("Start hour", selection: $workStartHour) {
                    ForEach(5..<13) { hour in
                        Text("\(hour):00").tag(hour)
                    }
                }
                .pickerStyle(.segmented)

                Text("Which days do you work?")
                    .font(.subheadline)
                    .padding(.top, 8)

                HStack(spacing: 6) {
                    ForEach(1..<8) { day in
                        let index = day - 1
                        Button(dayNames[index]) {
                            if selectedDays.contains(day) {
                                selectedDays.remove(day)
                            } else {
                                selectedDays.insert(day)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedDays.contains(day) ? .accentColor : .secondary)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func installDaemon() {
        isInstallingDaemon = true
        installError = nil

        Task {
            do {
                try await DaemonInstaller.install()
                appState.isDaemonInstalled = true
            } catch {
                installError = error.localizedDescription
            }
            isInstallingDaemon = false
        }
    }

    private func checkDoHSettings() {
        dohWarnings = DoHChecker.check()
        hasCheckedDoH = true
    }
}

// MARK: - Daemon Installer

enum DaemonInstaller {
    @MainActor
    static func install() async throws {
        let helperPath = Bundle.main.path(forAuxiliaryExecutable: "FocusHelper")
            ?? Bundle.main.bundlePath + "/Contents/MacOS/FocusHelper"

        guard FileManager.default.fileExists(atPath: helperPath) else {
            throw FocusError.daemonInstallFailed(underlying: "FocusHelper binary not found at \(helperPath)")
        }

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(AppConstants.launchDaemonLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(AppConstants.helperToolPath)</string>
            </array>
            <key>MachServices</key>
            <dict>
                <key>\(AppConstants.helperMachServiceName)</key>
                <true/>
            </dict>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """

        // Write a temporary script that does the privileged operations
        let scriptPath = NSTemporaryDirectory() + "focus_install_helper.sh"
        let script = """
        #!/bin/bash
        set -e
        cp "\(helperPath)" "\(AppConstants.helperToolPath)"
        chmod 544 "\(AppConstants.helperToolPath)"
        chown root:wheel "\(AppConstants.helperToolPath)"
        cat > "\(AppConstants.launchDaemonPlistPath)" << 'PLIST'
        \(plistContent)
        PLIST
        chmod 644 "\(AppConstants.launchDaemonPlistPath)"
        chown root:wheel "\(AppConstants.launchDaemonPlistPath)"
        launchctl bootout system/\(AppConstants.launchDaemonLabel) 2>/dev/null || true
        launchctl bootstrap system "\(AppConstants.launchDaemonPlistPath)"
        """

        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        // Use osascript to get admin privileges (one-time prompt)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"/bin/bash '\(scriptPath)'\" with administrator privileges",
        ]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        // Clean up
        try? FileManager.default.removeItem(atPath: scriptPath)

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw FocusError.daemonInstallFailed(underlying: errorString)
        }
    }
}

// MARK: - DoH Checker

enum DoHChecker {
    static func check() -> [String] {
        var warnings: [String] = []

        // Check Brave
        let bravePath = NSHomeDirectory() + "/Library/Application Support/BraveSoftware/Brave-Browser/Local State"
        if let warning = checkChromiumDoH(at: bravePath, browserName: "Brave") {
            warnings.append(warning)
        }

        // Check Chrome
        let chromePath = NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Local State"
        if let warning = checkChromiumDoH(at: chromePath, browserName: "Chrome") {
            warnings.append(warning)
        }

        // Check Firefox
        let firefoxDir = NSHomeDirectory() + "/Library/Application Support/Firefox/Profiles"
        if FileManager.default.fileExists(atPath: firefoxDir) {
            // Firefox stores DoH in prefs.js — just warn if Firefox is installed
            warnings.append("Firefox: Check about:preferences#privacy → DNS over HTTPS is disabled")
        }

        return warnings
    }

    private static func checkChromiumDoH(at path: String, browserName: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dnsConfig = json["dns_over_https"] as? [String: Any]
        else {
            return nil
        }

        let mode = dnsConfig["mode"] as? String ?? ""
        if mode == "secure" || mode == "automatic" {
            return "\(browserName): Secure DNS is enabled. Disable at \(browserName.lowercased())://settings/security"
        }

        return nil
    }
}
