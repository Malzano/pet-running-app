import Combine
import Foundation

struct PlannedActivity: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String = ""
    var activity: WorkoutActivity = .walking
    var scheduledAt: Date = .now
    var durationMinutes: Int = 20
    var isRestDay = false
    var reminderMinutesBefore: Int?
    var completion: Completion?
    // Club event identity will keep repeated joins from duplicating a plan.
    var clubEventID: String?

    struct Completion: Codable, Equatable {
        let workoutID: UUID
        let endedAt: Date
        let activeSeconds: Int
    }

    var displayTitle: String {
        let custom = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? (isRestDay ? "A little room to rest" : activity.displayName) : custom
    }

    var reminderDate: Date? {
        guard completion == nil, let minutes = reminderMinutesBefore else { return nil }
        return scheduledAt.addingTimeInterval(-Double(minutes * 60))
    }

    var isValid: Bool {
        scheduledAt.timeIntervalSinceReferenceDate.isFinite && (5...240).contains(durationMinutes)
            && title.count <= 80 && (reminderMinutesBefore.map { [0, 10, 30, 60].contains($0) } ?? true)
            && (completion.map { $0.activeSeconds > 0 && $0.endedAt.timeIntervalSinceReferenceDate.isFinite } ?? true)
    }
}

struct PlannerArchive: Codable, Equatable {
    var version = 1
    var plans: [PlannedActivity] = []
    var usedWorkoutIDs: Set<UUID> = []
    var usedWorkoutIntervals: [DateInterval] = []

    var isValid: Bool {
        version == 1 && plans.allSatisfy(\.isValid) && Set(plans.map(\.id)).count == plans.count
            && usedWorkoutIntervals.allSatisfy { $0.start.timeIntervalSinceReferenceDate.isFinite && $0.duration.isFinite && $0.duration > 0 }
    }

    /// A workout meets at most one same-day plan. Already matched copies cannot
    /// complete another plan even when Health assigns them a different UUID.
    mutating func reconcile(_ workouts: [RunSummary], calendar: Calendar = .current) {
        for workout in workouts.sorted(by: {
            $0.startedAt == $1.startedAt ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt
        }) {
            guard !usedWorkoutIDs.contains(workout.id), workout.elapsedSeconds > 0,
                  workout.endedAt > workout.startedAt else { continue }
            let intervals = WorkoutTiming.activeIntervals(startedAt: workout.startedAt, endedAt: workout.endedAt,
                                                         pauseIntervals: workout.pauseIntervals)
            let activeDuration = intervals.reduce(0) { $0 + $1.duration }
            let overlap = intervals.reduce(0.0) { total, interval in
                total + usedWorkoutIntervals.reduce(0.0) { $0 + (interval.intersection(with: $1)?.duration ?? 0) }
            }
            guard activeDuration > 0, overlap < min(activeDuration, Double(workout.elapsedSeconds)) * 0.5 else { continue }
            let candidates = plans.indices.filter {
                !plans[$0].isRestDay && plans[$0].completion == nil
                    && plans[$0].activity == workout.workoutConfiguration.activity
                    && calendar.isDate(plans[$0].scheduledAt, inSameDayAs: workout.startedAt)
                    && workout.elapsedSeconds >= plans[$0].durationMinutes * 60
            }
            guard let index = candidates.min(by: {
                let lhs = abs(plans[$0].scheduledAt.timeIntervalSince(workout.startedAt))
                let rhs = abs(plans[$1].scheduledAt.timeIntervalSince(workout.startedAt))
                return lhs == rhs ? plans[$0].id.uuidString < plans[$1].id.uuidString : lhs < rhs
            }) else { continue }
            plans[index].completion = .init(workoutID: workout.id, endedAt: workout.endedAt, activeSeconds: workout.elapsedSeconds)
            usedWorkoutIDs.insert(workout.id)
            usedWorkoutIntervals = CompanionJourney.union(usedWorkoutIntervals + intervals)
        }
    }
}

@MainActor
final class PlannerStore: ObservableObject {
    @Published private(set) var archive = PlannerArchive()
    @Published private(set) var storageMessage: String?
    @Published private(set) var reminderMessage: String?
    let reminders: any PlannerReminderScheduling
    private var storage: PawPacePrivateStorage?
    private var canWrite = true
    private var reminderTask: Task<Void, Never>?
    private var reminderRevision = 0
    static let fileName = "planner-v1.json"

    var plans: [PlannedActivity] { archive.plans.sorted { $0.scheduledAt < $1.scheduledAt } }

    init(storage: PawPacePrivateStorage? = nil, reminders: (any PlannerReminderScheduling)? = nil) {
        self.reminders = reminders ?? PlannerReminders()
        do {
            let resolved = try storage ?? PawPacePrivateStorage.shared()
            self.storage = resolved
            let saved = try resolved.load(PlannerArchive.self, named: Self.fileName) ?? PlannerArchive()
            guard saved.isValid else { throw CocoaError(.fileReadCorruptFile) }
            archive = saved
        } catch {
            self.storage = storage
            canWrite = false
            storageMessage = "Your planner couldn’t be read. Your saved file has been kept. Try opening PawPace again."
        }
    }

    @discardableResult
    func save(_ plan: PlannedActivity, workouts: [RunSummary] = [], calendar: Calendar = .current) -> Bool {
        guard plan.isValid else { storageMessage = "Choose a valid time and a duration from 5 to 240 minutes."; return false }
        var next = archive
        if let index = next.plans.firstIndex(where: { $0.id == plan.id }) {
            guard next.plans[index].completion == nil else { return false }
            // Completion belongs to the matching engine, never to an editor.
            var edited = plan
            edited.completion = nil
            next.plans[index] = edited
        } else {
            if let eventID = plan.clubEventID, next.plans.contains(where: { $0.clubEventID == eventID }) { return true }
            var added = plan
            added.completion = nil
            next.plans.append(added)
        }
        next.reconcile(workouts, calendar: calendar)
        return commit(next)
    }

    @discardableResult
    func remove(_ id: UUID) -> Bool {
        var next = archive
        next.plans.removeAll { $0.id == id }
        // Keep workout ownership after deleting a plan or the workout journal.
        return commit(next)
    }

    func reconcile(_ workouts: [RunSummary], calendar: Calendar = .current) {
        var next = archive
        next.reconcile(workouts, calendar: calendar)
        if next != archive { _ = commit(next) }
    }

    func plans(on date: Date, calendar: Calendar = .current) -> [PlannedActivity] {
        plans.filter { calendar.isDate($0.scheduledAt, inSameDayAs: date) }
    }

    func refreshReminders() {
        reminderRevision += 1
        let revision = reminderRevision
        let plans = plans
        // Await the previous replacement before beginning another: cancelling
        // an async notification add alone cannot prevent a stale request.
        let previous = reminderTask
        reminderTask = Task { [weak self] in
            await previous?.value
            guard let self, revision == self.reminderRevision else { return }
            let message = await self.reminders.replace(plans: plans, now: .now)
            if revision == self.reminderRevision { self.reminderMessage = message }
        }
    }

    private func commit(_ next: PlannerArchive) -> Bool {
        guard canWrite, let storage, next.isValid else { return false }
        do {
            try storage.save(next, named: Self.fileName)
            archive = next
            storageMessage = nil
            refreshReminders()
            return true
        } catch {
            storageMessage = "Your plan couldn’t be saved. Please try again; your previous plans are safe."
            return false
        }
    }
}
