import Foundation
import HealthKit
import Combine

struct EverydayActivityBatch {
    var workouts: [RunSummary]
    var steps: [(date: Date, steps: Double)]
}

@MainActor
protocol EverydayActivityReading {
    func requestAccess() async throws
    func read(since: Date, until: Date) async throws -> EverydayActivityBatch
}

@MainActor
final class EverydayActivityService: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isSyncing = false
    @Published private(set) var message: String?
    @Published private(set) var lastSynced: Date?
    private let defaults: UserDefaults
    private let reader: any EverydayActivityReading
    private var generation = 0
    private static let enabledKey = "pawpace.everyday.enabled.v1"
    private static let sinceKey = "pawpace.everyday.since.v1"

    init(defaults: UserDefaults = .standard, reader: (any EverydayActivityReading)? = nil) {
        self.defaults = defaults
        self.reader = reader ?? HealthMovementReader()
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    func setEnabled(_ enabled: Bool) async {
        generation += 1
        let request = generation
        if !enabled {
            isEnabled = false
            defaults.set(false, forKey: Self.enabledKey)
            message = "Everyday activity is off. Your earned progress stays with you."
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await reader.requestAccess()
            guard request == generation else { return }
            defaults.set(Date(), forKey: Self.sinceKey)
            defaults.set(true, forKey: Self.enabledKey)
            isEnabled = true
            message = "Ready to check the Health data you choose to share."
        } catch {
            guard request == generation else { return }
            message = "Health access couldn’t be requested. Try again on your iPhone; recorded PawPace workouts still count."
        }
    }

    func refresh(store: PetStore, history: WorkoutHistoryStore,
                 acceptWorkout: (RunSummary) -> Bool, now: Date = .now) async {
        guard isEnabled, !isSyncing, let enabledAt = defaults.object(forKey: Self.sinceKey) as? Date else { return }
        isSyncing = true
        let request = generation
        defer { isSyncing = false }
        do {
            // Re-read recent days for delayed device uploads. Durable identities,
            // interval unions and daily high-water marks make this idempotent.
            let since = max(enabledAt, Calendar.current.date(byAdding: .day, value: -7, to: now) ?? enabledAt)
            let batch = try await reader.read(since: since, until: now)
            guard isEnabled, request == generation else { return }
            guard store.rememberExistingWorkouts(history.workouts) else { throw EverydayActivityError.storage }
            for workout in batch.workouts.sorted(by: { $0.endedAt < $1.endedAt }) {
                guard acceptWorkout(workout) else { throw EverydayActivityError.storage }
            }
            guard store.applyDailySteps(batch.steps, epoch: String(enabledAt.timeIntervalSinceReferenceDate)) else { throw EverydayActivityError.storage }
            lastSynced = now
            message = batch.workouts.isEmpty && !batch.steps.contains(where: { $0.steps > 0 })
                ? "No shared activity found since you turned this on. Health may have no new data, or read access may be off."
                : "Your shared activity is up to date. Existing rewards are counted only once."
        } catch {
            guard request == generation else { return }
            message = "Activity couldn’t finish syncing. Your saved progress is safe. Try Sync now again."
        }
    }
}

enum EverydayActivityError: Error { case unavailable, authorization, storage }

@MainActor
final class HealthMovementReader: EverydayActivityReading {
    private let store = HKHealthStore()

    func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw EverydayActivityError.unavailable }
        try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType(), HKQuantityType(.stepCount)])
    }

    func read(since: Date, until: Date) async throws -> EverydayActivityBatch {
        guard HKHealthStore.isHealthDataAvailable() else { throw EverydayActivityError.unavailable }
        async let workouts = readWorkouts(since: since, until: until)
        async let steps = readSteps(since: since, until: until)
        return try await EverydayActivityBatch(workouts: workouts, steps: steps)
    }

    private func readWorkouts(since: Date, until: Date) async throws -> [RunSummary] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: until, options: [.strictStartDate, .strictEndDate])
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let summaries = (samples as? [HKWorkout] ?? []).compactMap(Self.summary)
                continuation.resume(returning: summaries)
            }
            store.execute(query)
        }
    }

    nonisolated static func summary(_ workout: HKWorkout) -> RunSummary? {
        // Phone, Watch and recovery saves carry this prefix. They already earn
        // through the durable completion outbox, even if delivery is delayed.
        let syncID = workout.metadata?[HKMetadataKeySyncIdentifier] as? String ?? ""
        guard !workout.sourceRevision.source.bundleIdentifier.hasPrefix("com.pawpace."),
              !syncID.hasPrefix("com.pawpace."), workout.duration.isFinite,
              workout.startDate.timeIntervalSinceReferenceDate.isFinite, workout.endDate.timeIntervalSinceReferenceDate.isFinite,
              workout.duration >= 1, workout.duration <= 7 * 86_400, workout.duration <= workout.endDate.timeIntervalSince(workout.startDate) + 1,
              workout.metadata?[HKMetadataKeyWasUserEntered] as? Bool != true else { return nil }
        let activity = WorkoutActivity(healthKitRawValue: workout.workoutActivityType.rawValue) ?? .other
        let pauses = pauseIntervals(for: workout)
        let seconds = min(Int(workout.duration), Int(WorkoutTiming.activeIntervals(startedAt: workout.startDate,
                             endedAt: workout.endDate, pauseIntervals: pauses).reduce(0) { $0 + $1.duration }))
        guard seconds > 0 else { return nil }
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
        let meters = distance.isFinite ? min(max(0, distance), 10_000_000) : 0
        return RunSummary(id: workout.uuid, startedAt: workout.startDate, endedAt: workout.endDate,
                          distanceMeters: meters, elapsedSeconds: seconds,
                          averagePaceSecondsPerKilometer: meters > 0 ? Int(min(Double(seconds) / (meters / 1_000), 86_400)) : 0,
                          averageHeartRate: nil,
                          experienceEarned: activity.experienceEarned(elapsedSeconds: seconds, distanceKilometers: meters / 1_000),
                          workoutConfiguration: WorkoutConfiguration(activity: activity), pauseIntervals: pauses)
    }

    nonisolated private static func pauseIntervals(for workout: HKWorkout) -> [DateInterval] {
        var pauses: [DateInterval] = []
        var began: Date?
        for event in (workout.workoutEvents ?? []).sorted(by: { $0.dateInterval.start < $1.dateInterval.start }) {
            if event.type == .pause || event.type == .motionPaused {
                if began == nil { began = max(workout.startDate, event.dateInterval.start) }
            } else if event.type == .resume || event.type == .motionResumed, let start = began {
                let end = min(workout.endDate, event.dateInterval.start)
                if end > start { pauses.append(DateInterval(start: start, end: end)) }
                began = nil
            }
        }
        if let start = began, workout.endDate > start {
            pauses.append(DateInterval(start: start, end: workout.endDate))
        }
        return pauses
    }

    private func readSteps(since: Date, until: Date) async throws -> [(date: Date, steps: Double)] {
        try await withCheckedThrowingContinuation { continuation in
            let calendar = Calendar.current
            let predicate = HKQuery.predicateForSamples(withStart: since, end: until, options: [.strictStartDate, .strictEndDate])
            let query = HKStatisticsCollectionQuery(quantityType: HKQuantityType(.stepCount), quantitySamplePredicate: predicate,
                options: .cumulativeSum, anchorDate: calendar.startOfDay(for: since), intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                var totals: [(date: Date, steps: Double)] = []
                results?.enumerateStatistics(from: since, to: until) { statistic, _ in
                    let steps = statistic.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    totals.append((min(statistic.endDate.addingTimeInterval(-1), until), steps))
                }
                continuation.resume(returning: totals)
            }
            store.execute(query)
        }
    }
}
