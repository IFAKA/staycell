import Foundation
import os.log

/// Anchor-relative daily schedule.
/// Work hours are fixed-duration from the day anchor, not fixed-time.
@MainActor
final class ScheduleEngine {
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "schedule")

    /// Current schedule blocks for the day.
    private(set) var blocks: [ScheduleBlock] = []

    /// Generate the day's schedule from the anchor time.
    func generateSchedule(anchor: Date, appState: AppState, solarNoon: Date?) {
        blocks = []

        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: anchor)
        let isWorkday = appState.workDays.contains(weekday)

        if isWorkday {
            generateWorkdaySchedule(anchor: anchor, solarNoon: solarNoon)
        } else {
            generateWeekendSchedule(anchor: anchor, solarNoon: solarNoon)
        }

        logger.info("Generated \(self.blocks.count) schedule blocks (workday: \(isWorkday))")
    }

    /// Get the current or next block based on the current time.
    func currentBlock(at date: Date = Date()) -> ScheduleBlock? {
        blocks.first { $0.contains(date) }
    }

    /// Get the next upcoming block.
    func nextBlock(after date: Date = Date()) -> ScheduleBlock? {
        blocks.first { $0.startTime > date }
    }

    // MARK: - Schedule Generation

    private func generateWorkdaySchedule(anchor: Date, solarNoon: Date?) {
        var cursor = anchor

        // Morning routine: 30 min
        blocks.append(ScheduleBlock(
            type: .routine,
            mode: .personalTime,
            startTime: cursor,
            durationMinutes: 30,
            label: "Morning Routine"
        ))
        cursor = cursor.addingTimeInterval(30 * 60)

        // Deep Work Block 1: 90 min
        blocks.append(ScheduleBlock(
            type: .deepWork,
            mode: .deepWork,
            startTime: cursor,
            durationMinutes: TimerDurations.deepWorkMinutes,
            label: "Deep Work 1"
        ))
        cursor = cursor.addingTimeInterval(Double(TimerDurations.deepWorkMinutes) * 60)

        // Break 1: 15 min
        blocks.append(ScheduleBlock(
            type: .breakTime,
            mode: .personalTime,
            startTime: cursor,
            durationMinutes: TimerDurations.breakMinutes,
            label: "Break"
        ))
        cursor = cursor.addingTimeInterval(Double(TimerDurations.breakMinutes) * 60)

        // Deep Work Block 2: 90 min
        blocks.append(ScheduleBlock(
            type: .deepWork,
            mode: .deepWork,
            startTime: cursor,
            durationMinutes: TimerDurations.deepWorkMinutes,
            label: "Deep Work 2"
        ))
        cursor = cursor.addingTimeInterval(Double(TimerDurations.deepWorkMinutes) * 60)

        // Lunch / Sixth Hour: 60 min (at solar noon if available, otherwise after block 2)
        if let noon = solarNoon, noon > cursor {
            // If solar noon is later, extend the gap
            let gap = noon.timeIntervalSince(cursor)
            if gap > 0 && gap < 3600 {
                cursor = noon
            }
        }
        blocks.append(ScheduleBlock(
            type: .prayer,
            mode: .personalTime,
            startTime: cursor,
            durationMinutes: 60,
            label: "Sixth Hour / Lunch"
        ))
        cursor = cursor.addingTimeInterval(60 * 60)

        // Deep Work Block 3: 90 min
        blocks.append(ScheduleBlock(
            type: .deepWork,
            mode: .deepWork,
            startTime: cursor,
            durationMinutes: TimerDurations.deepWorkMinutes,
            label: "Deep Work 3"
        ))
        cursor = cursor.addingTimeInterval(Double(TimerDurations.deepWorkMinutes) * 60)

        // Transition ritual: 15 min
        blocks.append(ScheduleBlock(
            type: .routine,
            mode: .shallowWork,
            startTime: cursor,
            durationMinutes: 15,
            label: "Work End Ritual"
        ))
        cursor = cursor.addingTimeInterval(15 * 60)

        // Personal time until bedtime
        blocks.append(ScheduleBlock(
            type: .personal,
            mode: .personalTime,
            startTime: cursor,
            durationMinutes: 180,
            label: "Personal Time"
        ))
    }

    private func generateWeekendSchedule(anchor: Date, solarNoon: Date?) {
        var cursor = anchor

        // Morning: personal time
        blocks.append(ScheduleBlock(
            type: .personal,
            mode: .personalTime,
            startTime: cursor,
            durationMinutes: 180,
            label: "Morning"
        ))
        cursor = cursor.addingTimeInterval(180 * 60)

        // Sixth Hour prayer (if solar noon known)
        if let noon = solarNoon {
            blocks.append(ScheduleBlock(
                type: .prayer,
                mode: .personalTime,
                startTime: noon,
                durationMinutes: 15,
                label: "Sixth Hour"
            ))
        }

        // Afternoon personal
        blocks.append(ScheduleBlock(
            type: .personal,
            mode: .personalTime,
            startTime: cursor,
            durationMinutes: 300,
            label: "Afternoon"
        ))
    }
}

/// A single block in the day's schedule.
struct ScheduleBlock: Identifiable, Sendable {
    let id = UUID()
    let type: BlockType
    let mode: Mode
    let startTime: Date
    let durationMinutes: Int
    let label: String

    var endTime: Date {
        startTime.addingTimeInterval(Double(durationMinutes) * 60)
    }

    func contains(_ date: Date) -> Bool {
        date >= startTime && date < endTime
    }

    enum BlockType: Sendable {
        case deepWork
        case shallowWork
        case breakTime
        case prayer
        case routine
        case personal
        case offline
    }
}
