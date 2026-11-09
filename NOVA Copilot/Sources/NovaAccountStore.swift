import AppKit
import Combine
import CryptoKit
import Foundation
import Security

struct NovaAuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let email: String?
    let isAnonymous: Bool?
}

@MainActor
final class NovaAccountStore: ObservableObject {
    static let shared = NovaAccountStore()

    @Published private(set) var session: NovaAuthSession?
    @Published private(set) var isWorking = false
    @Published private(set) var isGoogleSignInInProgress = false
    @Published private(set) var isOwner = false
    @Published private(set) var statusMessage: String?

    private let supabaseURL = URL(string: "https://nhzpodixkjhynvcwnzok.supabase.co")!
    private let publishableKey = "sb_publishable_LqyBAJMOMir72jmLcziX_A_wArHa_L0"
    private let keychainService = "com.novatechnologies.novacopilot.auth"
    private let keychainAccount = "supabase-session"
    private let oauthCallbackScheme = "com.novatechnologies.novacopilot"
    private var pendingPKCEVerifier: String?

    var email: String? { session?.email }
    var hasSession: Bool { session != nil }
    var isGuest: Bool { session?.isAnonymous == true }
    private init() {
        session = loadSession()
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

    func refreshOwnerStatus() async {
        guard session != nil else { return }
        do {
            let token = try await accessTokenForRequest()
            let data = try await rpc(path: "/rest/v1/rpc/nova_copilot_owner_status", body: [:], token: token)
            isOwner = (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
        } catch {
            isOwner = false
        }
    }

    func redeemOwnerCode(_ code: String) async throws {
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 20 else {
            throw NovaAccountError.message("Enter the full owner access code.")
        }
        let token = try await accessTokenForRequest()
        let data = try await rpc(
            path: "/rest/v1/rpc/nova_copilot_redeem_owner_code",
            body: ["p_code": cleaned],
            token: token
        )
        let result = try JSONDecoder().decode(OwnerCodeResponse.self, from: data)
        guard result.isOwner == true else {
            throw NovaAccountError.message("That owner code is invalid or has already been claimed.")
        }
        isOwner = true
        statusMessage = "Owner profile activated. Your messages are unlimited."
    }

    func beginGoogleSignIn() throws {
        guard !isGoogleSignInInProgress else { return }

        var randomBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes) == errSecSuccess else {
            throw NovaAccountError.message("NOVA couldn’t start secure Google sign-in. Please try again.")
        }
        let verifier = Data(randomBytes).base64URLString
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLString
        let redirectURL = "\(oauthCallbackScheme)://auth-callback"

        guard var components = URLComponents(url: endpoint("/auth/v1/authorize"), resolvingAgainstBaseURL: false) else {
            throw NovaAccountError.message("NOVA couldn’t prepare Google sign-in.")
        }
        components.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: redirectURL),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256")
        ]
        guard let authorizationURL = components.url, NSWorkspace.shared.open(authorizationURL) else {
            throw NovaAccountError.message("NOVA couldn’t open your browser. Try again or use email sign-in.")
        }

        pendingPKCEVerifier = verifier
        isGoogleSignInInProgress = true
        statusMessage = "Finish signing in with Google in your browser. NOVA will continue automatically."
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            guard let self, self.isGoogleSignInInProgress else { return }
            self.pendingPKCEVerifier = nil
            self.isGoogleSignInInProgress = false
            self.statusMessage = "Google sign-in timed out. Click Continue with Google and try again."
        }
    }

    func handleGoogleOAuthCallback(_ url: URL) async {
        guard url.scheme == oauthCallbackScheme, url.host == "auth-callback" else { return }
        guard isGoogleSignInInProgress, let verifier = pendingPKCEVerifier else {
            statusMessage = "That Google sign-in has expired. Start again from NOVA."
            return
        }

        defer {
            pendingPKCEVerifier = nil
            isGoogleSignInInProgress = false
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            statusMessage = "Google sign-in returned an invalid response. Please try again."
            return
        }
        let values = Dictionary(components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [], uniquingKeysWith: { first, _ in first })
        if let error = values["error_description"] ?? values["error"], !error.isEmpty {
            statusMessage = error.replacingOccurrences(of: "+", with: " ")
            return
        }
        guard let code = values["code"], !code.isEmpty else {
            statusMessage = "Google didn’t return a sign-in code. Please try again."
            return
        }

        do {
            let result = try await request(path: "/auth/v1/token?grant_type=pkce", body: [
                "auth_code": code,
                "code_verifier": verifier
            ])
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: result.data)
            guard let accessToken = tokenResponse.accessToken,
                  let refreshToken = tokenResponse.refreshToken,
                  let email = tokenResponse.user?.email,
                  tokenResponse.user?.emailConfirmedAt != nil else {
                throw NovaAccountError.message("Google didn’t return a verified email address. Try another Google account.")
            }
            accept(tokenResponse, accessToken: accessToken, refreshToken: refreshToken, fallbackEmail: email)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func accessTokenForRequest() async throws -> String {
        guard let current = session else { return try await signInAnonymously() }
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
            if current.isAnonymous == true { return try await signInAnonymously() }
            throw NovaAccountError.message("Your session expired. Please sign in again.")
        }
    }

    private func signInAnonymously() async throws -> String {
        let result = try await request(path: "/auth/v1/signup", body: ["data": [String: String]()])
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: result.data)
        guard let accessToken = tokenResponse.accessToken,
              let refreshToken = tokenResponse.refreshToken else {
            throw NovaAccountError.message("NOVA couldn’t start a guest profile. Try again or sign in.")
        }
        accept(tokenResponse, accessToken: accessToken, refreshToken: refreshToken, fallbackEmail: nil)
        statusMessage = nil
        return accessToken
    }

    func signOut() async {
        if let session {
            var request = URLRequest(url: endpoint("/auth/v1/logout"))
            request.httpMethod = "POST"
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await NovaNetworkSession.shared.data(for: request)
        }
        clearSession()
    }

    private func request(path: String, body: [String: Any]) async throws -> (data: Data, response: HTTPURLResponse) {
        isWorking = true
        defer { isWorking = false }

        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 25

        let (data, response) = try await NovaNetworkSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NovaAccountError.message("The sign-in service returned an invalid response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
            throw NovaAccountError.message(errorResponse?.message ?? errorResponse?.msg ?? "Account request failed (HTTP \(httpResponse.statusCode)).")
        }
        return (data, httpResponse)
    }

    private func accept(_ response: TokenResponse, accessToken: String, refreshToken: String, fallbackEmail: String?) {
        let expiry = response.expiresAt.map(Date.init(timeIntervalSince1970:))
            ?? Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))
        let newSession = NovaAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiry,
            email: response.user?.email ?? fallbackEmail,
            isAnonymous: response.user?.isAnonymous ?? false
        )
        session = newSession
        saveSession(newSession)
    }

    private func rpc(path: String, body: [String: Any], token: String) async throws -> Data {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 25
        let (data, response) = try await NovaNetworkSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NovaAccountError.message("The owner profile service returned an invalid response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NovaAccountError.message("NOVA couldn’t verify that owner code. Try again.")
        }
        return data
    }

    private func endpoint(_ path: String) -> URL {
        URL(string: path, relativeTo: supabaseURL)!.absoluteURL
    }

    private func clearSession() {
        session = nil
        isOwner = false
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

private extension Data {
    var base64URLString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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
    let isAnonymous: Bool?

    enum CodingKeys: String, CodingKey {
        case email
        case emailConfirmedAt = "email_confirmed_at"
        case isAnonymous = "is_anonymous"
    }
}

private struct OwnerCodeResponse: Decodable {
    let isOwner: Bool?

    enum CodingKeys: String, CodingKey {
        case isOwner = "is_owner"
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
