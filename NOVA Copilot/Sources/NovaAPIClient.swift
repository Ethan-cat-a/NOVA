import Foundation
import OSLog

enum NovaNetworkSession {
    private static let metricsDelegate = NovaNetworkMetricsDelegate()

    /// Keep one URLSession and its per-host connection pool alive for the life of the app.
    /// Limiting fan-out avoids unnecessary sockets while leaving room for a health check
    /// and a chat request to overlap; HTTP/2 can multiplex them on the same connection.
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration, delegate: metricsDelegate, delegateQueue: nil)
    }()
}

private final class NovaNetworkMetricsDelegate: NSObject, URLSessionTaskDelegate {
    private let logger = Logger(subsystem: "com.novatechnologies.novacopilot", category: "Network")

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transaction = metrics.transactionMetrics.last else { return }
        let tlsMilliseconds = Self.milliseconds(from: transaction.secureConnectionStartDate, to: transaction.secureConnectionEndDate)
        let dnsMilliseconds = Self.milliseconds(from: transaction.domainLookupStartDate, to: transaction.domainLookupEndDate)
        let tcpMilliseconds = Self.milliseconds(from: transaction.connectStartDate, to: transaction.connectEndDate)
        let responseMilliseconds = Self.milliseconds(from: transaction.fetchStartDate, to: transaction.responseStartDate)
        let tls = tlsMilliseconds.map(String.init) ?? (transaction.isReusedConnection ? "reused" : "n/a")
        let path = task.currentRequest?.url?.path ?? "/"

        logger.info("request path=\(path, privacy: .public) protocol=\(transaction.networkProtocolName ?? "unknown", privacy: .public) reused=\(transaction.isReusedConnection, privacy: .public) dns_ms=\(dnsMilliseconds ?? -1, privacy: .public) tcp_ms=\(tcpMilliseconds ?? -1, privacy: .public) tls_ms=\(tls, privacy: .public) first_byte_ms=\(responseMilliseconds ?? -1, privacy: .public)")
    }

    private static func milliseconds(from start: Date?, to end: Date?) -> Int? {
        guard let start, let end else { return nil }
        return max(0, Int((end.timeIntervalSince(start) * 1_000).rounded()))
    }
}

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
        let (data, response) = try await NovaNetworkSession.shared.data(for: request)
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

        let (bytes, response) = try await NovaNetworkSession.shared.bytes(for: request)
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
            if buffer.count >= 8 || byte == 10 {
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
