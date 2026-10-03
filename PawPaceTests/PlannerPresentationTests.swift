import SwiftUI
import UIKit
import XCTest
@testable import PawPace

final class PlannerPresentationTests: XCTestCase {
    @MainActor
    func testRenderPlannerEmptyPopulatedEditorAndAccessibility() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("planner-render-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PlannerStore(storage: PawPacePrivateStorage(directoryURL: directory), reminders: TestPlannerReminders())
        let history = WorkoutHistoryStore(fileURL: directory.appendingPathComponent("history.json"))
        let pet = PetStore(snapshot: .newPlayer())
        try await capture(PlannerView(planner: store, history: history, petStore: pet), name: "planner-empty")
        var plan = PlannedActivity(title: "An evening wander", scheduledAt: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now)!, reminderMinutesBefore: 10)
        XCTAssertTrue(store.save(plan))
        try await capture(PlannerView(planner: store, history: history, petStore: pet), name: "planner-today")
        try await capture(PlannerEditorView(plan: plan, planner: store, history: history), name: "planner-editor")
        try await capture(PlannerView(planner: store, history: history, petStore: pet).environment(\.dynamicTypeSize, .accessibility3), name: "planner-accessibility", size: CGSize(width: 375, height: 667))
        try await capture(PlannerView(planner: store, history: history, petStore: pet).environment(\.dynamicTypeSize, .accessibility3), name: "planner-accessibility-bottom", size: CGSize(width: 375, height: 667), bottom: true)
        plan.isRestDay = true
        XCTAssertTrue(store.save(plan))
        try await capture(PlannerView(planner: store, history: history, petStore: pet).environment(\.colorScheme, .dark), name: "planner-rest-dark")
    }

    @MainActor
    private func capture<V: View>(_ view: V, name: String, size: CGSize = CGSize(width: 393, height: 852), bottom: Bool = false) async throws {
        let bounds = CGRect(origin: .zero, size: size)
        let window = UIWindow(frame: bounds)
        let controller = UIHostingController(rootView: view)
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
        let image = UIGraphicsImageRenderer(bounds: bounds).image { _ in controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true) }
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
