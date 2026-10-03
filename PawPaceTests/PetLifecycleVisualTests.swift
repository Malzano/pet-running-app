import Metal
import SceneKit
import SwiftUI
import UIKit
import XCTest
import simd
@testable import PawPace

final class PetLifecycleVisualTests: XCTestCase {
    @MainActor
    func testEggIsAStationaryNestWithoutAnAnimalOrCareProps() throws {
        for species in PetSpecies.allCases {
            let rig = try XCTUnwrap(CompanionRig(species: species, lifeStage: .egg, variant: .aurora))
            rig.configureHabitat(roaming: true)
            rig.showsProps = true
            let egg = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "mystery-egg-shell", recursively: true))
            XCTAssertNil(rig.scene.rootNode.childNode(withName: "habitat-pet", recursively: true))
            XCTAssertNil(rig.scene.rootNode.childNode(withName: "genetic-sparkle", recursively: true), "Rarity stays secret until hatching")
            for name in ["play-ball", "food-bowl"] {
                let prop = rig.scene.rootNode.childNode(withName: name, recursively: true)
                XCTAssertTrue(prop == nil || prop!.isHidden)
            }
            rig.scene.rootNode.enumerateChildNodes { node, _ in
                XCTAssertNil(node.skinner, "An egg must not load the hidden animal's skin")
            }
            let initialPosition = egg.simdWorldPosition
            let initialOrientation = egg.simdWorldOrientation.vector
            var roaming = CompanionRoaming(species: species).pose
            for index in 0..<20 {
                roaming.position = SIMD2(Float(index) * 0.07, 0.5)
                roaming.yaw = Float(index)
                roaming.gaitDistance = Float(index) * 0.15
                rig.pose(time: Float(index), phase: Float(index), weights: SIMD4(0, 1, 1, 1), feeding: 1, roaming: roaming)
                XCTAssertLessThan(simd_distance(egg.simdWorldPosition, initialPosition), 0.00001)
                XCTAssertLessThan(simd_distance(egg.simdWorldOrientation.vector, initialOrientation), 0.00001)
            }
            let originalCamera = rig.camera.simdWorldPosition
            rig.setHabitatYaw(.pi / 2)
            XCTAssertGreaterThan(simd_distance(originalCamera, rig.camera.simdWorldPosition), 1)
            XCTAssertLessThan(simd_distance(egg.simdWorldPosition, initialPosition), 0.00001)
        }
    }

    @MainActor
    func testIncubationUpdatesReuseTheSceneAndHatchingReplacesIt() throws {
        let view = CompanionSceneView()
        let coordinator = AnimalCompanionView.Coordinator()
        coordinator.attach(view)
        defer { coordinator.stop() }
        coordinator.update(species: .corgi, motion: .idle, interaction: 0,
                           reduceMotion: false, active: true, showsProps: true, roams: true, lifeStage: .egg)
        let eggScene = try XCTUnwrap(view.scene)
        let egg = try XCTUnwrap(eggScene.rootNode.childNode(withName: "mystery-egg-shell", recursively: true))
        let before = egg.simdWorldPosition
        coordinator.guide(to: SIMD2(1, 0.5))
        for index in 1...20 {
            coordinator.update(species: .corgi, motion: .running, interaction: index,
                               reduceMotion: false, active: true, showsProps: true, roams: true, lifeStage: .egg)
            coordinator.advance(deltaTime: 1 / 30)
            XCTAssertTrue(view.scene === eggScene)
            XCTAssertFalse(view.isPlaying, "An egg does not need a continuous display clock")
            XCTAssertLessThan(simd_distance(egg.simdWorldPosition, before), 0.00001)
        }
        coordinator.update(species: .corgi, motion: .idle, interaction: 20,
                           reduceMotion: true, active: true, showsProps: true, roams: true,
                           lifeStage: .baby, variant: .mint)
        let babyScene = try XCTUnwrap(view.scene)
        XCTAssertFalse(babyScene === eggScene)
        XCTAssertNil(babyScene.rootNode.childNode(withName: "mystery-egg-shell", recursively: true))
        XCTAssertNotNil(babyScene.rootNode.childNode(withName: "habitat-pet", recursively: true))
        coordinator.update(species: .corgi, motion: .idle, interaction: 20,
                           reduceMotion: true, active: true, showsProps: true, roams: true,
                           lifeStage: .baby, variant: .mint)
        XCTAssertTrue(view.scene === babyScene)
    }

    @MainActor
    func testBabyMeshesAreSmallerAndKeepTheirFeetNearTheGroundAtFieldEdges() throws {
        let extremes: [SIMD2<Float>] = [SIMD2(1.35, 0), SIMD2(-1.35, 0), SIMD2(0, 0.85), SIMD2(0, -0.85)]
        for species in PetSpecies.allCases {
            let adult = try XCTUnwrap(CompanionRig(species: species))
            let baby = try XCTUnwrap(CompanionRig(species: species, lifeStage: .baby))
            let adultBounds = try meshBounds(adult.scene)
            let babyBounds = try meshBounds(baby.scene)
            let adultSize = adultBounds.maximum - adultBounds.minimum
            let babySize = babyBounds.maximum - babyBounds.minimum
            for axis in 0..<3 {
                XCTAssertGreaterThan(babySize[axis] / adultSize[axis], 0.50)
                XCTAssertLessThan(babySize[axis] / adultSize[axis], 0.80, "Baby silhouette must be visibly smaller")
            }
            XCTAssertEqual(babyBounds.minimum.y, adultBounds.minimum.y, accuracy: 0.035,
                           "Growth must not lift the mesh away from the ground")
            baby.configureHabitat(roaming: true)
            let pet = try XCTUnwrap(baby.scene.rootNode.childNode(withName: "habitat-pet", recursively: true))
            let feet = try footNames(species).map { try XCTUnwrap(baby.scene.rootNode.childNode(withName: $0, recursively: true)) }
            var restingPose = CompanionRoaming(species: species).pose
            restingPose.position = .zero
            restingPose.yaw = 0
            baby.pose(time: 0, phase: 0, weights: .zero, roaming: restingPose)
            let restHeights = feet.map { $0.simdWorldPosition.y }
            for start in extremes {
                // Each edge is a separate placement, not an impossible
                // instantaneous jump with feet pinned at the previous edge.
                baby.pose(time: 0, phase: 0, weights: .zero)
                let heading = atan2(-start.x, -start.y)
                var roaming = restingPose
                roaming.yaw = heading
                for frame in 0..<45 {
                    let distance = Float(frame) * 0.003
                    roaming.position = start + SIMD2(sin(heading), cos(heading)) * distance
                    roaming.gaitDistance = distance
                    baby.pose(time: Float(frame) / 30, phase: 0, weights: SIMD4(1, 0, 0, 0), roaming: roaming)
                    XCTAssertEqual(pet.simdWorldPosition.y, 0, accuracy: 0.00001)
                    XCTAssertEqual(pet.simdWorldPosition.x, roaming.position.x, accuracy: 0.00001)
                    XCTAssertEqual(pet.simdWorldPosition.z, roaming.position.y, accuracy: 0.00001)
                    let footLifts = zip(feet, restHeights).map { foot, restHeight in foot.simdWorldPosition.y - restHeight }
                    XCTAssertLessThan(try XCTUnwrap(footLifts.min()), 0.09, "A walking baby must retain ground contact")
                    XCTAssertGreaterThan(try XCTUnwrap(footLifts.min()), -0.045, "Baby paws must not sink through the field")
                    XCTAssertTrue(footLifts.allSatisfy(\.isFinite))
                }
            }
        }
    }

    @MainActor
    func testGeneticColorsTintTheTexturedMeshAndRareAccentsAreStatic() throws {
        let variants: [PetColorVariant] = [.classic, .mint, .peach, .lavender, .sky, .moonlight, .aurora]
        for variant in variants {
            let rig = try XCTUnwrap(CompanionRig(species: .corgi, lifeStage: .baby, variant: variant))
            var tintedMaterials: [SCNMaterial] = []
            var sparkleCount = 0
            rig.scene.rootNode.enumerateChildNodes { node, _ in
                if node.skinner != nil { tintedMaterials += node.geometry?.materials ?? [] }
                if node.name == "genetic-sparkle" {
                    sparkleCount += 1
                    XCTAssertTrue(node.animationKeys.isEmpty)
                    XCTAssertFalse(node.hasActions)
                }
            }
            XCTAssertFalse(tintedMaterials.isEmpty)
            for material in tintedMaterials {
                XCTAssertNotNil(material.diffuse.contents, "Genetic color must retain the original texture")
                let tint = try XCTUnwrap(material.multiply.contents as? UIColor)
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                XCTAssertTrue(tint.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
                if variant == .classic {
                    XCTAssertEqual(red + green + blue, 3, accuracy: 0.001)
                    XCTAssertNil(material.shaderModifiers?[.surface], "Classic keeps its original fur colors")
                } else {
                    XCTAssertNotNil(material.shaderModifiers?[.surface], "Variants neutralize the original orange fur before tinting")
                    XCTAssertGreaterThan(max(red, green, blue) - min(red, green, blue), 0.1,
                                         "The phenotype must produce a visible hue difference")
                }
            }
            XCTAssertEqual(sparkleCount, variant.isRare ? 3 : 0)
        }
    }

    @MainActor
    func testRenderGrowthStagesAndRarePortraitsForVisualReview() throws {
        let samples: [(String, PetLifeStage, PetColorVariant)] = [
            ("egg", .egg, .classic), ("baby-mint", .baby, .mint),
            ("adult-mint", .adult, .mint), ("adult-moonlight", .adult, .moonlight),
            ("adult-aurora", .adult, .aurora)
        ]
        for (name, stage, variant) in samples {
            let rig = try XCTUnwrap(CompanionRig(species: .corgi, lifeStage: stage, variant: variant))
            rig.configureHabitat(roaming: true)
            rig.pose(time: 0, phase: 0, weights: .zero)
            let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            renderer.scene = rig.scene
            renderer.pointOfView = rig.camera
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 640, height: 540), antialiasingMode: .multisampling4X)
            XCTAssertNotNil(image.cgImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "lifecycle-field-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)

            let portraitRenderer = ImageRenderer(content: AnimalPortraitView(species: .corgi, lifeStage: stage, variant: variant).frame(width: 160, height: 160))
            portraitRenderer.scale = 2
            let portrait = try XCTUnwrap(portraitRenderer.uiImage)
            let portraitAttachment = XCTAttachment(image: portrait)
            portraitAttachment.name = "lifecycle-portrait-\(name)"
            portraitAttachment.lifetime = .keepAlways
            add(portraitAttachment)
        }
    }

    private func footNames(_ species: PetSpecies) throws -> [String] {
        let profile = try XCTUnwrap(CompanionRigProfile.load(for: species))
        XCTAssertFalse(profile.legs.isEmpty, "Every companion needs actual foot joints")
        return profile.legs.map(\.foot)
    }

    @MainActor
    private func meshBounds(_ scene: SCNScene) throws -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        var minimum = SIMD3<Float>(repeating: .infinity)
        var maximum = SIMD3<Float>(repeating: -.infinity)
        var meshCount = 0
        scene.rootNode.enumerateChildNodes { node, _ in
            guard node.skinner != nil else { return }
            meshCount += 1
            let box = node.boundingBox
            for x in [box.min.x, box.max.x] {
                for y in [box.min.y, box.max.y] {
                    for z in [box.min.z, box.max.z] {
                        let point = node.simdConvertPosition(SIMD3(x, y, z), to: nil)
                        minimum = simd_min(minimum, point)
                        maximum = simd_max(maximum, point)
                    }
                }
            }
        }
        XCTAssertGreaterThan(meshCount, 0)
        return (minimum, maximum)
    }
}
