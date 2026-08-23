import Foundation

enum PawPaceFormatting {
    static func duration(seconds: Int) -> String {
        let clamped = max(seconds, 0)
        let hours = clamped / 3_600
        let minutes = (clamped % 3_600) / 60
        let remainingSeconds = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    static func pace(secondsPerKilometer: Int) -> String {
        guard secondsPerKilometer > 0 else { return "—" }
        return String(format: "%d′%02d″", secondsPerKilometer / 60, secondsPerKilometer % 60)
    }

    static func distance(kilometers: Double) -> String {
        kilometers.formatted(.number.precision(.fractionLength(2)))
    }
}

