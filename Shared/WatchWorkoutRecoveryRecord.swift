import Foundation

/// The Watch's launch identity and workout configuration travel together in one
/// protected, no-backup save. Optional identity fields preserve recovery from a
/// partially written legacy preference set; HealthKit supplies the same fallback
/// values as it did before this migration.
struct WatchWorkoutRecoveryRecord: Codable, Equatable {
    var workoutID: UUID?
    var startedAt: Date?
    var awaitingPhoneBinding: Bool
    var configuration: WorkoutConfiguration?
    var multisportLegIndex: Int
    var activitySegments: [WorkoutActivitySegment]
}

struct WatchWorkoutRecoveryStore {
    static let fileName = "watch-workout-recovery-v1.json"
    private let storage: PawPacePrivateStorage
    private let legacyDefaults: UserDefaults

    init(storage: PawPacePrivateStorage, legacyDefaults: UserDefaults) {
        self.storage = storage
        self.legacyDefaults = legacyDefaults
    }

    func load() throws -> WatchWorkoutRecoveryRecord? {
        if let record = try storage.load(WatchWorkoutRecoveryRecord.self, named: Self.fileName) {
            removeLegacyMetadata()
            return record
        }
        guard let record = try readLegacyMetadata() else { return nil }
        try storage.save(record, named: Self.fileName)
        // A failed encode, file write, or backup exclusion leaves all legacy
        // keys intact. Only the successfully written record supersedes them.
        removeLegacyMetadata()
        return record
    }

    func save(_ record: WatchWorkoutRecoveryRecord) throws {
        // Validate/migrate an existing recovery record before replacing it. A
        // corrupt legacy record must never disappear behind a new workout ID.
        _ = try load()
        try storage.save(record, named: Self.fileName)
        removeLegacyMetadata()
    }

    func clear() throws {
        // Completion can retire a readable recovery record; an unreadable save
        // needs recovery first, even when HealthKit reports no active session.
        _ = try load()
        try storage.remove(named: Self.fileName)
        removeLegacyMetadata()
    }

    private func readLegacyMetadata() throws -> WatchWorkoutRecoveryRecord? {
        guard LegacyKey.all.contains(where: { legacyDefaults.object(forKey: $0) != nil }) else { return nil }
        let identifier: String? = try legacyValue(forKey: LegacyKey.workoutID)
        let workoutID = identifier.flatMap(UUID.init(uuidString:))
        if identifier != nil && workoutID == nil { throw RecoveryStorageError.invalidLegacyMetadata }
        let startedAt: Date? = try legacyValue(forKey: LegacyKey.startedAt)
        if let startedAt, !startedAt.timeIntervalSinceReferenceDate.isFinite {
            throw RecoveryStorageError.invalidLegacyMetadata
        }
        let awaitingPhoneBinding: Bool = try legacyValue(forKey: LegacyKey.awaitingPhoneBinding) ?? false
        let multisportLegIndex: Int = try legacyValue(forKey: LegacyKey.multisportLegIndex) ?? 0
        return WatchWorkoutRecoveryRecord(
            workoutID: workoutID,
            startedAt: startedAt,
            awaitingPhoneBinding: awaitingPhoneBinding,
            configuration: try legacyJSON(WorkoutConfiguration.self, forKey: LegacyKey.configuration),
            multisportLegIndex: multisportLegIndex,
            activitySegments: try legacyJSON([WorkoutActivitySegment].self, forKey: LegacyKey.activitySegments) ?? []
        )
    }

    private func legacyValue<Value>(forKey key: String) throws -> Value? {
        guard let object = legacyDefaults.object(forKey: key) else { return nil }
        guard let value = object as? Value else { throw RecoveryStorageError.invalidLegacyMetadata }
        return value
    }

    private func legacyJSON<Value: Decodable>(_ type: Value.Type, forKey key: String) throws -> Value? {
        guard let data: Data = try legacyValue(forKey: key) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    private func removeLegacyMetadata() {
        LegacyKey.all.forEach { legacyDefaults.removeObject(forKey: $0) }
    }

    enum LegacyKey {
        static let workoutID = "pawpace.watch.activeWorkoutID"
        static let startedAt = "pawpace.watch.activeWorkoutStartedAt"
        static let awaitingPhoneBinding = "pawpace.watch.awaitingPhoneBinding"
        static let configuration = "pawpace.watch.workoutConfiguration"
        static let multisportLegIndex = "pawpace.watch.multisportLegIndex"
        static let activitySegments = "pawpace.watch.activitySegments"
        static let all = [workoutID, startedAt, awaitingPhoneBinding, configuration, multisportLegIndex, activitySegments]
    }

    enum RecoveryStorageError: LocalizedError {
        case invalidLegacyMetadata

        var errorDescription: String? {
            "The existing Watch workout recovery data could not be read. It has been preserved."
        }
    }
}
