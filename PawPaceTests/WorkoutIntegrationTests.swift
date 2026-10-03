import XCTest
@testable import PawPace

final class WorkoutIntegrationTests: XCTestCase {
    func testActiveIntervalsExcludeOverlappingAndOngoingPauses() {
        let start = Date(timeIntervalSince1970: 0)
        let intervals = WorkoutTiming.activeIntervals(
            startedAt: start,
            endedAt: start.addingTimeInterval(300),
            pauseIntervals: [
                DateInterval(start: start.addingTimeInterval(60), duration: 60),
                DateInterval(start: start.addingTimeInterval(90), duration: 60)
            ],
            pauseStartedAt: start.addingTimeInterval(240)
        )

        XCTAssertEqual(intervals, [
            DateInterval(start: start, duration: 60),
            DateInterval(start: start.addingTimeInterval(150), duration: 90)
        ])
        XCTAssertEqual(intervals.reduce(0) { $0 + $1.duration }, 150)
    }

    func testLegacyStatePreservesRunningDefaults() throws {
        var state = PawPaceRunState.idle
        state.workoutID = UUID()
        state.phase = .paused
        state.distanceKilometers = 2.3
        state.elapsedSeconds = 900
        let legacy = try removingKeys([
            "workoutConfiguration", "activeEnergyKilocalories", "multisportLegIndex",
            "activitySegments", "pauseIntervals", "pauseStartedAt", "endedAt"
        ], from: state)

        let decoded = try JSONDecoder().decode(PawPaceRunState.self, from: legacy)

        XCTAssertEqual(decoded.workoutConfiguration, WorkoutConfiguration(activity: .running, location: .outdoor))
        XCTAssertEqual(decoded.phase, .paused)
        XCTAssertEqual(decoded.distanceKilometers, 2.3)
        XCTAssertEqual(decoded.elapsedSeconds, 900)
        XCTAssertEqual(decoded.activeEnergyKilocalories, 0)
        XCTAssertTrue(decoded.activitySegments.isEmpty)
    }

    func testWorkoutControlCarriesPoolSettingsAndLegacyControlsStillDecode() throws {
        let control = PawPaceWatchControl(
            id: UUID(), workoutID: UUID(), action: .start,
            startedAt: .now, issuedAt: .now,
            workoutConfiguration: WorkoutConfiguration(activity: .swimming, location: .indoor, swimmingLocation: .pool, poolLengthMeters: 50)
        )
        let restored = try JSONDecoder().decode(PawPaceWatchControl.self, from: JSONEncoder().encode(control))
        XCTAssertEqual(restored, control)
        XCTAssertEqual(restored.workoutConfiguration.poolLengthMeters, 50)

        let legacy = try removingKeys(["workoutConfiguration", "multisportLegIndex"], from: control)
        let decoded = try JSONDecoder().decode(PawPaceWatchControl.self, from: legacy)
        XCTAssertEqual(decoded.workoutConfiguration.activity, .running)
        XCTAssertEqual(decoded.workoutConfiguration.location, .outdoor)
    }

    func testStationaryWorkoutEarnsDailyMinutesAndResources() {
        var pet = PetSnapshot.starter
        pet.distanceTodayKilometers = 0
        pet.dailyWorkoutSeconds = 0
        pet.friendship = 50
        pet.energy = 80
        let originalCoins = pet.coins
        let duration = 1_800
        let xp = WorkoutActivity.yoga.experienceEarned(elapsedSeconds: duration, distanceKilometers: 0)

        pet.applyRun(distanceKilometers: 0, experienceEarned: xp, elapsedSeconds: duration, at: pet.distanceDay)

        XCTAssertEqual(pet.dailyWorkoutSeconds, duration)
        XCTAssertEqual(pet.distanceTodayKilometers, 0)
        XCTAssertEqual(pet.energy, 74)
        XCTAssertEqual(pet.friendship, 56)
        XCTAssertGreaterThan(pet.coins, originalCoins)
        XCTAssertEqual(xp, 180)
    }

    func testWorkoutMinutesResetAtLocalMidnightAndDoNotResetOnPetInteractions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 23))!
        let today = calendar.date(byAdding: .hour, value: 2, to: yesterday)!
        var pet = PetSnapshot.starter
        pet.distanceDay = yesterday
        pet.dailyWorkoutSeconds = 1_200
        pet.feed(at: today)
        XCTAssertEqual(pet.workoutSeconds(on: yesterday, calendar: calendar), 1_200)
        XCTAssertEqual(pet.workoutSeconds(on: today, calendar: calendar), 0)

        pet.applyRun(distanceKilometers: 0, experienceEarned: 30, elapsedSeconds: 300, at: today, calendar: calendar)
        let decoded = try JSONDecoder().decode(PetSnapshot.self, from: JSONEncoder().encode(pet))
        XCTAssertEqual(decoded.dailyWorkoutSeconds, 300)
        XCTAssertEqual(decoded.workoutSeconds(on: today, calendar: calendar), 300)
    }

    func testSummaryPreservesWorkoutTypePausesAndMultisportLegs() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let finish = start.addingTimeInterval(1_200)
        let configuration = WorkoutConfiguration(activity: .swimBikeRun)
        let summary = RunSummary(
            id: UUID(), startedAt: start, endedAt: finish,
            distanceMeters: 1_500, elapsedSeconds: 1_100,
            averagePaceSecondsPerKilometer: 0, averageHeartRate: 120,
            experienceEarned: 110, workoutConfiguration: configuration,
            activeEnergyKilocalories: 85,
            activitySegments: [
                WorkoutActivitySegment(configuration: configuration.configuration(forMultisportLeg: 0), startedAt: start, endedAt: start.addingTimeInterval(600), distanceMeters: 500),
                WorkoutActivitySegment(configuration: configuration.configuration(forMultisportLeg: 1), startedAt: start.addingTimeInterval(600), endedAt: finish, distanceMeters: 1_000)
            ],
            pauseIntervals: [DateInterval(start: start.addingTimeInterval(50), duration: 100)]
        )
        let restored = try JSONDecoder().decode(RunSummary.self, from: JSONEncoder().encode(summary))
        XCTAssertEqual(restored, summary)
        XCTAssertEqual(restored.activitySegments.map(\.configuration.activity), [.swimming, .cycling])

        let legacy = try removingKeys(["workoutConfiguration", "activeEnergyKilocalories", "activitySegments", "pauseIntervals"], from: summary)
        let decoded = try JSONDecoder().decode(RunSummary.self, from: legacy)
        XCTAssertEqual(decoded.workoutConfiguration.activity, .running)
        XCTAssertEqual(decoded.distanceMeters, summary.distanceMeters)
        XCTAssertEqual(decoded.activeEnergyKilocalories, 0)
    }

    private func removingKeys<T: Encodable>(_ keys: [String], from value: T) throws -> Data {
        let encoded = try JSONEncoder().encode(value)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        keys.forEach { object.removeValue(forKey: $0) }
        return try JSONSerialization.data(withJSONObject: object)
    }
}
