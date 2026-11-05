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
    @StateObject private var viewState = AssistantViewState()

    private let accent = Color(red: 0.15, green: 0.34, blue: 0.77)
    private let ink = Color(red: 0.09, green: 0.13, blue: 0.20)
    private let muted = Color(red: 0.40, green: 0.45, blue: 0.54)

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
            Divider().overlay(Color(red: 0.89, green: 0.91, blue: 0.94))
            modeBar
            Divider().overlay(Color(red: 0.92, green: 0.93, blue: 0.95))
            conversation
            composer
        }
        .frame(minWidth: 370, minHeight: 500)
        .background(Color(red: 0.975, green: 0.980, blue: 0.988))
        .preferredColorScheme(.light)
        .onExitCommand(perform: onHide)
        .fileImporter(
            isPresented: $viewState.showsContextImporter,
            allowedContentTypes: [.image, .pdf] + WordDocument.importTypes,
            allowsMultipleSelection: false,
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
                    viewState.contextAttachment = attachment
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
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))

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
                .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(updateStatus.isChecking)
            .accessibilityLabel("Check for Updates Now")
            .help(updateStatus.message ?? "Check for Updates Now")

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
                    .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
            .menuStyle(.borderlessButton)
            .help("More options and chat history")

            Button(action: onHide) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(muted)
                    .frame(width: 27, height: 27)
                    .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Hide (⌘⇧Space to reopen)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white.opacity(0.97))
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
                    Text("Create a document or add one to fill with details in this message. Saved files contain text only; formatting and images aren’t retained.")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Add Word…") { viewState.showsContextImporter = true }
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
        .background(Color.white)
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
        .background(Color(red: 0.975, green: 0.980, blue: 0.988))
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
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.89, green: 0.91, blue: 0.94), lineWidth: 1))
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
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.89, green: 0.91, blue: 0.94), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func runClipboardQuickAction(_ action: ClipboardQuickAction) {
        if model.isSending {
            showFeedback("Finish the current reply before starting a clipboard action.", isError: true)
        } else if viewState.contextAttachment != nil {
            showFeedback("Send or remove the reviewed attachment before starting a clipboard action.", isError: true)
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
            guard let url = urls.first else { return }
            importContextFile(url)
        case .failure(let error):
            showFeedback("Couldn’t open that file: \(error.localizedDescription)", isError: true)
        }
    }

    private func handleContextDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            showFeedback("Drop an image, PDF or Word document to add context.", isError: true)
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            let droppedURL: URL?
            if let url = item as? URL {
                droppedURL = url
            } else if let url = item as? NSURL {
                droppedURL = url as URL
            } else if let data = item as? Data,
                      let string = String(data: data, encoding: .utf8) {
                droppedURL = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                droppedURL = nil
            }
            DispatchQueue.main.async {
                if let droppedURL {
                    importContextFile(droppedURL)
                } else {
                    showFeedback("Couldn’t read that dropped file. Try choosing it with the paperclip menu.", isError: true)
                }
            }
        }
        return true
    }

    private func importContextFile(_ url: URL) {
        guard !model.isSending else {
            showFeedback("Wait for the current reply to finish before adding context.", isError: true)
            return
        }
        viewState.contextAttachment = nil
        viewState.isExtractingContext = true
        Task {
            defer { viewState.isExtractingContext = false }
            do {
                viewState.contextReview = try await ContextTextExtractor.readFile(at: url)
            } catch {
                showFeedback(error.localizedDescription, isError: true)
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
        let attachment = viewState.contextAttachment
        if model.currentMode == .wordDocument, attachment?.wasTruncated == true {
            showFeedback("This document is too long to fill safely. Try a shorter document or ask about it in another mode.", isError: true)
            return
        }
        model.send(contextAttachment: attachment)
        if attachment != nil { viewState.contextAttachment = nil }
    }

    private func copyResponse(_ content: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        showFeedback("Copied NOVA’s response.")
    }

    @ViewBuilder
    private func contextAttachmentCard(_ attachment: ContextAttachment) -> some View {
        HStack(spacing: 8) {
            if let data = attachment.previewData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                Image(systemName: attachment.kind.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(attachment.name)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text("\(attachment.kind.label) · \(attachment.extractedText.count.formatted()) characters ready")
                    .font(.system(size: 9.5))
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Review") { viewState.contextReview = attachment }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
            Button { viewState.contextAttachment = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(muted)
            }
            .buttonStyle(.plain)
            .help("Remove context")
        }
        .padding(7)
        .background(Color(red: 0.975, green: 0.980, blue: 0.988), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(red: 0.89, green: 0.91, blue: 0.94), lineWidth: 1))
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
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.87, green: 0.89, blue: 0.93), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .help("Add an image, PDF, Word document, screenshot, or copied text")

                TextField(
                    viewState.contextAttachment == nil
                        ? (model.currentMode == .wordDocument ? "Describe your Word document…" : "Message Nova V8…")
                        : (model.currentMode == .wordDocument ? "How should NOVA fill this document?" : "Ask about this context…"),
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
                    .background(.white, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(red: 0.84, green: 0.87, blue: 0.92), lineWidth: 1))

                Button { sendMessage() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: model.isSending ? "stop.fill" : (model.currentMode == .wordDocument ? "doc.text" : "arrow.up"))
                        if model.isSending {
                            Text("Stop")
                        } else if model.currentMode == .wordDocument {
                            Text(viewState.contextAttachment?.kind == .word ? "Fill" : "Create")
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
                .disabled(!model.isSending && model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewState.contextAttachment == nil)
                .opacity(!model.isSending && model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewState.contextAttachment == nil ? 0.55 : 1)
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
            } else if let attachment = viewState.contextAttachment {
                contextAttachmentCard(attachment)
            }
            if viewState.isTargetingContext {
                Text("Drop an image, PDF or Word document to review its text")
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
        .background(.white)
        .overlay(alignment: .top) { Rectangle().fill(Color(red: 0.89, green: 0.91, blue: 0.94)).frame(height: 1) }
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
    @Published var contextAttachment: ContextAttachment?
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

private struct ContextReviewPopover: View {
    let attachment: ContextAttachment
    let onCancel: () -> Void
    let onUse: () -> Void

    private let ink = Color(red: 0.09, green: 0.13, blue: 0.20)
    private let muted = Color(red: 0.40, green: 0.45, blue: 0.54)
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
            .background(Color(red: 0.975, green: 0.980, blue: 0.988), in: RoundedRectangle(cornerRadius: 8))

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
            Text("Edit the text before saving. The Word file contains text; original formatting, tables and images aren’t retained.")
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
                    .foregroundStyle(Color(red: 0.09, green: 0.13, blue: 0.20))
                Text("NOVA Copilot \(version)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.40, green: 0.45, blue: 0.54))
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
                                .foregroundStyle(Color(red: 0.18, green: 0.22, blue: 0.29))
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

    private let ink = Color(red: 0.09, green: 0.13, blue: 0.20)
    private let muted = Color(red: 0.40, green: 0.45, blue: 0.54)
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
                .background(Color(red: 0.96, green: 0.97, blue: 0.985), in: RoundedRectangle(cornerRadius: 9))

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
    let onRetry: () -> Void
    let onSaveWord: () -> Void

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
                    Text("NOVA V8").font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.50))
                }
                if message.content.isEmpty && !isUser && isStreaming {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("NOVA is thinking…").font(.system(size: 12)).foregroundStyle(Color.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text(message.displayContent ?? message.content)
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .foregroundStyle(isUser ? Color.white : Color(red: 0.12, green: 0.16, blue: 0.23))
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                if !isUser && !message.content.isEmpty && !isStreaming {
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
            .background(isUser ? accent : .white, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(isUser ? Color.clear : Color(red: 0.90, green: 0.92, blue: 0.95), lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if isUser {
                Image(systemName: "person.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
                    .background(Color(red: 0.42, green: 0.48, blue: 0.61), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Spacer(minLength: 0).frame(maxWidth: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}
