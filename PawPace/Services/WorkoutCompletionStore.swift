import Combine
import Foundation

/// A durable outbox bridges the pet, journal and Watch acknowledgment writes.
/// Every entry remains until all requested destinations have accepted it.
@MainActor
final class WorkoutCompletionStore: ObservableObject {
    struct Entry: Codable, Equatable, Identifiable {
        var summary: RunSummary
        var rewardIDs: Set<UUID>
        var journalRequested: Bool
        var deferredTerminal: PawPaceRunState?
        var id: UUID { summary.id }
    }

    @Published private(set) var pending: [Entry] = []
    @Published private(set) var storageMessage: String?
    private let storage: PawPacePrivateStorage?
    private var retryableWrites: [Entry] = []
    private static let fileName = "workout-completions-v1.json"

    init(storage: PawPacePrivateStorage? = try? PawPacePrivateStorage.shared()) {
        self.storage = storage
        reload()
    }

    @discardableResult
    func reload() -> Bool {
        guard let storage else { return fail() }
        do {
            pending = try storage.load([Entry].self, named: Self.fileName) ?? []
            storageMessage = nil
            let retryable = retryableWrites
            retryableWrites = []
            var allSaved = true
            for entry in retryable {
                if enqueue(entry.summary, aliases: entry.rewardIDs, journalRequested: entry.journalRequested,
                           deferredTerminal: entry.deferredTerminal) == nil { allSaved = false }
            }
            if !allSaved { return fail() }
            return true
        } catch { return fail() }
    }

    func enqueue(
        _ summary: RunSummary,
        aliases: Set<UUID> = [],
        journalRequested: Bool = true,
        deferredTerminal: PawPaceRunState? = nil
    ) -> Entry? {
        var identities = aliases.union([summary.id])
        var previousCount = -1
        while previousCount != identities.count {
            previousCount = identities.count
            for entry in retryableWrites where !entry.rewardIDs.isDisjoint(with: identities) {
                identities.formUnion(entry.rewardIDs)
            }
        }
        let remembered = retryableWrites.filter { !$0.rewardIDs.isDisjoint(with: identities) }
        let terminal = (remembered.compactMap(\.deferredTerminal) + [deferredTerminal].compactMap { $0 })
            .max { $0.updatedAt < $1.updatedAt }
        let candidate = Entry(summary: remembered.first?.summary ?? summary, rewardIDs: identities,
                              journalRequested: remembered.first?.journalRequested ?? journalRequested,
                              deferredTerminal: terminal)
        guard mutate({ entries in
            let matches = entries.filter { !$0.rewardIDs.isDisjoint(with: identities) }
            if var entry = matches.first(where: { $0.summary.id == summary.id }) ?? matches.first {
                entry.rewardIDs.formUnion(identities)
                for match in matches { entry.rewardIDs.formUnion(match.rewardIDs) }
                entry.journalRequested = matches.contains(where: \.journalRequested)
                // A deletion decision already attached to an entry survives
                // later retries and delayed Watch messages.
                if let terminal,
                   entry.deferredTerminal == nil || terminal.updatedAt >= entry.deferredTerminal!.updatedAt {
                    entry.deferredTerminal = terminal
                }
                let mergedIDs = entry.rewardIDs
                entries.removeAll { !$0.rewardIDs.isDisjoint(with: mergedIDs) }
                entries.append(entry)
            } else {
                entries.append(candidate)
            }
        }) else {
            if let index = retryableWrites.firstIndex(where: { !$0.rewardIDs.isDisjoint(with: identities) }) {
                retryableWrites[index].rewardIDs.formUnion(identities)
                if let deferredTerminal { retryableWrites[index].deferredTerminal = deferredTerminal }
            } else { retryableWrites.append(candidate) }
            return nil
        }
        retryableWrites.removeAll { !$0.rewardIDs.isDisjoint(with: identities) }
        return pending.first { !$0.rewardIDs.isDisjoint(with: identities) }
    }

    @discardableResult
    func complete(_ identifier: UUID) -> Bool {
        mutate { $0.removeAll { $0.id == identifier } }
    }

    @discardableResult
    func process(
        _ entry: Entry,
        persistPet: () -> Bool,
        persistJournal: () -> Bool,
        acknowledge: () -> Bool
    ) -> Bool {
        guard persistPet() else { return false }
        if entry.journalRequested, !persistJournal() { return false }
        guard acknowledge() else { return false }
        return complete(entry.id)
    }

    /// Commit the user's deletion choice before deleting the journal so an
    /// interrupted delete/retry can never repopulate it from this outbox.
    @discardableResult
    func stopPendingJournalWrites() -> Bool {
        guard reload() else { return false }
        return mutate { entries in
            for index in entries.indices { entries[index].journalRequested = false }
        }
    }

    private func mutate(_ update: (inout [Entry]) -> Void) -> Bool {
        guard let storage else { return fail() }
        do {
            pending = try storage.update([Entry].self, named: Self.fileName,
                                         makeDefault: { [] }, update: update)
            storageMessage = nil
            return true
        } catch { return fail() }
    }

    private func fail() -> Bool {
        storageMessage = "This workout’s completion couldn’t be stored. Your existing data has been kept. Keep PawPace open and try again after unlocking your iPhone or freeing storage."
        return false
    }
}
