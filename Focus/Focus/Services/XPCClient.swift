import Foundation
import os.log

/// Client for communicating with the FocusHelper XPC daemon.
@MainActor
final class XPCClient {
    private var connection: NSXPCConnection?
    private let logger = Logger.xpc

    /// Get or create the XPC connection to FocusHelper daemon.
    private func getConnection() -> NSXPCConnection {
        if let existing = connection {
            return existing
        }

        let conn = NSXPCConnection(machServiceName: AppConstants.helperMachServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: FocusHelperProtocol.self)

        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.logger.warning("XPC connection invalidated")
                self?.connection = nil
            }
        }

        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.logger.warning("XPC connection interrupted")
                self?.connection = nil
            }
        }

        conn.resume()
        connection = conn
        return conn
    }

    /// Get the proxy object for calling daemon methods.
    private func proxy() throws -> FocusHelperProtocol {
        let conn = getConnection()
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            Logger.xpc.error("XPC proxy error: \(error.localizedDescription)")
        }) as? FocusHelperProtocol else {
            throw FocusError.xpcConnectionFailed(underlying: "Failed to get remote object proxy")
        }
        return proxy
    }

    // MARK: - Public API

    /// Update blocked domains via the daemon.
    func updateBlockedDomains(_ domains: [String]) async throws {
        let proxy = try proxy()
        return try await withCheckedThrowingContinuation { continuation in
            proxy.updateBlockedDomains(domains) { success, errorMessage in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: FocusError.hostsFileWriteFailed(underlying: errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    /// Restore the hosts file from backup.
    func restoreHostsFile() async throws {
        let proxy = try proxy()
        return try await withCheckedThrowingContinuation { continuation in
            proxy.restoreHostsFile { success, errorMessage in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: FocusError.hostsFileWriteFailed(underlying: errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    /// Check if the daemon is running.
    func ping() async -> Bool {
        guard let proxy = try? proxy() else { return false }
        return await withCheckedContinuation { continuation in
            proxy.ping { alive in
                continuation.resume(returning: alive)
            }
        }
    }

    /// Get current blocked domains.
    func currentBlockedDomains() async throws -> [String] {
        let proxy = try proxy()
        return await withCheckedContinuation { continuation in
            proxy.currentBlockedDomains { domains in
                continuation.resume(returning: domains)
            }
        }
    }

    /// Perform clean uninstall.
    func uninstall() async throws {
        let proxy = try proxy()
        return try await withCheckedThrowingContinuation { continuation in
            proxy.uninstall { success, errorMessage in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: FocusError.hostsFileWriteFailed(underlying: errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    /// Invalidate the connection.
    func disconnect() {
        connection?.invalidate()
        connection = nil
    }
}
