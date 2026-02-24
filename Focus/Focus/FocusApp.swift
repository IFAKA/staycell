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
    private var interceptionManager: InterceptionWindowManager!
    private var overrideWindow: NSWindow?
    private var dashboardWindow: NSWindow?
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

        // Initialize interception overlay
        interceptionManager = InterceptionWindowManager()
        interceptionManager.onOverrideRequested = { [weak self] in
            self?.showOverrideGate()
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

        // Show interception overlay if in a blocking mode
        let mode = appState.currentMode
        if !mode.blockedCategories.isEmpty && mode != .personalTime {
            if !interceptionManager.isShowing {
                interceptionManager.show()
            }
        }
    }

    @MainActor
    private func showOverrideGate() {
        let level = overrideLevelToday()

        let gateView = OverrideGateView(
            overrideLevel: level,
            onGranted: { [weak self] in
                self?.handleOverrideGranted(level: level)
            },
            onCancelled: { [weak self] in
                self?.overrideWindow?.close()
                self?.overrideWindow = nil
                self?.logOverride(level: level, granted: false)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
        window.contentView = NSHostingView(rootView: gateView)
        window.makeKeyAndOrderFront(nil)

        overrideWindow = window
    }

    @MainActor
    private func handleOverrideGranted(level: Int) {
        overrideWindow?.close()
        overrideWindow = nil
        logOverride(level: level, granted: true)

        // Temporarily switch to personal time for timed access
        modeEngine.switchMode(to: .personalTime)

        // Schedule re-block after timed access period
        let accessMinutes = TimerDurations.overrideTimedAccessMinutes
        logger.info("Override granted: \(accessMinutes) min timed access")

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(accessMinutes * 60)) { [weak self] in
            guard let self else { return }
            // Only re-block if still in personal time (user might have changed mode)
            if self.appState.currentMode == .personalTime {
                self.modeEngine.switchMode(to: .deepWork)
                self.logger.info("Timed override expired, returning to deep work")
            }
        }
    }

    @MainActor
    private func overrideLevelToday() -> Int {
        guard let dbPool else { return 1 }
        do {
            return try dbPool.read { db in
                try Override.countToday(db: db) + 1
            }
        } catch {
            return 1
        }
    }

    @MainActor
    private func logOverride(level: Int, granted: Bool) {
        guard let dbPool else { return }
        let phraseIndex = (Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0 + level) % OverridePhrases.pool.count
        var override = Override.attempt(
            mode: appState.currentMode,
            level: level,
            phrase: OverridePhrases.pool[phraseIndex],
            intention: appState.currentSessionIntention
        )
        override.granted = granted
        override.cancelled = !granted

        do {
            try dbPool.write { db in
                try override.save(db)
            }
        } catch {
            logger.error("Failed to log override: \(error.localizedDescription)")
        }
    }

    @MainActor
    func showDashboard() {
        if let window = dashboardWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let dashboardView = DashboardView(
            appState: appState,
            modeEngine: modeEngine,
            scheduleEngine: scheduleEngine,
            dbPool: dbPool
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Focus Dashboard"
        window.contentView = NSHostingView(rootView: dashboardView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window.delegate = self
        dashboardWindow = window
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

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === dashboardWindow {
            dashboardWindow = nil
        }
    }
}
