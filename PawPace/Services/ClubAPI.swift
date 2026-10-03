import Foundation
import Security
import AuthenticationServices

enum ClubIdentityState: Equatable {
    case authorized, revoked, notFound, transferred, unknown
}

@MainActor
protocol ClubIdentityChecking {
    func state(for userID: String) async throws -> ClubIdentityState
}

struct AppleClubIdentity: ClubIdentityChecking {
    func state(for userID: String) async throws -> ClubIdentityState {
        switch try await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID) {
        case .authorized: .authorized
        case .revoked: .revoked
        case .notFound: .notFound
        case .transferred: .transferred
        @unknown default: .unknown
        }
    }
}

struct ClubAPIError: LocalizedError {
    var status: Int
    var message: String
    var errorDescription: String? { message }
    var canRetry: Bool { status == 0 || status == 408 || status == 429 || status >= 500 }
}

@MainActor
protocol ClubServing {
    var isConfigured: Bool { get }
    func signIn(identityToken: String, nonce: String, authorizationCode: String) async throws -> ClubSession
    func snapshot(token: String) async throws -> ClubSnapshot
    func send(_ command: ClubCommand, token: String) async throws -> ClubCommandResult
    func signOut(token: String) async throws
    func deleteAccount(token: String) async throws
}

@MainActor
final class ClubAPI: ClubServing {
    private let baseURL: URL?
    private let session: URLSession
    var isConfigured: Bool { baseURL != nil }

    init(baseURL: URL? = nil, session: URLSession? = nil) {
        let configured = baseURL ?? (Bundle.main.object(forInfoDictionaryKey: "PawPaceClubAPIURL") as? String).flatMap(URL.init(string:))
        // Never send account credentials or activity to plain HTTP.
        self.baseURL = configured?.scheme == "https" && configured?.host != nil ? configured : nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = session ?? URLSession(configuration: configuration, delegate: ClubNoRedirectDelegate(), delegateQueue: nil)
    }

    func signIn(identityToken: String, nonce: String, authorizationCode: String) async throws -> ClubSession {
        try await request("v1/auth/apple", method: "POST", data: JSONSerialization.data(withJSONObject: [
            "identityToken": identityToken, "nonce": nonce, "authorizationCode": authorizationCode
        ]))
    }
    func snapshot(token: String) async throws -> ClubSnapshot { try await request("v1/clubs", token: token) }
    func send(_ command: ClubCommand, token: String) async throws -> ClubCommandResult {
        try await request("v1/commands", method: "POST", token: token, data: ClubJSON.encoder().encode(command))
    }
    func signOut(token: String) async throws {
        let _: ClubCommandResult = try await request("v1/auth/logout", method: "POST", token: token)
    }
    func deleteAccount(token: String) async throws {
        let _: ClubCommandResult = try await request("v1/account", method: "DELETE", token: token)
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", token: String? = nil, data: Data? = nil) async throws -> T {
        guard let baseURL else { throw ClubAPIError(status: 0, message: "Club isn’t connected in this build yet. Buddy and Planner are ready to use.") }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method; request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (body, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ClubAPIError(status: 0, message: "Club couldn’t connect. Please try again.") }
        guard (200..<300).contains(response.statusCode) else {
            let error = try? JSONDecoder().decode(ServerMessage.self, from: body)
            throw ClubAPIError(status: response.statusCode, message: error?.message ?? "Club couldn’t sync. Please try again.")
        }
        return try ClubJSON.decoder().decode(T.self, from: body)
    }
    private struct ServerMessage: Decodable { var message: String }
}

private final class ClubNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

protocol ClubSessionStoring {
    func load() throws -> ClubSession?
    func save(_ session: ClubSession) throws
    func clear() throws
}

struct ClubKeychain: ClubSessionStoring {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.pawpace.club", kSecAttrAccount as String: "session-v1"]
    }
    func load() throws -> ClubSession? {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw keychainError(status) }
        return try JSONDecoder().decode(ClubSession.self, from: data)
    }
    func save(_ session: ClubSession) throws {
        let data = try JSONEncoder().encode(session)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw keychainError(status) }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
    }
    private func keychainError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Your Club sign-in couldn’t be saved securely. Unlock your phone and try again."])
    }
}
