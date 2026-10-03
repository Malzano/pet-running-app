import SceneKit
import XCTest
import simd
@testable import PawPace

final class CompanionSpecialTests: XCTestCase {
    private let specialSpecies: [PetSpecies] = [.redPanda, .fox, .axolotl, .dragon, .unicorn, .phoenix]

    @MainActor
    func testEffectsAreDeterministicBoundedAndCleanUp() {
        for species in specialSpecies {
            let effects = CompanionSpecialEffects(species: species)
            let nodes = effects.root.childNodes
            XCTAssertFalse(nodes.isEmpty)
            XCTAssertLessThanOrEqual(nodes.count, 24)
            effects.update(time: 1.5, weight: 1, muzzle: SIMD3(0, 0.8, 0.3), growthScale: 1)
            XCTAssertFalse(effects.root.isHidden)
            XCTAssertGreaterThan(effects.root.opacity, 0.1)
            let original = nodes.map(\.simdTransform)
            for sample in 0..<240 {
                effects.update(time: Float(sample) / 60, weight: 1, muzzle: SIMD3(0, 0.8, 0.3), growthScale: 1)
                for node in nodes {
                    XCTAssertTrue(node.simdPosition.x.isFinite && node.simdPosition.y.isFinite && node.simdPosition.z.isFinite)
                    XCTAssertLessThan(simd_length(node.simdPosition), 3)
                }
                XCTAssertEqual(effects.root.childNodes.count, nodes.count)
            }
            effects.update(time: 1.5, weight: 1, muzzle: SIMD3(0, 0.8, 0.3), growthScale: 1)
            for (node, before) in zip(nodes, original) {
                for column in 0..<4 { XCTAssertLessThan(simd_length(node.simdTransform[column] - before[column]), 0.0001) }
            }
            effects.update(time: CompanionSpecialEffects.duration, weight: 1, muzzle: .zero, growthScale: 1)
            XCTAssertTrue(effects.root.isHidden, "A completed \(species) move must clear its effect")
            effects.update(time: 1.5, weight: 0, muzzle: .zero, growthScale: 1)
            XCTAssertTrue(effects.root.isHidden, "Reduce Motion must leave no active effect")
        }
    }

    @MainActor
    func testDragonFireTracksTheMuzzleAndRainbowHasSixBands() throws {
        let dragon = CompanionSpecialEffects(species: .dragon)
        dragon.update(time: 1.5, weight: 1, muzzle: .zero, growthScale: 1)
        let initial = dragon.root.childNodes.map(\.simdPosition)
        let movement = SIMD3<Float>(0.2, 0.1, -0.15)
        dragon.update(time: 1.5, weight: 1, muzzle: movement, growthScale: 1)
        for (node, before) in zip(dragon.root.childNodes, initial) {
            XCTAssertLessThan(simd_distance(node.simdPosition - before, movement), 0.0001)
        }
        dragon.update(time: 1.5, weight: 1, muzzle: .zero, growthScale: 1, direction: SIMD3(1, 0, 0))
        for (node, before) in zip(dragon.root.childNodes, initial) {
            XCTAssertLessThan(simd_distance(node.simdPosition, SIMD3(before.z, before.y, -before.x)), 0.0001,
                              "Turning the head must also turn the breath stream")
        }
        let unicorn = CompanionSpecialEffects(species: .unicorn)
        XCTAssertEqual(unicorn.root.childNodes.filter { $0.name?.hasPrefix("rainbow-band-") == true }.count, 6)
        let lift = CompanionSpecialEffects.pose(species: .unicorn, time: 2, weight: 1).lift
        XCTAssertGreaterThan(lift, 0.2, "The rainbow accompanies an actual leap")
    }

    func testSpecialFinishesAndWanderingResumes() {
        for species in specialSpecies {
            var roaming = CompanionRoaming(species: species, seed: 234)
            roaming.request(.special)
            var specialFrames = 0
            var resumed = false
            for _ in 0..<900 {
                let pose = roaming.step(deltaTime: 1 / 60)
                if pose.action == .special { specialFrames += 1 }
                if specialFrames > 0, pose.action == .walking { resumed = true }
            }
            XCTAssertGreaterThan(specialFrames, 200)
            XCTAssertLessThan(specialFrames, 260)
            XCTAssertTrue(resumed, "\(species)'s special must return to ordinary roaming")
        }
    }

    @MainActor
    func testEverySpecialUsesItsOwnRigAndHonorsReduceMotion() throws {
        for species in specialSpecies {
            let view = CompanionSceneView()
            let coordinator = AnimalCompanionView.Coordinator()
            coordinator.attach(view)
            defer { coordinator.stop() }
            coordinator.update(species: species, motion: .special, interaction: 1,
                               reduceMotion: false, active: true, showsProps: true)
            for _ in 0..<100 { coordinator.advance(deltaTime: 1 / 60) }
            let effects = try XCTUnwrap(view.scene?.rootNode.childNode(withName: "companion-special-effects", recursively: true))
            XCTAssertFalse(effects.isHidden, "\(species)'s gesture must reach the real scene")
            coordinator.update(species: species, motion: .special, interaction: 2,
                               reduceMotion: true, active: true, showsProps: true)
            XCTAssertTrue(effects.isHidden)
            XCTAssertFalse(view.isPlaying)
            let still = effects.childNodes.map(\.simdTransform)
            for _ in 0..<30 { coordinator.advance(deltaTime: 1 / 60) }
            for (node, before) in zip(effects.childNodes, still) {
                for column in 0..<4 { XCTAssertLessThan(simd_length(node.simdTransform[column] - before[column]), 0.0001) }
            }
        }
    }

    @MainActor
    func testStaticPreviewKeepsTheMeadowAndCameraAcrossCommandedMoves() throws {
        let view = CompanionSceneView()
        let coordinator = AnimalCompanionView.Coordinator()
        coordinator.attach(view)
        defer { coordinator.stop() }
        coordinator.update(species: .corgi, motion: .idle, interaction: 0,
                           reduceMotion: false, active: true, showsProps: true, staticHabitat: true)
        let root = try XCTUnwrap(view.scene?.rootNode)
        let field = try XCTUnwrap(root.childNode(withName: "companion-field", recursively: true))
        let pet = try XCTUnwrap(root.childNode(withName: "habitat-pet", recursively: true))
        coordinator.rotate(by: 0.6)
        coordinator.zoom(by: 1.5)
        let camera = try XCTUnwrap(view.pointOfView)
        let position = camera.simdWorldPosition
        let zoom = try XCTUnwrap(camera.camera?.orthographicScale)
        for (index, action) in [PetMotion.walking, .running, .jumping, .playing, .idle].enumerated() {
            coordinator.update(species: .corgi, motion: action, interaction: index + 1,
                               reduceMotion: false, active: true, showsProps: true, staticHabitat: true)
            for _ in 0..<90 { coordinator.advance(deltaTime: 1 / 60) }
            XCTAssertTrue(root.childNode(withName: "companion-field", recursively: true) === field)
            XCTAssertLessThan(simd_length(pet.simdPosition), 0.0001, "A catalogue action must not teleport into a roaming location")
            XCTAssertLessThan(simd_distance(camera.simdWorldPosition, position), 0.0001)
            XCTAssertEqual(camera.camera?.orthographicScale, zoom)
        }
    }
}
