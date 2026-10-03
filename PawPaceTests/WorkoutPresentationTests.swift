import SwiftUI
import UIKit
import CoreLocation
import XCTest
@testable import PawPace

final class WorkoutPresentationTests: XCTestCase {
    @MainActor
    func testFriendlyWorkoutAndRouteRecap() async throws {
        let storage = PawPacePrivateStorage(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let tracker = RunTracker(healthKit: HealthKitService(), petSnapshot: { .starter },
            watchConnectivity: PhoneWatchConnectivityService(), privateStorage: storage)
        defer { tracker.reset(); try? FileManager.default.removeItem(at: storage.directoryURL) }
        tracker.configure(WorkoutConfiguration(activity: .yoga))
        tracker.start(syncToWatch: false)
        var state = tracker.currentRunState
        state.workoutConfiguration = WorkoutConfiguration(activity: .running)
        state.elapsedSeconds = 732
        state.distanceKilometers = 1.65
        state.updatedAt = .now
        XCTAssertTrue(tracker.applyWatchState(state, allowWorkoutAdoption: true))
        func view(_ pet: PetSnapshot = .starter) -> some View {
            RunView(tracker: tracker, pet: pet, onStart: {}, onFinish: {})
        }
        try await capture(view(), name: "friendly-running")
        try await capture(view(), name: "friendly-running-small", size: CGSize(width: 375, height: 667))
        try await capture(view(), name: "friendly-running-dark", colorScheme: .dark)
        try await capture(view().environment(\.dynamicTypeSize, .accessibility3), name: "friendly-running-large-text")
        try await capture(view(.newPlayer(seed: 42)), name: "friendly-mystery-egg")
        let points = [CLLocation(latitude: 13.7300, longitude: 100.5400),
                      CLLocation(latitude: 13.7304, longitude: 100.5406),
                      CLLocation(latitude: 13.7308, longitude: 100.5408),
                      CLLocation(latitude: 13.7312, longitude: 100.5403)]
        tracker.locationManager(CLLocationManager(), didUpdateLocations: points)
        let summary = RunSummary(id: try XCTUnwrap(state.workoutID), startedAt: .now.addingTimeInterval(-732),
            endedAt: .now, distanceMeters: 1_650, elapsedSeconds: 732, averagePaceSecondsPerKilometer: 443,
            averageHeartRate: nil, experienceEarned: 73)
        let route = tracker.recordedRoute(for: summary)
        XCTAssertEqual(route.count, points.count)
        let unrelated = RunSummary(id: UUID(), startedAt: summary.startedAt, endedAt: summary.endedAt,
            distanceMeters: 0, elapsedSeconds: 1, averagePaceSecondsPerKilometer: 0, averageHeartRate: nil, experienceEarned: 0)
        XCTAssertTrue(tracker.recordedRoute(for: unrelated).isEmpty)
        let encoded = String(decoding: try JSONEncoder().encode(summary), as: UTF8.self)
        XCTAssertFalse(encoded.contains("latitude"))
        XCTAssertFalse(encoded.contains("longitude"))
        tracker.pause(syncToWatch: false)
        try await capture(view(), name: "friendly-paused")
        try await capture(RunSummaryView(summary: summary, pet: .starter, route: route) {}, name: "friendly-route-recap", scrollOffset: 360)
        try await capture(RunSummaryView(summary: summary, pet: .starter) {}, name: "friendly-no-route", scrollOffset: 320)
        tracker.reset()
        XCTAssertTrue(tracker.recordedRoute(for: summary).isEmpty)
    }
    func testEveryWorkoutHasAnAvailableSystemSymbol() {
        for activity in WorkoutActivity.allCases {
            XCTAssertNotNil(UIImage(systemName: activity.symbol), "Missing icon for \(activity.displayName)")
        }
    }

    /// Keep native screenshots in the test result for reviewing small-screen
    /// layout, swim settings, and workouts that have no distance component.
    @MainActor
    func testRenderWorkoutScreensForVisualReview() async throws {
        let model = AppModel()
        model.selectedTab = .run
        for activity in [WorkoutActivity.running, .swimming, .yoga, .swimBikeRun] {
            model.runTracker.configure(WorkoutConfiguration(activity: activity))
            try await capture(AppRootView(model: model, enablesWelcome: false), name: "workout-\(activity.rawValue)")
        }
        try await capture(WorkoutPickerView(selection: .running) { _ in }, name: "workout-catalog")
        model.selectedTab = .home
        try await capture(AppRootView(model: model, enablesWelcome: false), name: "workout-home")
        let summary = RunSummary(
            id: UUID(), startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_001_800),
            distanceMeters: 0, elapsedSeconds: 1_800,
            averagePaceSecondsPerKilometer: 0, averageHeartRate: nil,
            experienceEarned: 180, workoutConfiguration: WorkoutConfiguration(activity: .yoga)
        )
        try await capture(RunSummaryView(summary: summary, pet: .starter) {}, name: "workout-yoga-summary")
    }

    @MainActor
    func testRenderReleaseSurfacesForVisualReview() async throws {
        let egg = PetSnapshot.newPlayer(seed: 42)
        @MainActor func home(_ pet: PetSnapshot) -> some View {
            TabView {
                HomeView(store: PetStore(snapshot: pet), selectedTab: .constant(.home))
                    .tabItem { Label("Home", systemImage: "house") }
            }
            .tint(PawTheme.adventureBlue)
            .foregroundStyle(PawTheme.ink)
        }
        try await capture(home(egg), name: "release-home-egg")
        try await capture(home(.starter), name: "release-home-small", size: CGSize(width: 375, height: 667))
        try await capture(home(.starter), name: "release-home-dark", colorScheme: .dark)
        try await capture(home(egg).environment(\.dynamicTypeSize, .accessibility3),
                          name: "release-home-accessibility")
        try await capture(WelcomeView {}, name: "release-welcome-small", size: CGSize(width: 375, height: 667))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = WorkoutHistoryStore(fileURL: directory.appendingPathComponent("journal.json"))
        try await capture(SettingsView(store: PetStore(snapshot: egg), healthKit: HealthKitService(), history: history),
                          name: "release-settings")
        try await capture(NavigationStack { WorkoutHistoryView(history: history) }, name: "release-journal-empty")
    }

    @MainActor
    private func capture<V: View>(_ view: V, name: String,
                                 size: CGSize = CGSize(width: 393, height: 852),
                                 colorScheme: ColorScheme = .light, scrollOffset: CGFloat = 0) async throws {
        let bounds = CGRect(origin: .zero, size: size)
        let window = UIWindow(frame: bounds)
        let controller = UIHostingController(rootView: view.environment(\.colorScheme, colorScheme))
        window.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(800))
        if scrollOffset > 0 {
            func scrollView(in view: UIView) -> UIScrollView? {
                if let scroll = view as? UIScrollView { return scroll }
                return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
            }
            scrollView(in: controller.view)?.setContentOffset(CGPoint(x: 0, y: scrollOffset), animated: false)
            try await Task.sleep(for: .milliseconds(500))
        }
        let image = UIGraphicsImageRenderer(bounds: bounds).image { _ in
            controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        XCTAssertNotNil(image.cgImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
