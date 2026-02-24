import CoreAudio
import os.log

/// Monitors system audio output to detect active calls.
/// Uses AudioObjectAddPropertyListener (event-driven, zero-cost idle).
@MainActor
final class AudioMonitor {
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "audio")
    private(set) var isAudioActive = false

    var onAudioStateChanged: ((Bool) -> Void)?

    func startMonitoring() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // Listen for default output device changes
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            audioPropertyListener,
            Unmanaged.passUnretained(self).toOpaque()
        )

        if status != noErr {
            logger.warning("Failed to add audio property listener: \(status)")
        }

        // Check initial state
        checkAudioState()
        logger.info("Audio monitor started")
    }

    func stopMonitoring() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            audioPropertyListener,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    /// Check if any audio process is currently running (proxy for calls).
    func checkAudioState() {
        var defaultDevice = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size,
            &defaultDevice
        )

        guard status == noErr, defaultDevice != 0 else {
            isAudioActive = false
            return
        }

        // Check if the device is running (audio is playing/recording)
        var isRunning: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let runningStatus = AudioObjectGetPropertyData(
            defaultDevice,
            &runningAddress,
            0, nil,
            &runningSize,
            &isRunning
        )

        let wasActive = isAudioActive
        isAudioActive = runningStatus == noErr && isRunning != 0

        if wasActive != isAudioActive {
            logger.info("Audio state changed: active=\(self.isAudioActive)")
            onAudioStateChanged?(isAudioActive)
        }
    }
}

private func audioPropertyListener(
    _: AudioObjectID,
    _: UInt32,
    _: UnsafePointer<AudioObjectPropertyAddress>,
    clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else { return noErr }
    let monitor = Unmanaged<AudioMonitor>.fromOpaque(clientData).takeUnretainedValue()
    Task { @MainActor in
        monitor.checkAudioState()
    }
    return noErr
}
