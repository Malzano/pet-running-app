import SwiftUI
import UIKit
import XCTest
@testable import PawPace

final class JourneyPresentationTests: XCTestCase {
    @MainActor
    func testRenderJourneysEverydayAndShareCards() async throws {
        var pet = PetSnapshot.starter
        pet.journey.activeTrail = .meadow
        for index in 1...3 {
            pet.applyRun(distanceKilometers: 0, experienceEarned: 120, elapsedSeconds: 3_600,
                         workoutID: UUID(), at: Date().addingTimeInterval(Double(-index * 86_400)))
        }
        try await capture(JourneyView(store: PetStore(snapshot: pet)), name: "journey-adult")
        try await capture(JourneyView(store: PetStore(snapshot: pet)), name: "journey-adult-memories", bottom: true)
        try await capture(NavigationStack { CompanionTricksView(pet: pet) }, name: "journey-tricks")
        pet.beginNextEgg()
        try await capture(JourneyView(store: PetStore(snapshot: pet)), name: "journey-family", bottom: true)
        try await capture(JourneyView(store: PetStore(snapshot: pet)).environment(\.dynamicTypeSize, .accessibility3),
                          name: "journey-accessibility", size: CGSize(width: 375, height: 667))
        try await capture(NavigationStack { EverydayActivityView(service: EverydayActivityService(), sync: {}) }, name: "journey-everyday")
        try await capture(CompanionShareView(pet: .starter), name: "journey-share-small", size: CGSize(width: 375, height: 667))
        for reveal in [false, true] {
            let card = CompanionShareCard(content: CompanionShareContent(pet: .starter, revealsCompanion: reveal))
            let renderer = ImageRenderer(content: card)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, 360)
            let attachment = XCTAttachment(image: image)
            attachment.name = reveal ? "journey-export-revealed" : "journey-export-secret"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private func capture<V: View>(_ view: V, name: String, bottom: Bool = false,
                                  size: CGSize = CGSize(width: 393, height: 852)) async throws {
        let bounds = CGRect(origin: .zero, size: size)
        let window = UIWindow(frame: bounds)
        let controller = UIHostingController(rootView: view.environment(\.colorScheme, .light))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        if bottom, let scroll = findScroll(controller.view) {
            scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top,
                scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
            try await Task.sleep(for: .milliseconds(150))
        }
        let image = UIGraphicsImageRenderer(bounds: bounds).image { _ in
            controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func findScroll(_ view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for child in view.subviews { if let found = findScroll(child) { return found } }
        return nil
    }
}
