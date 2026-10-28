import Foundation

enum MenuBarAnimationTiming {
    static let conversionDuration: TimeInterval = 2

    static func completedTableTime(after elapsed: TimeInterval) -> TimeInterval {
        let cycleStart = floor(elapsed / conversionDuration) * conversionDuration
        let withinCycle = elapsed - cycleStart
        // The last line finishes at 0.68s. Hold the complete table briefly.
        if withinCycle < 0.8 { return cycleStart + 0.8 }
        if withinCycle < 0.94 { return elapsed }
        // Erasing has started: finish at the next completed drawing, never an empty frame.
        return cycleStart + conversionDuration + 0.8
    }
}
