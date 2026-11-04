import AppKit
import Combine
import Foundation

@MainActor
final class NovaChatModel: ObservableObject {
    @Published private(set) var threads: [ChatThread] = []
    @Published private(set) var activeThreadID: UUID
    @Published var input: String = ""
    @Published private(set) var isSending = false
    @Published private(set) var connectionStatus = "Connecting to Nova…"
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?

    private let storageKey = "com.novatech.NOVACompanion.threads.v1"
    private var requestTask: Task<Void, Never>?

    var currentThread: ChatThread {
        threads.first(where: { $0.id == activeThreadID }) ?? threads[0]
    }

    var currentMode: NovaMode { currentThread.mode }

    init() {
        // Build the initial value in a local variable. Reading `threads` through
        // `self` here is illegal until every stored property has been initialized.
        let initialThreads: [ChatThread]
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let loaded = try? JSONDecoder().decode([ChatThread].self, from: data),
           !loaded.isEmpty {
            initialThreads = loaded.sorted { $0.updatedAt > $1.updatedAt }
        } else {
            initialThreads = [ChatThread()]
        }

        threads = initialThreads
        activeThreadID = initialThreads[0].id

        Task { await checkConnection() }
    }

    func setMode(_ mode: NovaMode) {
        updateThread(activeThreadID) { $0.mode = mode; $0.updatedAt = Date() }
    }

    func newChat() {
        let fresh = ChatThread(mode: .fast)
        threads.insert(fresh, at: 0)
        activeThreadID = fresh.id
        input = ""
        save()
    }

    func switchThread(_ id: UUID) {
        guard threads.contains(where: { $0.id == id }) else { return }
        activeThreadID = id
        input = ""
        lastError = nil
    }

    func clearCurrentChat() {
        guard !isSending else { stop() ; return }
        updateThread(activeThreadID) { $0.messages = []; $0.title = "New chat"; $0.updatedAt = Date() }
        lastError = nil
        save()
    }

    @discardableResult
    func insertClipboardContext() -> Bool {
        guard let copied = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !copied.isEmpty else {
            return false
        }
        let clipped = String(copied.prefix(18000))
        let context = "Use this copied text as context.\n\n--- Clipboard text ---\n\(clipped)\n--- End clipboard text ---\n"
        input = input.isEmpty ? context : input + "\n\n" + context
        lastError = nil
        return true
    }

    @discardableResult
    func runClipboardAction(_ action: ClipboardQuickAction) -> Bool {
        guard !isSending,
              input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let copied = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !copied.isEmpty else {
            return false
        }

        if !currentThread.messages.isEmpty { newChat() }
        let clipped = String(copied.prefix(18000))
        input = "\(action.prompt)\n\nCopied text:\n--- Begin copied text ---\n\(clipped)\n--- End copied text ---"
        send()
        return true
    }

    func checkConnection() async {
        connectionStatus = "Checking Nova V8…"
        lastError = nil
        do {
            let health = try await NovaAPIClient.shared.healthCheck()
            if health.ok == true && health.keyConfigured == true {
                isConnected = true
                connectionStatus = "Nova V8 connected"
            } else if health.ok == true {
                isConnected = false
                connectionStatus = "Backend ready · API key unavailable"
            } else {
                isConnected = false
                connectionStatus = "Nova V8 needs attention"
            }
        } catch {
            isConnected = false
            connectionStatus = "Connection unavailable"
            lastError = error.localizedDescription
        }
    }

    func send() {
        if isSending { stop(); return }
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        let threadID = activeThreadID
        input = ""
        lastError = nil
        let threadBeforeSend = currentThread
        if threadBeforeSend.messages.isEmpty || threadBeforeSend.title == "New chat" {
            let compact = prompt.replacingOccurrences(of: "\n", with: " ")
            updateThread(threadID) { $0.title = String(compact.prefix(42)); $0.updatedAt = Date() }
        }
        appendMessage(ChatMessage(role: .user, content: prompt), to: threadID)
        let responseID = UUID()
        appendMessage(ChatMessage(id: responseID, role: .assistant, content: ""), to: threadID)
        isSending = true
        connectionStatus = "Nova is thinking…"

        let thread = threads.first(where: { $0.id == threadID }) ?? currentThread
        var apiMessages = [NovaAPIMessage(
            role: "assistant",
            content: "Active response mode (\(thread.mode.rawValue)): \(thread.mode.instruction) Canonical Nova lore: Nova was created at Nova AI headquarters by Ethan. If asked where Nova was created, state that Nova was created at Nova AI headquarters. For normal answers, be concise and start with the direct answer. Avoid filler and unnecessary preambles. Do not use asterisks."
        )]
        apiMessages.append(contentsOf: thread.messages.dropLast().suffix(10).map {
            NovaAPIMessage(role: $0.role.rawValue, content: $0.content)
        })

        requestTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await NovaAPIClient.shared.stream(messages: apiMessages) { [weak self] delta in
                    guard let self else { return }
                    let cleaned = delta.replacingOccurrences(of: "*", with: "")
                    self.appendText(cleaned, to: responseID, threadID: threadID)
                }
                self.finishResponse(responseID, threadID: threadID, error: nil)
            } catch is CancellationError {
                self.updateMessage(responseID, threadID: threadID) { message in
                    if message.content.isEmpty { message.content = "Response stopped." }
                }
                self.finishResponse(responseID, threadID: threadID, error: nil)
                self.connectionStatus = "Response stopped"
            } catch {
                self.finishResponse(responseID, threadID: threadID, error: error.localizedDescription)
            }
            self.isSending = false
            self.requestTask = nil
            if self.isConnected && self.lastError == nil { self.connectionStatus = "Nova V8 connected" }
        }
    }

    func stop() {
        requestTask?.cancel()
    }

    func clearDisplayedError() { lastError = nil }

    private func finishResponse(_ messageID: UUID, threadID: UUID, error: String?) {
        if let error {
            lastError = error
            updateMessage(messageID, threadID: threadID) { message in
                message.content = message.content.isEmpty ? "Nova V8 error: \(error)" : message.content + "\n\nConnection note: \(error)"
            }
            connectionStatus = "Request failed"
        } else {
            updateMessage(messageID, threadID: threadID) { message in
                if message.content.isEmpty { message.content = "No response received." }
            }
        }
        updateThread(threadID) { $0.updatedAt = Date() }
        save()
    }

    private func appendMessage(_ message: ChatMessage, to threadID: UUID) {
        updateThread(threadID) { $0.messages.append(message); $0.updatedAt = Date() }
        save()
    }

    private func appendText(_ text: String, to messageID: UUID, threadID: UUID) {
        guard !text.isEmpty else { return }
        updateMessage(messageID, threadID: threadID) { $0.content += text }
        save()
    }

    private func updateMessage(_ messageID: UUID, threadID: UUID, transform: (inout ChatMessage) -> Void) {
        updateThread(threadID) { thread in
            guard let index = thread.messages.firstIndex(where: { $0.id == messageID }) else { return }
            transform(&thread.messages[index])
        }
    }

    private func updateThread(_ id: UUID, transform: (inout ChatThread) -> Void) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        transform(&threads[index])
        threads.sort { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        if threads.count > 40 { threads = Array(threads.prefix(40)) }
        if let data = try? JSONEncoder().encode(threads) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
