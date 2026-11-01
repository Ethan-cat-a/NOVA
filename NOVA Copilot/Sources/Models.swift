import Foundation

// The native companion uses Nova V8's existing conversation contract.
enum NovaMode: String, Codable, CaseIterable, Identifiable {
    case fast
    case thinker
    case coding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "Fast"
        case .thinker: return "Hard Thinker"
        case .coding: return "Coding"
        }
    }

    var instruction: String {
        switch self {
        case .fast:
            return "Answer quickly and directly. Keep the answer concise, prioritize the most useful result first, and avoid unnecessary background or long explanations."
        case .thinker:
            return "Take extra time to analyze the task carefully. Check assumptions, reason through important steps, consider alternatives and edge cases, and verify calculations when possible. Present the conclusion and key rationale clearly without exposing private chain-of-thought."
        case .coding:
            return "Act as a senior software engineer. Provide practical, runnable code when appropriate, with sensible defaults, clear structure, and robust error handling. For debugging, identify the likely root cause and give corrected code. Include concise setup or usage notes and avoid pseudocode unless requested."
        }
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
}

struct ChatMessage: Codable, Identifiable {
    var id: UUID = UUID()
    var role: MessageRole
    var content: String
    var createdAt: Date = Date()
}

struct ChatThread: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String = "New chat"
    var mode: NovaMode = .fast
    var messages: [ChatMessage] = []
    var updatedAt: Date = Date()
}

struct NovaAPIMessage: Codable {
    let role: String
    let content: String
}

struct NovaHealthResponse: Decodable {
    let ok: Bool?
    let keyConfigured: Bool?
    let model: String?
    let upstream: String?
}
