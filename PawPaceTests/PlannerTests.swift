import XCTest
@testable import PawPace

final class PlannerTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return value
    }
    private var date: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 18))! }

    private func workout(id: UUID = UUID(), start: Date? = nil, minutes: Int = 20, activity: WorkoutActivity = .walking) -> RunSummary {
        let start = start ?? date
        return RunSummary(id: id, startedAt: start, endedAt: start.addingTimeInterval(Double(minutes * 60)),
                          distanceMeters: 0, elapsedSeconds: minutes * 60, averagePaceSecondsPerKilometer: 0,
                          averageHeartRate: nil, experienceEarned: 10,
                          workoutConfiguration: WorkoutConfiguration(activity: activity))
    }

    func testMatchesNearestPlanAndCannotReuseWorkout() {
        let early = PlannedActivity(scheduledAt: date.addingTimeInterval(-3_600))
        let close = PlannedActivity(scheduledAt: date.addingTimeInterval(60))
        let run = workout()
        var archive = PlannerArchive(plans: [early, close])
        archive.reconcile([run], calendar: calendar)
        XCTAssertNil(archive.plans[0].completion)
        XCTAssertEqual(archive.plans[1].completion?.workoutID, run.id)
        archive.reconcile([run], calendar: calendar)
        XCTAssertEqual(archive.plans.filter { $0.completion != nil }.count, 1)
    }

    func testCopiedWorkoutCannotCompleteSecondPlanButSeparateSessionCan() {
        var archive = PlannerArchive(plans: [PlannedActivity(scheduledAt: date), PlannedActivity(scheduledAt: date.addingTimeInterval(3_600))])
        archive.reconcile([workout()], calendar: calendar)
        archive.reconcile([workout(start: date.addingTimeInterval(2))], calendar: calendar)
        XCTAssertEqual(archive.plans.filter { $0.completion != nil }.count, 1)
        archive.reconcile([workout(start: date.addingTimeInterval(3_600))], calendar: calendar)
        XCTAssertEqual(archive.plans.filter { $0.completion != nil }.count, 2)
    }

    func testRestWrongActivityShortSessionAndOtherDayDoNotCompletePlan() {
        var archive = PlannerArchive(plans: [PlannedActivity(scheduledAt: date), PlannedActivity(scheduledAt: date, isRestDay: true)])
        archive.reconcile([workout(minutes: 19), workout(activity: .running), workout(start: calendar.date(byAdding: .day, value: 1, to: date))], calendar: calendar)
        XCTAssertTrue(archive.plans.allSatisfy { $0.completion == nil })
        archive.reconcile([workout()], calendar: calendar)
        XCTAssertNotNil(archive.plans[0].completion)
        XCTAssertNil(archive.plans[1].completion)
    }

    func testMatchingUsesStartDayAndLocalCalendarAcrossMidnight() {
        let late = calendar.date(bySettingHour: 23, minute: 50, second: 0, of: date)!
        var archive = PlannerArchive(plans: [PlannedActivity(scheduledAt: date), PlannedActivity(scheduledAt: calendar.date(byAdding: .day, value: 1, to: date)!)])
        archive.reconcile([workout(start: late)], calendar: calendar)
        XCTAssertNotNil(archive.plans[0].completion)
        XCTAssertNil(archive.plans[1].completion)
    }

    @MainActor
    func testReschedulingPersistsAndReconcilesDelayedWorkouts() throws {
        let storage = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let store = PlannerStore(storage: storage, reminders: TestPlannerReminders())
        var plan = PlannedActivity(scheduledAt: date)
        XCTAssertTrue(store.save(plan))
        plan.scheduledAt = calendar.date(byAdding: .day, value: 2, to: date)!
        XCTAssertTrue(store.save(plan))
        store.reconcile([workout()], calendar: calendar)
        XCTAssertNil(store.plans.first?.completion)
        let reloaded = PlannerStore(storage: storage, reminders: TestPlannerReminders())
        XCTAssertEqual(reloaded.plans.first?.scheduledAt, plan.scheduledAt)
        let futureRun = workout(start: plan.scheduledAt)
        reloaded.reconcile([futureRun], calendar: calendar)
        XCTAssertEqual(reloaded.plans.first?.completion?.workoutID, futureRun.id)
        let final = PlannerStore(storage: storage, reminders: TestPlannerReminders())
        XCTAssertEqual(final.plans.first?.completion?.workoutID, futureRun.id)
    }

    @MainActor
    func testDeletedPlanAndJournalDoNotReleaseWorkoutForReuse() {
        let storage = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let store = PlannerStore(storage: storage, reminders: TestPlannerReminders())
        let plan = PlannedActivity(scheduledAt: date)
        let run = workout()
        XCTAssertTrue(store.save(plan, workouts: [run], calendar: calendar))
        XCTAssertTrue(store.remove(plan.id))
        store.reconcile([], calendar: calendar)
        let reloaded = PlannerStore(storage: storage, reminders: TestPlannerReminders())
        XCTAssertTrue(reloaded.save(PlannedActivity(scheduledAt: date), workouts: [run], calendar: calendar))
        XCTAssertNil(reloaded.plans.first?.completion)
    }

    @MainActor
    func testClubEventJoinIsIdempotentAndEditorCannotForgeCompletion() {
        let storage = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let store = PlannerStore(storage: storage, reminders: TestPlannerReminders())
        var plan = PlannedActivity(scheduledAt: date, clubEventID: "club/event")
        plan.completion = .init(workoutID: UUID(), endedAt: date, activeSeconds: 600)
        XCTAssertTrue(store.save(plan))
        XCTAssertNil(store.plans.first?.completion)
        XCTAssertTrue(store.save(PlannedActivity(scheduledAt: date, clubEventID: "club/event")))
        XCTAssertEqual(store.plans.count, 1)
    }

    @MainActor
    func testCorruptStorageIsPreserved() throws {
        let storage = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        try FileManager.default.createDirectory(at: storage.directoryURL, withIntermediateDirectories: true)
        let file = storage.directoryURL.appendingPathComponent(PlannerStore.fileName)
        let bad = Data("not a planner".utf8)
        try bad.write(to: file)
        let store = PlannerStore(storage: storage, reminders: TestPlannerReminders())
        XCTAssertNotNil(store.storageMessage)
        XCTAssertFalse(store.save(PlannedActivity(scheduledAt: date)))
        XCTAssertEqual(try Data(contentsOf: file), bad)
    }

    @MainActor
    func testFailedSaveKeepsPreviousInMemoryPlans() throws {
        let storage = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let store = PlannerStore(storage: storage, reminders: TestPlannerReminders())
        XCTAssertTrue(store.save(PlannedActivity(scheduledAt: date)))
        let file = storage.directoryURL.appendingPathComponent(PlannerStore.fileName)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertFalse(store.save(PlannedActivity(scheduledAt: date)))
        XCTAssertEqual(store.plans.count, 1)
        XCTAssertNotNil(store.storageMessage)
    }

    @MainActor
    func testCompletedAndPastPlansDoNotScheduleReminders() {
        let future = Date.now.addingTimeInterval(3_600)
        let pending = PlannedActivity(scheduledAt: future, reminderMinutesBefore: 10)
        var complete = pending
        complete.completion = .init(workoutID: UUID(), endedAt: .now, activeSeconds: 1_200)
        let past = PlannedActivity(scheduledAt: .now.addingTimeInterval(-100), reminderMinutesBefore: 0)
        XCTAssertEqual(PlannerReminders.upcoming([pending, complete, past, PlannedActivity(scheduledAt: future)], now: .now).map(\.id), [pending.id])
    }

    @MainActor
    func testReminderReplacementFinishesWithLatestRevision() async {
        let storage = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let reminders = TestPlannerReminders()
        reminders.delay = true
        let store = PlannerStore(storage: storage, reminders: reminders)
        var plan = PlannedActivity(scheduledAt: .now.addingTimeInterval(4_000), reminderMinutesBefore: 10)
        XCTAssertTrue(store.save(plan))
        await Task.yield()
        plan.reminderMinutesBefore = nil
        XCTAssertTrue(store.save(plan))
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(reminders.latestPlans, [plan])
        XCTAssertEqual(reminders.maxConcurrent, 1)
    }

    func testMondayWeekHandlesDSTWithoutFixedSecondArithmetic() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 14))!
        let monday = CompanionJourney.weekStart(sunday, calendar: calendar)
        XCTAssertEqual(calendar.component(.weekday, from: monday), 2)
        XCTAssertEqual(calendar.component(.day, from: monday), 2)
        let next = calendar.date(byAdding: .day, value: 7, to: monday)!
        XCTAssertEqual(next.timeIntervalSince(monday), 167 * 3_600)
    }

    private func temporaryStorage() -> PawPacePrivateStorage {
        PawPacePrivateStorage(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent("planner-test-\(UUID())"))
    }
}

@MainActor
final class TestPlannerReminders: PlannerReminderScheduling {
    var latestPlans: [PlannedActivity] = []
    var allowed = true
    var delay = false
    var concurrent = 0
    var maxConcurrent = 0
    func requestPermission() async -> Bool { allowed }
    func replace(plans: [PlannedActivity], now: Date) async -> String? {
        concurrent += 1
        maxConcurrent = max(maxConcurrent, concurrent)
        if delay { try? await Task.sleep(for: .milliseconds(50)) }
        latestPlans = plans
        concurrent -= 1
        return nil
    }
}
