import simd
import XCTest
@testable import PawPace

final class CompanionRoamingTests: XCTestCase {
    func testWanderingStaysInsideFieldAndExploresForEverySpecies() {
        for species in PetSpecies.allCases {
            var roaming = CompanionRoaming(species: species)
            var minimum = SIMD2<Float>(repeating: .infinity)
            var maximum = SIMD2<Float>(repeating: -.infinity)
            var settledFrames = 0
            for _ in 0..<36_000 {
                let pose = roaming.step(deltaTime: 1 / 60)
                XCTAssertLessThanOrEqual(simd_length(pose.position / CompanionRoaming.fieldRadii), 1.001)
                minimum = simd_min(minimum, pose.position)
                maximum = simd_max(maximum, pose.position)
                if roaming.behavior == .settling { settledFrames += 1 }
            }
            XCTAssertGreaterThan(maximum.x - minimum.x, 1.1, "\(species) should explore horizontally")
            XCTAssertGreaterThan(maximum.y - minimum.y, 0.65, "\(species) should explore depth")
            XCTAssertGreaterThan(roaming.pose.gaitDistance, 30)
            XCTAssertGreaterThan(settledFrames, 120, "Wandering includes pauses to look around")
        }
    }

    func testMovementFollowsHeadingAndTurnsAndAccelerationStayContinuous() {
        var roaming = CompanionRoaming(species: .corgi)
        let dt: Float = 1 / 120
        for frame in 0..<18_000 {
            if frame == 1_000 { roaming.request(.moveTo(SIMD2(-4, -4))) }
            if frame == 4_000 { roaming.request(.play) }
            if frame == 8_000 { roaming.request(.feed) }
            let before = roaming.pose
            let after = roaming.step(deltaTime: dt)
            let translation = after.position - before.position
            let forward = SIMD2<Float>(sin(after.yaw), cos(after.yaw))
            XCTAssertGreaterThanOrEqual(simd_dot(translation, forward), -0.000001)
            XCTAssertLessThan(abs(translation.x * forward.y - translation.y * forward.x), 0.000001)
            XCTAssertLessThanOrEqual(abs(after.yaw - before.yaw), 1.81 * dt)
            XCTAssertLessThanOrEqual(abs(after.turnRate - before.turnRate), 4.51 * dt)
            XCTAssertLessThanOrEqual(abs(after.speed - before.speed), 1.41 * dt)
            XCTAssertEqual(after.gaitDistance - before.gaitDistance, simd_length(translation), accuracy: 0.00001)
        }
    }

    func testRestDeceleratesThenStaysPutAndCanResume() {
        var roaming = CompanionRoaming(species: .bunny)
        for _ in 0..<120 { roaming.step(deltaTime: 1 / 60) }
        let before = roaming.pose
        roaming.request(.rest)
        let first = roaming.step(deltaTime: 1 / 60)
        XCTAssertLessThan(simd_distance(first.position, before.position), 0.01)
        for _ in 0..<120 { roaming.step(deltaTime: 1 / 60) }
        let resting = roaming.pose
        for _ in 0..<600 { roaming.step(deltaTime: 1 / 60) }
        XCTAssertEqual(roaming.behavior, .resting)
        XCTAssertEqual(roaming.pose.speed, 0)
        XCTAssertEqual(roaming.pose.position, resting.position)
        XCTAssertEqual(roaming.pose.gaitDistance, resting.gaitDistance)
        roaming.request(.wander)
        for _ in 0..<240 { roaming.step(deltaTime: 1 / 60) }
        XCTAssertGreaterThan(roaming.pose.gaitDistance, resting.gaitDistance + 0.2)
    }

    func testExternalRestPausesBehaviorAndLongDeltaNeverTeleportsOrResets() {
        var roaming = CompanionRoaming(species: .penguin)
        for _ in 0..<120 { roaming.step(deltaTime: 1 / 60) }
        for _ in 0..<120 { roaming.step(deltaTime: 1 / 60, isResting: true) }
        let resting = roaming.pose
        for _ in 0..<120 { roaming.step(deltaTime: 1 / 60, isResting: true) }
        XCTAssertEqual(roaming.pose.position, resting.position)
        let before = roaming.pose
        let resumed = roaming.step(deltaTime: 1_000)
        XCTAssertLessThan(simd_distance(before.position, resumed.position), 0.031)
        XCTAssertGreaterThanOrEqual(resumed.gaitDistance, before.gaitDistance)
        let invalid = roaming.step(deltaTime: .infinity)
        XCTAssertEqual(invalid.position, resumed.position)
        XCTAssertEqual(roaming.step(deltaTime: -1).yaw, resumed.yaw)
        for _ in 0..<180 { roaming.step(deltaTime: 1 / 60) }
        XCTAssertGreaterThan(roaming.pose.gaitDistance, before.gaitDistance + 0.1)
    }

    func testSeededControllerIsDeterministicAcrossActions() {
        var first = CompanionRoaming(species: .corgi, seed: 42)
        var second = CompanionRoaming(species: .corgi, seed: 42)
        for frame in 0..<6_000 {
            if frame == 200 { first.request(.play); second.request(.play) }
            if frame == 2_000 { first.request(.greet); second.request(.greet) }
            if frame == 3_000 { first.request(.feed); second.request(.feed) }
            let a = first.step(deltaTime: 1 / 60)
            let b = second.step(deltaTime: 1 / 60)
            XCTAssertEqual(a.position, b.position)
            XCTAssertEqual(a.yaw, b.yaw)
            XCTAssertEqual(a.action, b.action)
            XCTAssertEqual(first.behavior, second.behavior)
        }
    }

    func testInteractionsApproachFacePropsAndResumeWandering() {
        for species in PetSpecies.allCases {
            for (intent, action, prop) in [
                (CompanionRoamingIntent.play, PetMotion.playing, CompanionRoaming.ballPosition),
                (.feed, .feeding, CompanionRoaming.bowlPosition),
                (.greet, .jumping, SIMD2<Float>.zero)
            ] {
                var roaming = CompanionRoaming(species: species)
                roaming.request(intent)
                var interacted = false
                var resumed = false
                for _ in 0..<3_600 {
                    let pose = roaming.step(deltaTime: 1 / 60)
                    if pose.action == action {
                        interacted = true
                        XCTAssertLessThan(pose.speed, 0.045)
                        if action != .jumping {
                            XCTAssertLessThan(simd_distance(pose.position, prop), 0.85)
                            let direction = simd_normalize(prop - pose.position)
                            XCTAssertGreaterThan(simd_dot(direction, SIMD2(sin(pose.yaw), cos(pose.yaw))), 0.99)
                        }
                    }
                    if interacted && roaming.behavior == .wandering { resumed = true; break }
                }
                XCTAssertTrue(interacted, "\(species) must reach \(action)")
                XCTAssertTrue(resumed, "\(species) must resume roaming after \(action)")
            }
        }
    }

    func testInteractionApproachWorksFromDifferentPositionsAndHeadings() {
        for species in PetSpecies.allCases {
            for seed: UInt64 in [0, 1, 42, 999, .max] {
                var roaming = CompanionRoaming(species: species, seed: seed)
                for _ in 0..<520 { roaming.step(deltaTime: 1 / 60) }
                for (intent, action) in [(CompanionRoamingIntent.feed, PetMotion.feeding), (.play, .playing)] {
                    roaming.request(intent)
                    var reached = false
                    for _ in 0..<3_600 {
                        let pose = roaming.step(deltaTime: 1 / 60)
                        XCTAssertLessThanOrEqual(simd_length(pose.position / CompanionRoaming.fieldRadii), 1.001)
                        if pose.action == action { reached = true; break }
                    }
                    XCTAssertTrue(reached, "\(species), seed \(seed), \(action) should settle at its prop")
                }
            }
        }
    }
}
