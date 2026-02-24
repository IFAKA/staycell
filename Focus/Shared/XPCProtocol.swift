import Foundation

/// Protocol for the XPC service provided by FocusHelper daemon.
/// The daemon runs as root and owns all /etc/hosts writes.
@objc protocol FocusHelperProtocol {
    /// Update the hosts file with the given blocked domains.
    /// - Parameters:
    ///   - domains: Array of domain strings to block (mapped to 0.0.0.0)
    ///   - reply: Callback with success flag and optional error message
    func updateBlockedDomains(_ domains: [String], withReply reply: @escaping (Bool, String?) -> Void)

    /// Restore /etc/hosts from backup, removing all Focus-managed entries.
    func restoreHostsFile(withReply reply: @escaping (Bool, String?) -> Void)

    /// Check if the daemon is running and responsive.
    func ping(withReply reply: @escaping (Bool) -> Void)

    /// Get the current list of blocked domains from /etc/hosts.
    func currentBlockedDomains(withReply reply: @escaping ([String]) -> Void)

    /// Perform clean uninstall: restore hosts, remove daemon files.
    func uninstall(withReply reply: @escaping (Bool, String?) -> Void)
}
