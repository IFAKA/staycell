import SwiftUI
import CoreLocation

/// First-launch onboarding: welcome, install daemon, check DoH, location, schedule, guide.
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
    @State private var locationGranted = false

    private let totalSteps = 5
    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            HStack(spacing: 4) {
                ForEach(0..<totalSteps, id: \.self) { step in
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
                case 0: welcomeStep
                case 1: daemonInstallStep
                case 2: dohCheckStep
                case 3: locationStep
                case 4: scheduleStep
                default: EmptyView()
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
                if currentStep < totalSteps - 1 {
                    Button("Next") {
                        currentStep += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentStep == 1 && !appState.isDaemonInstalled)
                } else {
                    Button("Start Working") {
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
        .frame(width: 520, height: 480)
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Welcome to StayCell")
                .font(.title.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                welcomePoint(
                    icon: "shield.fill",
                    title: "Blocks distracting websites",
                    detail: "Reddit, YouTube, social media — blocked when you're working, available when you're not."
                )
                welcomePoint(
                    icon: "timer",
                    title: "90-minute deep work sessions",
                    detail: "Structured work blocks with automatic breaks. A timer lives in your menu bar."
                )
                welcomePoint(
                    icon: "flame",
                    title: "FIRE tracker",
                    detail: "Track your savings rate and progress toward financial independence."
                )
                welcomePoint(
                    icon: "moon.stars",
                    title: "Sleep enforcement",
                    detail: "Progressive wind-down at night. Screen dims, distractions blocked."
                )
            }
            .padding(.top, 8)

            Text("Setup takes about 60 seconds.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private func welcomePoint(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 1: Install Daemon

    private var daemonInstallStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Install StayCell Helper")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("StayCell blocks websites by editing a system file (/etc/hosts). To do this, it needs a tiny background helper that runs with admin privileges.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("You'll see a macOS password prompt — this is the only time StayCell will ever ask for your password.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)

            if appState.isDaemonInstalled {
                Label("Helper installed successfully", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(isInstallingDaemon ? "Installing..." : "Install Helper") {
                    installDaemon()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInstallingDaemon)
            }

            if let installError {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Installation failed:")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                    Text(installError)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text("Make sure you entered the correct password and try again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Some browsers have a feature called \"Secure DNS\" that bypasses website blocking. StayCell needs this turned off to work properly.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !hasCheckedDoH {
                Button("Check My Browsers") {
                    checkDoHSettings()
                }
                .buttonStyle(.borderedProminent)
            } else if dohWarnings.isEmpty {
                Label("All clear — no issues found", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Action needed:")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)

                    ForEach(dohWarnings, id: \.self) { warning in
                        dohWarningCard(warning)
                    }
                }
            }
        }
    }

    private func dohWarningCard(_ warning: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)

            if warning.contains("Brave") {
                dohFixInstructions(
                    browser: "Brave",
                    steps: [
                        "Open Brave and go to brave://settings/security",
                        "Scroll down to \"Use secure DNS\"",
                        "Turn it OFF",
                    ]
                )
            } else if warning.contains("Chrome") {
                dohFixInstructions(
                    browser: "Chrome",
                    steps: [
                        "Open Chrome and go to chrome://settings/security",
                        "Scroll down to \"Use secure DNS\"",
                        "Turn it OFF",
                    ]
                )
            } else if warning.contains("Firefox") {
                dohFixInstructions(
                    browser: "Firefox",
                    steps: [
                        "Open Firefox and go to about:preferences#privacy",
                        "Scroll down to \"DNS over HTTPS\"",
                        "Select \"Off\"",
                    ]
                )
            }
        }
        .padding(10)
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func dohFixInstructions(browser: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How to fix:")
                .font(.caption.weight(.medium))
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(index + 1).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .trailing)
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Step 3: Location

    private var locationStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "location")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Location (Optional)")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("StayCell uses your location once a day to calculate sunrise and sunset times. This powers:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Label("Prayer time notifications at solar noon", systemImage: "sun.max")
                    Label("Automatic bedtime based on sunset", systemImage: "moon")
                    Label("Holiday detection based on your country", systemImage: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("If you skip this, StayCell will use default times instead.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if locationGranted {
                Label("Location access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                HStack(spacing: 12) {
                    Button("Grant Location Access") {
                        requestLocation()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Skip") {
                        currentStep += 1
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Step 4: Schedule

    private var scheduleStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Your Schedule")
                .font(.title2.weight(.semibold))

            Text("StayCell builds your daily schedule around when you wake up. If you wake late, the schedule shifts automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                Text("What time does your workday usually start?")
                    .font(.subheadline.weight(.medium))

                Picker("Start hour", selection: $workStartHour) {
                    ForEach(5..<13) { hour in
                        Text("\(hour):00").tag(hour)
                    }
                }
                .pickerStyle(.segmented)

                Text("Which days do you work?")
                    .font(.subheadline.weight(.medium))
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

            VStack(alignment: .leading, spacing: 4) {
                Text("After setup:")
                    .font(.caption.weight(.medium))
                Text("Look for the colored dot in your menu bar (top-right of your screen). Click it to start a deep work session, switch modes, or open the dashboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func requestLocation() {
        let manager = CLLocationManager()
        manager.requestAlwaysAuthorization()
        // The actual location service will handle the rest on app launch
        locationGranted = true
    }
}

// MARK: - Daemon Installer

enum DaemonInstaller {
    @MainActor
    static func install() async throws {
        let helperPath = Bundle.main.path(forAuxiliaryExecutable: "StayCellHelper")
            ?? Bundle.main.bundlePath + "/Contents/MacOS/StayCellHelper"

        guard FileManager.default.fileExists(atPath: helperPath) else {
            throw StayCellError.daemonInstallFailed(underlying: "StayCellHelper binary not found at \(helperPath)")
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
        let scriptPath = NSTemporaryDirectory() + "staycell_install_helper.sh"
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
            throw StayCellError.daemonInstallFailed(underlying: errorString)
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
            warnings.append("Firefox: DNS over HTTPS may be enabled")
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
            return "\(browserName): Secure DNS is enabled"
        }

        return nil
    }
}
