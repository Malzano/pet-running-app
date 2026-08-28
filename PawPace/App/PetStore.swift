import Foundation
import SwiftUI
import WidgetKit

private let petSnapshotChangedCallback: CFNotificationCallback = { _, observer, _, _, _ in
    guard let observer else { return }
    let store = Unmanaged<PetStore>.fromOpaque(observer).takeUnretainedValue()
    Task { @MainActor in
        store.reloadFromSharedStorage()
    }
}

@MainActor
final class PetStore: ObservableObject {
    @Published private(set) var snapshot: PetSnapshot
    @Published var latestReaction: String?
    var onSnapshotChange: ((PetSnapshot) -> Void)?

    init(snapshot: PetSnapshot = PawPaceShared.loadSnapshot()) {
        self.snapshot = snapshot
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            petSnapshotChangedCallback,
            PawPaceShared.snapshotChangedDarwinName as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(PawPaceShared.snapshotChangedDarwinName as CFString),
            nil
        )
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

    func equipDecoration(_ decoration: String) {
        mutate(reaction: "\(decoration) is ready for our next adventure!") {
            $0.equippedDecoration = decoration
            $0.lastUpdated = .now
        }
    }

    func clearReaction() {
        latestReaction = nil
    }

    func reloadFromSharedStorage() {
        let latest = PawPaceShared.loadSnapshot()
        guard latest != snapshot else { return }
        snapshot = latest
        onSnapshotChange?(latest)
    }

    private func mutate(reaction: String?, _ update: (inout PetSnapshot) -> Void) {
        var next = snapshot
        update(&next)
        snapshot = next
        latestReaction = reaction
        PawPaceShared.saveSnapshot(next)
        WidgetCenter.shared.reloadAllTimelines()
        onSnapshotChange?(next)
    }
}
