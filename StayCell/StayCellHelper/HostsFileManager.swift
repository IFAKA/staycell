import Foundation
import os.log

/// Manages atomic reads/writes to /etc/hosts with backup and validation.
/// Runs inside the StayCellHelper daemon (as root).
final class HostsFileManager: Sendable {
    private let hostsPath = AppConstants.hostsFilePath
    private let backupPath = AppConstants.hostsBackupPath
    private let tempPath = AppConstants.hostsTempPath
    private let managedHeader = AppConstants.staycellManagedHeader
    private let managedFooter = AppConstants.staycellManagedFooter

    private let logger = Logger(subsystem: "com.staycell.helper", category: "hosts")

    /// Update /etc/hosts with the given blocked domains.
    /// Preserves user-defined entries outside the managed section.
    func updateBlockedDomains(_ domains: [String]) throws {
        logger.info("Updating hosts file with \(domains.count) blocked domains")

        // 1. Read current hosts file
        let currentContent: String
        do {
            currentContent = try String(contentsOfFile: hostsPath, encoding: .utf8)
        } catch {
            // If hosts file doesn't exist or can't be read, start with defaults
            currentContent = "##\n# Host Database\n##\n127.0.0.1\tlocalhost\n255.255.255.255\tbroadcasthost\n::1\tlocalhost\n"
            logger.warning("Could not read hosts file, starting with defaults: \(error.localizedDescription)")
        }

        // 2. Parse: separate user section from StayCell managed section
        let userSection = extractUserSection(from: currentContent)

        // 3. Generate new managed section
        let managedSection = generateManagedSection(domains: domains)

        // 4. Combine
        let newContent: String
        if domains.isEmpty {
            newContent = userSection
        } else {
            newContent = userSection.trimmingCharacters(in: .newlines) + "\n\n" + managedSection + "\n"
        }

        // 5. Write to temp file
        try newContent.write(toFile: tempPath, atomically: true, encoding: .utf8)

        // 6. Validate temp file
        try validateHostsFile(at: tempPath)

        // 7. Create backup of current hosts
        if FileManager.default.fileExists(atPath: hostsPath) {
            try? FileManager.default.removeItem(atPath: backupPath)
            try FileManager.default.copyItem(atPath: hostsPath, toPath: backupPath)
        }

        // 8. Atomic rename
        // On macOS, rename(2) is atomic on the same filesystem
        if rename(tempPath, hostsPath) != 0 {
            let errMsg = String(cString: strerror(errno))
            throw StayCellHelperError.renameFailed(errMsg)
        }

        // 9. Set permissions (hosts should be 644, owned by root:wheel)
        try setHostsPermissions()

        // 10. Flush DNS
        try flushDNS()

        logger.info("Hosts file updated successfully with \(domains.count) domains")
    }

    /// Restore hosts file from backup
    func restoreFromBackup() throws {
        logger.info("Restoring hosts file from backup")

        guard FileManager.default.fileExists(atPath: backupPath) else {
            // No backup — just remove managed section from current file
            try updateBlockedDomains([])
            return
        }

        try? FileManager.default.removeItem(atPath: hostsPath)
        try FileManager.default.copyItem(atPath: backupPath, toPath: hostsPath)
        try setHostsPermissions()
        try flushDNS()

        logger.info("Hosts file restored from backup")
    }

    /// Get currently blocked domains from the managed section
    func currentBlockedDomains() -> [String] {
        guard let content = try? String(contentsOfFile: hostsPath, encoding: .utf8) else {
            return []
        }

        let lines = content.components(separatedBy: .newlines)
        var inManagedSection = false
        var domains: [String] = []

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == managedHeader {
                inManagedSection = true
                continue
            }
            if line.trimmingCharacters(in: .whitespaces) == managedFooter {
                inManagedSection = false
                continue
            }
            if inManagedSection {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("0.0.0.0") {
                    let parts = trimmed.split(separator: " ", maxSplits: 1)
                    if parts.count == 2 {
                        // Remove inline comments
                        let domain = parts[1].split(separator: "#").first?
                            .trimmingCharacters(in: .whitespaces) ?? ""
                        if !domain.isEmpty {
                            domains.append(domain)
                        }
                    }
                }
            }
        }

        return domains
    }

    /// Remove all StayCell artifacts for clean uninstall
    func cleanUninstall() throws {
        // Remove managed section
        try updateBlockedDomains([])

        // Remove backup
        try? FileManager.default.removeItem(atPath: backupPath)

        // Remove temp file if lingering
        try? FileManager.default.removeItem(atPath: tempPath)

        logger.info("Clean uninstall of hosts file complete")
    }

    // MARK: - Private

    private func extractUserSection(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var userLines: [String] = []
        var inManagedSection = false

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == managedHeader {
                inManagedSection = true
                continue
            }
            if line.trimmingCharacters(in: .whitespaces) == managedFooter {
                inManagedSection = false
                continue
            }
            if !inManagedSection {
                userLines.append(line)
            }
        }

        // Remove trailing empty lines
        while userLines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            userLines.removeLast()
        }

        return userLines.joined(separator: "\n")
    }

    private func generateManagedSection(domains: [String]) -> String {
        var lines = [managedHeader]
        lines.append("# Do not edit this section. Managed by StayCell app.")
        lines.append("# Mode changes update these entries automatically.")
        for domain in domains.sorted() {
            lines.append("0.0.0.0 \(domain)")
        }
        lines.append(managedFooter)
        return lines.joined(separator: "\n")
    }

    private func validateHostsFile(at path: String) throws {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty lines and comments are fine
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Must be: IP<whitespace>hostname
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            if parts.isEmpty {
                continue
            }

            let ip = String(parts[0])
            // Basic IP validation
            if !isValidIP(ip) {
                throw StayCellHelperError.validationFailed(line: index + 1, content: trimmed)
            }
        }
    }

    private func isValidIP(_ ip: String) -> Bool {
        // Accept 0.0.0.0, 127.0.0.1, 255.255.255.255, ::1, and other common patterns
        if ip == "::1" || ip == "fe80::1%lo0" {
            return true
        }
        let parts = ip.split(separator: ".")
        if parts.count == 4 {
            return parts.allSatisfy { part in
                if let num = Int(part) {
                    return num >= 0 && num <= 255
                }
                return false
            }
        }
        return false
    }

    private func setHostsPermissions() throws {
        let attrs: [FileAttributeKey: Any] = [
            .posixPermissions: 0o644,
            .ownerAccountName: "root",
            .groupOwnerAccountName: "wheel",
        ]
        try FileManager.default.setAttributes(attrs, ofItemAtPath: hostsPath)
    }

    private func flushDNS() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
        process.arguments = ["-flushcache"]
        try process.run()
        process.waitUntilExit()

        let process2 = Process()
        process2.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process2.arguments = ["-HUP", "mDNSResponder"]
        try process2.run()
        process2.waitUntilExit()

        if process.terminationStatus != 0 || process2.terminationStatus != 0 {
            logger.warning("DNS flush returned non-zero exit status")
        }
    }
}

enum StayCellHelperError: Error, Sendable {
    case renameFailed(String)
    case validationFailed(line: Int, content: String)
    case hostsFileNotFound
}
