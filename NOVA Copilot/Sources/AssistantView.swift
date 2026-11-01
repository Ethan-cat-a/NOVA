import AppKit
import SwiftUI

struct AssistantView: View {
    @ObservedObject var model: NovaChatModel
    @ObservedObject var panelState: PanelState
    let onHide: () -> Void
    let onQuit: () -> Void

    @FocusState private var inputFocused: Bool
    @State private var showAlert = false
    @State private var alertTitle = "NOVA Copilot"
    @State private var alertMessage = ""

    private let accent = Color(red: 0.15, green: 0.34, blue: 0.77)
    private let ink = Color(red: 0.09, green: 0.13, blue: 0.20)
    private let muted = Color(red: 0.40, green: 0.45, blue: 0.54)

    var body: some View {
        VStack(spacing: 0) {
            header
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
        .onAppear {
            inputFocused = true
            if let error = model.lastError { showNotice("NOVA Copilot", message: error) }
        }
        .onChange(of: model.lastError) { value in
            if let value, !model.isSending { showNotice("NOVA Copilot", message: value) }
        }
        .alert(Text(alertTitle), isPresented: $showAlert) {
            Button("OK", role: .cancel) {
                showAlert = false
                model.clearDisplayedError()
            }
        } message: { Text(alertMessage) }
    }

    private func showNotice(_ title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
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
                HStack(spacing: 5) {
                    Circle().fill(model.isConnected ? Color(red: 0.13, green: 0.65, blue: 0.39) : Color.orange).frame(width: 6, height: 6)
                    Text(model.connectionStatus).font(.system(size: 10, weight: .medium)).foregroundStyle(muted).lineLimit(1)
                }
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
                            MessageBubble(message: message, accent: accent)
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
            VStack(spacing: 8) {
                starter("Summarize copied text", subtitle: "Use context from another app", icon: "doc.text") {
                    if model.insertClipboardContext() { showNotice("Clipboard", message: "Copied text added to your draft.") }
                    else { showNotice("Clipboard", message: "No text found. Copy some text in any app first.") }
                    inputFocused = true
                }
                starter("Help me write something", subtitle: "Email, essay, or a clear reply", icon: "pencil.line") {
                    model.input = "Help me write something. Ask any essential questions first, then draft it clearly."
                    inputFocused = true
                }
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

    private var composer: some View {
        VStack(spacing: 8) {
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
                Button {
                    if model.insertClipboardContext() {
                        showNotice("Clipboard", message: "Copied text added to your draft.")
                    } else {
                        showNotice("Clipboard", message: "No text found. Copy some text in any app first.")
                    }
                    inputFocused = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(muted)
                        .frame(width: 32, height: 38)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.87, green: 0.89, blue: 0.93), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Attach text from your clipboard")

                TextField("Message Nova V8…", text: $model.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit { model.send() }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 38)
                    .background(.white, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(red: 0.84, green: 0.87, blue: 0.92), lineWidth: 1))

                Button { model.send() } label: {
                    Image(systemName: model.isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(model.isSending ? Color(red: 0.35, green: 0.40, blue: 0.49) : accent, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.isSending && model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(!model.isSending && model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
                .help(model.isSending ? "Stop response" : "Send message (⌘Return)")
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

private struct MessageBubble: View {
    let message: ChatMessage
    let accent: Color

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
                if message.content.isEmpty && !isUser {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("Thinking…").font(.system(size: 12)).foregroundStyle(Color.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text(message.content)
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .foregroundStyle(isUser ? Color.white : Color(red: 0.12, green: 0.16, blue: 0.23))
                        .frame(maxWidth: .infinity, alignment: .leading)
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
