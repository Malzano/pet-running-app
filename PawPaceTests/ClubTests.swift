import XCTest
import AuthenticationServices
@testable import PawPace

@MainActor
final class ClubTestIdentity: ClubIdentityChecking {
    var value: ClubIdentityState = .authorized
    var error: Error?
    var users: [String] = []
    func state(for userID: String) async throws -> ClubIdentityState {
        users.append(userID)
        if let error { throw error }
        return value
    }
}

@MainActor
final class ClubTestCredentials: ClubSessionStoring {
    var session: ClubSession?
    var failsClear = false
    init(_ session: ClubSession? = ClubFixtures.session) { self.session = session }
    func load() throws -> ClubSession? { session }
    func save(_ session: ClubSession) throws { self.session = session }
    func clear() throws {
        if failsClear { throw CocoaError(.fileWriteNoPermission) }
        session = nil
    }
}

@MainActor
final class ClubTestAPI: ClubServing {
    var isConfigured = true
    var value = ClubFixtures.snapshot
    var login = ClubFixtures.session
    var sent: [ClubCommand] = []
    var sendError: ClubAPIError?
    var snapshotError: ClubAPIError?
    var suspended: CheckedContinuation<Void, Never>?
    var holdsNextSend = false
    var loggedOut: [String] = []
    func signIn(identityToken: String, nonce: String, authorizationCode: String) async throws -> ClubSession { login }
    func snapshot(token: String) async throws -> ClubSnapshot {
        if let snapshotError { throw snapshotError }; return value
    }
    func send(_ command: ClubCommand, token: String) async throws -> ClubCommandResult {
        sent.append(command)
        if holdsNextSend { holdsNextSend = false; await withCheckedContinuation { suspended = $0 } }
        if let sendError { throw sendError }
        if command.action == "sharing", let enabled = command.data.enabled {
            value.clubs[0].members[0].sharesActivity = enabled
        }
        return ClubCommandResult()
    }
    func signOut(token: String) async throws { loggedOut.append(token) }
    func deleteAccount(token: String) async throws { }
}

enum ClubFixtures {
    static let account = ClubAccount(id: "10000000-0000-0000-0000-000000000001", alias: "Maple 204")
    static let friend = "20000000-0000-0000-0000-000000000002"
    static let clubID = "30000000-0000-0000-0000-000000000003"
    static var session: ClubSession { ClubSession(token: "test-only-session", account: account, appleUserID: "test-only-apple-id", expiresAt: Date().addingTimeInterval(86_400)) }
    static var snapshot: ClubSnapshot {
        let today = Date(), yesterday = today.addingTimeInterval(-86_400)
        let club = RunningClub(id: clubID, ownerID: account.id, name: "Morning paths", timeZone: "Asia/Bangkok", weeklyTarget: 7,
            createdAt: yesterday, weekStart: "2026-09-21", weekEnd: "2026-09-28", totalDays: 24,
            members: [.init(id: account.id, alias: account.alias, joinedAt: yesterday, sharesActivity: true),
                      .init(id: friend, alias: "Cedar 108", joinedAt: yesterday, sharesActivity: false)],
            days: [.init(id: UUID().uuidString, memberID: account.id, day: "2026-09-26", earnedAt: today)],
            events: [.init(id: "40000000-0000-0000-0000-000000000004", clubID: clubID, activity: .walking, scheduledAt: today.addingTimeInterval(86_400), durationMinutes: 20, cancelled: false)],
            cheers: [.init(id: UUID().uuidString, senderID: friend, recipientID: account.id, kind: .withYou, createdAt: today)])
        return ClubSnapshot(account: account, clubs: [club], fetchedAt: today)
    }
}

@MainActor
final class ClubTests: XCTestCase {
    private func storage() -> PawPacePrivateStorage {
        PawPacePrivateStorage(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }
    private func settle(_ store: ClubStore) async {
        await store.refresh()
        for _ in 0..<20 { await Task.yield() }
        await store.refresh()
    }

    func testInvalidAppleCredentialsStopTheOutboxBeforeAnyUpload() async throws {
        for state in [ClubIdentityState.revoked, .notFound, .transferred, .unknown] {
            let storage = storage(); defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
            let api = ClubTestAPI(), credentials = ClubTestCredentials(), identity = ClubTestIdentity()
            identity.value = state
            let store = ClubStore(identity: identity, api: api, credentials: credentials, storage: storage)
            let command = ClubCommand(action: "day", clubID: ClubFixtures.clubID, data: .init(earnedAt: .now))
            XCTAssertTrue(store.enqueue(command))
            await settle(store)
            XCTAssertNil(store.session); XCTAssertNil(credentials.session); XCTAssertTrue(store.clubs.isEmpty)
            XCTAssertTrue(api.sent.isEmpty)
            XCTAssertEqual(identity.users, [ClubFixtures.session.appleUserID])
            XCTAssertEqual(api.loggedOut, [ClubFixtures.session.token])
            XCTAssertEqual(try storage.load(ClubArchive.self, named: ClubStore.fileName)?.pending.map(\.id), [command.id])
        }
    }

    func testUnavailableAppleCheckPreservesOfflineStateAndWaitsBeforeUploading() async throws {
        let storage = storage(); defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let api = ClubTestAPI(), credentials = ClubTestCredentials(), identity = ClubTestIdentity()
        let store = ClubStore(identity: identity, api: api, credentials: credentials, storage: storage)
        await store.refresh()
        identity.error = URLError(.notConnectedToInternet)
        let command = ClubCommand(action: "cheer", clubID: ClubFixtures.clubID, data: .init(recipientID: ClubFixtures.friend, kind: .withYou))
        XCTAssertTrue(store.enqueue(command)); await settle(store)
        XCTAssertNotNil(store.session); XCTAssertEqual(store.clubs.count, 1)
        XCTAssertEqual(store.pending.map(\.id), [command.id]); XCTAssertTrue(api.sent.isEmpty)
        XCTAssertNotNil(store.message)
        identity.error = nil
        await settle(store)
        XCTAssertEqual(api.sent.map(\.id), [command.id]); XCTAssertTrue(store.pending.isEmpty)
    }

    func testRevocationDuringAnUploadStopsLaterActionsAndConcealsItsResponse() async throws {
        let storage = storage(); defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let api = ClubTestAPI(), identity = ClubTestIdentity(), credentials = ClubTestCredentials()
        let store = ClubStore(identity: identity, api: api, credentials: credentials, storage: storage)
        await store.refresh()
        api.holdsNextSend = true
        let first = ClubCommand(action: "cheer", clubID: ClubFixtures.clubID, data: .init(recipientID: ClubFixtures.friend, kind: .withYou))
        let second = ClubCommand(action: "day", clubID: ClubFixtures.clubID, data: .init(earnedAt: .now))
        XCTAssertTrue(store.enqueue(first))
        for _ in 0..<100 where api.suspended == nil { await Task.yield() }
        XCTAssertNotNil(api.suspended)
        XCTAssertTrue(store.enqueue(second))
        NotificationCenter.default.post(name: ASAuthorizationAppleIDProvider.credentialRevokedNotification, object: nil)
        for _ in 0..<100 where store.session != nil { await Task.yield() }
        XCTAssertNil(store.session, "The actual Apple notification must sign the local account out")
        api.suspended?.resume(); api.suspended = nil
        await settle(store)
        XCTAssertNil(store.session); XCTAssertTrue(store.clubs.isEmpty); XCTAssertNil(store.invitation)
        XCTAssertEqual(api.sent.map(\.id), [first.id], "An already-sent request cannot be recalled; no later request may start")
        XCTAssertEqual(try storage.load(ClubArchive.self, named: ClubStore.fileName)?.pending.map(\.id), [first.id, second.id])
        XCTAssertEqual(api.loggedOut, [ClubFixtures.session.token])
    }

    func testKeychainClearFailureDoesNotKeepRevokedAccountActive() async throws {
        let storage = storage(); defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let api = ClubTestAPI(), credentials = ClubTestCredentials(), identity = ClubTestIdentity()
        identity.value = .revoked; credentials.failsClear = true
        let store = ClubStore(identity: identity, api: api, credentials: credentials, storage: storage)
        await settle(store)
        XCTAssertNil(store.session); XCTAssertNotNil(store.message)
        let reopened = ClubStore(identity: identity, api: api, credentials: credentials, storage: storage)
        await settle(reopened)
        XCTAssertNil(reopened.session); XCTAssertTrue(api.sent.isEmpty)
    }

    func testOfflineActionPersistsAndRetriesWithExactlyTheSameIdentity() async throws {
        let storage = storage(); defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let api = ClubTestAPI(), credentials = ClubTestCredentials()
        api.sendError = ClubAPIError(status: 0, message: "Offline")
        let store = ClubStore(identity: ClubTestIdentity(), api: api, credentials: credentials, storage: storage)
        let command = ClubCommand(action: "cheer", clubID: ClubFixtures.clubID, data: .init(recipientID: ClubFixtures.friend, kind: .wellDone))
        XCTAssertTrue(store.enqueue(command))
        await settle(store)
        XCTAssertEqual(store.pending.map(\.id), [command.id])
        let saved = try XCTUnwrap(storage.load(ClubArchive.self, named: ClubStore.fileName))
        XCTAssertEqual(saved.pending.first?.command, command)
        api.sendError = nil
        let reloaded = ClubStore(identity: ClubTestIdentity(), api: api, credentials: credentials, storage: storage)
        await settle(reloaded)
        XCTAssertTrue(reloaded.pending.isEmpty)
        XCTAssertTrue(api.sent.allSatisfy { $0.id == command.id })
        XCTAssertNotNil(reloaded.archive?.snapshot)
    }

    func testOnlyOptedInCurrentDaysQueueOnceAcrossSourcesAndReload() async throws {
        let storage = storage(); defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let api = ClubTestAPI(), credentials = ClubTestCredentials()
        api.value.clubs[0].members[0].sharesActivity = false
        let store = ClubStore(identity: ClubTestIdentity(), api: api, credentials: credentials, storage: storage)
        await settle(store)
        var pet = PetSnapshot.starter
        let today = Date(), yesterday = today.addingTimeInterval(-86_400)
        pet.journey.days[CompanionJourney.dayKey(yesterday)] = JourneyDay(date: yesterday, creditedSeconds: 3_600)
        store.observeActivity(pet, at: today)
        XCTAssertTrue(store.pending.isEmpty)
        pet.journey.days[CompanionJourney.dayKey(today)] = JourneyDay(date: today, creditedSeconds: 299)
        store.observeActivity(pet, at: today); XCTAssertTrue(store.pending.isEmpty)
        pet.journey.days[CompanionJourney.dayKey(today)]?.creditedSeconds = 300
        store.observeActivity(pet, at: today); XCTAssertTrue(store.pending.isEmpty, "Sharing begins off")
        store.setSharing(true, clubID: ClubFixtures.clubID)
        await settle(store)
        XCTAssertEqual(api.sent.filter { $0.action == "day" }.count, 1)
        let first = try XCTUnwrap(api.sent.first { $0.action == "day" })
        XCTAssertNotNil(first.data.earnedAt)
        XCTAssertNil(first.data.name); XCTAssertNil(first.data.activity)
        let reloaded = ClubStore(identity: ClubTestIdentity(), api: api, credentials: credentials, storage: storage)
        reloaded.observeActivity(pet, at: today)
        await settle(reloaded)
        XCTAssertEqual(api.sent.filter { $0.action == "day" }.count, 1)
        XCTAssertEqual(reloaded.archive?.submittedDays.count, 1)
    }

    func testOfflineOptOutImmediatelyStopsAndRemovesQueuedDayUploads() async throws {
        let storage = storage(); defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let api = ClubTestAPI()
        let store = ClubStore(identity: ClubTestIdentity(), api: api, credentials: ClubTestCredentials(), storage: storage)
        await settle(store)
        api.sendError = ClubAPIError(status: 0, message: "Offline")
        var pet = PetSnapshot.starter
        pet.journey.days[CompanionJourney.dayKey(.now)] = JourneyDay(date: .now, creditedSeconds: 600)
        store.observeActivity(pet)
        XCTAssertEqual(store.pending.filter { $0.command.action == "day" }.count, 1)
        store.setSharing(false, clubID: ClubFixtures.clubID)
        store.observeActivity(pet)
        XCTAssertFalse(store.pending.contains { $0.command.action == "day" })
        XCTAssertTrue(store.archive?.sharingPaused.contains(ClubFixtures.clubID) == true)
        await settle(store)
        XCTAssertEqual(store.pending.last?.command.action, "sharing")
    }

    func testActionsAddedWhileARequestIsAwaitingAreNotLost() async {
        let storage = storage(); defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let api = ClubTestAPI()
        let store = ClubStore(identity: ClubTestIdentity(), api: api, credentials: ClubTestCredentials(), storage: storage)
        api.holdsNextSend = true
        let first = ClubCommand(action: "cheer", clubID: ClubFixtures.clubID, data: .init(recipientID: ClubFixtures.friend, kind: .wellDone))
        let second = ClubCommand(action: "cheer", clubID: ClubFixtures.clubID, data: .init(recipientID: ClubFixtures.friend, kind: .withYou))
        XCTAssertTrue(store.enqueue(first))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNotNil(api.suspended)
        XCTAssertTrue(store.enqueue(second))
        api.suspended?.resume(); api.suspended = nil
        await settle(store)
        XCTAssertEqual(Set(api.sent.map(\.id)), [first.id, second.id])
        XCTAssertTrue(store.pending.isEmpty)
    }

    func testPermanentPermissionErrorRemainsReviewableAndDoesNotRetryForever() async {
        let storage = storage(); defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let api = ClubTestAPI(); api.sendError = ClubAPIError(status: 403, message: "Membership changed")
        let store = ClubStore(identity: ClubTestIdentity(), api: api, credentials: ClubTestCredentials(), storage: storage)
        let command = ClubCommand(action: "event", clubID: ClubFixtures.clubID)
        XCTAssertTrue(store.enqueue(command)); await settle(store)
        XCTAssertEqual(store.pending.first?.failure, "Membership changed")
        let attempts = api.sent.count
        await settle(store); XCTAssertEqual(api.sent.count, attempts)
        store.discard(command.id); XCTAssertTrue(store.pending.isEmpty)
    }

    func testExpiredSessionConcealsCacheAndNeverReplaysAnotherAccountsQueue() async throws {
        let storage = storage(); defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let api = ClubTestAPI(), credentials = ClubTestCredentials()
        let store = ClubStore(identity: ClubTestIdentity(), api: api, credentials: credentials, storage: storage)
        await settle(store)
        api.sendError = ClubAPIError(status: 401, message: "Expired")
        XCTAssertTrue(store.enqueue(ClubCommand(action: "leave", clubID: ClubFixtures.clubID)))
        await settle(store)
        XCTAssertNil(store.session); XCTAssertTrue(store.clubs.isEmpty)
        XCTAssertEqual(try storage.load(ClubArchive.self, named: ClubStore.fileName)?.pending.count, 1)
        api.login.account = .init(id: ClubFixtures.friend, alias: "Cedar 108")
        api.value = ClubSnapshot(account: api.login.account, clubs: [], fetchedAt: .now)
        api.sendError = nil; api.sent = []
        await store.signIn(identityToken: "test", nonce: "test", authorizationCode: "test")
        XCTAssertEqual(store.session?.account.id, ClubFixtures.friend)
        XCTAssertTrue(store.pending.isEmpty); XCTAssertTrue(api.sent.isEmpty)
    }

    func testCorruptClubStorageIsPreserved() throws {
        let storage = storage(); defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        try FileManager.default.createDirectory(at: storage.directoryURL, withIntermediateDirectories: true)
        let file = storage.directoryURL.appendingPathComponent(ClubStore.fileName), original = Data("broken".utf8)
        try original.write(to: file)
        let store = ClubStore(identity: ClubTestIdentity(), api: ClubTestAPI(), credentials: ClubTestCredentials(), storage: storage)
        XCTAssertNotNil(store.message)
        XCTAssertFalse(store.enqueue(ClubCommand(action: "join")))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testClubEventHasStablePlannerIdentityAndDoesNotAwardGrowth() {
        let storage = storage(); defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let planner = PlannerStore(storage: storage, reminders: TestPlannerReminders())
        let event = ClubFixtures.snapshot.clubs[0].events[0]
        XCTAssertTrue(planner.save(event.plan)); XCTAssertTrue(planner.save(event.plan))
        XCTAssertEqual(planner.plans.count, 1); XCTAssertEqual(planner.plans[0].activity, .walking)
        XCTAssertNil(planner.plans[0].completion)
        XCTAssertEqual(planner.plans[0].clubEventID, event.plannerID)
    }

    func testSpoilerConcealmentAndInvitationParsing() {
        let egg = PetSnapshot.newPlayer(seed: 0)
        for species in PetSpecies.allCases {
            XCTAssertFalse(ClubPrivacy.title("\(species.displayName) club", pet: egg).localizedCaseInsensitiveContains(species.displayName))
            if let move = species.specialMoveName {
                XCTAssertFalse(ClubPrivacy.title(move, pet: egg).localizedCaseInsensitiveContains(move))
            }
        }
        XCTAssertEqual(ClubPrivacy.title("Corgi club", pet: .starter), "Corgi club")
        let token = String(repeating: "A", count: 43)
        XCTAssertEqual(ClubStore.invitationToken("pawpace://club/join?token=\(token)"), token)
        XCTAssertNil(ClubStore.invitationToken("https://example.com/?token=\(token)"))
        XCTAssertNil(ClubStore.invitationToken("pawpace://run/join?token=\(token)"))
    }

    func testHTTPConfigurationAndServerDateFormats() throws {
        XCTAssertFalse(ClubAPI(baseURL: URL(string: "http://localhost:8080")).isConfigured)
        XCTAssertTrue(ClubAPI(baseURL: URL(string: "https://club.example.com")).isConfigured)
        let decoder = ClubJSON.decoder()
        XCTAssertEqual(try decoder.decode(Date.self, from: Data("\"2026-09-26T08:00:00.000Z\"".utf8)),
                       try decoder.decode(Date.self, from: Data("\"2026-09-26T08:00:00Z\"".utf8)))
        XCTAssertTrue(ClubFixtures.snapshot.isValid)
        var invalid = ClubFixtures.snapshot; invalid.clubs[0].members.removeAll()
        XCTAssertFalse(invalid.isValid)
    }
}
