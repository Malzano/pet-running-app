import Foundation
import Combine
import AuthenticationServices

@MainActor
final class ClubStore: ObservableObject {
    struct Invitation: Identifiable {
        var id: URL { url }
        var url: URL
        var expiresAt: Date
    }
    @Published private(set) var session: ClubSession?
    @Published private(set) var archive: ClubArchive?
    @Published private(set) var isSyncing = false
    @Published private(set) var message: String?
    @Published var invitation: Invitation?
    @Published var incomingInvitation: String?
    let api: any ClubServing
    private let credentials: any ClubSessionStoring
    private let identity: any ClubIdentityChecking
    private var revocationObserver: AnyCancellable?
    private var storage: PawPacePrivateStorage?
    private var canWrite = true
    private var generation = 0
    private var syncAgain = false
    private var latestPet: PetSnapshot?
    static let fileName = "club-v1.json"
    var clubs: [RunningClub] { archive?.snapshot?.clubs ?? [] }
    var social: FriendSnapshot? { archive?.snapshot?.social }
    var friends: [FriendConnection] { social?.connections.filter { $0.status == .accepted } ?? [] }
    var pending: [ClubOutboxItem] { archive?.pending ?? [] }
    var isConfigured: Bool { api.isConfigured }

    init(identity: (any ClubIdentityChecking)? = nil, api: (any ClubServing)? = nil, credentials: any ClubSessionStoring = ClubKeychain(), storage: PawPacePrivateStorage? = nil) {
        self.api = api ?? ClubAPI(); self.credentials = credentials
        self.identity = identity ?? AppleClubIdentity()
        do {
            self.storage = try storage ?? PawPacePrivateStorage.shared()
            let savedSession = try credentials.load()
            if let savedSession, savedSession.expiresAt > .now {
                session = savedSession
                archive = try loadArchive(for: savedSession.account.id)
            }
        } catch {
            canWrite = false
            message = "Your saved Club data couldn’t be opened. It has been preserved. Unlock your phone and open PawPace again."
        }
        revocationObserver = NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.appleAuthorizationRevoked() }
            }
    }

    func signIn(identityToken: String, nonce: String, authorizationCode: String) async {
        guard !isSyncing, canWrite else { return }
        isSyncing = true
        do {
            let result = try await api.signIn(identityToken: identityToken, nonce: nonce, authorizationCode: authorizationCode)
            let saved = try loadArchive(for: result.account.id)
            try credentials.save(result)
            session = result; archive = saved; generation += 1; message = nil
        } catch { message = error.localizedDescription }
        isSyncing = false
        if session != nil { await refresh() }
    }

    @discardableResult
    func enqueue(_ command: ClubCommand) -> Bool {
        guard session != nil, isConfigured, archive != nil else { return false }
        let saved = change { value in
            if !value.pending.contains(where: { $0.id == command.id }) { value.pending.append(ClubOutboxItem(command: command)) }
        }
        if saved { Task { await refresh() } }
        return saved
    }

    func setSharing(_ enabled: Bool, clubID: String) {
        let command = ClubCommand(action: "sharing", clubID: clubID, data: .init(enabled: enabled))
        guard change({ value in
            if enabled { value.sharingPaused.remove(clubID) } else {
                value.sharingPaused.insert(clubID)
                value.pending.removeAll { $0.command.clubID == clubID && $0.command.action == "day" }
            }
            value.pending.append(.init(command: command))
        }) else { return }
        Task { await refresh() }
    }

    func eraseSharedDays(clubID: String) {
        guard change({ value in
            value.sharingPaused.insert(clubID)
            value.pending.removeAll { $0.command.clubID == clubID && ["day", "sharing"].contains($0.command.action) }
            value.pending.append(.init(command: ClubCommand(action: "eraseDays", clubID: clubID)))
        }) else { return }
        Task { await refresh() }
    }

    func observeActivity(_ pet: PetSnapshot, at date: Date = .now, calendar: Calendar = .current) {
        latestPet = pet
        guard let session, let archive else { return }
        let localDay = CompanionJourney.dayKey(date, calendar: calendar)
        guard (pet.journey.days[localDay]?.creditedSeconds ?? 0) >= 300 else { return }
        var additions: [(String, ClubCommand)] = []
        for club in clubs {
            let key = "\(club.id):\(localDay)"
            guard club.members.contains(where: { $0.id == session.account.id && $0.sharesActivity }),
                  !archive.sharingPaused.contains(club.id), !archive.submittedDays.contains(key),
                  !archive.pending.contains(where: { $0.command.clubID == club.id && ["sharing", "eraseDays", "leave", "deleteClub"].contains($0.command.action) }) else { continue }
            additions.append((key, ClubCommand(action: "day", clubID: club.id, data: .init(earnedAt: date))))
        }
        guard !additions.isEmpty else { return }
        guard change({ value in
            for (key, command) in additions where value.submittedDays.insert(key).inserted {
                value.pending.append(.init(command: command))
            }
        }) else { return }
        Task { await refresh() }
    }

    func isWorkoutSharedOrQueued(_ id: UUID) -> Bool {
        social?.posts.contains { $0.authorID == session?.account.id && $0.workoutID.caseInsensitiveCompare(id.uuidString) == .orderedSame } == true
            || pending.contains { $0.command.action == "friendPost" && $0.command.data.workoutID == id.uuidString }
    }

    // Hide removed posts/people immediately; their server operation remains in
    // the durable queue until acknowledged. The UI also filters queued removals.
    func removeFriend(_ id: String, block: Bool) {
        _ = enqueue(ClubCommand(action: block ? "friendBlock" : "friendRemove", data: .init(memberID: id)))
    }

    func retry(_ id: String) {
        guard change({ value in
            if let index = value.pending.firstIndex(where: { $0.id == id }) { value.pending[index].failure = nil }
        }) else { return }
        Task { await refresh() }
    }
    func discard(_ id: String) {
        _ = change { $0.pending.removeAll { $0.id == id } }
    }

    func refresh() async {
        guard let currentSession = session, canWrite, isConfigured else { return }
        if isSyncing { syncAgain = true; return }
        isSyncing = true
        let revision = generation
        defer { isSyncing = false }
        do {
            guard currentSession.expiresAt > .now else {
                invalidateSession("Sign in again to reconnect. Your unsent actions are saved for your account.")
                return
            }
            // Check before sending any saved action, including on a cold launch.
            // An unavailable check preserves the queue without assuming consent.
            let credentialState = try await identity.state(for: currentSession.appleUserID)
            guard revision == generation else { return }
            guard credentialState == .authorized else {
                invalidateSession("Your Apple sign-in is no longer available. Sign in again to reconnect; your unsent actions are saved for your account.", invalidateRemote: true)
                return
            }
            repeat {
                syncAgain = false
                while let item = archive?.pending.first(where: { $0.failure == nil }) {
                    do {
                        let result = try await api.send(item.command, token: currentSession.token)
                        guard revision == generation else { return }
                        guard change({ $0.pending.removeAll { $0.id == item.id } }) else { return }
                        if let url = result.invitationURL, let expires = result.expiresAt,
                           Self.invitationToken(url.absoluteString) != nil {
                            invitation = Invitation(url: url, expiresAt: expires)
                        }
                    } catch let error as ClubAPIError where !error.canRetry && error.status != 401 {
                        guard revision == generation else { return }
                        guard change({ value in
                            if let index = value.pending.firstIndex(where: { $0.id == item.id }) { value.pending[index].failure = error.message }
                        }) else { return }
                    }
                }
                let fresh = try await api.snapshot(token: currentSession.token)
                guard revision == generation else { return }
                guard fresh.isValid, fresh.account.id == currentSession.account.id else {
                    throw ClubAPIError(status: 0, message: "Club returned an incomplete update. Your last saved view is safe; try again.")
                }
                guard change({ $0.snapshot = fresh }) else { return }
                message = nil
                if let latestPet { observeActivity(latestPet) }
                if archive?.pending.contains(where: { $0.failure == nil }) == true { syncAgain = true }
            } while syncAgain
        } catch {
            guard revision == generation else { return }
            if let error = error as? ClubAPIError, error.status == 401 {
                // Keep this account's outbox for reauthentication, but conceal it
                // until the same verified account returns.
                invalidateSession("Sign in again to reconnect. Your unsent actions are saved for your account.")
            } else {
                message = "Club couldn’t sync. Your last saved view and unsent actions are safe. \(error.localizedDescription)"
            }
        }
    }

    private func appleAuthorizationRevoked() {
        guard session != nil else { return }
        invalidateSession("Your Apple sign-in was revoked. Sign in again to reconnect; your unsent actions are saved for your account.", invalidateRemote: true)
    }

    private func invalidateSession(_ explanation: String, invalidateRemote: Bool = false) {
        let previous = session
        generation += 1; syncAgain = false
        session = nil; archive = nil; invitation = nil
        do { try credentials.clear(); message = explanation }
        catch { message = "\(explanation) Your saved sign-in couldn’t be cleared. Unlock your phone and reopen PawPace to try again." }
        if invalidateRemote, let previous {
            Task { [api] in try? await api.signOut(token: previous.token) }
        }
    }

    func signOut() async {
        guard let session, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        try? await api.signOut(token: session.token)
        do { try clearLocalSession() }
        catch { message = error.localizedDescription }
    }

    func deleteAccount() async {
        guard let session, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await api.deleteAccount(token: session.token)
            try clearLocalSession()
        } catch { message = "Your Club account couldn’t be removed. \(error.localizedDescription)" }
    }

    static func invitationToken(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let token: String
        if let url = URLComponents(string: trimmed), url.scheme == "pawpace", url.host == "club", url.path == "/join" {
            guard let value = url.queryItems?.first(where: { $0.name == "token" })?.value else { return nil }
            token = value
        } else { token = trimmed }
        return token.range(of: "^[A-Za-z0-9_-]{40,60}$", options: .regularExpression) != nil ? token : nil
    }

    private func loadArchive(for accountID: String) throws -> ClubArchive {
        guard let storage else { throw CocoaError(.fileReadUnknown) }
        if let saved = try storage.load(ClubArchive.self, named: Self.fileName), saved.accountID == accountID {
            guard saved.snapshot?.isValid ?? true, saved.snapshot?.account.id == nil || saved.snapshot?.account.id == accountID else { throw CocoaError(.fileReadCorruptFile) }
            return saved
        }
        return ClubArchive(accountID: accountID)
    }

    private func clearLocalSession() throws {
        try credentials.clear()
        generation += 1; session = nil; archive = nil; invitation = nil
        try storage?.remove(named: Self.fileName)
        message = nil
    }

    @discardableResult private func change(_ edit: (inout ClubArchive) -> Void) -> Bool {
        guard canWrite, let storage, var next = archive else { return false }
        edit(&next)
        do {
            try storage.save(next, named: Self.fileName)
            archive = next
            return true
        } catch {
            message = "Your Club changes couldn’t be saved. Please try again; previous data is safe."
            return false
        }
    }
}
