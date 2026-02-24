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
            generateWorkdaySchedule(
                anchor: anchor,
                startHour: appState.workdayStartHour,
                endHour: appState.workdayEndHour,
                solarNoon: solarNoon
            )
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

    private func generateWorkdaySchedule(anchor: Date, startHour: Int, endHour: Int, solarNoon: Date?) {
        var cursor = anchor

        // Guard: floor at 4.5 hours of work time
        let availableMinutes = max((endHour - startHour) * 60, 270)

        // workEnd = anchor + morning routine (30) + work window
        let workEnd = anchor.addingTimeInterval(Double(30 + availableMinutes) * 60)

        // Morning routine: 30 min
        blocks.append(ScheduleBlock(
            type: .routine,
            mode: .personalTime,
            startTime: cursor,
            durationMinutes: 30,
            label: "Morning Routine"
        ))
        cursor = cursor.addingTimeInterval(30 * 60)

        // Calculate how many deep work cycles fit
        // Fixed overhead (inside work window): lunch(60) + shallow wrap(30) + end ritual(15) = 105
        // Morning(30) is already consumed above
        let cyclePoolMinutes = availableMinutes - 135 // 135 = morning + lunch + shallow + ritual
        let cycleMinutes = TimerDurations.deepWorkMinutes + TimerDurations.breakMinutes // 90 + 15 = 105
        let numCycles = max(1, cyclePoolMinutes / cycleMinutes)
        let beforeLunch = (numCycles + 1) / 2
        let afterLunch = numCycles - beforeLunch

        // Deep work cycles before lunch (no break after last pre-lunch cycle)
        for i in 0..<beforeLunch {
            blocks.append(ScheduleBlock(
                type: .deepWork,
                mode: .deepWork,
                startTime: cursor,
                durationMinutes: TimerDurations.deepWorkMinutes,
                label: "Deep Work \(i + 1)"
            ))
            cursor = cursor.addingTimeInterval(Double(TimerDurations.deepWorkMinutes) * 60)

            if i < beforeLunch - 1 {
                blocks.append(ScheduleBlock(
                    type: .breakTime,
                    mode: .personalTime,
                    startTime: cursor,
                    durationMinutes: TimerDurations.breakMinutes,
                    label: "Break"
                ))
                cursor = cursor.addingTimeInterval(Double(TimerDurations.breakMinutes) * 60)
            }
        }

        // Lunch — snap to solar noon if within ±45 min ahead of cursor
        if let noon = solarNoon {
            let diff = noon.timeIntervalSince(cursor)
            if diff > 0 && diff <= 45 * 60 {
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

        // Deep work cycles after lunch (no break after last cycle)
        for i in 0..<afterLunch {
            blocks.append(ScheduleBlock(
                type: .deepWork,
                mode: .deepWork,
                startTime: cursor,
                durationMinutes: TimerDurations.deepWorkMinutes,
                label: "Deep Work \(beforeLunch + i + 1)"
            ))
            cursor = cursor.addingTimeInterval(Double(TimerDurations.deepWorkMinutes) * 60)

            if i < afterLunch - 1 {
                blocks.append(ScheduleBlock(
                    type: .breakTime,
                    mode: .personalTime,
                    startTime: cursor,
                    durationMinutes: TimerDurations.breakMinutes,
                    label: "Break"
                ))
                cursor = cursor.addingTimeInterval(Double(TimerDurations.breakMinutes) * 60)
            }
        }

        // Shallow wrap (emails/admin): 30 min, anchored 45 min before workEnd
        let shallowStart = workEnd.addingTimeInterval(-45 * 60)
        if shallowStart > cursor { cursor = shallowStart }
        blocks.append(ScheduleBlock(
            type: .shallowWork,
            mode: .shallowWork,
            startTime: cursor,
            durationMinutes: 30,
            label: "Emails & Admin"
        ))
        cursor = cursor.addingTimeInterval(30 * 60)

        // Work End Ritual: 15 min, anchored 15 min before workEnd
        let ritualStart = workEnd.addingTimeInterval(-15 * 60)
        if ritualStart > cursor { cursor = ritualStart }
        blocks.append(ScheduleBlock(
            type: .routine,
            mode: .shallowWork,
            startTime: cursor,
            durationMinutes: 15,
            label: "Work End Ritual"
        ))

        // Personal time from workEnd
        blocks.append(ScheduleBlock(
            type: .personal,
            mode: .personalTime,
            startTime: workEnd,
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
