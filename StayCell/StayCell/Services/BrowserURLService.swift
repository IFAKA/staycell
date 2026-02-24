import AppKit
import os.log

/// Reads the current URL from the frontmost browser tab using AppleScript.
///
/// No permissions required — browsers publish their URL via their AppleScript dictionary.
/// Only called at the exact moment of an override attempt (not continuously).
enum BrowserURLService {
    private static let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "browserURL")

    // MARK: - Supported browsers

    /// Maps bundle IDs to AppleScript source.
    /// Chrome-based browsers use "active tab"; Safari uses "current tab".
    private static let scripts: [String: String] = [
        "com.brave.Browser":           "tell application \"Brave Browser\" to get URL of active tab of front window",
        "com.brave.Browser.nightly":   "tell application \"Brave Browser Nightly\" to get URL of active tab of front window",
        "com.google.Chrome":           "tell application \"Google Chrome\" to get URL of active tab of front window",
        "com.google.Chrome.canary":    "tell application \"Google Chrome Canary\" to get URL of active tab of front window",
        "org.chromium.Chromium":       "tell application \"Chromium\" to get URL of active tab of front window",
        "com.microsoft.edgemac":       "tell application \"Microsoft Edge\" to get URL of active tab of front window",
        "com.apple.Safari":            "tell application \"Safari\" to get URL of current tab of front window",
        "com.apple.SafariTechnologyPreview": "tell application \"Safari Technology Preview\" to get URL of current tab of front window",
        "company.thebrowser.Browser":  "tell application \"Arc\" to get URL of active tab of front window",
        // Firefox has no AppleScript URL support — intentionally omitted
    ]

    // MARK: - Public API

    /// Result of a browser URL query.
    struct BrowserContext: Sendable {
        let url: String
        let domain: String
    }

    /// Synchronously reads the current URL from the frontmost browser.
    /// Returns nil if the foreground app is not a supported browser,
    /// the query fails, or the URL is not an http/https URL.
    ///
    /// Safe to call from the main thread — executes in ~50–150ms.
    static func currentContext(bundleId: String?) -> BrowserContext? {
        guard let bundleId,
              let script = scripts[bundleId] else { return nil }

        guard let appleScript = NSAppleScript(source: script) else { return nil }

        var errorInfo: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorInfo)

        if errorInfo != nil {
            // Browser has no open window, or is unresponsive — not an error worth logging
            return nil
        }

        guard let urlString = result.stringValue,
              urlString.hasPrefix("http://") || urlString.hasPrefix("https://") else {
            return nil
        }

        guard let domain = extractDomain(from: urlString) else { return nil }

        return BrowserContext(url: urlString, domain: domain)
    }

    // MARK: - Private

    private static func extractDomain(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host,
              !host.isEmpty else { return nil }
        // Strip www. prefix for cleaner grouping
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
