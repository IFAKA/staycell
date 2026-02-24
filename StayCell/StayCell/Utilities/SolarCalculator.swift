import Foundation

/// Calculates sunrise, sunset, and solar noon from coordinates and date.
/// Uses the NOAA solar position algorithm (simplified).
enum SolarCalculator {
    struct SolarTimes {
        let sunrise: Date
        let sunset: Date
        let solarNoon: Date
    }

    /// Calculate solar times for a given date and location.
    static func calculate(date: Date, latitude: Double, longitude: Double) -> SolarTimes? {
        let calendar = Calendar.current
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let year = calendar.component(.year, from: date)

        // Fractional year (radians)
        let daysInYear = Double(calendar.range(of: .day, in: .year, for: date)?.count ?? 365)
        let gamma = 2.0 * .pi / daysInYear * (dayOfYear - 1.0)

        // Equation of time (minutes)
        let eqTime = 229.18 * (0.000075
            + 0.001868 * cos(gamma)
            - 0.032077 * sin(gamma)
            - 0.014615 * cos(2.0 * gamma)
            - 0.040849 * sin(2.0 * gamma))

        // Solar declination (radians)
        let decl = 0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2.0 * gamma)
            + 0.000907 * sin(2.0 * gamma)
            - 0.002697 * cos(3.0 * gamma)
            + 0.00148 * sin(3.0 * gamma)

        let latRad = latitude * .pi / 180.0

        // Hour angle for sunrise/sunset
        let zenith = 90.833 * .pi / 180.0
        let cosHA = (cos(zenith) / (cos(latRad) * cos(decl))) - tan(latRad) * tan(decl)

        // Check for polar day/night
        guard cosHA >= -1.0 && cosHA <= 1.0 else {
            return nil
        }

        let ha = acos(cosHA) * 180.0 / .pi // degrees

        // Solar noon (minutes from midnight UTC)
        let solarNoonMinutes = 720.0 - 4.0 * longitude - eqTime

        // Sunrise and sunset (minutes from midnight UTC)
        let sunriseMinutes = solarNoonMinutes - ha * 4.0
        let sunsetMinutes = solarNoonMinutes + ha * 4.0

        // Convert to local time
        let timeZoneOffset = Double(TimeZone.current.secondsFromGMT(for: date)) / 60.0

        let startOfDay = calendar.startOfDay(for: date)

        func makeDate(utcMinutes: Double) -> Date {
            let localMinutes = utcMinutes + timeZoneOffset
            return startOfDay.addingTimeInterval(localMinutes * 60.0)
        }

        return SolarTimes(
            sunrise: makeDate(utcMinutes: sunriseMinutes),
            sunset: makeDate(utcMinutes: sunsetMinutes),
            solarNoon: makeDate(utcMinutes: solarNoonMinutes)
        )
    }
}
