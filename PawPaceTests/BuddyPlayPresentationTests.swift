import SwiftUI
import UIKit
import XCTest
@testable import PawPace

final class BuddyPlayPresentationTests: XCTestCase {
    @MainActor
    func testRenderPersonalityGamesAndSpoilerFreeEgg() async throws {
        let store = PetStore(snapshot: .starter)
        try await capture(NavigationStack { BuddyPlayView(store: store) }, name: "buddy-personality")
        for game in BuddyGame.allCases {
            try await capture(BuddyGameView(store: store, game: game), name: "buddy-\(game.rawValue)")
        }
        var hidden = BuddyPlaySession(game: .hideAndSeek, companionID: store.snapshot.companionID)
        hidden.ready()
        try await capture(BuddyGameView(store: store, game: .hideAndSeek, session: hidden), name: "buddy-hidden")
        var trick = BuddyPlaySession(game: .trickTrail, companionID: store.snapshot.companionID)
        trick.ready()
        try await capture(BuddyGameView(store: store, game: .trickTrail, session: trick), name: "buddy-practice")
        let won = BuddyPlayTests.finishedGame(.fetch, id: store.snapshot.companionID)
        try await capture(BuddyGameView(store: store, game: .fetch, session: won), name: "buddy-game-finished")
        try await capture(NavigationStack { BuddyPlayView(store: PetStore(snapshot: .newPlayer(seed: 999))) }, name: "buddy-egg-locked")
        try await capture(BuddyGameView(store: store, game: .hideAndSeek).environment(\.dynamicTypeSize, .accessibility3),
                          name: "buddy-game-accessibility", size: CGSize(width: 375, height: 667), bottom: true)
        try await capture(NavigationStack { BuddyPlayView(store: store) }.environment(\.colorScheme, .dark), name: "buddy-play-dark", bottom: true)
        XCTAssertTrue(store.completeBuddyGame(BuddyPlayTests.finishedGame(.trickTrail, id: store.snapshot.companionID)))
        try await capture(NavigationStack { BuddyPlayView(store: store) }, name: "buddy-learned-routine", bottom: true)
        try await capture(NavigationStack { BuddyRoutineView(pet: store.snapshot) }, name: "buddy-routine-practice")
    }

    @MainActor private func capture<V: View>(_ view: V, name: String, size: CGSize = CGSize(width: 393, height: 852), bottom: Bool = false) async throws {
        let bounds = CGRect(origin: .zero, size: size)
        let window = UIWindow(frame: bounds)
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = bounds; controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(700))
        if bottom, let scroll = findScroll(controller.view) {
            scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top,
                scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
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
