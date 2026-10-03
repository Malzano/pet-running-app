import SceneKit
import XCTest
import simd
@testable import PawPace

final class AnimalMotionTests: XCTestCase {
    private struct Action {
        let name: String
        let weights: SIMD4<Float>
        var feeding: Float = 0
    }

    private let actions: [Action] = [
        Action(name: "idle", weights: .zero),
        Action(name: "walk", weights: SIMD4(1, 0, 0, 0)),
        Action(name: "run", weights: SIMD4(0, 1, 0, 0)),
        Action(name: "jump", weights: SIMD4(0, 0, 1, 0)),
        Action(name: "play", weights: SIMD4(0, 0, 0, 1)),
        Action(name: "feed", weights: .zero, feeding: 1),
        Action(name: "celebrate", weights: SIMD4(0, 0, 0, 1))
    ]

    @MainActor
    func testEveryActionArticulatesTheWeightedHeadAndRear() throws {
        for species in PetSpecies.allCases {
            let rig = try XCTUnwrap(CompanionRig(species: species))
            let names = try articulatedBones(species)
            let head = try XCTUnwrap(rig.scene.rootNode.childNode(withName: names.head, recursively: true))
            let rear = try XCTUnwrap(rig.scene.rootNode.childNode(withName: names.rear, recursively: true))
            for action in actions {
                var firstHead: simd_quatf?
                var firstRear: simd_quatf?
                var headRange: Float = 0
                var rearRange: Float = 0
                for sample in 0..<20 {
                    let time = Float(sample) / 10
                    rig.pose(time: time, phase: time * 1.15, weights: action.weights, feeding: action.feeding)
                    if let firstHead, let firstRear {
                        headRange = max(headRange, angleBetween(firstHead, head.simdOrientation))
                        rearRange = max(rearRange, angleBetween(firstRear, rear.simdOrientation))
                    } else {
                        firstHead = head.simdOrientation
                        firstRear = rear.simdOrientation
                    }
                }
                // Local rotations prove the actual weighted bones articulate;
                // translating or rocking the whole model cannot pass this test.
                XCTAssertGreaterThan(headRange, 0.04, "\(species) \(action.name) needs visible head articulation")
                XCTAssertGreaterThan(rearRange, 0.03, "\(species) \(action.name) needs tail/rear follow-through")
            }
        }
    }

    @MainActor
    func testSecondaryMotionHasNoSingleFrameRotationPops() throws {
        for species in PetSpecies.allCases {
            let rig = try XCTUnwrap(CompanionRig(species: species))
            let names = try articulatedBones(species)
            let head = try XCTUnwrap(rig.scene.rootNode.childNode(withName: names.head, recursively: true))
            let rear = try XCTUnwrap(rig.scene.rootNode.childNode(withName: names.rear, recursively: true))
            for action in actions {
                var previous: (head: simd_quatf, rear: simd_quatf)?
                for frame in 0..<120 {
                    let time = Float(frame) / 60
                    rig.pose(time: time, phase: time * 1.15, weights: action.weights, feeding: action.feeding)
                    if let previous {
                        XCTAssertLessThan(angleBetween(previous.head, head.simdOrientation), 0.12,
                                          "\(species) \(action.name) head must move continuously")
                        XCTAssertLessThan(angleBetween(previous.rear, rear.simdOrientation), 0.12,
                                          "\(species) \(action.name) rear must move continuously")
                    }
                    previous = (head.simdOrientation, rear.simdOrientation)
                }
            }
        }
    }

    @MainActor
    func testReducedMotionKeepsHeadAndRearStillAcrossInteractions() throws {
        for species in PetSpecies.allCases {
            let view = CompanionSceneView()
            let coordinator = AnimalCompanionView.Coordinator()
            coordinator.attach(view)
            defer { coordinator.stop() }
            coordinator.update(species: species, motion: .idle, interaction: 0,
                               reduceMotion: true, active: true, showsProps: true)
            let root = try XCTUnwrap(view.scene?.rootNode)
            let names = try articulatedBones(species)
            let head = try XCTUnwrap(root.childNode(withName: names.head, recursively: true))
            let rear = try XCTUnwrap(root.childNode(withName: names.rear, recursively: true))
            let stillHead = head.simdOrientation
            let stillRear = rear.simdOrientation
            let interactions: [PetMotion] = [.walking, .running, .jumping, .playing, .feeding, .celebrating, .special]
            for (index, motion) in interactions.enumerated() {
                coordinator.update(species: species, motion: motion, interaction: index + 1,
                                   reduceMotion: true, active: true, showsProps: true)
                XCTAssertLessThan(angleBetween(stillHead, head.simdOrientation), 0.001)
                XCTAssertLessThan(angleBetween(stillRear, rear.simdOrientation), 0.001)
                XCTAssertFalse(view.isPlaying)
            }
        }
    }

    private func articulatedBones(_ species: PetSpecies) throws -> (head: String, rear: String) {
        let profile = try XCTUnwrap(CompanionRigProfile.load(for: species))
        let head = try XCTUnwrap(profile.head.last?.name)
        let rear = try XCTUnwrap(profile.tail.first?.name ?? profile.torso.first?.name)
        return (head, rear)
    }

    private func angleBetween(_ first: simd_quatf, _ second: simd_quatf) -> Float {
        let a = simd_normalize(first.vector)
        let b = simd_normalize(second.vector)
        // Chord distance stays accurate near zero; acos(dot) magnifies tiny
        // normalization errors into apparent motion even for identical poses.
        let chord = min(simd_length(a - b), simd_length(a + b))
        return 4 * asin(min(chord * 0.5, 1))
    }
}
