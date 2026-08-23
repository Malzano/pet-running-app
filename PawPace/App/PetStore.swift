import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class PetStore: ObservableObject {
    @Published private(set) var snapshot: PetSnapshot
    @Published var latestReaction: String?

    init(snapshot: PetSnapshot = PawPaceShared.loadSnapshot()) {
        self.snapshot = snapshot
    }

    func feed() {
        mutate(reaction: "Crunch! Snack power restored.") { $0.feed() }
    }

    func pet() {
        mutate(reaction: "That is exactly the right spot. Best human.") { $0.pet() }
    }

    func play() {
        mutate(reaction: "Ball acquired. Activating maximum zoomies!") { $0.play() }
    }

    func applyRun(_ summary: RunSummary) {
        mutate(reaction: "We did it! That trail officially belongs to us.") {
            $0.applyRun(distanceKilometers: summary.distanceKilometers, experienceEarned: summary.experienceEarned)
        }
    }

    func equip(_ accessory: String?) {
        mutate(reaction: accessory.map { "\($0) equipped. Adventure-ready!" }) {
            $0.equippedAccessory = accessory
            $0.lastUpdated = .now
        }
    }

    func clearReaction() {
        latestReaction = nil
    }

    private func mutate(reaction: String?, _ update: (inout PetSnapshot) -> Void) {
        var next = snapshot
        update(&next)
        snapshot = next
        latestReaction = reaction
        PawPaceShared.saveSnapshot(next)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

