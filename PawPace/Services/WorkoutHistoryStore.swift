import Combine
import Foundation

/// A private, on-device journal. It is separate from the reward ledger so deleting
/// a journal never grants rewards again or changes a companion's progress.
@MainActor
final class WorkoutHistoryStore: ObservableObject {
    @Published private(set) var workouts: [RunSummary] = []
    @Published private(set) var storageMessage: String?

    private let fileURL: URL
    private var canWrite = true

    init(fileURL: URL? = nil) {
        let fileURL = fileURL ?? Self.defaultFileURL
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
            guard archive.version == 1, archive.workouts.allSatisfy(Self.isValid) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            var seen: Set<UUID> = []
            workouts = archive.workouts.filter { seen.insert($0.id).inserted }
                .sorted { $0.endedAt > $1.endedAt }
        } catch {
            // Preserve an unreadable file instead of silently overwriting history.
            canWrite = false
            storageMessage = "Your workout journal couldn’t be read. The saved file has been kept. Your companion’s progress is stored separately."
        }
    }

    @discardableResult
    func append(_ summary: RunSummary) -> Bool {
        guard canWrite, Self.isValid(summary), !workouts.contains(where: { $0.id == summary.id }) else { return false }
        let next = (workouts + [summary]).sorted { $0.endedAt > $1.endedAt }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var excludedDirectory = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try excludedDirectory.setResourceValues(values)
            let data = try JSONEncoder().encode(Archive(version: 1, workouts: next))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            workouts = next
            storageMessage = nil
            return true
        } catch {
            storageMessage = "This workout couldn’t be added to your journal. Your companion’s progress is stored separately."
            return false
        }
    }

    @discardableResult
    func deleteAll() -> Bool {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            workouts = []
            storageMessage = nil
            canWrite = true
            return true
        } catch {
            storageMessage = "Your journal couldn’t be deleted. Please try again."
            return false
        }
    }

    private static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("PawPaceJournal", isDirectory: true)
            .appendingPathComponent("workouts-v1.json")
    }

    private static func isValid(_ summary: RunSummary) -> Bool {
        summary.elapsedSeconds > 0
            && summary.startedAt.timeIntervalSinceReferenceDate.isFinite
            && summary.endedAt.timeIntervalSinceReferenceDate.isFinite
            && summary.endedAt >= summary.startedAt
            && summary.distanceMeters.isFinite && summary.distanceMeters >= 0
            && summary.activeEnergyKilocalories.isFinite && summary.activeEnergyKilocalories >= 0
            && summary.averagePaceSecondsPerKilometer >= 0
            && (summary.averageHeartRate.map { $0 > 0 } ?? true)
            && summary.experienceEarned >= 0
    }

    private struct Archive: Codable {
        let version: Int
        let workouts: [RunSummary]
    }
}
