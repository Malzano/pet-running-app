import SceneKit
import UIKit
import XCTest
import simd
@testable import PawPace

final class AnimalRoamingIntegrationTests: XCTestCase {
    @MainActor
    func testFrontFacingWorkoutPortraitFitsEveryActualAnimal() throws {
        for species in PetSpecies.allCases {
            let rig = try XCTUnwrap(CompanionRig(species: species))
            rig.configurePortrait(facesViewer: true)
            XCTAssertEqual(rig.camera.position.x, 0, accuracy: 0.0001)
            var skins: [SkinnedSilhouette] = []
            rig.scene.rootNode.enumerateChildNodes { node, _ in
                if let skin = SkinnedSilhouette(node) { skins.append(skin) }
            }
            XCTAssertFalse(skins.isEmpty)
            for phase in stride(from: Float(0), to: 1, by: 0.2) {
                rig.pose(time: phase, phase: phase, weights: SIMD4(0, 1, 0, 0))
                for skin in skins {
                    let bounds = skin.projectedBounds(camera: rig.camera, aspect: 327.0 / 215)
                    XCTAssertGreaterThan(bounds.x, 0.01, "\(species) left")
                    XCTAssertGreaterThan(bounds.y, 0.01, "\(species) head")
                    XCTAssertLessThan(bounds.z, 0.99, "\(species) right")
                    XCTAssertLessThan(bounds.w, 0.99, "\(species) feet")
                }
            }
        }
    }

    @MainActor
    func testLoadedAnimalFollowsControllerPositionAndFacing() throws {
        for species in PetSpecies.allCases {
            let rig = try XCTUnwrap(CompanionRig(species: species))
            rig.configureHabitat(roaming: true)
            let animal = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "habitat-pet", recursively: true))
            var controller = CompanionRoaming(species: species)
            let start = controller.pose.position
            var largestTravel: Float = 0
            var headingRange: Float = 0
            for frame in 0..<360 {
                autoreleasepool {
                    if frame == 120 { controller.request(.moveTo(SIMD2(-1, -0.4))) }
                    let pose = controller.step(deltaTime: 1 / 30)
                    rig.pose(time: Float(frame) / 30, phase: 0, weights: SIMD4(1, 0, 0, 0), roaming: pose)
                    let actual = animal.simdWorldPosition
                    XCTAssertEqual(actual.x, pose.position.x, accuracy: 0.00001)
                    XCTAssertEqual(actual.z, pose.position.y, accuracy: 0.00001)
                    XCTAssertEqual(actual.y, 0, accuracy: 0.00001)
                    let forward = simd_normalize(animal.simdConvertVector(SIMD3(0, 0, 1), to: nil))
                    let expected = SIMD3<Float>(sin(pose.yaw), 0, cos(pose.yaw))
                    XCTAssertGreaterThan(simd_dot(forward, expected), 0.99999,
                                         "The mesh must face its actual direction of travel")
                    largestTravel = max(largestTravel, simd_distance(start, pose.position))
                    headingRange = max(headingRange, abs(pose.yaw - 0.25))
                }
            }
            XCTAssertGreaterThan(largestTravel, 0.3, "The real scene must travel, not only animate in place")
            XCTAssertGreaterThan(headingRange, 0.8, "The real scene must turn with the controller")
        }
    }

    @MainActor
    func testHabitatPropsStayInTheFieldWhileTheAnimalMoves() throws {
        for species in PetSpecies.allCases {
            let rig = try XCTUnwrap(CompanionRig(species: species))
            rig.configureHabitat(roaming: true)
            rig.showsProps = true
            let ball = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "play-ball", recursively: true))
            let bowl = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "food-bowl", recursively: true))
            var pose = CompanionRoaming(species: species).pose
            for (index, position) in [SIMD2<Float>(-0.9, 0.2), SIMD2(0.8, -0.3), SIMD2(0, 0.6)].enumerated() {
                pose.position = position
                pose.yaw = Float(index) * 1.7
                pose.gaitDistance = Float(index) * 0.4
                rig.pose(time: Float(index), phase: 0, weights: SIMD4(1, 0, 0, 0), roaming: pose)
                XCTAssertEqual(ball.simdWorldPosition.x, CompanionRoaming.ballPosition.x, accuracy: 0.00001)
                XCTAssertEqual(ball.simdWorldPosition.z, CompanionRoaming.ballPosition.y, accuracy: 0.00001)
                XCTAssertEqual(bowl.simdWorldPosition.x, CompanionRoaming.bowlPosition.x, accuracy: 0.00001)
                XCTAssertEqual(bowl.simdWorldPosition.z, CompanionRoaming.bowlPosition.y, accuracy: 0.00001)
            }
        }
    }

    @MainActor
    func testHabitatOrbitMovesOnlyTheCameraAndReturnsAfterAFullRevolution() throws {
        let rig = try XCTUnwrap(CompanionRig(species: .corgi))
        rig.configureHabitat(roaming: true)
        rig.showsProps = true
        let originalCamera = rig.camera.simdWorldTransform
        let originalPosition = rig.camera.simdWorldPosition
        let originalScene = sceneTransforms(rig.scene.rootNode)
        let target = SIMD3<Float>(0, 0.32, 0)

        rig.setHabitatYaw(.pi / 2)

        let rotatedPosition = rig.camera.simdWorldPosition
        XCTAssertGreaterThan(simd_distance(originalPosition, rotatedPosition), 1,
                             "A quarter-turn must reveal a different side of the field")
        XCTAssertEqual(rotatedPosition.y, originalPosition.y, accuracy: 0.00001)
        XCTAssertEqual(simd_distance(rotatedPosition, target), simd_distance(originalPosition, target),
                       accuracy: 0.00001, "Orbiting must retain the camera's distance from the field")
        let viewingDirection = simd_normalize(rig.camera.simdConvertVector(SIMD3(0, 0, -1), to: nil))
        XCTAssertGreaterThan(simd_dot(viewingDirection, simd_normalize(target - rotatedPosition)), 0.99999,
                             "The camera must keep looking at the center while it orbits")
        let rotatedScene = sceneTransforms(rig.scene.rootNode)
        XCTAssertEqual(rotatedScene.count, originalScene.count)
        for (identity, expected) in originalScene where identity != ObjectIdentifier(rig.camera) {
            let actual = try XCTUnwrap(rotatedScene[identity], "Orbiting must preserve every world node")
            assertTransform(actual, equals: expected)
        }

        rig.setHabitatYaw(2 * .pi)

        assertTransform(rig.camera.simdWorldTransform, equals: originalCamera)
        assertScene(rig.scene.rootNode, equals: originalScene)
    }

    @MainActor
    func testHabitatOrbitSurvivesViewportAndDecorationUpdates() throws {
        let rig = try XCTUnwrap(CompanionRig(species: .corgi))
        rig.configureHabitat(roaming: true)
        rig.setHabitatYaw(-.pi / 3)
        let selectedCamera = rig.camera.simdWorldTransform

        for size in [CGSize(width: 300, height: 500), CGSize(width: 600, height: 400)] {
            rig.resizeViewport(size)
            assertTransform(rig.camera.simdWorldTransform, equals: selectedCamera)
            rig.configureHabitat(roaming: true)
            assertTransform(rig.camera.simdWorldTransform, equals: selectedCamera)
        }

        rig.configureHabitat(roaming: true, decoration: "Camp Glow")
        assertTransform(rig.camera.simdWorldTransform, equals: selectedCamera)
        rig.configureHabitat(roaming: true, decoration: "Flower Meadow")
        assertTransform(rig.camera.simdWorldTransform, equals: selectedCamera)
    }

    @MainActor
    func testHabitatOrbitWrapsAnglesAndIgnoresNonfiniteInput() throws {
        let rig = try XCTUnwrap(CompanionRig(species: .corgi))
        rig.configureHabitat(roaming: true)
        rig.setHabitatYaw(.pi / 2)
        let selectedCamera = rig.camera.simdWorldTransform

        for yaw in [Float.pi / 2 + 4 * .pi, Float.pi / 2 - 4 * .pi] {
            rig.setHabitatYaw(yaw)
            assertTransform(rig.camera.simdWorldTransform, equals: selectedCamera)
        }
        for yaw in [Float.nan, .infinity, -.infinity] {
            rig.setHabitatYaw(yaw)
            assertTransform(rig.camera.simdWorldTransform, equals: selectedCamera)
        }
    }

    @MainActor
    func testActualSkinnedSilhouettesFitAtFieldExtremesAndJumpApex() throws {
        let extremes: [SIMD2<Float>] = [
            .zero, SIMD2(1.35, 0), SIMD2(-1.35, 0), SIMD2(0, 0.85), SIMD2(0, -0.85)
        ]
        for species in PetSpecies.allCases {
            let rig = try XCTUnwrap(CompanionRig(species: species))
            rig.configureHabitat(roaming: true)
            var skins: [SkinnedSilhouette] = []
            rig.scene.rootNode.enumerateChildNodes { node, _ in
                if let skin = SkinnedSilhouette(node) { skins.append(skin) }
            }
            XCTAssertFalse(skins.isEmpty, "Camera coverage must inspect the loaded animal mesh")
            var pose = CompanionRoaming(species: species).pose
            for position in extremes {
                for heading in [Float(0), .pi / 2, .pi, -.pi / 2] {
                    autoreleasepool {
                        pose.position = position
                        pose.yaw = heading
                        rig.pose(time: 0.5 / 0.76, phase: 0.3, weights: SIMD4(0, 0, 1, 0),
                                 jumpTime: 0.5 / 0.76, roaming: pose)
                        for skin in skins {
                            // Include a narrow phone habitat, not only the square
                            // preview. Positions include all deformed ears/feet/tail.
                            for aspect in [Float(0.78), 1] {
                                let bounds = skin.projectedBounds(camera: rig.camera, aspect: aspect)
                                XCTAssertGreaterThan(bounds.x, 0.01, "\(species) clips its left silhouette")
                                XCTAssertGreaterThan(bounds.y, 0.01, "\(species) clips its ears/head")
                                XCTAssertLessThan(bounds.z, 0.99, "\(species) clips its right silhouette")
                                XCTAssertLessThan(bounds.w, 0.99, "\(species) clips its feet")
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testHabitatZoomClampsAndPreservesTheWorldAndOrbitAcrossViewportChanges() throws {
        let rig = try XCTUnwrap(CompanionRig(species: .corgi))
        rig.configureHabitat(roaming: true)
        rig.setHabitatYaw(.pi / 3)
        let world = sceneTransforms(rig.scene.rootNode)
        let base = try XCTUnwrap(rig.camera.camera).orthographicScale

        rig.setHabitatZoom(100)
        XCTAssertEqual(rig.camera.camera?.orthographicScale ?? 0, base / CompanionCameraZoom.maximum, accuracy: 0.00001)
        let closeCamera = rig.camera.simdWorldTransform
        for invalid in [Double.nan, .infinity, -.infinity] {
            rig.setHabitatZoom(invalid)
            assertTransform(rig.camera.simdWorldTransform, equals: closeCamera)
            XCTAssertEqual(rig.camera.camera?.orthographicScale ?? 0, base / CompanionCameraZoom.maximum, accuracy: 0.00001)
        }
        rig.resizeViewport(CGSize(width: 320, height: 700))
        XCTAssertEqual(rig.camera.camera?.orthographicScale ?? 0, 2.85 * 1.08 / (320.0 / 700) / CompanionCameraZoom.maximum, accuracy: 0.00001)
        rig.configureHabitat(roaming: true)
        assertTransform(rig.camera.simdWorldTransform, equals: closeCamera)
        let currentWorld = sceneTransforms(rig.scene.rootNode)
        for (identity, expected) in world where identity != ObjectIdentifier(rig.camera) {
            assertTransform(try XCTUnwrap(currentWorld[identity]), equals: expected)
        }
        rig.setHabitatZoom(-100)
        XCTAssertEqual(rig.camera.camera?.orthographicScale ?? 0, 2.85 * 1.08 / (320.0 / 700) / CompanionCameraZoom.minimum, accuracy: 0.00001)
        rig.resizeViewport(CGSize(width: CGFloat.infinity, height: 1))
        XCTAssertTrue(try XCTUnwrap(rig.camera.camera).orthographicScale.isFinite)
    }

    @MainActor
    func testZoomedCameraFollowsTheCompanionWithoutMovingTheGarden() throws {
        for species in PetSpecies.allCases {
            let rig = try XCTUnwrap(CompanionRig(species: species))
            rig.configureHabitat(roaming: true, immersive: true)
            rig.resizeViewport(CGSize(width: 390, height: 760))
            rig.setHabitatYaw(-.pi / 4)
            rig.setHabitatZoom(CompanionCameraZoom.maximum)
            let garden = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "companion-field", recursively: true))
            let gardenTransform = garden.simdWorldTransform
            var pose = CompanionRoaming(species: species).pose
            let initialCamera = rig.camera.simdWorldPosition
            let initialPet = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "habitat-pet", recursively: true)).simdPosition
            for position in [SIMD2<Float>(1.35, 0.5), SIMD2(-1.35, -0.5), SIMD2(0, 0.85)] {
                pose.position = position
                rig.pose(time: 0, phase: 0, weights: .zero, roaming: pose)
                let actual = rig.camera.simdWorldPosition - initialCamera
                let expected = SIMD3(position.x, 0, position.y) - initialPet
                XCTAssertLessThan(simd_distance(actual, expected), 0.00001)
                let target = SIMD3<Float>(position.x, 0.65, position.y)
                let viewDirection = simd_normalize(rig.camera.simdConvertVector(SIMD3(0, 0, -1), to: nil))
                XCTAssertGreaterThan(simd_dot(viewDirection, simd_normalize(target - rig.camera.simdWorldPosition)), 0.99999)
                assertTransform(garden.simdWorldTransform, equals: gardenTransform)
            }
        }
    }

    @MainActor
    func testClosestImmersiveViewKeepsCompleteSkinnedPetsVisibleThroughOrbitAndJump() throws {
        for species in PetSpecies.allCases {
            let rig = try XCTUnwrap(CompanionRig(species: species))
            rig.configureHabitat(roaming: true, immersive: true)
            rig.setHabitatZoom(CompanionCameraZoom.maximum)
            var skins: [SkinnedSilhouette] = []
            rig.scene.rootNode.enumerateChildNodes { node, _ in
                if let skin = SkinnedSilhouette(node) { skins.append(skin) }
            }
            XCTAssertFalse(skins.isEmpty)
            let roaming = CompanionRoaming(species: species).pose
            for aspect in [Float(0.45), 1.4] {
                rig.resizeViewport(CGSize(width: CGFloat(aspect) * 700, height: 700))
                for angle in 0..<8 {
                    rig.setHabitatYaw(Float(angle) * .pi / 4)
                    for jumping in [false, true] {
                        rig.pose(time: 0.5 / 0.76, phase: 0.3, weights: jumping ? SIMD4(0, 0, 1, 0) : .zero,
                                 jumpTime: 0.5 / 0.76, roaming: roaming)
                        for skin in skins {
                            let bounds = skin.projectedBounds(camera: rig.camera, aspect: aspect)
                            XCTAssertGreaterThan(bounds.x, 0, "\(species) clips its left silhouette at closest zoom")
                            XCTAssertGreaterThan(bounds.y, 0, "\(species) clips jumping ears at closest zoom")
                            XCTAssertLessThan(bounds.z, 1, "\(species) clips its right silhouette at closest zoom")
                            XCTAssertLessThan(bounds.w, 1, "\(species) clips its paws at closest zoom")
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testCoordinatorRetainsPinchZoomAndResetsBothCameraAxesForAnEgg() throws {
        let view = CompanionSceneView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 760)
        let coordinator = AnimalCompanionView.Coordinator()
        coordinator.attach(view)
        defer { coordinator.stop() }
        var zoomReports: [Double] = []
        coordinator.onZoomChange = { zoomReports.append($0) }
        coordinator.update(species: .bunny, motion: .idle, interaction: 0, reduceMotion: true,
                           active: true, showsProps: true, roams: true, immersive: true, lifeStage: .egg)
        let scene = try XCTUnwrap(view.scene)
        let camera = try XCTUnwrap(view.pointOfView)
        let initialCamera = camera.simdWorldTransform
        let initialScale = try XCTUnwrap(camera.camera).orthographicScale
        coordinator.rotate(by: .pi / 2)
        coordinator.zoom(by: 2)
        XCTAssertEqual(zoomReports.last, 2)
        XCTAssertEqual(camera.camera?.orthographicScale ?? 0, initialScale / 2, accuracy: 0.00001)
        XCTAssertEqual(view.accessibilityValue, "Zoom 200 percent")
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1] { coordinator.zoom(by: invalid) }
        XCTAssertEqual(zoomReports.count, 1)
        coordinator.update(species: .bunny, motion: .idle, interaction: 0, reduceMotion: true,
                           active: true, showsProps: true, roams: true, immersive: true, lifeStage: .egg)
        XCTAssertTrue(view.scene === scene, "Gestures and unrelated UI updates must preserve the same egg scene")
        XCTAssertEqual(camera.camera?.orthographicScale ?? 0, initialScale / 2, accuracy: 0.00001)
        coordinator.resetCamera()
        assertTransform(camera.simdWorldTransform, equals: initialCamera)
        XCTAssertEqual(camera.camera?.orthographicScale ?? 0, initialScale, accuracy: 0.00001)
        XCTAssertEqual(zoomReports.last, 1)
        XCTAssertFalse(view.isPlaying, "Pinching an egg must not start an animation clock")
        coordinator.update(species: .bunny, motion: .idle, interaction: 0, reduceMotion: true,
                           active: true, showsProps: true, roams: true, cameraZoom: 1.8, immersive: true, lifeStage: .egg)
        XCTAssertEqual(camera.camera?.orthographicScale ?? 0, initialScale / 1.8, accuracy: 0.00001)
        coordinator.rotate(by: 1)
        coordinator.update(species: .bunny, motion: .idle, interaction: 0, reduceMotion: true,
                           active: true, showsProps: true, roams: true, cameraReset: 1,
                           cameraZoom: 1, immersive: true, lifeStage: .egg)
        assertTransform(camera.simdWorldTransform, equals: initialCamera)
        XCTAssertEqual(camera.camera?.orthographicScale ?? 0, initialScale, accuracy: 0.00001)
    }

    @MainActor
    func testPinchAndAccessibleZoomRemainIndependentOfSingleFingerOrbit() throws {
        let scrollView = UIScrollView()
        let view = CompanionSceneView()
        scrollView.addSubview(view)
        // SCNView also installs disabled gestures for its built-in camera
        // controller. Inspect the app's registered gestures, not the first
        // recognizer of each UIKit type in SceneKit's internal ordering.
        let pinches = view.gestureRecognizers?.compactMap { $0 as? UIPinchGestureRecognizer }
            .filter { $0.name == "PawPace garden zoom" } ?? []
        let pans = view.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }
            .filter { $0.name == "PawPace garden orbit" } ?? []
        XCTAssertEqual(pinches.count, 1)
        XCTAssertEqual(pans.count, 1)
        let pinch = try XCTUnwrap(pinches.first)
        let pan = try XCTUnwrap(pans.first)
        XCTAssertTrue(pinch.delegate === view)
        XCTAssertTrue(pan.delegate === view)
        XCTAssertFalse(pinch.isEnabled)
        XCTAssertEqual(pan.maximumNumberOfTouches, 1)
        view.onZoom = { _ in }
        view.onRotate = { _ in }
        XCTAssertTrue(pinch.isEnabled)
        XCTAssertTrue(pan.isEnabled)
        let actionNames = Set(view.accessibilityCustomActions?.map(\.name) ?? [])
        XCTAssertTrue(actionNames.isSuperset(of: ["Zoom in", "Zoom out", "Rotate garden left", "Rotate garden right", "Reset garden view"]))
        XCTAssertTrue(view.gestureRecognizer(pinch, shouldBeRequiredToFailBy: scrollView.panGestureRecognizer))
        XCTAssertTrue(view.gestureRecognizer(pan, shouldBeRequiredToFailBy: scrollView.panGestureRecognizer))
        view.onZoom = nil
        XCTAssertFalse(pinch.isEnabled)
        XCTAssertTrue(pan.isEnabled)
        XCTAssertFalse(view.accessibilityCustomActions?.contains(where: { $0.name == "Zoom in" }) ?? true)
    }

    @MainActor
    func testImmersiveMeadowExtendsBeyondTheOriginalIslandAndCanReturnToCompactFraming() throws {
        let rig = try XCTUnwrap(CompanionRig(species: .corgi, lifeStage: .egg))
        rig.configureHabitat(roaming: true)
        rig.resizeViewport(CGSize(width: 390, height: 760))
        let compactScale = try XCTUnwrap(rig.camera.camera).orthographicScale
        rig.configureHabitat(roaming: true, immersive: true)
        let immersiveScale = try XCTUnwrap(rig.camera.camera).orthographicScale
        XCTAssertLessThan(immersiveScale, compactScale * 0.65, "Full-screen Home must frame a substantially larger garden")
        let meadow = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "companion-field", recursively: true))
        XCTAssertTrue(meadow.childNodes.contains { $0.name == "habitat-ground" && $0.simdScale.x > 5 })
        rig.configureHabitat(roaming: true, immersive: false)
        XCTAssertEqual(rig.camera.camera?.orthographicScale ?? 0, compactScale, accuracy: 0.00001)
        let compactMeadow = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "companion-field", recursively: true))
        XCTAssertFalse(compactMeadow.childNodes.contains { $0.name == "habitat-ground" && $0.simdScale.x > 5 })
    }

    @MainActor
    func testReducedMotionAndBackgroundFreezeARealRoamingSceneWithoutCatchUp() throws {
        for species in PetSpecies.allCases {
            let view = CompanionSceneView()
            let coordinator = AnimalCompanionView.Coordinator()
            coordinator.attach(view)
            defer { coordinator.stop() }
            coordinator.update(species: species, motion: .idle, interaction: 0, reduceMotion: false,
                               active: true, showsProps: true, roams: true)
            coordinator.guide(to: SIMD2(1, 0.45))
            for _ in 0..<60 { autoreleasepool { coordinator.advance(deltaTime: 1 / 60) } }
            let root = try XCTUnwrap(view.scene?.rootNode)
            let animal = try XCTUnwrap(root.childNode(withName: "habitat-pet", recursively: true))
            let beforeFreeze = animal.simdWorldTransform
            coordinator.update(species: species, motion: .idle, interaction: 0, reduceMotion: true,
                               active: true, showsProps: true, roams: true)
            assertTransform(animal.simdWorldTransform, equals: beforeFreeze)
            let reducedPose = sceneTransforms(root)
            coordinator.guide(to: SIMD2(-1, -0.4))
            for _ in 0..<20 { autoreleasepool { coordinator.advance(deltaTime: 10) } }
            assertScene(root, equals: reducedPose)
            XCTAssertFalse(view.isPlaying)

            coordinator.update(species: species, motion: .idle, interaction: 0, reduceMotion: false,
                               active: false, showsProps: true, roams: true)
            let backgroundPose = sceneTransforms(root)
            coordinator.advance(deltaTime: 600)
            assertScene(root, equals: backgroundPose)
            XCTAssertFalse(view.isPlaying)

            coordinator.update(species: species, motion: .idle, interaction: 0, reduceMotion: false,
                               active: true, showsProps: true, roams: true)
            let beforeResume = animal.simdWorldPosition
            coordinator.advance(deltaTime: 600)
            XCTAssertLessThan(simd_distance(beforeResume, animal.simdWorldPosition), 0.035,
                              "Resuming must not catch up ten minutes of hidden movement")
            for _ in 0..<180 { autoreleasepool { coordinator.advance(deltaTime: 1 / 60) } }
            XCTAssertGreaterThan(simd_distance(beforeResume, animal.simdWorldPosition), 0.1,
                                 "The preserved scene must resume moving normally")
        }
    }

    @MainActor
    private func sceneTransforms(_ root: SCNNode) -> [ObjectIdentifier: simd_float4x4] {
        var result: [ObjectIdentifier: simd_float4x4] = [:]
        root.enumerateChildNodes { node, _ in result[ObjectIdentifier(node)] = node.simdWorldTransform }
        return result
    }

    @MainActor
    private func assertScene(_ root: SCNNode, equals frozen: [ObjectIdentifier: simd_float4x4]) {
        let current = sceneTransforms(root)
        XCTAssertEqual(current.count, frozen.count)
        for (identity, expected) in frozen {
            guard let actual = current[identity] else { XCTFail("A frozen scene replaced a node"); continue }
            assertTransform(actual, equals: expected)
        }
    }

    private func assertTransform(_ actual: simd_float4x4, equals expected: simd_float4x4) {
        for column in 0..<4 { XCTAssertLessThan(simd_length(actual[column] - expected[column]), 0.00001) }
    }
}

/// Evaluate the exported skin weights against current joint transforms. A static
/// geometry bounding box would miss a lifted ear, extended paw or jumping head.
@MainActor
private struct SkinnedSilhouette {
    private struct Influence { let index: Int; let weight: Float }
    private struct Vertex { let point: SIMD4<Float>; let influences: [Influence] }
    private let skinner: SCNSkinner
    private let vertices: [Vertex]
    private let inverseBind: [simd_float4x4]

    init?(_ node: SCNNode) {
        guard let skin = node.skinner,
              let positions = skin.baseGeometry?.sources(for: .vertex).first,
              let inverses = skin.boneInverseBindTransforms else { return nil }
        skinner = skin
        inverseBind = inverses.map { simd_float4x4($0.scnMatrix4Value) }
        let positionReader = SourceReader(positions)
        let weightReader = SourceReader(skin.boneWeights)
        let indexReader = SourceReader(skin.boneIndices)
        let influenceCount = skin.boneWeights.componentsPerVector
        vertices = (0..<positions.vectorCount).map { index in
            let p = SIMD4(positionReader.number(index, 0), positionReader.number(index, 1),
                          positionReader.number(index, 2), 1)
            let influences = (0..<influenceCount).compactMap { component -> Influence? in
                let weight = weightReader.number(index, component)
                return weight > 0 ? Influence(index: Int(indexReader.number(index, component)), weight: weight) : nil
            }
            return Vertex(point: p, influences: influences)
        }
    }

    func projectedBounds(camera: SCNNode, aspect: Float) -> SIMD4<Float> {
        let view = camera.simdWorldTransform.inverse
        let transforms = zip(skinner.bones, inverseBind).map { view * $0.simdWorldTransform * $1 }
        let scale = Float(camera.camera!.orthographicScale)
        var bounds = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)
        for vertex in vertices {
            var point = SIMD4<Float>.zero
            for influence in vertex.influences {
                point += transforms[influence.index] * vertex.point * influence.weight
            }
            let x = 0.5 + point.x / (2 * scale * aspect)
            let y = 0.5 - point.y / (2 * scale)
            bounds = SIMD4(min(bounds.x, x), min(bounds.y, y), max(bounds.z, x), max(bounds.w, y))
        }
        return bounds
    }

    private struct SourceReader {
        let data: Data
        let offset: Int
        let stride: Int
        let componentSize: Int
        let floats: Bool

        init(_ source: SCNGeometrySource) {
            data = source.data
            offset = source.dataOffset
            stride = source.dataStride
            componentSize = source.bytesPerComponent
            floats = source.usesFloatComponents
        }

        func number(_ index: Int, _ component: Int) -> Float {
            let location = offset + stride * index + componentSize * component
            return data.withUnsafeBytes { bytes in
                if floats {
                    return componentSize == 8
                        ? Float(bytes.loadUnaligned(fromByteOffset: location, as: Double.self))
                        : bytes.loadUnaligned(fromByteOffset: location, as: Float.self)
                }
                switch componentSize {
                case 1: return Float(bytes.loadUnaligned(fromByteOffset: location, as: UInt8.self))
                case 2: return Float(bytes.loadUnaligned(fromByteOffset: location, as: UInt16.self))
                default: return Float(bytes.loadUnaligned(fromByteOffset: location, as: UInt32.self))
                }
            }
        }
    }
}
