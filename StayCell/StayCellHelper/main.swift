import Foundation
import os.log

/// StayCellHelper — Privileged LaunchDaemon that manages /etc/hosts.
/// Runs as root. Communicates with StayCell.app via XPC (NSXPCListener).
final class StayCellHelperDelegate: NSObject, NSXPCListenerDelegate, StayCellHelperProtocol, @unchecked Sendable {
    private let hostsManager = HostsFileManager()
    private let logger = Logger(subsystem: "com.staycell.helper", category: "daemon")

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        logger.info("Accepting new XPC connection")

        newConnection.exportedInterface = NSXPCInterface(with: StayCellHelperProtocol.self)
        newConnection.exportedObject = self

        newConnection.invalidationHandler = { [weak self] in
            self?.logger.info("XPC connection invalidated")
        }

        newConnection.interruptionHandler = { [weak self] in
            self?.logger.warning("XPC connection interrupted")
        }

        newConnection.resume()
        return true
    }

    // MARK: - StayCellHelperProtocol

    func updateBlockedDomains(_ domains: [String], withReply reply: @escaping (Bool, String?) -> Void) {
        logger.info("Received request to block \(domains.count) domains")
        do {
            try hostsManager.updateBlockedDomains(domains)
            reply(true, nil)
        } catch {
            logger.error("Failed to update blocked domains: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    func restoreHostsFile(withReply reply: @escaping (Bool, String?) -> Void) {
        logger.info("Received request to restore hosts file")
        do {
            try hostsManager.restoreFromBackup()
            reply(true, nil)
        } catch {
            logger.error("Failed to restore hosts file: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    func ping(withReply reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func currentBlockedDomains(withReply reply: @escaping ([String]) -> Void) {
        reply(hostsManager.currentBlockedDomains())
    }

    func uninstall(withReply reply: @escaping (Bool, String?) -> Void) {
        logger.info("Received uninstall request")
        do {
            try hostsManager.cleanUninstall()
            reply(true, nil)
        } catch {
            logger.error("Uninstall failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }
}

// MARK: - Main

let delegate = StayCellHelperDelegate()
let listener = NSXPCListener(machServiceName: "com.staycell.helper")
listener.delegate = delegate
listener.resume()

Logger(subsystem: "com.staycell.helper", category: "daemon").info("StayCellHelper daemon started")

RunLoop.current.run()
