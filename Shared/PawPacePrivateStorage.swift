import Foundation

/// Local fitness-bearing files stay outside system backups. File coordination
/// serializes read/modify/write across the app and its widget processes.
struct PawPacePrivateStorage {
    let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    static func shared() throws -> PawPacePrivateStorage {
        let manager = FileManager.default
#if os(iOS)
        if let group = manager.containerURL(forSecurityApplicationGroupIdentifier: PawPaceShared.suiteName) {
            return PawPacePrivateStorage(directoryURL: group
                .appendingPathComponent("Library/Application Support/PawPacePrivate", isDirectory: true))
        }
#endif
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true)
        return PawPacePrivateStorage(directoryURL: support.appendingPathComponent("PawPacePrivate", isDirectory: true))
    }

    func load<Value: Codable>(
        _ type: Value.Type,
        named name: String,
        legacyDefaults: UserDefaults? = nil,
        legacyKey: String? = nil
    ) throws -> Value? {
        try coordinated(name) { url in
            try readOrMigrate(type, at: url, legacyDefaults: legacyDefaults, legacyKey: legacyKey)
        }
    }

    func loadOrCreate<Value: Codable>(
        _ type: Value.Type,
        named name: String,
        legacyDefaults: UserDefaults? = nil,
        legacyKey: String? = nil,
        makeDefault: () -> Value
    ) throws -> Value {
        try coordinated(name) { url in
            if let existing = try readOrMigrate(type, at: url, legacyDefaults: legacyDefaults, legacyKey: legacyKey) {
                return existing
            }
            let value = makeDefault()
            try write(value, to: url)
            return value
        }
    }

    func save<Value: Codable>(
        _ value: Value,
        named name: String,
        legacyDefaults: UserDefaults? = nil,
        legacyKey: String? = nil
    ) throws {
        try coordinated(name) { url in
            // Never replace unreadable existing progress with an in-memory
            // placeholder. Recovery or an explicit deletion must happen first.
            _ = try readOrMigrate(Value.self, at: url, legacyDefaults: legacyDefaults, legacyKey: legacyKey)
            try write(value, to: url)
            if let legacyDefaults, let legacyKey { legacyDefaults.removeObject(forKey: legacyKey) }
        }
    }

    func update<Value: Codable>(
        _ type: Value.Type,
        named name: String,
        legacyDefaults: UserDefaults? = nil,
        legacyKey: String? = nil,
        makeDefault: () -> Value,
        update: (inout Value) -> Void
    ) throws -> Value {
        try coordinated(name) { url in
            var value = try readOrMigrate(type, at: url, legacyDefaults: legacyDefaults, legacyKey: legacyKey)
                ?? makeDefault()
            update(&value)
            try write(value, to: url)
            return value
        }
    }

    /// Use only for an explicit data-deletion action or a completed queue.
    func remove(named name: String) throws {
        try coordinated(name) { url in
            do { try FileManager.default.removeItem(at: url) }
            catch where Self.isMissingFile(error) { }
        }
    }

    private func readOrMigrate<Value: Codable>(
        _ type: Value.Type,
        at url: URL,
        legacyDefaults: UserDefaults?,
        legacyKey: String?
    ) throws -> Value? {
        let data: Data?
        do { data = try Data(contentsOf: url) }
        catch where Self.isMissingFile(error) { data = nil }
        if let data {
            let value = try JSONDecoder().decode(type, from: data)
            // A durable, valid private file takes precedence after migration.
            if let legacyDefaults, let legacyKey { legacyDefaults.removeObject(forKey: legacyKey) }
            return value
        }
        guard let legacyDefaults, let legacyKey,
              let legacy = legacyDefaults.object(forKey: legacyKey) else { return nil }
        guard let data = legacy as? Data else { throw StorageError.invalidLegacyData }
        let value = try JSONDecoder().decode(type, from: data)
        try write(value, to: url)
        legacyDefaults.removeObject(forKey: legacyKey)
        return value
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
#if os(iOS) || os(watchOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
#else
        try data.write(to: url, options: .atomic)
#endif
    }

    private func coordinated<Result>(_ name: String, operation: (URL) throws -> Result) throws -> Result {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\") else {
            throw StorageError.invalidFileName
        }
        let manager = FileManager.default
#if os(iOS) || os(watchOS)
        try manager.createDirectory(at: directoryURL, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
#else
        try manager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
#endif
        var directory = directoryURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)

        let url = directoryURL.appendingPathComponent(name, isDirectory: false)
        var coordinationError: NSError?
        var result: Swift.Result<Result, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging,
                                                       error: &coordinationError) { coordinatedURL in
            result = Swift.Result { try operation(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw StorageError.coordinationFailed }
        return try result.get()
    }

    private static func isMissingFile(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSCocoaErrorDomain &&
                [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code)) ||
            (error.domain == NSPOSIXErrorDomain && error.code == 2)
    }

    enum StorageError: LocalizedError {
        case invalidFileName, invalidLegacyData, coordinationFailed

        var errorDescription: String? {
            switch self {
            case .invalidFileName: "The local save name is invalid."
            case .invalidLegacyData: "The existing local save could not be read. It has been preserved."
            case .coordinationFailed: "The local save is busy. Please try again."
            }
        }
    }
}

struct PawPaceSnapshotStore {
    static let fileName = "pet-snapshot-v1.json"
    private let storage: PawPacePrivateStorage
    private let legacyDefaults: UserDefaults

    init(directoryURL: URL, legacyDefaults: UserDefaults) {
        self.init(storage: PawPacePrivateStorage(directoryURL: directoryURL), legacyDefaults: legacyDefaults)
    }

    init(storage: PawPacePrivateStorage, legacyDefaults: UserDefaults) {
        self.storage = storage
        self.legacyDefaults = legacyDefaults
    }

    func loadIfPresent() throws -> PetSnapshot? {
        try storage.load(PetSnapshot.self, named: Self.fileName,
                         legacyDefaults: legacyDefaults, legacyKey: PawPaceShared.snapshotKey)
    }

    func loadOrCreate(makeDefault: () -> PetSnapshot = { .newPlayer() }) throws -> PetSnapshot {
        try storage.loadOrCreate(PetSnapshot.self, named: Self.fileName,
                                 legacyDefaults: legacyDefaults, legacyKey: PawPaceShared.snapshotKey,
                                 makeDefault: makeDefault)
    }

    func save(_ snapshot: PetSnapshot) throws {
        try storage.save(snapshot, named: Self.fileName,
                         legacyDefaults: legacyDefaults, legacyKey: PawPaceShared.snapshotKey)
    }

    func update(_ update: (inout PetSnapshot) -> Void) throws -> PetSnapshot {
        try storage.update(PetSnapshot.self, named: Self.fileName,
                           legacyDefaults: legacyDefaults, legacyKey: PawPaceShared.snapshotKey,
                           makeDefault: { .newPlayer() }, update: update)
    }
}
