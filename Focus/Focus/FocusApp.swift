import SwiftUI
import ServiceManagement
import os.log

@main
struct FocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var appState: AppState!
    private var xpcClient: XPCClient!
    private var blockingEngine: BlockingEngine!
    private var menuBarManager: MenuBarManager!
    private var hostsWatcher: HostsFileWatcher!
    private var onboardingWindow: NSWindow?
    private let logger = Logger.app

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Focus app launching")

        // Initialize core services
        appState = AppState()
        xpcClient = XPCClient()
        blockingEngine = BlockingEngine(xpcClient: xpcClient)

        // Handle dirty shutdown
        if appState.isDirtyShutdown {
            logger.warning("Detected dirty shutdown — restoring hosts file")
            Task {
                try? await xpcClient.restoreHostsFile()
            }
        }
        appState.setDirtyFlag()

        // Set up menubar
        menuBarManager = MenuBarManager(appState: appState, blockingEngine: blockingEngine)
        menuBarManager.setup()

        // Set up hosts file watcher
        hostsWatcher = HostsFileWatcher()
        hostsWatcher.onTamperDetected = { [weak self] in
            Task { @MainActor in
                self?.handleHostsTamper()
            }
        }
        hostsWatcher.startWatching()

        // Register as login item
        registerLoginItem()

        // Check if onboarding needed
        if !appState.isOnboardingComplete {
            showOnboarding()
        } else {
            // Apply current mode's blocking rules
            Task {
                do {
                    try await blockingEngine.applyMode(appState.currentMode)
                } catch let error as FocusError {
                    appState.setError(error)
                } catch {
                    appState.setError(.xpcConnectionFailed(underlying: error.localizedDescription))
                }
            }
        }

        // Observe mode changes to update menubar
        Task { @MainActor in
            // Use a simple polling approach for @Observable changes
            // (withObservationTracking is the proper way but requires careful setup)
            var lastMode = appState.currentMode
            while true {
                try? await Task.sleep(for: .seconds(1))
                if appState.currentMode != lastMode {
                    lastMode = appState.currentMode
                    menuBarManager.updateStatusItemDisplay()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            appState.clearDirtyFlag()
            hostsWatcher.stopWatching()
            xpcClient.disconnect()
            logger.info("Focus app terminating cleanly")
        }
    }

    // MARK: - Private

    @MainActor
    private func showOnboarding() {
        let onboardingView = OnboardingView(appState: appState) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            // Apply initial blocking
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.blockingEngine.applyMode(self.appState.currentMode)
                } catch let error as FocusError {
                    self.appState.setError(error)
                } catch {
                    self.appState.setError(.xpcConnectionFailed(underlying: error.localizedDescription))
                }
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Welcome to Focus"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        onboardingWindow = window
    }

    @MainActor
    private func handleHostsTamper() {
        logger.warning("Hosts file tamper detected, restoring blocking rules")
        Task {
            do {
                try await blockingEngine.applyMode(appState.currentMode)
            } catch let error as FocusError {
                appState.setError(error)
            } catch {
                appState.setError(.xpcConnectionFailed(underlying: error.localizedDescription))
            }
        }
    }

    private func registerLoginItem() {
        do {
            try SMAppService.mainApp.register()
            logger.info("Registered as login item")
        } catch {
            logger.warning("Failed to register as login item: \(error.localizedDescription)")
        }
    }
}
