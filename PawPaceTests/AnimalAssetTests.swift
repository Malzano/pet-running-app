import Metal
import SceneKit
import UIKit
import XCTest
import simd
@testable import PawPace

final class AnimalAssetTests: XCTestCase {
    func testEveryCompanionShipsWithAnIntactTexturedRig() throws {
        for species in PetSpecies.allCases {
            let url = try XCTUnwrap(
                Bundle.main.url(forResource: species.rawValue, withExtension: "scn"),
                "Missing bundled model for \(species.rawValue)"
            )
            let scene = try SCNScene(url: url)
            var skinnedNodes = [SCNNode]()
            scene.rootNode.enumerateChildNodes { node, _ in
                if node.skinner != nil { skinnedNodes.append(node) }
            }
            XCTAssertFalse(skinnedNodes.isEmpty, "\(species.rawValue) must move its own skeleton")
            for node in skinnedNodes {
                let skin = try XCTUnwrap(node.skinner)
                XCTAssertGreaterThan(skin.bones.count, 10)
                XCTAssertEqual(skin.boneInverseBindTransforms?.count, skin.bones.count)
                let vertices = try XCTUnwrap(skin.baseGeometry?.sources(for: .vertex).first)
                XCTAssertEqual(skin.boneWeights.vectorCount, vertices.vectorCount)
                XCTAssertEqual(skin.boneIndices.vectorCount, vertices.vectorCount)
                XCTAssertTrue(skin.bones.allSatisfy { $0.parent != nil })
                let material = try XCTUnwrap(skin.baseGeometry?.firstMaterial)
                XCTAssertNotNil(material.diffuse.contents, "Model texture must survive GLB conversion")
            }
            let bounds = scene.rootNode.boundingBox
            XCTAssertGreaterThan(bounds.max.y - bounds.min.y, 0.1)
            XCTAssertTrue(bounds.max.y.isFinite)
        }
    }

    func testEveryCompanionHasALightweightPortrait() {
        for species in PetSpecies.allCases {
            let image = UIImage(named: "pet-\(species.rawValue)")
            XCTAssertNotNil(image, "Watch and widgets need a portrait for \(species.rawValue)")
            XCTAssertGreaterThan(image?.size.width ?? 0, 100)
        }
    }

    @MainActor
    func testWalkingMovesTheLegsAndPosesDoNotAccumulate() throws {
        for species in PetSpecies.allCases {
            let rig = try XCTUnwrap(CompanionRig(species: species))
            let legName = try XCTUnwrap(rig.articulatedJointNames.leg)
            let leg = try XCTUnwrap(rig.scene.rootNode.childNode(withName: legName, recursively: true))
            rig.pose(time: 0.2, phase: 0.2, weights: SIMD4(1, 0, 0, 0))
            let walkingPose = leg.simdTransform
            rig.pose(time: 0.7, phase: 0.7, weights: SIMD4(1, 0, 0, 0))
            XCTAssertGreaterThan(simd_length(walkingPose.columns.1 - leg.simdTransform.columns.1), 0.001,
                                 "\(species.rawValue) must articulate its legs during a gait")
            for frame in 0..<120 {
                let t = Float(frame) / 60
                rig.pose(time: t, phase: t, weights: SIMD4(0, 1, 0, 0))
                rig.scene.rootNode.enumerateChildNodes { node, _ in
                    let q = node.simdOrientation.vector
                    XCTAssertTrue(q.x.isFinite && q.y.isFinite && q.z.isFinite && q.w.isFinite)
                }
            }
            rig.pose(time: 0.2, phase: 0.2, weights: SIMD4(1, 0, 0, 0))
            for column in 0..<4 {
                XCTAssertLessThan(simd_length(walkingPose[column] - leg.simdTransform[column]), 0.0001,
                                  "Replaying the same pose must not accumulate joint rotation")
            }
        }
    }

    @MainActor
    func testChangingToyActionDoesNotResetAJumpInFlight() throws {
        for species in PetSpecies.allCases {
            let rig = try XCTUnwrap(CompanionRig(species: species))
            rig.pose(time: 0.65, phase: 0.3, weights: SIMD4(0, 0, 1, 0), actionTime: 0.65, jumpTime: 0.65)
            let airborne = rig.jointPositions()
            rig.pose(time: 0.65, phase: 0.3, weights: SIMD4(0, 0, 1, 0), actionTime: 0, jumpTime: 0.65)
            let afterNewAction = rig.jointPositions()
            for (name, position) in airborne {
                let next = try XCTUnwrap(afterNewAction[name])
                XCTAssertLessThan(simd_distance(position, next), 0.0001,
                                  "Changing the toy clock must not teleport \(species.rawValue)'s \(name)")
            }
        }
    }

    @MainActor
    func testRenderEveryCompanionActionForVisualReview() throws {
        for species in PetSpecies.allCases {
            let rig = try XCTUnwrap(CompanionRig(species: species))
            rig.showsProps = true
            let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            renderer.scene = rig.scene
            renderer.pointOfView = rig.camera
            let samples: [(String, SIMD4<Float>, Float)] = [
                ("rest", .zero, 0), ("walk", SIMD4(1, 0, 0, 0), 0),
                ("jump", SIMD4(0, 0, 1, 0), 0), ("play", SIMD4(0, 0, 0, 1), 0),
                ("feed", .zero, 1)
            ]
            for (action, weights, feeding) in samples {
                rig.pose(time: 0.65, phase: 0.3, weights: weights, feeding: feeding)
                let image = renderer.snapshot(atTime: 0, with: CGSize(width: 512, height: 512), antialiasingMode: .multisampling4X)
                XCTAssertNotNil(image.cgImage)
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(species.rawValue)-\(action)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            if species.specialMoveName != nil {
                rig.pose(time: 2, phase: 0.3, weights: .zero, specialTime: 2, specialWeight: 1)
                let image = renderer.snapshot(atTime: 0, with: CGSize(width: 512, height: 512), antialiasingMode: .multisampling4X)
                XCTAssertNotNil(image.cgImage)
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(species.rawValue)-special"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
