import Combine
import Foundation
import Security

struct NovaAuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let email: String
}

@MainActor
final class NovaAccountStore: ObservableObject {
    static let shared = NovaAccountStore()

    @Published private(set) var session: NovaAuthSession?
    @Published private(set) var isWorking = false
    @Published private(set) var statusMessage: String?

    private let supabaseURL = URL(string: "https://nhzpodixkjhynvcwnzok.supabase.co")!
    private let publishableKey = "sb_publishable_LqyBAJMOMir72jmLcziX_A_wArHa_L0"
    private let keychainService = "com.novatechnologies.novacopilot.auth"
    private let keychainAccount = "supabase-session"

    var email: String? { session?.email }
    var hasSession: Bool { session != nil }
    private init() {
        session = loadSession()
    }

    func createAccount(email: String, password: String) async throws -> String {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let result = try await request(path: "/auth/v1/signup", body: [
            "email": normalizedEmail,
            "password": password
        ])
        if let tokenResponse = try? JSONDecoder().decode(TokenResponse.self, from: result.data),
           let accessToken = tokenResponse.accessToken,
           let refreshToken = tokenResponse.refreshToken,
           tokenResponse.user?.emailConfirmedAt != nil {
            accept(tokenResponse, accessToken: accessToken, refreshToken: refreshToken, fallbackEmail: normalizedEmail)
            return "Your NOVA Copilot account is ready."
        }
        let confirmationMessage = "Check your email to verify the account, then return here to sign in."
        statusMessage = confirmationMessage
        return confirmationMessage
    }

    func signIn(email: String, password: String) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let result = try await request(path: "/auth/v1/token?grant_type=password", body: [
            "email": normalizedEmail,
            "password": password
        ])
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: result.data)
        guard let accessToken = tokenResponse.accessToken,
              let refreshToken = tokenResponse.refreshToken,
              tokenResponse.user?.emailConfirmedAt != nil else {
            throw NovaAccountError.message("Sign-in did not return a session. Verify your email and try again.")
        }
        accept(tokenResponse, accessToken: accessToken, refreshToken: refreshToken, fallbackEmail: normalizedEmail)
        statusMessage = nil
    }

    func accessTokenForRequest() async throws -> String {
        guard let current = session else {
            throw NovaAccountError.message("Sign in with a verified account before sending a message.")
        }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }

        do {
            let result = try await request(path: "/auth/v1/token?grant_type=refresh_token", body: [
                "refresh_token": current.refreshToken
            ])
            let response = try JSONDecoder().decode(TokenResponse.self, from: result.data)
            guard let accessToken = response.accessToken,
                  let refreshToken = response.refreshToken else {
                throw NovaAccountError.message("Your session expired. Sign in again.")
            }
            accept(response, accessToken: accessToken, refreshToken: refreshToken, fallbackEmail: current.email)
            return accessToken
        } catch {
            clearSession()
            throw NovaAccountError.message("Your session expired. Please sign in again.")
        }
    }

    func signOut() async {
        if let session {
            var request = URLRequest(url: endpoint("/auth/v1/logout"))
            request.httpMethod = "POST"
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        clearSession()
    }

    private func request(path: String, body: [String: String]) async throws -> (data: Data, response: HTTPURLResponse) {
        isWorking = true
        defer { isWorking = false }

        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 25

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NovaAccountError.message("The sign-in service returned an invalid response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
            throw NovaAccountError.message(errorResponse?.message ?? errorResponse?.msg ?? "Account request failed (HTTP \(httpResponse.statusCode)).")
        }
        return (data, httpResponse)
    }

    private func accept(_ response: TokenResponse, accessToken: String, refreshToken: String, fallbackEmail: String) {
        let expiry = response.expiresAt.map(Date.init(timeIntervalSince1970:))
            ?? Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))
        let newSession = NovaAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiry,
            email: response.user?.email ?? fallbackEmail
        )
        session = newSession
        saveSession(newSession)
    }

    private func endpoint(_ path: String) -> URL {
        URL(string: path, relativeTo: supabaseURL)!.absoluteURL
    }

    private func clearSession() {
        session = nil
        statusMessage = nil
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func loadSession() -> NovaAuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(NovaAuthSession.self, from: data)
    }

    private func saveSession(_ session: NovaAuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let expiresAt: TimeInterval?
    let user: AuthUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }
}

private struct AuthUser: Decodable {
    let email: String?
    let emailConfirmedAt: String?

    enum CodingKeys: String, CodingKey {
        case email
        case emailConfirmedAt = "email_confirmed_at"
    }
}

private struct AuthErrorResponse: Decodable {
    let message: String?
    let msg: String?
}

private enum NovaAccountError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(value) = self { return value }
        return nil
    }
}
