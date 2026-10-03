import XCTest
import SceneKit
import UIKit
import ImageIO
@testable import PawPace

final class BuddyKeepsakeTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_300_000)

    func testAllBranchesBankProgressUntilChoiceAndAwardDistinctKeepsakes() throws {
        var stories = Set<String>(), items = Set<String>()
        for branch in AdventureBranch.allCases {
            var pet = PetSnapshot.starter
            pet.startExpedition(branch.trail)
            let id = try XCTUnwrap(pet.journey.expedition?.id)
            XCTAssertFalse(pet.chooseExpeditionBranch(branch, expeditionID: id))
            let coins = pet.coins, xp = pet.experience
            pet.journey.explore(seconds: branch.trail.seconds * 2, name: pet.name, companionID: pet.companionID, at: date)
            XCTAssertEqual(pet.journey.trailSeconds, branch.trail.seconds)
            XCTAssertEqual(pet.journey.memories.count, 0)
            pet = try roundTrip(pet)
            XCTAssertFalse(pet.chooseExpeditionBranch(branch, expeditionID: UUID()))
            XCTAssertTrue(pet.chooseExpeditionBranch(branch, expeditionID: id, at: date))
            let memory = try XCTUnwrap(pet.journey.memories.first)
            XCTAssertEqual(memory.id, id)
            XCTAssertEqual(memory.companionID, pet.companionID)
            XCTAssertEqual(memory.branch, branch)
            XCTAssertEqual(memory.date, date)
            XCTAssertNil(pet.journey.activeTrail)
            XCTAssertEqual(pet.journey.unlockedDecorations, [branch.decoration.rawValue])
            XCTAssertFalse(pet.chooseExpeditionBranch(branch, expeditionID: id))
            XCTAssertEqual(pet.journey.memories.count, 1)
            XCTAssertEqual(pet.coins, coins); XCTAssertEqual(pet.experience, xp)
            stories.insert(memory.story); items.insert(memory.decoration)
        }
        XCTAssertEqual(stories.count, 6); XCTAssertEqual(items.count, 6)
    }

    func testChoiceAtHalfwayIsPermanentAndRestDoesNotResetProgress() throws {
        var pet = PetSnapshot.starter
        pet.startExpedition(.meadow)
        let id = try XCTUnwrap(pet.journey.expedition?.id)
        pet.journey.explore(seconds: 1_800, name: pet.name, at: date)
        XCTAssertFalse(pet.chooseExpeditionBranch(.stars, expeditionID: id))
        XCTAssertTrue(pet.chooseExpeditionBranch(.stream, expeditionID: id))
        XCTAssertFalse(pet.chooseExpeditionBranch(.ribbons, expeditionID: id))
        pet.startExpedition(.camp)
        XCTAssertEqual(pet.journey.activeTrail, .meadow)
        pet = try roundTrip(pet)
        pet.journey.explore(seconds: 0, name: pet.name, at: date.addingTimeInterval(864_000))
        XCTAssertEqual(pet.journey.trailSeconds, 1_800)
        pet.journey.explore(seconds: 1_800, name: pet.name, at: date.addingTimeInterval(864_000))
        XCTAssertEqual(pet.journey.memories.first?.branch, .stream)
        pet.startExpedition(.meadow)
        XCTAssertNotEqual(pet.journey.expedition?.id, id)
    }

    func testEggCannotStartOrChooseAndYoungCompanionPausesExistingExpedition() throws {
        var egg = PetSnapshot.newPlayer(seed: 0)
        egg.startExpedition(.camp)
        XCTAssertNil(egg.journey.activeTrail)
        var pet = PetSnapshot.starter
        pet.startExpedition(.meadow)
        let id = try XCTUnwrap(pet.journey.expedition?.id)
        pet.journey.trailSeconds = 1_800
        pet.journey.waitingEggs = [PetLifecycle(seed: 0)]
        let adultID = pet.companionID
        pet.beginNextEgg()
        XCTAssertFalse(pet.chooseExpeditionBranch(.ribbons, expeditionID: id))
        pet.applyMovementGrowth(seconds: 600, activity: .walking, at: date)
        XCTAssertEqual(pet.journey.trailSeconds, 1_800)
        pet.visitCompanion(adultID)
        XCTAssertTrue(pet.chooseExpeditionBranch(.ribbons, expeditionID: id))
    }

    func testOldJourneyAndBondDecodeWithoutNewFieldsAndKeepOriginalStory() throws {
        var pet = PetSnapshot.starter
        pet.journey.activeTrail = .meadow
        pet.journey.memories = [AdventureMemory(id: UUID(), trail: .camp, companionName: "Old friend", date: date)]
        pet.journey.residents = [CompanionResident(pet)]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pet)) as? [String: Any])
        var journey = try XCTUnwrap(json["journey"] as? [String: Any])
        journey.removeValue(forKey: "expedition"); journey.removeValue(forKey: "habitatPlacements")
        json["journey"] = journey
        var bond = try XCTUnwrap(json["buddyBond"] as? [String: Any])
        for key in ["firstOutingAt", "firstHopAt", "firstDanceAt"] { bond.removeValue(forKey: key) }
        json["buddyBond"] = bond
        var decoded = try JSONDecoder().decode(PetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.buddyBond.firstOutingAt)
        XCTAssertEqual(decoded.journey.memories.first?.story, AdventureTrail.camp.story)
        XCTAssertEqual(decoded.journey.memories.first?.decoration, "Camp Glow")
        decoded.journey.explore(seconds: 3_600, name: pet.name, at: date)
        XCTAssertNil(decoded.journey.activeTrail, "Legacy expeditions finish with their original reward")
        XCTAssertEqual(decoded.journey.memories.count, 2)
        XCTAssertEqual(try roundTrip(decoded), decoded)
    }

    func testGardenRequiresEarnedItemsMovesWithoutDuplicatesAndPreservesEmptyLayout() throws {
        var pet = PetSnapshot.starter
        XCTAssertFalse(pet.placeDecoration(.flags, at: .left))
        pet.journey.unlockedDecorations = ["Trail Flags", "Glow Jar"]
        pet.equippedDecoration = "Trail Flags"
        XCTAssertEqual(pet.habitatPlacements, [HabitatPlacement(spot: .back, decoration: .flags)])
        XCTAssertTrue(pet.placeDecoration(.flags, at: .left))
        XCTAssertTrue(pet.placeDecoration(.glowJar, at: .right))
        XCTAssertTrue(pet.placeDecoration(.flags, at: .right))
        XCTAssertEqual(pet.habitatPlacements, [HabitatPlacement(spot: .right, decoration: .flags)])
        XCTAssertTrue(pet.placeDecoration(nil, at: .right))
        pet = try roundTrip(pet)
        XCTAssertEqual(pet.habitatPlacements, [], "Putting away the last item must not restore the legacy decoration")
        pet.journey.habitatPlacements = [.init(spot: .left, decoration: .flags), .init(spot: .right, decoration: .flags), .init(spot: .back, decoration: .cushion)]
        XCTAssertEqual(pet.habitatPlacements.count, 1, "Invalid unearned or duplicate placements never render")
    }

    func testMemoryBookRecordsRealMilestonesAndRetainsThemWithEachFriend() throws {
        var pet = PetSnapshot.newPlayer(seed: 0, at: date)
        XCTAssertTrue(pet.buddyMemories.isEmpty)
        pet.applyMovementGrowth(seconds: 1_800, activity: .walking, at: date)
        XCTAssertEqual(pet.buddyMemories.map(\.title), ["Hello, little one"])
        let firstOuting = date.addingTimeInterval(86_400)
        pet.applyMovementGrowth(seconds: 600, activity: .walking, at: firstOuting)
        pet.applyMovementGrowth(seconds: 600, activity: .walking, at: firstOuting)
        XCTAssertEqual(pet.buddyBond.firstOutingAt, firstOuting)
        XCTAssertEqual(pet.buddyMemories.filter { $0.title == "First outing together" }.count, 1)
        _ = pet.completeBuddyGame(BuddyPlayTests.finishedGame(.trickTrail, id: pet.companionID), at: firstOuting)
        XCTAssertEqual(pet.buddyMemories.filter { $0.title == "Our first trick trail" }.count, 1)
        let original = pet.companionID
        for i in 2...6 { pet.applyMovementGrowth(seconds: 3_600, activity: .walking, at: date.addingTimeInterval(Double(i) * 86_400)) }
        XCTAssertNotNil(pet.buddyBond.firstHopAt)
        let old = pet.buddyMemories
        pet.journey.waitingEggs = [PetLifecycle(seed: 1)]
        pet.beginNextEgg()
        XCTAssertEqual(pet.buddyMemories, old)
        XCTAssertFalse(pet.buddyMemories.contains { $0.companionID == pet.companionID })
        pet = try roundTrip(pet)
        pet.visitCompanion(original)
        XCTAssertEqual(pet.buddyBond.firstOutingAt, firstOuting)
    }

    func testLegacyMilestonesAreNotInventedAndUnknownCompanionsAreConcealed() {
        var pet = PetSnapshot.starter
        pet.companionAdultSeconds = 50_000
        XCTAssertTrue(pet.buddyMemories.isEmpty)
        pet.journey.memories = [AdventureMemory(id: UUID(), trail: .camp, companionName: "Hidden", date: date, companionID: UUID())]
        XCTAssertTrue(pet.buddyMemories.isEmpty)
    }

    func testAllSpeciesCanApproachEveryKeepsakeWithoutLeavingGarden() {
        for species in PetSpecies.allCases {
            for spot in HabitatSpot.allCases {
                for playful in [true, false] {
                    var roaming = CompanionRoaming(species: species)
                    roaming.request(.visitDecoration(SIMD2(spot.x, spot.z), playful: playful))
                    var reached = false
                    for _ in 0..<1_200 {
                        let pose = roaming.step(deltaTime: 1 / 60)
                        XCTAssertLessThanOrEqual(simd_length(pose.position / CompanionRoaming.fieldRadii), 1.001)
                        if roaming.behavior == .interacting {
                            reached = true
                            XCTAssertEqual(pose.action, playful ? .jumping : .idle)
                            break
                        }
                    }
                    XCTAssertTrue(reached, "\(species) must reach \(spot)")
                }
            }
        }
    }

    @MainActor func testPlacedKeepsakesExistInSceneAndReduceMotionKeepsCompanionStill() throws {
        let placements = zip(HabitatSpot.allCases, [HabitatDecoration.flags, .glowJar, .cushion]).map { HabitatPlacement(spot: $0, decoration: $1) }
        let field = CompanionField.make(placements: placements)
        for item in placements {
            let node = try XCTUnwrap(field.childNode(withName: "keepsake-\(item.spot.rawValue)", recursively: false))
            XCTAssertFalse(node.childNodes.isEmpty)
            XCTAssertEqual(node.position.x, item.spot.x); XCTAssertEqual(node.position.z, item.spot.z)
        }
        let view = CompanionSceneView()
        let coordinator = AnimalCompanionView.Coordinator()
        coordinator.attach(view)
        coordinator.update(species: .corgi, motion: .idle, interaction: 0, reduceMotion: true, active: true,
                           showsProps: true, roams: true, placements: placements)
        let pet = try XCTUnwrap(view.scene?.rootNode.childNode(withName: "habitat-pet", recursively: true))
        let before = pet.transform
        coordinator.visitDecoration(placements[0])
        XCTAssertTrue(SCNMatrix4EqualToMatrix4(pet.transform, before))
        coordinator.stop()
    }

    @MainActor func testPhotoIsResizedMetadataFreeAndSurvivesInvalidReplacement() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try MemoryPhotoStore(directoryURL: folder)
        let input = UIGraphicsImageRenderer(size: CGSize(width: 1_600, height: 800)).image { ctx in
            UIColor.systemGreen.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1_600, height: 800))
        }.pngData()!
        let id = UUID().uuidString
        let pixels = try XCTUnwrap(CGImageSourceCreateWithData(input as CFData, nil))
        let withMetadata = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(withMetadata, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImageFromSource(destination, pixels, 0, [kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 13.75, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 100.5, kCGImagePropertyGPSLongitudeRef: "E"
        ]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let originalSource = try XCTUnwrap(CGImageSourceCreateWithData(withMetadata, nil))
        let originalProperties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil) as? [String: Any])
        XCTAssertNotNil(originalProperties[kCGImagePropertyGPSDictionary as String])
        let saved = try store.save(withMetadata as Data, memoryID: id)
        let image = try XCTUnwrap(UIImage(data: saved))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 1_200)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(saved as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        XCTAssertThrowsError(try store.save(Data("bad".utf8), memoryID: id))
        XCTAssertEqual(try store.load(memoryID: id), saved)
        XCTAssertThrowsError(try store.save(input, memoryID: "../escape"))
        XCTAssertEqual(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        try store.remove(memoryID: id)
        XCTAssertNil(try store.load(memoryID: id))
    }

    private func roundTrip(_ pet: PetSnapshot) throws -> PetSnapshot {
        try JSONDecoder().decode(PetSnapshot.self, from: JSONEncoder().encode(pet))
    }
}
