import Foundation
import os.log

/// Monitors /etc/hosts for external modifications using VNODE dispatch sources.
/// Event-driven, zero-cost when idle.
@MainActor
final class HostsFileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let logger = Logger.watcher
    private var tamperCount = 0
    private var tamperWindowStart = Date()

    var onTamperDetected: (() -> Void)?

    func startWatching() {
        stopWatching()

        fileDescriptor = open(AppConstants.hostsFilePath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            logger.error("Failed to open \(AppConstants.hostsFilePath) for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.handleFileChange()
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        source.resume()
        self.source = source
        logger.info("Started watching /etc/hosts")
    }

    func stopWatching() {
        source?.cancel()
        source = nil
    }

    private func handleFileChange() {
        logger.info("Detected change to /etc/hosts")

        // Track tamper frequency
        let now = Date()
        if now.timeIntervalSince(tamperWindowStart) > 3600 {
            tamperCount = 0
            tamperWindowStart = now
        }
        tamperCount += 1

        if tamperCount > AppConstants.maxTamperEventsPerHour {
            logger.warning("Excessive tamper events (\(self.tamperCount)/hour). Consider disabling blocking for today.")
            return
        }

        onTamperDetected?()

        // Re-open the file descriptor if the file was deleted/renamed
        if source != nil {
            let events = source!.data
            if events.contains(.delete) || events.contains(.rename) {
                logger.info("File was deleted/renamed, re-establishing watch")
                // Brief delay to allow the new file to be created
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.startWatching()
                }
            }
        }
    }

    deinit {
        source?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }
}
