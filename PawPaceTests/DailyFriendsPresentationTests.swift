import SwiftUI
import UIKit
import XCTest
@testable import PawPace

final class DailyFriendsPresentationTests: XCTestCase {
    @MainActor func testDailyAdventuresAndFriendsScreens() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = PawPacePrivateStorage(directoryURL: folder)
        var pet = PetSnapshot.starter
        let start = Calendar.current.date(byAdding: .day, value: -3, to: .now)!
        pet.quests.beganAt = start
        for offset in 0..<4 {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: start)!
            pet.quests.checkIn(at: date)
            if offset < 3 { _ = pet.journey.credit(workoutSeconds: 600, at: date) }
        }
        pet.quests.prepareGifts(journey: pet.journey, at: .now)
        let petStore = PetStore(snapshot: pet)
        try await capture(DailyQuestsView(store: petStore), "daily-quests")
        try await capture(DailyQuestsView(store: petStore), "daily-gifts", offset: 750)
        try await capture(DailyQuestsView(store: petStore).environment(\.colorScheme, .dark), "daily-dark")
        try await capture(DailyQuestsView(store: petStore).environment(\.dynamicTypeSize, .accessibility3), "daily-large-text")
        try await capture(HomeView(store: petStore, selectedTab: .constant(.home)), "daily-buddy")
        try await capture(HomeView(store: petStore, selectedTab: .constant(.home)), "daily-buddy-small", size: CGSize(width: 375, height: 667))
        let api = ClubTestAPI()
        api.value.social = FriendSnapshot(friendCode: "ABCDEF1234567890", connections: [
            .init(id: ClubFixtures.friend, alias: "Clover 128", status: .accepted, since: .now),
            .init(id: "20000000-0000-0000-0000-000000000003", alias: "Willow 302", status: .incoming, since: .now)], posts: [
                .init(id: UUID().uuidString, authorID: ClubFixtures.friend, alias: "Clover 128", workoutID: UUID().uuidString,
                    activity: .running, endedAt: .now, elapsedSeconds: 1842, distanceMeters: 5200, createdAt: .now, cheerCount: 2, cheeredByMe: false),
                .init(id: UUID().uuidString, authorID: ClubFixtures.account.id, alias: ClubFixtures.account.alias, workoutID: UUID().uuidString,
                    activity: .yoga, endedAt: .now, elapsedSeconds: 900, distanceMeters: nil, createdAt: .now, cheerCount: 1, cheeredByMe: false)], blocks: [])
        let store = ClubStore(identity: ClubTestIdentity(), api: api, credentials: ClubTestCredentials(), storage: storage)
        await store.refresh()
        let planner = PlannerStore(storage: storage, reminders: TestPlannerReminders())
        try await capture(ClubView(store: store, planner: planner, petStore: petStore), "friends-feed")
        try await capture(ClubView(store: store, planner: planner, petStore: petStore), "friends-feed-posts", offset: 310)
        try await capture(ClubView(store: store, planner: planner, petStore: petStore, initialSection: 1), "friends-list", offset: 320)
        try await capture(ClubView(store: store, planner: planner, petStore: petStore).environment(\.colorScheme, .dark), "friends-dark")
        try await capture(ClubView(store: store, planner: planner, petStore: petStore).environment(\.dynamicTypeSize, .accessibility3), "friends-large-text", offset: 360)
        let summary = RunSummary(id: UUID(), startedAt: .now.addingTimeInterval(-600), endedAt: .now, distanceMeters: 1450,
            elapsedSeconds: 600, averagePaceSecondsPerKilometer: 420, averageHeartRate: 145, experienceEarned: 60)
        try await capture(NavigationStack { FriendPostComposer(store: store, summary: summary) }, "friends-share")
    }

    @MainActor private func capture<V: View>(_ view: V, _ name: String, size: CGSize = CGSize(width: 393, height: 852), offset: CGFloat = 0) async throws {
        let bounds = CGRect(origin: .zero, size: size), window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = bounds; controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(700))
        func findScroll(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScroll($0) }.first
        }
        if offset > 0, let scroll = findScroll(controller.view) {
            scroll.setContentOffset(CGPoint(x: 0, y: min(offset, max(0, scroll.contentSize.height - scroll.bounds.height))), animated: false)
            try await Task.sleep(for: .milliseconds(150))
        }
        let image = UIGraphicsImageRenderer(bounds: bounds).image { _ in controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
