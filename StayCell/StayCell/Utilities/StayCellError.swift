import Foundation
import os.log

/// AI-debuggable error type for all StayCell app errors.
/// Format: What happened, what failed, system error, app state, suggestion.
enum StayCellError: Error, LocalizedError, Sendable {
    case xpcConnectionFailed(underlying: String)
    case xpcConnectionInterrupted
    case xpcConnectionInvalidated
    case hostsFileWriteFailed(underlying: String)
    case hostsFileCorrupted(details: String)
    case hostsFileBackupMissing
    case hostsFileValidationFailed(line: Int, content: String)
    case daemonNotInstalled
    case daemonInstallFailed(underlying: String)
    case daemonNotRunning
    case dnsFlushFailed(underlying: String)
    case permissionDenied(operation: String)
    case invalidModeTransition(from: String, to: String)
    case fileWatcherSetupFailed(path: String, underlying: String)
    case ollamaNotRunning
    case ollamaModelNotInstalled(model: String)
    case ollamaRequestFailed(underlying: String)

    var errorDescription: String? {
        switch self {
        case .xpcConnectionFailed(let underlying):
            "XPC connection to StayCellHelper daemon refused: \(underlying)"
        case .xpcConnectionInterrupted:
            "XPC connection to StayCellHelper daemon interrupted"
        case .xpcConnectionInvalidated:
            "XPC connection to StayCellHelper daemon invalidated"
        case .hostsFileWriteFailed(let underlying):
            "Failed to write /etc/hosts: \(underlying)"
        case .hostsFileCorrupted(let details):
            "/etc/hosts appears corrupted: \(details)"
        case .hostsFileBackupMissing:
            "No hosts file backup found at /etc/hosts.staycell.backup"
        case .hostsFileValidationFailed(let line, let content):
            "Hosts file validation failed at line \(line): \(content)"
        case .daemonNotInstalled:
            "StayCellHelper daemon is not installed"
        case .daemonInstallFailed(let underlying):
            "Failed to install StayCellHelper daemon: \(underlying)"
        case .daemonNotRunning:
            "StayCellHelper daemon is not running"
        case .dnsFlushFailed(let underlying):
            "DNS cache flush failed: \(underlying)"
        case .permissionDenied(let operation):
            "Permission denied for operation: \(operation)"
        case .invalidModeTransition(let from, let to):
            "Invalid mode transition from \(from) to \(to)"
        case .fileWatcherSetupFailed(let path, let underlying):
            "Failed to set up file watcher for \(path): \(underlying)"
        case .ollamaNotRunning:
            "Ollama is not running (localhost:11434 not reachable)"
        case .ollamaModelNotInstalled(let model):
            "Ollama model '\(model)' is not installed"
        case .ollamaRequestFailed(let underlying):
            "Ollama chat request failed: \(underlying)"
        }
    }

    var suggestion: String {
        switch self {
        case .xpcConnectionFailed, .xpcConnectionInterrupted, .xpcConnectionInvalidated, .daemonNotRunning:
            "Restart StayCellHelper daemon: sudo launchctl kickstart system/com.staycell.helper"
        case .hostsFileWriteFailed:
            "Check /etc/hosts permissions. Daemon must run as root."
        case .hostsFileCorrupted:
            "Restore from backup: sudo cp /etc/hosts.staycell.backup /etc/hosts"
        case .hostsFileBackupMissing:
            "No backup available. Manually verify /etc/hosts content."
        case .hostsFileValidationFailed:
            "Check the generated hosts file content for syntax errors."
        case .daemonNotInstalled, .daemonInstallFailed:
            "Re-run StayCell onboarding to install the helper daemon."
        case .dnsFlushFailed:
            "Manually flush DNS: sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
        case .permissionDenied:
            "Ensure the app has the required permissions."
        case .invalidModeTransition:
            "This mode transition is not allowed in the current state."
        case .fileWatcherSetupFailed:
            "Check file exists and app has read access."
        case .ollamaNotRunning:
            "Install Ollama from ollama.com, then run: ollama serve"
        case .ollamaModelNotInstalled(let model):
            "Pull the model manually: ollama pull \(model)"
        case .ollamaRequestFailed:
            "Check Ollama is running and the model is loaded."
        }
    }
}

// MARK: - Logging

extension Logger {
    static let app = Logger(subsystem: AppConstants.bundleIdentifier, category: "app")
    static let blocking = Logger(subsystem: AppConstants.bundleIdentifier, category: "blocking")
    static let xpc = Logger(subsystem: AppConstants.bundleIdentifier, category: "xpc")
    static let daemon = Logger(subsystem: AppConstants.helperBundleIdentifier, category: "daemon")
    static let hosts = Logger(subsystem: AppConstants.helperBundleIdentifier, category: "hosts")
    static let watcher = Logger(subsystem: AppConstants.bundleIdentifier, category: "watcher")
}

/// Log a StayCellError with full context
func logError(
    _ error: StayCellError,
    function: String = #function,
    file: String = #file,
    line: Int = #line,
    context: [String: String] = [:]
) {
    let fileName = (file as NSString).lastPathComponent
    let contextString = context.map { "  \($0.key): \($0.value)" }.joined(separator: "\n")
    let message = """
    ERROR \(fileName):\(line) \(function)
      What: \(error.localizedDescription)
      State: \(contextString)
      Suggestion: \(error.suggestion)
    """
    Logger.app.error("\(message)")
}
