import SwiftUI
import ServiceManagement
import GRDB
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
    private var timerEngine: TimerEngine!
    private var modeEngine: ModeEngine!
    private var scheduleEngine: ScheduleEngine!
    private var wakeDetector: WakeDetector!
    private var locationService: LocationService!
    private var notificationService: NotificationService!
    private var dbPool: DatabasePool?
    private var onboardingWindow: NSWindow?
    private let logger = Logger.app

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Focus app launching")

        // Initialize core state
        appState = AppState()

        // Initialize database
        do {
            dbPool = try DatabaseManager.openDatabase()
        } catch {
            logger.error("Failed to open database: \(error.localizedDescription)")
        }

        // Initialize services
        xpcClient = XPCClient()
        blockingEngine = BlockingEngine(xpcClient: xpcClient)
        timerEngine = TimerEngine()
        notificationService = NotificationService()
        notificationService.requestPermission()

        // Initialize engines
        modeEngine = ModeEngine(
            timerEngine: timerEngine,
            blockingEngine: blockingEngine,
            notificationService: notificationService,
            appState: appState
        )
        if let dbPool {
            modeEngine.setDatabase(dbPool)
        }

        scheduleEngine = ScheduleEngine()
        wakeDetector = WakeDetector()
        locationService = LocationService()

        // Handle dirty shutdown
        if appState.isDirtyShutdown {
            logger.warning("Detected dirty shutdown — restoring hosts file")
            Task {
                try? await xpcClient.restoreHostsFile()
            }
        }
        appState.setDirtyFlag()

        // Recover timer if crashed mid-session
        if timerEngine.recoverIfNeeded() {
            appState.timerIsRunning = true
            logger.info("Recovered active timer session")
        }

        // Set up menubar
        menuBarManager = MenuBarManager(appState: appState)
        menuBarManager.setup()
        menuBarManager.setupPopover(modeEngine: modeEngine)

        // Set up hosts file watcher
        hostsWatcher = HostsFileWatcher()
        hostsWatcher.onTamperDetected = { [weak self] in
            Task { @MainActor in
                self?.handleHostsTamper()
            }
        }
        hostsWatcher.startWatching()

        // Wire timer updates to UI
        setupTimerUIUpdates()

        // Wire mode changes to menubar
        modeEngine.onModeChanged = { [weak self] _ in
            self?.menuBarManager.updateStatusItemDisplay()
        }

        // Set up wake detection and schedule
        setupScheduleSystem()

        // Register as login item
        registerLoginItem()

        // Request location for solar calculations
        locationService.requestLocation()

        // Check if onboarding needed
        if !appState.isOnboardingComplete {
            showOnboarding()
        } else {
            applyCurrentMode()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            appState.clearDirtyFlag()
            hostsWatcher.stopWatching()
            wakeDetector.stopMonitoring()
            xpcClient.disconnect()
            logger.info("Focus app terminating cleanly")
        }
    }

    // MARK: - Timer → UI Bridge

    @MainActor
    private func setupTimerUIUpdates() {
        timerEngine.onTick = { [weak self] remaining in
            guard let self else { return }
            self.appState.timerRemainingSeconds = remaining
            self.appState.timerIsRunning = self.timerEngine.isRunning

            // Update menubar every minute (not every second)
            if remaining % 60 == 0 {
                self.menuBarManager.updateStatusItemDisplay()
            }
        }

        // When timer completes
        let originalOnComplete = timerEngine.onComplete
        timerEngine.onComplete = { [weak self] in
            self?.appState.timerIsRunning = false
            self?.appState.timerRemainingSeconds = 0
            self?.appState.sessionsCompletedToday = self?.modeEngine.sessionCount ?? 0
            self?.menuBarManager.updateStatusItemDisplay()
            originalOnComplete?()
        }
    }

    // MARK: - Schedule System

    @MainActor
    private func setupScheduleSystem() {
        wakeDetector.onDayAnchorSet = { [weak self] anchor in
            guard let self else { return }
            self.scheduleEngine.generateSchedule(
                anchor: anchor,
                appState: self.appState,
                solarNoon: self.locationService.solarTimes?.solarNoon
            )
            self.logger.info("Schedule generated from anchor: \(anchor)")
        }

        locationService.onSolarTimesUpdated = { [weak self] times in
            guard let self else { return }
            self.notificationService.scheduleSolarPrayers(solarTimes: times)

            // Regenerate schedule with solar noon
            if let anchor = self.wakeDetector.dayAnchor {
                self.scheduleEngine.generateSchedule(
                    anchor: anchor,
                    appState: self.appState,
                    solarNoon: times.solarNoon
                )
            }
        }

        wakeDetector.startMonitoring()
    }

    // MARK: - Helpers

    @MainActor
    private func showOnboarding() {
        let onboardingView = OnboardingView(appState: appState) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.applyCurrentMode()
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
    private func applyCurrentMode() {
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

    @MainActor
    private func handleHostsTamper() {
        logger.warning("Hosts file tamper detected, restoring blocking rules")
        applyCurrentMode()
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
