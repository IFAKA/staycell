import AppKit
import os.log

/// Detects when the user is in a call, screen share, or presentation.
/// When active, suppresses all overlays and notifications.
@MainActor
final class PresentationDetector {
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "presentation")

    private(set) var isPresentationActive = false
    var onStateChanged: ((Bool) -> Void)?

    private var checkTimer: DispatchSourceTimer?

    /// Presentation-mode apps and processes to detect.
    private static let presentationApps: Set<String> = [
        "com.apple.Keynote",
        "com.microsoft.Powerpoint",
        "us.zoom.xos",
        "com.google.Chrome.app.kjgfgldnnfobanianaljmfjpleigioa", // Google Meet
    ]

    private static let screenShareProcesses: Set<String> = [
        "screencaptureui",
        "ScreenSharingAgent",
    ]

    func startMonitoring() {
        // Check every 10 seconds (lightweight)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 10)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.checkPresentationState()
            }
        }
        timer.resume()
        checkTimer = timer

        // Also respond to app activation changes
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkPresentationState()
            }
        }
    }

    func stopMonitoring() {
        checkTimer?.cancel()
        checkTimer = nil
    }

    private func checkPresentationState() {
        let wasActive = isPresentationActive

        // Check 1: Camera in use (proxy for video call)
        let cameraActive = isCameraActive()

        // Check 2: Known presentation apps in foreground
        let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let inPresentationApp = Self.presentationApps.contains(frontApp)

        // Check 3: Mirrored displays (presentation mode)
        let hasMirroredDisplays = NSScreen.screens.count > 1 && CGDisplayIsInMirrorSet(CGMainDisplayID()) != 0

        // Check 4: Screen sharing processes running
        let screenSharing = NSWorkspace.shared.runningApplications.contains {
            guard let name = $0.localizedName else { return false }
            return Self.screenShareProcesses.contains(name)
        }

        isPresentationActive = cameraActive || inPresentationApp || hasMirroredDisplays || screenSharing

        if isPresentationActive != wasActive {
            logger.info("Presentation mode: \(self.isPresentationActive ? "active" : "inactive")")
            onStateChanged?(isPresentationActive)
        }
    }

    private func isCameraActive() -> Bool {
        // Check if any camera device is being used by reading the system log indicator
        // The simplest reliable approach: check if the camera indicator light is on
        // via IOKit. For now, use a conservative heuristic based on running apps.
        let videoCallApps: Set<String> = [
            "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2",
            "com.google.Chrome", "com.brave.Browser", // Could be Google Meet
            "com.apple.FaceTime",
        ]

        let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        return videoCallApps.contains(frontApp)
    }
}
