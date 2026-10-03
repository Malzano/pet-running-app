import SwiftUI
import UIKit
import XCTest
@testable import PawPace

final class BuddyKeepsakePresentationTests: XCTestCase {
    @MainActor func testGardenMemoriesAndBranchingAdventureLayouts() async throws {
        var pet = PetSnapshot.starter
        pet.startExpedition(.meadow)
        pet.journey.trailSeconds = 1_800
        pet.journey.unlockedDecorations = Set(HabitatDecoration.allCases.map(\.rawValue))
        pet.journey.habitatPlacements = [.init(spot: .left, decoration: .flags), .init(spot: .back, decoration: .lanterns), .init(spot: .right, decoration: .glowJar)]
        pet.buddyBond.firstOutingAt = Date().addingTimeInterval(-172_800)
        pet.buddyBond.firstHopAt = Date().addingTimeInterval(-86_400)
        pet.journey.memories = [AdventureMemory(id: UUID(), trail: .camp, companionName: pet.name, date: .now,
                                                companionID: pet.companionID, branch: .clouds)]
        let store = PetStore(snapshot: pet)
        try await capture(JourneyView(store: store), name: "buddy-expedition-choice", offset: 490)
        try await capture(NavigationStack { HabitatArrangeView(store: store) }, name: "buddy-garden")
        try await capture(NavigationStack { HabitatArrangeView(store: store) }, name: "buddy-garden-placement", offset: 500)
        try await capture(NavigationStack { BuddyMemoryBookView(store: store) }, name: "buddy-memory-book")
        try await capture(NavigationStack { BuddyMemoryDetailView(memory: pet.buddyMemories[0]) }, name: "buddy-memory-detail")
        try await capture(NavigationStack { BuddyMemoryBookView(store: store) }.environment(\.colorScheme, .dark), name: "buddy-memory-dark")
        try await capture(NavigationStack { HabitatArrangeView(store: store) }.environment(\.dynamicTypeSize, .accessibility3),
                          name: "buddy-garden-large-text", size: CGSize(width: 375, height: 667), offset: 570)
        try await capture(NavigationStack { BuddyMemoryBookView(store: PetStore(snapshot: .newPlayer(seed: 0))) }, name: "buddy-memory-egg")
    }

    @MainActor private func capture<V: View>(_ view: V, name: String, size: CGSize = CGSize(width: 393, height: 852), offset: CGFloat = 0) async throws {
        let bounds = CGRect(origin: .zero, size: size)
        let window = UIWindow(frame: bounds)
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = bounds; controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(700))
        if offset > 0, let scroll = findScroll(controller.view) {
            scroll.setContentOffset(CGPoint(x: 0, y: min(offset, max(0, scroll.contentSize.height - scroll.bounds.height))), animated: false)
            try await Task.sleep(for: .milliseconds(150))
        }
        let screenshot = UIGraphicsImageRenderer(bounds: bounds).image { _ in controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor private func findScroll(_ view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for child in view.subviews { if let result = findScroll(child) { return result } }
        return nil
    }
}
