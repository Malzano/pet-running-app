import AppIntents
import Foundation
import WidgetKit

struct FeedPetIntent: AppIntent {
    static var title: LocalizedStringResource = "Feed your companion"
    static var description = IntentDescription("Restore your companion’s energy and friendship.")

    func perform() async throws -> some IntentResult {
        let saved = PawPaceShared.updateSnapshot { snapshot in
            guard snapshot.lifeStage != .egg else { return }
            snapshot.feed()
        }
        guard saved != nil else { throw CompanionSaveError.unavailable }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct PlayWithPetIntent: AppIntent {
    static var title: LocalizedStringResource = "Play with your companion"
    static var description = IntentDescription("Play for friendship and a little XP.")

    func perform() async throws -> some IntentResult {
        let saved = PawPaceShared.updateSnapshot { snapshot in
            guard snapshot.lifeStage != .egg else { return }
            snapshot.play()
        }
        guard saved != nil else { throw CompanionSaveError.unavailable }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct CheerPetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Cheer your companion"

    func perform() async throws -> some IntentResult {
        let saved = PawPaceShared.updateSnapshot { snapshot in
            guard snapshot.lifeStage != .egg else { return }
            snapshot.friendship = min(100, snapshot.friendship + 1)
            snapshot.mood = .excited
            snapshot.lastUpdated = .now
        }
        guard saved != nil else { throw CompanionSaveError.unavailable }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct ToggleRunPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or resume workout"

    func perform() async throws -> some IntentResult {
        let isPaused = PawPaceShared.defaults.bool(forKey: PawPaceShared.runPausedKey)
        PawPaceShared.defaults.set(!isPaused, forKey: PawPaceShared.runPausedKey)
        NotificationCenter.default.post(name: .pawPaceToggleRun, object: nil)
        return .result()
    }
}


private enum CompanionSaveError: LocalizedError {
    case unavailable
    var errorDescription: String? {
        "Your companion could not be saved. Open PawPace and try again."
    }
}
