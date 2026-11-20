import AppKit
import SwiftUI

struct ProjectPatchComposerSheet: View {
    let draft: ProjectPatchDraft
    let onSend: (String, Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var task: String
    @State private var includedPaths: Set<String>

    init(draft: ProjectPatchDraft, initialTask: String, onSend: @escaping (String, Set<String>) -> Void) {
        self.draft = draft
        self.onSend = onSend
        _task = State(initialValue: initialTask)
        _includedPaths = State(initialValue: Set(draft.candidates.map(\.relativePath)))
    }

    private var includedCharacters: Int {
        draft.candidates.filter { includedPaths.contains($0.relativePath) }.reduce(0) { $0 + $1.source.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prepare a project patch").font(.system(size: 16, weight: .semibold))
                    Text(draft.rootName).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("Choose the files NOVA may read. Only the checked files below are sent; nothing is changed until you review and approve the proposed diff.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(draft.candidates) { candidate in
                        VStack(alignment: .leading, spacing: 5) {
                            Toggle(isOn: Binding(
                                get: { includedPaths.contains(candidate.relativePath) },
                                set: { selected in
                                    if selected { includedPaths.insert(candidate.relativePath) }
                                    else { includedPaths.remove(candidate.relativePath) }
                                }
                            )) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(candidate.relativePath)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .lineLimit(2)
                                    Spacer(minLength: 8)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(candidate.byteCount), countStyle: .file))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)

                            DisclosureGroup("Preview file text") {
                                ScrollView([.horizontal, .vertical]) {
                                    Text(candidate.source)
                                        .font(.system(size: 9, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(7)
                                }
                                .frame(maxHeight: 105)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                            }
                            .font(.system(size: 9, weight: .medium))
                            .padding(.leading, 22)
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
            .frame(maxHeight: 240)

            HStack {
                Text("Task for NOVA")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(includedPaths.count) files · \(includedCharacters.formatted()) characters")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: $task)
                .font(.system(size: 11))
                .frame(height: 78)
                .padding(5)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 1))

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Ask NOVA for a patch") {
                    onSend(task.trimmingCharacters(in: .whitespacesAndNewlines), includedPaths)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(includedPaths.isEmpty || task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 560, height: 620)
    }
}

struct ProjectPatchReviewSheet: View {
    let message: ChatMessage
    let onApplied: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var patches: [ProposedProjectFilePatch] = []
    @State private var selectedPaths: Set<String> = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isApplying = false
    @State private var confirmsApply = false

    private var context: ProjectPatchContext? { message.projectPatchContext }
    private var selectedPatches: [ProposedProjectFilePatch] {
        patches.filter { selectedPaths.contains($0.relativePath) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review code changes").font(.system(size: 16, weight: .semibold))
                    Text(context?.rootName ?? "Selected project")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("Select each file you want to change. NOVA saves the originals to a local backup before applying your approval.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking the proposed changes against the selected project files…")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(patches) { patch in
                            VStack(alignment: .leading, spacing: 7) {
                                Toggle(patch.relativePath, isOn: Binding(
                                    get: { selectedPaths.contains(patch.relativePath) },
                                    set: { selected in
                                        if selected { selectedPaths.insert(patch.relativePath) }
                                        else { selectedPaths.remove(patch.relativePath) }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                DisclosureGroup("View unified diff") {
                                    ScrollView([.horizontal, .vertical]) {
                                        Text(patch.diff)
                                            .font(.system(size: 9, design: .monospaced))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(8)
                                    }
                                    .frame(maxHeight: 190)
                                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                                }
                                .font(.system(size: 9, weight: .medium))
                                .padding(.leading, 21)
                            }
                            .padding(9)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }

            if isApplying {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Saving backups and applying the approved files…")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            HStack {
                if let errorMessage, !isLoading {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button("Apply \(selectedPaths.count) selected file\(selectedPaths.count == 1 ? "" : "s")…") { confirmsApply = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || errorMessage != nil || selectedPaths.isEmpty || isApplying)
            }
        }
        .padding(18)
        .frame(width: 560, height: 570)
        .onAppear(perform: loadPatches)
        .confirmationDialog(
            "Apply the selected project changes?",
            isPresented: $confirmsApply,
            titleVisibility: .visible
        ) {
            Button("Apply \(selectedPaths.count) file\(selectedPaths.count == 1 ? "" : "s")", role: .destructive, action: applySelectedPatches)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("NOVA will make a local backup of each original file, then apply only the checked diffs. This will change files in \(context?.rootName ?? "the selected project").")
        }
    }

    private func loadPatches() {
        guard let context else {
            errorMessage = "This response has no project review data."
            isLoading = false
            return
        }
        Task { @MainActor in
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try ProjectPatchEngine.proposePatches(from: message.content, context: context)
                }.value
                patches = parsed
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func applySelectedPatches() {
        guard let context, !selectedPatches.isEmpty else { return }
        isApplying = true
        errorMessage = nil
        let approved = selectedPatches
        Task { @MainActor in
            do {
                let backupFolder = try await Task.detached(priority: .userInitiated) {
                    try ProjectPatchEngine.apply(approved, context: context)
                }.value
                onApplied(backupFolder)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isApplying = false
        }
    }
}
