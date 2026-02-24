import CoreLocation
import os.log

/// CoreLocation service — requests location once per day for solar calculations.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "location")

    private(set) var lastLocation: CLLocation?
    private(set) var solarTimes: SolarCalculator.SolarTimes?

    var onSolarTimesUpdated: ((SolarCalculator.SolarTimes) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer // City-level is fine
    }

    func requestLocation() {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways, .authorized:
            manager.requestLocation()
        case .denied, .restricted:
            logger.warning("Location access denied — using default coordinates")
            useFallbackLocation()
        @unknown default:
            useFallbackLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            self.lastLocation = location
            self.logger.info("Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            self.calculateSolarTimes(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.logger.warning("Location failed: \(error.localizedDescription) — using fallback")
            self.useFallbackLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorized || status == .authorizedAlways {
                self.manager.requestLocation()
            }
        }
    }

    // MARK: - Private

    private func calculateSolarTimes(for location: CLLocation) {
        guard let times = SolarCalculator.calculate(
            date: Date(),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ) else {
            logger.warning("Could not calculate solar times — polar region?")
            return
        }

        solarTimes = times
        onSolarTimesUpdated?(times)
        logger.info("Solar times: sunrise=\(times.sunrise), noon=\(times.solarNoon), sunset=\(times.sunset)")
    }

    private func useFallbackLocation() {
        // Default to approximate center of continental US if no location
        let fallback = CLLocation(latitude: 39.8283, longitude: -98.5795)
        lastLocation = fallback
        calculateSolarTimes(for: fallback)
    }
}
