import Foundation

/// Contains recorded values only. Recovery never infers active time while the
/// phone process was gone and never includes a raw GPS route.
struct PhoneWorkoutCheckpoint: Codable, Equatable {
    let state: PawPaceRunState

    init?(state: PawPaceRunState) {
        guard Self.isValid(state) else { return nil }
        self.state = state
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let state = try values.decode(PawPaceRunState.self, forKey: .state)
        guard let valid = Self(state: state) else {
            throw DecodingError.dataCorruptedError(forKey: .state, in: values, debugDescription: "Invalid interrupted phone workout")
        }
        self = valid
    }

    func pausedState(at date: Date = .now) -> PawPaceRunState? {
        guard Self.isValid(state), date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        var restored = state
        restored.phase = .paused
        restored.pauseStartedAt = state.phase == .paused ? (state.pauseStartedAt ?? state.updatedAt) : state.updatedAt
        restored.updatedAt = max(date, state.updatedAt)
        restored.endedAt = nil
        restored.isAwaitingPhoneConfiguration = false
        return restored
    }

    private static func isValid(_ state: PawPaceRunState) -> Bool {
        guard state.phase == .running || state.phase == .paused,
              state.workoutID != nil,
              let start = state.startedAt,
              start.timeIntervalSinceReferenceDate.isFinite,
              state.updatedAt.timeIntervalSinceReferenceDate.isFinite,
              state.updatedAt >= start,
              state.elapsedSeconds > 0,
              state.distanceKilometers.isFinite, state.distanceKilometers >= 0,
              state.activeEnergyKilocalories.isFinite, state.activeEnergyKilocalories >= 0,
              state.heartRate >= 0,
              !state.isAwaitingPhoneConfiguration
        else { return false }
        return true
    }
}
