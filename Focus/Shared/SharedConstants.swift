import Foundation

/// Constants shared between Focus app and FocusHelper daemon.
enum AppConstants {
    static let bundleIdentifier = "com.focus.app"
    static let helperBundleIdentifier = "com.focus.helper"
    static let helperMachServiceName = "com.focus.helper"
    static let launchDaemonLabel = "com.focus.helper"
    static let launchDaemonPlistPath = "/Library/LaunchDaemons/com.focus.helper.plist"
    static let helperToolPath = "/Library/PrivilegedHelperTools/com.focus.helper"
    static let hostsFilePath = "/etc/hosts"
    static let hostsBackupPath = "/etc/hosts.focus.backup"
    static let hostsTempPath = "/etc/hosts.focus.tmp"
    static let logDirectory = "~/Library/Logs/Focus/"
    static let focusManagedHeader = "# === FOCUS MANAGED START ==="
    static let focusManagedFooter = "# === FOCUS MANAGED END ==="
    static let maxTamperEventsPerHour = 3
}
