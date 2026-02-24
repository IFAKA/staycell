import Foundation

/// Constants shared between StayCell app and StayCellHelper daemon.
enum AppConstants {
    static let bundleIdentifier = "com.staycell.app"
    static let helperBundleIdentifier = "com.staycell.helper"
    static let helperMachServiceName = "com.staycell.helper"
    static let launchDaemonLabel = "com.staycell.helper"
    static let launchDaemonPlistPath = "/Library/LaunchDaemons/com.staycell.helper.plist"
    static let helperToolPath = "/Library/PrivilegedHelperTools/com.staycell.helper"
    static let hostsFilePath = "/etc/hosts"
    static let hostsBackupPath = "/etc/hosts.staycell.backup"
    static let hostsTempPath = "/etc/hosts.staycell.tmp"
    static let logDirectory = "~/Library/Logs/StayCell/"
    static let staycellManagedHeader = "# === STAYCELL MANAGED START ==="
    static let staycellManagedFooter = "# === STAYCELL MANAGED END ==="
    static let maxTamperEventsPerHour = 3
}
