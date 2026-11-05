import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AssistantView: View {
    @ObservedObject var model: NovaChatModel
    @ObservedObject var panelState: PanelState
    let onHide: () -> Void
    let onQuit: () -> Void
    let onCheckForUpdates: () -> Void
    let onShowPreferences: () -> Void
    @ObservedObject var updateStatus: UpdaterStatus

    @FocusState private var inputFocused: Bool
    @State private var showsUpdateNotes = false
    @State private var showsChatHistory = false
    @State private var historySearchText = ""
    @State private var renameRequest: ChatThread?
    @State private var renameTitle = ""
    @State private var deleteRequest: ChatThread?
    @StateObject private var viewState = AssistantViewState()

    private let accent = Color(red: 0.15, green: 0.34, blue: 0.77)
    private let ink = Color.primary
    private let muted = Color.secondary

    var body: some View {
        VStack(spacing: 0) {
            header
            if let message = updateStatus.message {
                HStack(spacing: 7) {
                    Image(systemName: updateStatus.isError
                          ? "exclamationmark.circle.fill"
                          : updateStatus.hasAvailableUpdate ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                    Text(message).lineLimit(2)
                    Spacer(minLength: 0)
                    if updateStatus.hasReleaseNotes {
                        Button("What’s New") { showsUpdateNotes = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .accessibilityLabel("Read release notes for version \(updateStatus.availableVersion ?? "")")
                            .popover(isPresented: $showsUpdateNotes, arrowEdge: .top) {
                                UpdateReleaseNotesPopover(
                                    version: updateStatus.availableVersion ?? "",
                                    releaseNotes: updateStatus.releaseNotes
                                )
                            }
                    }
                    Button { updateStatus.dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss update status")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(updateStatus.isError ? Color.orange : accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background((updateStatus.isError ? Color.orange : accent).opacity(0.07))
            }
            Divider()
            modeBar
            Divider()
            conversation
            composer
        }
        .frame(minWidth: 370, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand(perform: onHide)
        .fileImporter(
            isPresented: $viewState.showsContextImporter,
            allowedContentTypes: [.image, .pdf] + WordDocument.importTypes,
            allowsMultipleSelection: true,
            onCompletion: handleContextImport
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $viewState.isTargetingContext, perform: handleContextDrop)
        .onAppear {
            inputFocused = true
            if let error = model.lastError { showNotice("NOVA Copilot", message: error) }
        }
        .onChange(of: model.lastError) { value in
            if let value, !model.isSending { showNotice("NOVA Copilot", message: value) }
        }
        .onChange(of: model.currentThread.messages.count) { count in
            if count > 0 { viewState.dismissFirstRunTip() }
        }
        .onChange(of: viewState.contextReview?.id) { id in
            if id == nil { processNextContextFile() }
        }
        .alert(Text(viewState.alertTitle), isPresented: $viewState.showAlert) {
            if model.canRetryLastRequest {
                Button("Retry") {
                    viewState.showAlert = false
                    model.clearDisplayedError()
                    model.retryLastRequest()
                }
            }
            Button("OK", role: .cancel) {
                viewState.showAlert = false
                model.clearDisplayedError()
            }
        } message: { Text(viewState.alertMessage) }
        .popover(item: $viewState.clipboardReview, arrowEdge: .top) { review in
            ClipboardActionPopover(
                review: review,
                tone: $viewState.rewriteTone,
                onCancel: { viewState.clipboardReview = nil },
                onRun: { tone in
                    guard model.runClipboardAction(review.action, snapshot: review.snapshot, tone: tone) else {
                        viewState.clipboardReview = nil
                        showFeedback("Send or clear your draft, then try the clipboard action again.", isError: true)
                        return
                    }

                    viewState.clipboardReview = nil
                    let included = review.snapshot.includedCharacterCount.formatted()
                    let count = review.snapshot.wasTruncated
                        ? "first \(included) of \(review.snapshot.originalCharacterCount.formatted()) characters"
                        : "\(included) characters"
                    showFeedback("\(review.action.title) started · \(count) sent to Nova")
                    inputFocused = true
                }
            )
            .padding(6)
        }
        .popover(item: $viewState.contextReview, arrowEdge: .bottom) { attachment in
            ContextReviewPopover(
                attachment: attachment,
                onCancel: { viewState.contextReview = nil },
                onUse: {
                    viewState.contextAttachments.append(attachment)
                    viewState.contextReview = nil
                    inputFocused = true
                }
            )
        }
        .sheet(item: $viewState.wordDraftReview) { draft in
            WordDocumentEditor(draft: draft)
        }
    }

    private func showNotice(_ title: String, message: String) {
        viewState.alertTitle = title
        viewState.alertMessage = message
        viewState.showAlert = true
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("NOVAIcon")
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("NOVA COPILOT").font(.system(size: 13, weight: .bold, design: .rounded)).tracking(0.3).foregroundStyle(ink)
                    Text("V8 CORE").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(accent)
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background(accent.opacity(0.08), in: Capsule())
                }
                Button {
                    guard !model.isConnected, !model.isSending, !model.isCheckingConnection else { return }
                    Task { await model.checkConnection() }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(model.isConnected ? Color(red: 0.13, green: 0.65, blue: 0.39) : Color.orange).frame(width: 6, height: 6)
                        Text(model.connectionStatus).font(.system(size: 10, weight: .medium)).foregroundStyle(muted).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.isConnected || model.isSending || model.isCheckingConnection)
                .help(model.isConnected ? "Nova connection is ready" : "Click to retry the Nova connection")
            }
            Spacer(minLength: 2)
            Button { panelState.togglePinned() } label: {
                Image(systemName: panelState.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(panelState.isPinned ? accent : muted)
                    .frame(width: 29, height: 29)
                    .background(panelState.isPinned ? accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help(panelState.isPinned ? "Unpin from top" : "Keep on top")

            Button(action: onCheckForUpdates) {
                HStack(spacing: 5) {
                    Image(systemName: updateStatus.isChecking ? "arrow.triangle.2.circlepath" : "arrow.down.circle")
                        .font(.system(size: 12, weight: .semibold))
                    Text(updateStatus.isChecking ? "Checking…" : "Update")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(muted)
                .padding(.horizontal, 8)
                .frame(height: 29)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(updateStatus.isChecking)
            .accessibilityLabel("Check for Updates Now")
            .help(updateStatus.message ?? "Check for Updates Now")

            Button { showsChatHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(muted)
                    .frame(width: 29, height: 29)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search chat history")
            .help("Search, rename or delete saved chats")
            .popover(isPresented: $showsChatHistory, arrowEdge: .top) {
                ChatHistoryPopover(
                    model: model,
                    searchText: $historySearchText,
                    onSelect: { thread in
                        model.switchThread(thread.id)
                        showsChatHistory = false
                    },
                    onRename: { thread in
                        renameTitle = thread.title
                        renameRequest = thread
                        showsChatHistory = false
                    },
                    onDelete: { thread in
                        deleteRequest = thread
                        showsChatHistory = false
                    }
                )
            }
            .alert("Rename chat", isPresented: Binding(
                get: { renameRequest != nil },
                set: { if !$0 { renameRequest = nil } }
            )) {
                TextField("Chat name", text: $renameTitle)
                Button("Cancel", role: .cancel) { renameRequest = nil }
                Button("Save") {
                    if let renameRequest { model.renameThread(renameRequest.id, to: renameTitle) }
                    renameRequest = nil
                }
                .disabled(renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Give this conversation a short name. It stays on this Mac.")
            }
            .confirmationDialog("Delete this chat?", isPresented: Binding(
                get: { deleteRequest != nil },
                set: { if !$0 { deleteRequest = nil } }
            ), titleVisibility: .visible) {
                Button("Delete Chat", role: .destructive) {
                    if let deleteRequest { model.deleteThread(deleteRequest.id) }
                    deleteRequest = nil
                }
                Button("Cancel", role: .cancel) { deleteRequest = nil }
            } message: {
                Text("\(deleteRequest?.title ?? "This chat") and its messages will be removed from this Mac.")
            }

            Menu {
                Button { model.newChat() } label: { Label("New chat", systemImage: "plus.message") }
                Divider()
                Text("RECENT CHATS").font(.caption2)
                ForEach(model.threads.prefix(12)) { thread in
                    Button { model.switchThread(thread.id) } label: {
                        if thread.id == model.activeThreadID {
                            Label(thread.title, systemImage: "checkmark")
                        } else {
                            Text(thread.title)
                        }
                    }
                }
                Divider()
                Toggle("Keep on top", isOn: Binding(get: { panelState.isPinned }, set: { panelState.setPinned($0) }))
                Toggle("Launch at Login", isOn: Binding(get: { panelState.launchAtLogin }, set: { panelState.setLaunchAtLogin($0) }))
                Button { onShowPreferences() } label: { Label("Preferences…", systemImage: "slider.horizontal.3") }
                Divider()
                Button { runClipboardQuickAction(.summarize) } label: { Label("Summarize copied text", systemImage: "text.alignleft") }
                Button { runClipboardQuickAction(.rewrite) } label: { Label("Rewrite copied text", systemImage: "pencil.line") }
                Button { Task { await model.checkConnection() } } label: { Label("Check Nova connection", systemImage: "arrow.clockwise") }
                Button { model.clearCurrentChat() } label: { Label("Clear current chat", systemImage: "trash") }
                Divider()
                Button("Hide panel") { onHide() }
                Button("Quit NOVA Copilot") { onQuit() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(muted)
                    .frame(width: 29, height: 29)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
            .menuStyle(.borderlessButton)
            .help("More options and chat history")

            Button(action: onHide) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(muted)
                    .frame(width: 27, height: 27)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Hide (⌘⇧Space to reopen)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.97))
    }

    private var modeBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("MODE").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(muted)
                Picker("Mode", selection: Binding(get: { model.currentMode }, set: { model.setMode($0) })) {
                    ForEach(NovaMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
            if model.currentMode == .wordDocument {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(accent)
                    Text("Create a document or fill one with details. New files format headings, lists, bold and italics; original layouts, tables and images aren’t retained.")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Add files…") { viewState.showsContextImporter = true }
                        .buttonStyle(.plain)
                        .fontWeight(.semibold)
                        .foregroundStyle(accent)
                }
                .font(.system(size: 10))
                .foregroundStyle(muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 15) {
                    if model.currentThread.messages.isEmpty {
                        welcome
                    } else {
                        ForEach(model.currentThread.messages) { message in
                            MessageBubble(
                                message: message,
                                accent: accent,
                                isStreaming: model.streamingMessageID == message.id,
                                canRetry: model.canRetryResponse(message.id),
                                onCopy: { copyResponse(message.content) },
                                onCopyCode: { copyCodeBlock($0) },
                                onRetry: { model.retryResponse(message.id) },
                                onSaveWord: { viewState.wordDraftReview = WordDraftReview(text: message.content) }
                            )
                                .id(message.id)
                        }
                    }
                    Color.clear.frame(height: 1).id("conversation-bottom")
                }
                .padding(.horizontal, 15)
                .padding(.top, 17)
                .padding(.bottom, 15)
            }
            .scrollIndicators(.visible)
            .onChange(of: model.currentThread.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
            }
            .onChange(of: model.currentThread.messages.last?.content) { content in
                guard content != nil,
                      model.streamingMessageID == model.currentThread.messages.last?.id else { return }
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
            .onChange(of: model.activeThreadID) { _ in
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
            .onAppear { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
        }
            // Keep the conversation canvas consistent with the rest of the panel.
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Your AI, one shortcut away.")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Ask Nova V8, work through a problem, or bring in copied text from any Mac app.")
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if viewState.showFirstRunTip {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(accent)
                    Text("Quick tip: ⌘⇧Space opens NOVA anywhere. Copied text is previewed before it’s sent.")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { viewState.dismissFirstRunTip() } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss tip")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(muted)
                .padding(9)
                .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            }
            clipboardQuickActions
            VStack(spacing: 8) {
                starter("Help me write something", subtitle: "Email, essay, or a clear reply", icon: "pencil.line") {
                    model.input = "Help me write something. Ask any essential questions first, then draft it clearly."
                    inputFocused = true
                }
                DisclosureGroup("More examples", isExpanded: $viewState.showMoreExamples) {
                    VStack(spacing: 8) {
                        starter("Explain this simply", subtitle: "Make a difficult concept easier", icon: "sparkles") {
                            model.input = "Explain this concept simply, step by step, with a quick example: "
                            inputFocused = true
                        }
                        starter("Help with code", subtitle: "Debug, build, or improve a project", icon: "chevron.left.forwardslash.chevron.right") {
                            model.setMode(.coding)
                            model.input = "Help me debug or improve this code:\n"
                            inputFocused = true
                        }
                    }
                    .padding(.top, 8)
                }
            }
            HStack(spacing: 5) {
                Image(systemName: "command.circle").font(.system(size: 11))
                Text("Press ⌘⇧Space anywhere to open this panel")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(muted.opacity(0.92))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
    }

    private var clipboardQuickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("COPIED TEXT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(muted)
                Spacer()
                Text("Preview before sending")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(muted.opacity(0.9))
            }

            HStack(spacing: 8) {
                ForEach([ClipboardQuickAction.summarize, .rewrite]) { action in
                    Button { runClipboardQuickAction(action) } label: {
                        Label(action.title, systemImage: action.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }

    private func starter(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left").font(.system(size: 10, weight: .semibold)).foregroundStyle(muted.opacity(0.75))
            }
            .padding(9)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func runClipboardQuickAction(_ action: ClipboardQuickAction) {
        if model.isSending {
            showFeedback("Finish the current reply before starting a clipboard action.", isError: true)
        } else if (
            !viewState.contextAttachments.isEmpty
                || viewState.contextReview != nil
                || !viewState.pendingContextURLs.isEmpty
                || viewState.isExtractingContext
        ) {
            showFeedback("Finish reviewing or remove the attached files before starting a clipboard action.", isError: true)
        } else if !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showFeedback("Send or clear your draft before starting a clipboard action.", isError: true)
        } else if let snapshot = model.clipboardTextSnapshot() {
            viewState.clipboardReview = ClipboardActionReview(action: action, snapshot: snapshot)
        } else {
            showFeedback("No copied text found. Copy some text first, then try again.", isError: true)
        }
    }

    private func handleContextImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            importContextFiles(urls)
        case .failure(let error):
            showFeedback("Couldn’t open that file: \(error.localizedDescription)", isError: true)
        }
    }

    private func handleContextDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else {
            showFeedback("Drop an image, PDF or Word document to add context.", isError: true)
            return false
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var droppedURLs = [URL?](repeating: nil, count: fileProviders.count)
        for (index, provider) in fileProviders.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let value = item as? URL {
                    url = value
                } else if let value = item as? NSURL {
                    url = value as URL
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8) {
                    url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    url = nil
                }
                lock.lock()
                droppedURLs[index] = url
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = droppedURLs.compactMap { $0 }
            if urls.isEmpty {
                showFeedback("Couldn’t read those dropped files. Try choosing them with the paperclip menu.", isError: true)
            } else {
                if urls.count < fileProviders.count {
                    showFeedback("Some dropped files couldn’t be read.", isError: true)
                }
                importContextFiles(urls)
            }
        }
        return true
    }

    private func importContextFiles(_ urls: [URL]) {
        guard !model.isSending else {
            showFeedback("Wait for the current reply to finish before adding context.", isError: true)
            return
        }
        let occupiedSlots = viewState.contextAttachments.count
            + viewState.pendingContextURLs.count
            + (viewState.contextReview == nil ? 0 : 1)
            + (viewState.isExtractingContext ? 1 : 0)
        let remainingSlots = max(0, 5 - occupiedSlots)
        guard remainingSlots > 0 else {
            showFeedback("You can add up to 5 files to one message. Remove a file to add another.", isError: true)
            return
        }
        let acceptedURLs = Array(urls.prefix(remainingSlots))
        if acceptedURLs.count < urls.count {
            showFeedback("NOVA can review up to 5 files for one message. The extra files were skipped.", isError: true)
        }
        viewState.pendingContextURLs.append(contentsOf: acceptedURLs)
        processNextContextFile()
    }

    private func processNextContextFile() {
        guard !viewState.isExtractingContext,
              viewState.contextReview == nil,
              !viewState.pendingContextURLs.isEmpty else { return }
        let url = viewState.pendingContextURLs.removeFirst()
        viewState.isExtractingContext = true
        Task {
            do {
                let attachment = try await ContextTextExtractor.readFile(at: url)
                viewState.isExtractingContext = false
                viewState.contextReview = attachment
            } catch {
                viewState.isExtractingContext = false
                showFeedback(error.localizedDescription, isError: true)
                processNextContextFile()
            }
        }
    }

    private func captureScreenContext() {
        guard !model.isSending else {
            showFeedback("Wait for the current reply to finish before capturing context.", isError: true)
            return
        }
        guard #available(macOS 14.0, *), let screenPicker = viewState.screenPicker else {
            showFeedback(ContextCaptureError.systemCaptureUnavailable.localizedDescription, isError: true)
            return
        }
        viewState.isExtractingContext = true
        do {
            try screenPicker.present { result in
                viewState.isExtractingContext = false
                switch result {
                case .success(let attachment):
                    viewState.contextReview = attachment
                case .failure(let error) where error is CancellationError:
                    break
                case .failure(let error):
                    showFeedback("Couldn’t read the capture: \(error.localizedDescription)", isError: true)
                }
            }
        } catch {
            viewState.isExtractingContext = false
            showFeedback(error.localizedDescription, isError: true)
        }
    }

    private func sendMessage() {
        if model.isSending {
            model.send()
            return
        }
        let attachments = viewState.contextAttachments
        let wordDocuments = attachments.filter { $0.kind == .word }
        if model.currentMode == .wordDocument, wordDocuments.count > 1 {
            showFeedback("Word Doc mode can fill one Word document at a time. Keep one Word file attached and use the other files as references.", isError: true)
            return
        }
        if model.currentMode == .wordDocument, wordDocuments.first?.wasTruncated == true {
            showFeedback("This document is too long to fill safely. Try a shorter document or ask about it in another mode.", isError: true)
            return
        }
        model.send(contextAttachments: attachments)
        if !attachments.isEmpty { viewState.contextAttachments = [] }
    }

    private func copyResponse(_ content: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        showFeedback("Copied NOVA’s response.")
    }

    private func copyCodeBlock(_ content: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        showFeedback("Copied code block.")
    }

    private func contextAttachmentChip(_ attachment: ContextAttachment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.kind.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
            Text(attachment.name)
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 110)
            Button { viewState.contextReview = attachment } label: {
                Image(systemName: "eye")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(muted)
            .help("Review extracted text")
            Button {
                viewState.contextAttachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(muted)
            .help("Remove \(attachment.name)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        .overlay(Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        .help("\(attachment.kind.label) · \(attachment.extractedText.count.formatted()) characters extracted. Review or remove this file.")
    }

    private func showFeedback(_ message: String, isError: Bool = false) {
        withAnimation(.easeOut(duration: 0.18)) {
            viewState.feedbackMessage = message
            viewState.feedbackIsError = isError
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard viewState.feedbackMessage == message else { return }
            withAnimation(.easeIn(duration: 0.18)) { viewState.feedbackMessage = nil }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let feedbackMessage = viewState.feedbackMessage {
                HStack(spacing: 7) {
                    Image(systemName: viewState.feedbackIsError ? "info.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(feedbackMessage)
                        .font(.system(size: 10.5, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.easeIn(duration: 0.15)) { viewState.feedbackMessage = nil }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss message")
                }
                .foregroundStyle(viewState.feedbackIsError ? Color.orange : accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background((viewState.feedbackIsError ? Color.orange : accent).opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityElement(children: .combine)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if panelState.launchLoginError != nil {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(panelState.launchLoginError ?? "")
                    Spacer(minLength: 0)
                    Button { panelState.clearLaunchLoginError() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.orange)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button {
                        viewState.showsContextImporter = true
                    } label: {
                        Label("Add image, PDF or Word document…", systemImage: "doc.badge.plus")
                    }
                    if #available(macOS 14.0, *) {
                        Button(action: captureScreenContext) {
                            Label("Capture a window or screen…", systemImage: "viewfinder")
                        }
                    } else {
                        Button {
                            showFeedback(ContextCaptureError.systemCaptureUnavailable.localizedDescription, isError: true)
                        } label: {
                            Label("Capture a window or screen… (macOS 14+)", systemImage: "viewfinder")
                        }
                    }
                    Divider()
                    Button {
                        if model.insertClipboardContext() {
                            showFeedback("Copied text added to your draft.")
                        } else {
                            showFeedback("No copied text found. Copy some text in any app first.", isError: true)
                        }
                        inputFocused = true
                    } label: {
                        Label("Add copied text", systemImage: "doc.on.clipboard")
                    }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(muted)
                        .frame(width: 32, height: 38)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .help("Add up to 5 images, PDFs or Word documents, capture a screen, or add copied text")

                TextField(
                    viewState.contextAttachments.isEmpty
                        ? (model.currentMode == .wordDocument ? "Describe your Word document…" : "Message Nova V8…")
                        : (model.currentMode == .wordDocument && viewState.contextAttachments.contains(where: { $0.kind == .word })
                           ? "How should NOVA fill this document?"
                           : "Ask about these files…"),
                    text: $model.input,
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit { sendMessage() }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 38)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(nsColor: .separatorColor), lineWidth: 1))

                Button { sendMessage() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: model.isSending ? "stop.fill" : (model.currentMode == .wordDocument ? "doc.text" : "arrow.up"))
                        if model.isSending {
                            Text("Stop")
                        } else if model.currentMode == .wordDocument {
                            Text(viewState.contextAttachments.contains(where: { $0.kind == .word }) ? "Fill" : "Create")
                        }
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, (model.currentMode == .wordDocument && !model.isSending) || model.isSending ? 10 : 0)
                    .frame(minWidth: 38, minHeight: 38)
                    .background(model.isSending ? Color(red: 0.35, green: 0.40, blue: 0.49) : accent, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.isSending && model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewState.contextAttachments.isEmpty)
                .opacity(!model.isSending && model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewState.contextAttachments.isEmpty ? 0.55 : 1)
                .accessibilityLabel(model.isSending ? "Stop response" : "Send message")
                .help(model.isSending ? "Stop response" : (model.currentMode == .wordDocument ? "Create or fill a Word document (⌘Return)" : "Send message (⌘Return)"))
            }
            if viewState.isExtractingContext {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small).scaleEffect(0.75)
                    Text("Reading text on this Mac…")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(muted)
            }
            if !viewState.contextAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewState.contextAttachments) { attachment in
                            contextAttachmentChip(attachment)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .accessibilityLabel("Reviewed files attached to this message")
            }
            if !viewState.pendingContextURLs.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.72)
                    Text("\(viewState.pendingContextURLs.count) more file\(viewState.pendingContextURLs.count == 1 ? "" : "s") waiting for review")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(muted)
            }
            if viewState.isTargetingContext {
                Text("Drop up to 5 images, PDFs or Word documents to review their text")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 5) {
                Text("⌘Return to send")
                Text("·")
                Text("⌘⇧Space to toggle")
                Spacer()
                Text("Chats saved on this Mac")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(muted.opacity(0.82))
        }
        .padding(.horizontal, 13)
        .padding(.top, 11)
        .padding(.bottom, 11)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1) }
    }
}

@MainActor
private final class AssistantViewState: ObservableObject {
    @Published var showAlert = false
    @Published var alertTitle = "NOVA Copilot"
    @Published var alertMessage = ""
    @Published var clipboardReview: ClipboardActionReview?
    @Published var rewriteTone: RewriteTone {
        didSet { UserDefaults.standard.set(rewriteTone.rawValue, forKey: Self.rewriteToneKey) }
    }
    @Published var showFirstRunTip: Bool
    @Published var feedbackMessage: String?
    @Published var feedbackIsError = false
    @Published var showMoreExamples = false
    @Published var showsContextImporter = false
    @Published var contextReview: ContextAttachment?
    @Published var contextAttachments: [ContextAttachment] = []
    @Published var pendingContextURLs: [URL] = []
    @Published var wordDraftReview: WordDraftReview?
    @Published var isExtractingContext = false
    @Published var isTargetingContext = false
    let screenPicker: ScreenContextCapturing?

    private static let rewriteToneKey = "com.novatech.NOVACompanion.rewriteTone"
    private static let firstRunTipDismissedKey = "com.novatech.NOVACompanion.firstRunTipDismissed"

    init() {
        if #available(macOS 14.0, *) {
            screenPicker = ScreenContextPicker()
        } else {
            screenPicker = nil
        }
        rewriteTone = RewriteTone(rawValue: UserDefaults.standard.string(forKey: Self.rewriteToneKey) ?? "") ?? .natural
        showFirstRunTip = !UserDefaults.standard.bool(forKey: Self.firstRunTipDismissedKey)
    }

    func dismissFirstRunTip() {
        guard showFirstRunTip else { return }
        showFirstRunTip = false
        UserDefaults.standard.set(true, forKey: Self.firstRunTipDismissedKey)
    }
}

private struct ChatHistoryPopover: View {
    @ObservedObject var model: NovaChatModel
    @Binding var searchText: String
    let onSelect: (ChatThread) -> Void
    let onRename: (ChatThread) -> Void
    let onDelete: (ChatThread) -> Void

    private var matchingThreads: [ChatThread] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.threads }
        return model.threads.filter { thread in
            thread.title.localizedCaseInsensitiveContains(query)
                || thread.messages.contains { message in
                    (message.displayContent ?? message.content).localizedCaseInsensitiveContains(query)
                }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat history")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Search saved conversations on this Mac")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    model.newChat()
                    onSelect(model.currentThread)
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Start a new chat")
            }

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search titles and messages", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search chat history")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .font(.system(size: 11))
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 1))

            if matchingThreads.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: searchText.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "No chats yet" : "No matching chats")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(matchingThreads) { thread in
                            historyRow(thread)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.visible)
            }
        }
        .padding(14)
        .frame(width: 360, height: 390)
    }

    private func historyRow(_ thread: ChatThread) -> some View {
        HStack(spacing: 4) {
            Button { onSelect(thread) } label: {
                HStack(spacing: 8) {
                    Image(systemName: thread.id == model.activeThreadID ? "checkmark.circle.fill" : "bubble.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(thread.id == model.activeThreadID ? Color.accentColor : Color.secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(thread.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(thread.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(preview(for: thread))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open chat: \(thread.title)")

            Menu {
                Button { onRename(thread) } label: {
                    Label("Rename…", systemImage: "pencil")
                }
                Button(role: .destructive) { onDelete(thread) } label: {
                    Label("Delete…", systemImage: "trash")
                }
                    .disabled(model.isSending)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help("Rename or delete this chat")
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(
            thread.id == model.activeThreadID ? Color.accentColor.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func preview(for thread: ChatThread) -> String {
        guard let message = thread.messages.reversed().first(where: {
            !(($0.displayContent ?? $0.content).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }) else {
            return "No messages yet"
        }
        let content = (message.displayContent ?? message.content)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(content.prefix(120))
    }
}

private struct ContextReviewPopover: View {
    let attachment: ContextAttachment
    let onCancel: () -> Void
    let onUse: () -> Void

    private let ink = Color.primary
    private let muted = Color.secondary
    private let accent = Color(red: 0.15, green: 0.34, blue: 0.77)

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                if let data = attachment.previewData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: attachment.kind.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 42, height: 42)
                        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Review context")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ink)
                    Text(attachment.name)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
            }

            Text("NOVA reads text on this Mac. The original file or capture stays here; only the text below is sent when you submit your question.")
                .font(.system(size: 10.5))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(attachment.extractedText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
            }
            .frame(height: 190)
            .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Text(attachment.wasTruncated
                     ? "First \(attachment.extractedText.count.formatted()) of \(attachment.originalCharacterCount.formatted()) characters"
                     : "\(attachment.extractedText.count.formatted()) characters")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(muted)
                Spacer(minLength: 0)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use extracted text", action: onUse)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 350)
    }
}

private struct WordDraftReview: Identifiable {
    let id = UUID()
    let text: String
}

@MainActor
private struct WordDocumentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var saveError: String?

    init(draft: WordDraftReview) {
        _text = State(initialValue: draft.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review your Word document")
                .font(.system(size: 17, weight: .semibold))
            Text("Use # for headings, - for bullets, and **bold** or *italic*; these are formatted when saved. Existing page layouts, tables and images aren’t retained.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.system(size: 12))
                .accessibilityLabel("Word document text")
                .frame(minHeight: 250)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.gray.opacity(0.25)))
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Word…", action: saveDocument)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(minWidth: 460, minHeight: 370)
        .alert("Couldn’t save the Word document", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Please try again.")
        }
    }

    private func saveDocument() {
        let draftText = text
        let panel = NSSavePanel()
        panel.allowedContentTypes = [WordDocument.docxType]
        panel.nameFieldStringValue = "NOVA Document.docx"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let didStartAccess = url.startAccessingSecurityScopedResource()
                defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try WordDocument.makeData(text: draftText)
                    try data.write(to: url)
                    dismiss()
                } catch {
                    saveError = error.localizedDescription
                }
            }
        }
    }
}

@MainActor
final class UpdaterStatus: ObservableObject {
    @Published private(set) var isChecking = false
    @Published private(set) var message: String?
    @Published private(set) var isError = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var releaseNotes: [String] = []

    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    private var clearWorkItem: DispatchWorkItem?

    var hasAvailableUpdate: Bool { availableVersion != nil }
    var hasReleaseNotes: Bool { !releaseNotes.isEmpty }

    func beginCheck() {
        clearWorkItem?.cancel()
        clearWorkItem = nil
        message = nil
        isError = false
        availableVersion = nil
        releaseNotes = []
        isChecking = true
    }

    func foundUpdate(version: String, description: String?, format: String?) {
        availableVersion = version
        releaseNotes = Self.releaseNoteLines(description, format: format)
        finish("\(version) available · current \(currentVersion)", dismissAfter: nil)
    }

    func finishUpToDate() {
        finish("Up to date · \(currentVersion)")
    }

    func finish(_ message: String, isError: Bool = false, dismissAfter: TimeInterval? = 6) {
        clearWorkItem?.cancel()
        clearWorkItem = nil
        isChecking = false
        self.message = message
        self.isError = isError
        if let dismissAfter {
            let workItem = DispatchWorkItem { [weak self] in self?.dismiss() }
            clearWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + dismissAfter, execute: workItem)
        }
    }

    func dismiss() {
        clearWorkItem?.cancel()
        clearWorkItem = nil
        message = nil
        isError = false
        availableVersion = nil
        releaseNotes = []
    }

    private static func releaseNoteLines(_ description: String?, format: String?) -> [String] {
        guard format == "plain-text", let description else { return [] }
        return description
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: #"^(?:[-*•]\s*)+"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
    }
}

private struct UpdateReleaseNotesPopover: View {
    @Environment(\.dismiss) private var dismiss

    let version: String
    let releaseNotes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("What’s New")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text("NOVA Copilot \(version)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(releaseNotes.enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(red: 0.15, green: 0.34, blue: 0.77))
                                .padding(.top, 2)
                            Text(note)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 210)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 310)
    }
}

private struct ClipboardActionPopover: View {
    let review: ClipboardActionReview
    @Binding var tone: RewriteTone
    let onCancel: () -> Void
    let onRun: (RewriteTone) -> Void

    private let ink = Color.primary
    private let muted = Color.secondary
    private let accent = Color(red: 0.15, green: 0.34, blue: 0.77)

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: review.action.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                Text("Review copied text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ink)
                Spacer(minLength: 0)
            }

            Text("Check the preview before NOVA sends it.")
                .font(.system(size: 11))
                .foregroundStyle(muted)

            Text(review.snapshot.text)
                .font(.system(size: 11.5))
                .lineSpacing(2)
                .lineLimit(5)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                .padding(10)
                .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 9))

            Text(characterCountLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(muted)

            if review.action == .rewrite {
                HStack {
                    Text("Tone")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ink)
                    Spacer()
                    Picker("Tone", selection: $tone) {
                        ForEach(RewriteTone.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                Button(review.action.title) { onRun(tone) }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var characterCountLabel: String {
        let included = review.snapshot.includedCharacterCount.formatted()
        if review.snapshot.wasTruncated {
            return "Showing first \(included) of \(review.snapshot.originalCharacterCount.formatted()) characters"
        }
        return "\(included) characters"
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let accent: Color
    let isStreaming: Bool
    let canRetry: Bool
    let onCopy: () -> Void
    let onCopyCode: (String) -> Void
    let onRetry: () -> Void
    let onSaveWord: () -> Void
    @State private var isHovered = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !isUser {
                Image("NOVAIcon")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Spacer(minLength: 26)
            }
            VStack(alignment: .leading, spacing: 4) {
                if !isUser {
                    Text("NOVA V8").font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(Color.secondary)
                }
                if message.content.isEmpty && !isUser && isStreaming {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("NOVA is thinking…").font(.system(size: 12)).foregroundStyle(Color.secondary)
                    }
                    .padding(.vertical, 4)
                } else if !isUser && !isStreaming {
                    MarkdownResponseView(content: message.content, accent: accent, onCopyCode: onCopyCode)
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAction(named: Text("Copy response")) { onCopy() }
                } else {
                    Text(message.displayContent ?? message.content)
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .foregroundStyle(isUser ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAction(named: Text("Copy response")) {
                            if !isUser { onCopy() }
                        }
                }
                if !isUser && isStreaming && !message.content.isEmpty {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small).scaleEffect(0.62)
                        Text("NOVA is writing…")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(.top, 4)
                    .accessibilityElement(children: .combine)
                }
                if !isUser && !message.content.isEmpty && !isStreaming && isHovered {
                    HStack(spacing: 12) {
                        Button(action: onCopy) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .help("Copy NOVA’s response")

                        if canRetry {
                            Button(action: onRetry) {
                                Label("Try again", systemImage: "arrow.clockwise")
                            }
                            .help("Regenerate this response")
                        }

                        if message.isWordDocumentDraft == true {
                            Button(action: onSaveWord) {
                                Label("Review & Save Word…", systemImage: "square.and.arrow.down")
                            }
                            .help("Review and save this response as a Word document")
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
                    .padding(.top, 7)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(isUser ? accent : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(isUser ? Color.clear : Color(nsColor: .separatorColor), lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if isUser {
                Image(systemName: "person.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
                    .background(accent, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Spacer(minLength: 0).frame(maxWidth: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct MarkdownResponseView: View {
    let content: String
    let accent: Color
    let onCopyCode: (String) -> Void

    private var blocks: [MarkdownResponseBlock] { MarkdownResponseBlock.parse(content) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownResponseBlock) -> some View {
        switch block.style {
        case .paragraph:
            markdownText(block.text)
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .heading(let level):
            markdownText(block.text)
                .font(.system(size: level == 1 ? 17 : level == 2 ? 15 : 13.5, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 3)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Circle().fill(accent).frame(width: 4, height: 4).padding(.leading, 3)
                markdownText(block.text)
                    .font(.system(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .numbered(let number):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(number)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(minWidth: 15, alignment: .trailing)
                markdownText(block.text)
                    .font(.system(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .quote:
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.6)).frame(width: 3)
                markdownText(block.text)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
        case .code(let language):
            MarkdownCodeBlock(code: block.text, language: language, onCopy: onCopyCode)
        }
    }

    private func markdownText(_ source: String) -> Text {
        if let attributed = try? AttributedString(markdown: source) {
            return Text(attributed)
        }
        return Text(source)
    }
}

private struct MarkdownCodeBlock: View {
    let code: String
    let language: String
    let onCopy: (String) -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !language.isEmpty || isHovered {
                HStack {
                    Text(language.isEmpty ? "CODE" : language.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isHovered {
                        Button { onCopy(code) } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .help("Copy this code block")
                    }
                }
            }
            Text(code)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct MarkdownResponseBlock: Identifiable {
    enum Style {
        case paragraph
        case heading(Int)
        case bullet
        case numbered(String)
        case quote
        case code(String)
    }

    let id: Int
    let style: Style
    let text: String

    static func parse(_ source: String) -> [MarkdownResponseBlock] {
        var blocks: [MarkdownResponseBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?

        func append(_ style: Style, _ text: String) {
            blocks.append(MarkdownResponseBlock(id: blocks.count, style: style, text: text))
        }

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let text = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { append(.paragraph, text) }
            paragraphLines.removeAll(keepingCapacity: true)
        }

        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if codeLanguage != nil {
                if trimmed.hasPrefix("```") {
                    append(.code(codeLanguage ?? ""), codeLines.joined(separator: "\n"))
                    codeLines.removeAll(keepingCapacity: true)
                    codeLanguage = nil
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            let headingMarks = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(headingMarks), trimmed.dropFirst(headingMarks).first?.isWhitespace == true {
                flushParagraph()
                let text = trimmed.dropFirst(headingMarks).trimmingCharacters(in: .whitespaces)
                append(.heading(headingMarks), text)
                continue
            }

            if let bullet = ["- ", "* ", "+ "].first(where: { trimmed.hasPrefix($0) }) {
                flushParagraph()
                append(.bullet, String(trimmed.dropFirst(bullet.count)))
                continue
            }

            if let match = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flushParagraph()
                let prefix = String(trimmed[match]).trimmingCharacters(in: .whitespaces)
                append(.numbered(prefix), String(trimmed[match.upperBound...]))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                append(.quote, String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }

            if trimmed.range(of: #"^(?:---+|___+|\*\*\*+)$"#, options: .regularExpression) != nil {
                flushParagraph()
                continue
            }

            paragraphLines.append(line)
        }

        flushParagraph()
        if let codeLanguage {
            append(.code(codeLanguage), codeLines.joined(separator: "\n"))
        }
        return blocks
    }
}
