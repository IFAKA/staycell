import AppKit
import Foundation
import os.log

/// Monitors the active browser tab URL every 15 seconds for blocked keywords or paths.
///
/// Only active in deepWork and shallowWork modes.
/// Triggers the interception overlay as a soft block for content that /etc/hosts cannot
/// block (e.g. NSFW subreddits on reddit.com, or individual pages on otherwise-allowed sites).
@MainActor
final class URLKeywordMonitor {
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "urlKeyword")
    private var timer: DispatchSourceTimer?

    private let appState: AppState
    private let interceptionManager: InterceptionWindowManager

    init(appState: AppState, interceptionManager: InterceptionWindowManager) {
        self.appState = appState
        self.interceptionManager = interceptionManager
    }

    /// Begin periodic URL checks. Safe to call multiple times — no-ops if already running.
    func start() {
        guard timer == nil else { return }

        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 15, repeating: 15.0)
        t.setEventHandler { [weak self] in
            self?.checkCurrentURL()
        }
        t.resume()
        timer = t
        logger.info("URLKeywordMonitor started")
    }

    /// Stop periodic URL checks.
    func stop() {
        timer?.cancel()
        timer = nil
        logger.info("URLKeywordMonitor stopped")
    }

    // MARK: - Private

    private func checkCurrentURL() {
        guard !interceptionManager.suppressOverlays else { return }
        guard !interceptionManager.isShowing else { return }

        let mode = appState.currentMode
        guard mode == .deepWork || mode == .shallowWork else {
            stop()
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        guard let ctx = BrowserURLService.currentContext(bundleId: frontApp?.bundleIdentifier) else { return }

        let urlLower = ctx.url.lowercased()

        // Check path segments first (more specific)
        if let path = BlockedURLKeywords.paths.first(where: { urlLower.contains($0) }) {
            logger.warning("Blocked path '\(path)' matched in URL on \(ctx.domain)")
            interceptionManager.show()
            return
        }

        // Check full-URL keywords
        if let keyword = BlockedURLKeywords.keywords.first(where: { urlLower.contains($0) }) {
            logger.warning("Blocked keyword '\(keyword)' matched in URL on \(ctx.domain)")
            interceptionManager.show()
        }
    }
}
