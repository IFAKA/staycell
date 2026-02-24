import Foundation
import os.log

/// Coordinates mode changes with hosts file updates via XPC.
@MainActor
final class BlockingEngine {
    private let xpcClient: XPCClient
    private let logger = Logger.blocking

    init(xpcClient: XPCClient) {
        self.xpcClient = xpcClient
    }

    /// Apply blocking rules for the given mode.
    func applyMode(_ mode: FocusMode) async throws {
        let domains = mode.blockedDomains
        logger.info("Applying \(mode.rawValue) mode: \(domains.count) domains blocked")
        try await xpcClient.updateBlockedDomains(domains)
        logger.info("Mode \(mode.rawValue) applied successfully")
    }

    /// Remove all blocking (used during uninstall).
    func removeAllBlocking() async throws {
        logger.info("Removing all blocking")
        try await xpcClient.restoreHostsFile()
    }

    /// Check if the daemon is available.
    func isDaemonAvailable() async -> Bool {
        await xpcClient.ping()
    }
}
