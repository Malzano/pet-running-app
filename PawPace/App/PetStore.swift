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
    @Published private(set) var storageMessage: String?
    private let persistsToSharedStorage: Bool
    var onSnapshotChange: ((PetSnapshot) -> Void)?

    init(snapshot: PetSnapshot? = nil) {
        self.persistsToSharedStorage = snapshot == nil
        self.snapshot = snapshot ?? PawPaceShared.loadSnapshot()
        self.storageMessage = snapshot == nil ? PawPaceShared.snapshotStorageError : nil
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
        guard snapshot.lifeStage != .egg else { latestReaction = "Your egg gathers warmth from workouts."; return }
        mutate(reaction: "Crunch! Snack power restored.") { $0.feed() }
    }

    func pet() {
        guard snapshot.lifeStage != .egg else { latestReaction = "A little friend is waiting inside."; return }
        mutate(reaction: "That is exactly the right spot. Best human.") { $0.pet() }
    }

    func play() {
        guard snapshot.lifeStage != .egg else { latestReaction = "Hatch your egg to play together."; return }
        mutate(reaction: "Ball acquired. Activating maximum zoomies!") { $0.play() }
    }

    func exploreWithBuddy() {
        guard snapshot.lifeStage != .egg else { return }
        mutate(reaction: nil) { $0.buddyBond.interact(.curious, at: .now) }
    }

    @discardableResult
    func completeBuddyGame(_ session: BuddyPlaySession) -> Bool {
        guard snapshot.lifeStage != .egg, snapshot.companionID == session.companionID,
              session.phase == .finished else { return false }
        let saved = mutate(reaction: "A little game, a little closer.") { _ = $0.completeBuddyGame(session) }
        return saved && snapshot.companionID == session.companionID && snapshot.buddyBond.completedSessions.contains(session.id)
    }

    func selectSpecies(_ species: PetSpecies) {
        guard snapshot.lifecycle == nil else { return }
        guard snapshot.species != species else { return }
        mutate(reaction: "Your \(species.displayName.lowercased()) is ready for an adventure!") {
            $0.selectSpecies(species)
        }
    }

    @discardableResult
    func applyRun(_ summary: RunSummary, rewardAliases: Set<UUID> = [], awardIfUnrecorded: Bool = true) -> Bool {
        let previousStage = snapshot.lifeStage
        let identities = rewardAliases.union([summary.id])
        let saved = mutate(reaction: "A little movement, a little closer.") {
            let alreadyRewarded = identities.contains(where: $0.hasRewardedWorkout)
            if !alreadyRewarded, awardIfUnrecorded {
                $0.applyRun(distanceKilometers: summary.distanceKilometers, experienceEarned: summary.experienceEarned,
                            elapsedSeconds: summary.elapsedSeconds, activity: summary.workoutConfiguration.activity,
                            workoutID: summary.id, at: summary.endedAt,
                            activeIntervals: WorkoutTiming.activeIntervals(startedAt: summary.startedAt,
                                endedAt: summary.endedAt, pauseIntervals: summary.pauseIntervals))
            }
            $0.rewardedWorkoutIDs.formUnion(identities)
        }
        guard saved else { return false }
        if previousStage == .egg, snapshot.lifeStage != .egg {
            latestReaction = "Your egg hatched! Meet your baby \(snapshot.species.displayName.lowercased())."
        } else if previousStage == .baby, snapshot.lifeStage == .adult {
            latestReaction = "\(snapshot.name) is all grown up. Your adventures shaped this little friend."
        }
        return true
    }

    func beginNextEgg() {
        guard !snapshot.hasYoungCompanion, !snapshot.journey.waitingEggs.isEmpty else { return }
        mutate(reaction: "A new beginning. Your grown friends are still at home.") { $0.beginNextEgg() }
    }

    func visitCompanion(_ id: UUID) {
        mutate(reaction: "Together again.") { $0.visitCompanion(id) }
    }

    func chooseTrail(_ trail: AdventureTrail) {
        guard snapshot.lifeStage == .adult, snapshot.journey.activeTrail == nil else { return }
        mutate(reaction: "A new adventure begins, at your own pace.") { $0.startExpedition(trail) }
    }

    func chooseBranch(_ branch: AdventureBranch, expeditionID: UUID) {
        mutate(reaction: nil) { _ = $0.chooseExpeditionBranch(branch, expeditionID: expeditionID) }
    }

    func placeDecoration(_ item: HabitatDecoration?, at spot: HabitatSpot) {
        mutate(reaction: nil) { _ = $0.placeDecoration(item, at: spot) }
    }

    func chooseWeeklyTarget(_ target: Int) {
        mutate(reaction: nil) { $0.journey.chooseWeeklyTarget(target, at: .now) }
    }

    @discardableResult
    func applyDailySteps(_ totals: [(date: Date, steps: Double)], epoch: String? = nil) -> Bool {
        mutate(reaction: nil) { pet in
            for total in totals.sorted(by: { $0.date < $1.date }) {
                pet.applyDailySteps(total.steps, at: total.date, epoch: epoch)
            }
        }
    }

    // Seed time exclusions from pre-upgrade journal entries without awarding
    // their rewards again. This survives journal deletion and app relaunch.
    @discardableResult
    func rememberExistingWorkouts(_ summaries: [RunSummary]) -> Bool {
        mutate(reaction: nil) { pet in
            _ = pet.journey.consumeWorkoutIntervals(summaries.flatMap {
                WorkoutTiming.activeIntervals(startedAt: $0.startedAt, endedAt: $0.endedAt, pauseIntervals: $0.pauseIntervals)
            })
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

    @discardableResult
    func rename(to proposedName: String) -> Bool {
        guard let name = PetName.normalized(proposedName) else { return false }
        guard snapshot.name != name else { return true }
        return mutate(reaction: "A name to grow into: \(name).") {
            $0.name = name
            $0.lastUpdated = .now
        }
    }

    func checkIn() {
        mutate(reaction: "A little hello goes a long way.") { $0.quests.checkIn(at: .now) }
    }

    func refreshQuests(at date: Date = .now) {
        mutate(reaction: nil) { $0.quests.prepareGifts(journey: $0.journey, at: date) }
    }

    func openQuestGift(_ id: String) -> QuestGift? {
        let saved = mutate(reaction: nil) { _ = $0.openQuestGift(id) }
        return saved ? snapshot.quests.gifts.first { $0.id == id && $0.openedAt != nil } : nil
    }

    func clearReaction() {
        latestReaction = nil
    }

    func reloadFromSharedStorage() {
        guard persistsToSharedStorage else { return }
        let latest = PawPaceShared.loadSnapshot()
        storageMessage = PawPaceShared.snapshotStorageError
        guard storageMessage == nil, latest != snapshot else { return }
        snapshot = latest
        onSnapshotChange?(latest)
    }

    @discardableResult
    private func mutate(reaction: String?, _ update: @escaping (inout PetSnapshot) -> Void) -> Bool {
        let next: PetSnapshot
        let apply: (inout PetSnapshot) -> Void = { pet in
            let before = pet
            update(&pet)
            pet.quests.prepareGifts(journey: pet.journey, at: .now)
            if pet != before {
                // Health and Watch deliveries can describe older activity. The
                // sync revision must reflect this mutation, not its workout day.
                pet.lastUpdated = max(Date(), before.lastUpdated.addingTimeInterval(0.000001))
            }
        }
        if persistsToSharedStorage {
            guard let saved = PawPaceShared.updateSnapshot(apply) else {
                storageMessage = PawPaceShared.snapshotStorageError
                return false
            }
            next = saved
        } else {
            var preview = snapshot
            apply(&preview)
            next = preview
        }
        snapshot = next
        storageMessage = nil
        latestReaction = reaction
        if persistsToSharedStorage { WidgetCenter.shared.reloadAllTimelines() }
        onSnapshotChange?(next)
        return true
    }
}
