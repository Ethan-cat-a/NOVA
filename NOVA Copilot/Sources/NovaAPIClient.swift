import Foundation

@MainActor
final class NovaAPIClient {
    static let shared = NovaAPIClient()

    private let chatURL = URL(string: "https://nova-copilot-gateway.vercel.app/api/chat")!

    private init() {}

    func healthCheck() async throws -> NovaHealthResponse {
        var request = URLRequest(url: chatURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NovaAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NovaAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(NovaHealthResponse.self, from: data)
    }

    /// Streams the raw text response through the authenticated NOVA gateway.
    /// The model credential remains on the server.
    func stream(messages: [NovaAPIMessage], onText: @escaping @MainActor (String) -> Void) async throws {
        let accessToken = try await NovaAccountStore.shared.accessTokenForRequest()
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 180
        request.httpBody = try JSONEncoder().encode(NovaChatRequest(messages: messages))

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NovaAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
                if errorData.count >= 8192 { break }
            }
            let rawDetail = String(data: errorData, encoding: .utf8) ?? "The NOVA backend returned an error."
            let detail = (try? JSONDecoder().decode(GatewayErrorResponse.self, from: errorData).error) ?? rawDetail
            throw NovaAPIError.httpStatus(http.statusCode, detail)
        }

        // Flush small chunks for a responsive typing effect without splitting UTF-8 characters.
        var buffer = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= 28 || byte == 10 {
                let safeCount = Self.completeUTF8PrefixLength(in: buffer)
                if safeCount > 0 {
                    let prefix = buffer.prefix(safeCount)
                    let piece = String(decoding: prefix, as: UTF8.self)
                    buffer.removeFirst(safeCount)
                    if !piece.isEmpty { onText(piece) }
                }
            }
        }
        if !buffer.isEmpty {
            onText(String(decoding: buffer, as: UTF8.self))
        }
    }

    private static func completeUTF8PrefixLength(in data: Data) -> Int {
        guard !data.isEmpty else { return 0 }
        let bytes = [UInt8](data)
        var leadIndex = bytes.count - 1
        while leadIndex > 0 && (bytes[leadIndex] & 0xC0) == 0x80 {
            leadIndex -= 1
        }
        let lead = bytes[leadIndex]
        let expectedLength: Int
        if lead < 0x80 { expectedLength = 1 }
        else if (lead & 0xE0) == 0xC0 { expectedLength = 2 }
        else if (lead & 0xF0) == 0xE0 { expectedLength = 3 }
        else if (lead & 0xF8) == 0xF0 { expectedLength = 4 }
        else { expectedLength = 1 }
        let availableFromLead = bytes.count - leadIndex
        if availableFromLead < expectedLength { return leadIndex }
        return bytes.count
    }
}

private struct NovaChatRequest: Encodable {
    let messages: [NovaAPIMessage]
}

private struct GatewayErrorResponse: Decodable {
    let error: String?
}

enum NovaAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Nova V8 returned an invalid response."
        case let .httpStatus(code, detail):
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Nova V8 request failed (HTTP \(code))." : "Nova V8 request failed (HTTP \(code)): \(trimmed.prefix(450))"
        }
    }
}
