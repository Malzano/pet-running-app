import XCTest
import HealthKit
@testable import PawPace

final class WorkoutActivityTests: XCTestCase {
    func testCatalogCoversEveryModernPublicWorkoutType() {
        // Independent SDK contract: 1...80 minus the three deprecated aliases;
        // 81 is not assigned, 83 is a transition segment, 2998/2999 unavailable.
        var expected = Set((1...80).map(UInt.init))
        expected.subtract([14, 15, 30])
        expected.formUnion([82, 84, 3000])
        XCTAssertEqual(Set(WorkoutActivity.allCases.map(\.healthKitRawValue)), expected)
        XCTAssertEqual(WorkoutActivity.allCases.count, expected.count, "No duplicate HealthKit mappings")
        XCTAssertEqual(WorkoutActivity.selectableActivities.count, expected.count)
        XCTAssertFalse(WorkoutActivity.allCases.contains { [83, 2998, 2999].contains($0.healthKitRawValue) })
    }

    func testRepresentativeActivitiesMapToActualHealthKitConstants() {
        let pairs: [(WorkoutActivity, HKWorkoutActivityType)] = [
            (.running, .running), (.walking, .walking), (.cycling, .cycling),
            (.traditionalStrengthTraining, .traditionalStrengthTraining), (.yoga, .yoga),
            (.cardioDance, .cardioDance), (.preparationAndRecovery, .preparationAndRecovery),
            (.swimming, .swimming), (.wheelchairRunPace, .wheelchairRunPace),
            (.underwaterDiving, .underwaterDiving), (.swimBikeRun, .swimBikeRun), (.other, .other)
        ]
        for (activity, healthKit) in pairs {
            XCTAssertEqual(activity.healthKitRawValue, healthKit.rawValue)
            XCTAssertEqual(activity.healthKitActivityType, healthKit)
        }
    }

    func testEveryActivityHasDiscoverableMetadataAndRoundTrips() throws {
        for activity in WorkoutActivity.allCases {
            XCTAssertFalse(activity.displayName.isEmpty)
            XCTAssertFalse(activity.symbol.isEmpty)
            XCTAssertTrue(activity.allowedLocations.contains(activity.defaultLocation))
            XCTAssertTrue(WorkoutActivity.search(activity.displayName).contains(activity))
            let config = WorkoutConfiguration(activity: activity)
            let decoded = try JSONDecoder().decode(WorkoutConfiguration.self, from: JSONEncoder().encode(config))
            XCTAssertEqual(decoded, config)
            XCTAssertEqual(config.makeHealthKitConfiguration().activityType.rawValue, activity.healthKitRawValue)
        }
    }

    func testSearchIncludesCommonNamesAndMultisportWithoutDeprecatedDuplicates() {
        XCTAssertTrue(WorkoutActivity.search("HIIT").contains(.highIntensityIntervalTraining))
        XCTAssertTrue(WorkoutActivity.search("bike").contains(.cycling))
        XCTAssertTrue(WorkoutActivity.search("  Open   Water ").contains(.swimming))
        XCTAssertTrue(WorkoutActivity.search("weights").contains(.traditionalStrengthTraining))
        XCTAssertTrue(WorkoutActivity.search("kayak").contains(.paddleSports))
        XCTAssertTrue(WorkoutActivity.search("triathlon").contains(.swimBikeRun))
        XCTAssertTrue(WorkoutActivity.search("rolling").contains(.preparationAndRecovery))
        XCTAssertEqual(WorkoutActivity.search(""), WorkoutActivity.selectableActivities)
        XCTAssertTrue(WorkoutActivity.search("this is not an activity").isEmpty)
    }

    func testLegacyConfigurationDefaultsToOutdoorRunning() throws {
        let decoded = try JSONDecoder().decode(WorkoutConfiguration.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.activity, .running)
        XCTAssertEqual(decoded.location, .outdoor)
        XCTAssertTrue(decoded.supportsRoute)
        let partial = try JSONDecoder().decode(WorkoutConfiguration.self, from: Data(#"{"activity":"yoga"}"#.utf8))
        XCTAssertEqual(partial.location, .unknown)
        XCTAssertFalse(partial.supportsDistance)
    }

    func testPoolAndOpenWaterKeepDistinctMetricsAndLocations() throws {
        let pool = WorkoutConfiguration(activity: .swimming)
        XCTAssertEqual(pool.swimmingLocation, .pool)
        XCTAssertEqual(pool.poolLengthMeters, 25)
        XCTAssertEqual(pool.makeHealthKitConfiguration().swimmingLocationType, .pool)
        XCTAssertEqual(try XCTUnwrap(pool.makeHealthKitConfiguration().lapLength).doubleValue(for: .meter()), 25)
        XCTAssertFalse(pool.supportsRoute)
        XCTAssertTrue(pool.supportsDistance)
        XCTAssertEqual(pool.measurement, .swimPace)
        XCTAssertEqual(pool.distanceQuantityIdentifier, .distanceSwimming)

        let outdoorPool = WorkoutConfiguration(activity: .swimming, location: .outdoor, swimmingLocation: .pool, poolLengthMeters: 50)
        XCTAssertFalse(outdoorPool.supportsRoute, "An outdoor pool is not an open-water route")
        XCTAssertEqual(outdoorPool.poolLengthMeters, 50)
        let openWater = WorkoutConfiguration(activity: .swimming, location: .indoor, swimmingLocation: .openWater, poolLengthMeters: 50)
        XCTAssertEqual(openWater.location, .outdoor)
        XCTAssertNil(openWater.poolLengthMeters)
        XCTAssertNil(openWater.makeHealthKitConfiguration().lapLength)
        XCTAssertTrue(openWater.supportsRoute)
        XCTAssertEqual(WorkoutConfiguration(healthKit: openWater.makeHealthKitConfiguration()), openWater)
    }

    func testInvalidPoolLengthsCannotReachHealthKit() {
        for length in [Double.nan, Double.infinity, -1, 0, 501] {
            var config = WorkoutConfiguration(activity: .swimming)
            config.poolLengthMeters = length // Also exercise direct UI field mutation.
            XCTAssertEqual(config.makeHealthKitConfiguration().lapLength?.doubleValue(for: .meter()), 25)
        }
    }

    func testIndoorWorkoutsNeverRequestGPSAndUseTheirOwnDistanceType() {
        let cycling = WorkoutConfiguration(activity: .cycling, location: .indoor)
        XCTAssertTrue(cycling.supportsDistance)
        XCTAssertFalse(cycling.supportsRoute)
        XCTAssertFalse(cycling.supportsPace)
        XCTAssertEqual(cycling.measurement, .speed)
        XCTAssertEqual(cycling.distanceQuantityIdentifier, .distanceCycling)
        XCTAssertEqual(WorkoutActivity.wheelchairWalkPace.distanceQuantityIdentifier, .distanceWheelchair)
        XCTAssertNil(WorkoutActivity.yoga.distanceQuantityIdentifier)
        XCTAssertFalse(WorkoutConfiguration(activity: .yoga, location: .outdoor).supportsRoute)
    }

    func testDurationWorkoutsEarnXPWithoutMovementAndIgnoreUnrelatedDistance() {
        for activity in [WorkoutActivity.yoga, .traditionalStrengthTraining, .pilates, .boxing, .other] {
            XCTAssertEqual(activity.experienceEarned(elapsedSeconds: 1_800, distanceKilometers: 0), 180)
            XCTAssertEqual(activity.experienceEarned(elapsedSeconds: 1_800, distanceKilometers: 100), 180)
            XCTAssertEqual(activity.experienceEarned(elapsedSeconds: -30, distanceKilometers: .nan), 0)
        }
        XCTAssertEqual(WorkoutActivity.running.experienceEarned(elapsedSeconds: 0, distanceKilometers: 5), 260)
        XCTAssertGreaterThan(WorkoutActivity.running.experienceEarned(elapsedSeconds: 600, distanceKilometers: 0), 0)
        XCTAssertEqual(WorkoutActivity.running.experienceEarned(elapsedSeconds: 0, distanceKilometers: .infinity), 0)
    }

    func testMultisportUsesRealSelectedLegsAndNeverClaimsASinglePace() {
        let triathlon = WorkoutConfiguration(activity: .swimBikeRun)
        XCTAssertEqual(triathlon.makeHealthKitConfiguration().activityType, .swimBikeRun)
        XCTAssertTrue(triathlon.activity.requiresMultisportSession)
        XCTAssertFalse(triathlon.supportsPace)
        XCTAssertNil(triathlon.distanceQuantityIdentifier)
        XCTAssertEqual(triathlon.multisportLegs, [.swimming, .cycling, .running])
        XCTAssertEqual(triathlon.configuration(forMultisportLeg: 0).activity, .swimming)
        XCTAssertEqual(triathlon.configuration(forMultisportLeg: 0).swimmingLocation, .openWater)
        XCTAssertEqual(triathlon.configuration(forMultisportLeg: 1).distanceQuantityIdentifier, .distanceCycling)
        XCTAssertEqual(triathlon.configuration(forMultisportLeg: 2).distanceQuantityIdentifier, .distanceWalkingRunning)
        let duathlon = WorkoutConfiguration(activity: .swimBikeRun, multisportLegs: [.running, .cycling, .running])
        XCTAssertEqual(duathlon.multisportLegs, [.running, .cycling, .running])
        XCTAssertEqual(duathlon.configuration(forMultisportLeg: -1), duathlon)
        XCTAssertEqual(duathlon.configuration(forMultisportLeg: 99), duathlon)
        XCTAssertEqual(WorkoutConfiguration(activity: .swimBikeRun, multisportLegs: [.yoga, .boxing]).multisportLegs, [.swimming, .cycling, .running])
        XCTAssertEqual(WorkoutConfiguration(activity: .swimBikeRun, multisportLegs: [.running, .running]).multisportLegs, [.swimming, .cycling, .running])
    }
}
