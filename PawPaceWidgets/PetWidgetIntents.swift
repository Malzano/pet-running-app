import AppIntents
import Foundation
import WidgetKit

struct FeedPetIntent: AppIntent {
    static var title: LocalizedStringResource = "Feed Mochi"
    static var description = IntentDescription("Restore your companion’s energy and friendship.")

    func perform() async throws -> some IntentResult {
        var snapshot = PawPaceShared.loadSnapshot()
        snapshot.feed()
        PawPaceShared.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct PlayWithPetIntent: AppIntent {
    static var title: LocalizedStringResource = "Play with Mochi"
    static var description = IntentDescription("Play for friendship and a little XP.")

    func perform() async throws -> some IntentResult {
        var snapshot = PawPaceShared.loadSnapshot()
        snapshot.play()
        PawPaceShared.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct CheerPetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Cheer Mochi"

    func perform() async throws -> some IntentResult {
        var snapshot = PawPaceShared.loadSnapshot()
        snapshot.friendship = min(100, snapshot.friendship + 1)
        snapshot.mood = .excited
        snapshot.lastUpdated = .now
        PawPaceShared.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct ToggleRunPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or resume run"

    func perform() async throws -> some IntentResult {
        let isPaused = PawPaceShared.defaults.bool(forKey: PawPaceShared.runPausedKey)
        PawPaceShared.defaults.set(!isPaused, forKey: PawPaceShared.runPausedKey)
        NotificationCenter.default.post(name: .pawPaceToggleRun, object: nil)
        return .result()
    }
}

