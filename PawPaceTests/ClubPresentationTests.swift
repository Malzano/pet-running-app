import SwiftUI
import UIKit
import XCTest
@testable import PawPace

final class ClubPresentationTests: XCTestCase {
    @MainActor func testClubStatesAndForms() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = PawPacePrivateStorage(directoryURL: folder)
        let api = ClubTestAPI()
        let store = ClubStore(identity: ClubTestIdentity(), api: api, credentials: ClubTestCredentials(), storage: storage)
        let planner = PlannerStore(storage: storage, reminders: TestPlannerReminders())
        let pet = PetStore(snapshot: .starter)
        await store.refresh()
        try await capture(ClubView(store: store, planner: planner, petStore: pet), name: "club-overview")
        try await capture(NavigationStack { ClubDetailView(store: store, planner: planner, petStore: pet, clubID: ClubFixtures.clubID) }, name: "club-campsite")
        try await capture(NavigationStack { ClubDetailView(store: store, planner: planner, petStore: pet, clubID: ClubFixtures.clubID) }, name: "club-activities", offset: 660)
        try await capture(NavigationStack { ClubDetailView(store: store, planner: planner, petStore: pet, clubID: ClubFixtures.clubID) }, name: "club-members", offset: 1_200)
        try await capture(ClubCreateView(store: store), name: "club-create")
        try await capture(ClubJoinView(store: store), name: "club-join")
        try await capture(ClubEventEditor(store: store, clubID: ClubFixtures.clubID), name: "club-event")
        try await capture(NavigationStack { ClubDetailView(store: store, planner: planner, petStore: pet, clubID: ClubFixtures.clubID) }.environment(\.colorScheme, .dark), name: "club-dark")
        try await capture(NavigationStack { ClubDetailView(store: store, planner: planner, petStore: pet, clubID: ClubFixtures.clubID) }.environment(\.dynamicTypeSize, .accessibility3),
                          name: "club-large-text", size: CGSize(width: 375, height: 667), offset: 500)
        api.sendError = ClubAPIError(status: 0, message: "Offline")
        _ = store.enqueue(ClubCommand(action: "cheer", clubID: ClubFixtures.clubID, data: .init(recipientID: ClubFixtures.friend, kind: .wellDone)))
        await store.refresh()
        try await capture(ClubView(store: store, planner: planner, petStore: pet), name: "club-offline", offset: 430)
        let unconfiguredAPI = ClubTestAPI(); unconfiguredAPI.isConfigured = false
        let unconfigured = ClubStore(identity: ClubTestIdentity(), api: unconfiguredAPI, credentials: ClubTestCredentials(nil), storage: storage)
        try await capture(ClubView(store: unconfigured, planner: planner, petStore: pet), name: "club-unconfigured")
        try await capture(ClubView(store: unconfigured, planner: planner, petStore: pet), name: "club-connection", offset: 500)
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
