import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct DocumentLibraryFolder: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var bookmarkData: Data
}

enum DocumentLibraryError: LocalizedError {
    case noFolders
    case noSupportedDocuments
    case noSearchTerms
    case noMatches
    case noGitRepository
    case gitUnavailable
    case gitFailed(String)

    var errorDescription: String? {
        switch self {
        case .noFolders:
            return "Choose a document folder first."
        case .noSupportedDocuments:
            return "No readable documents or source-code files were found in those folders."
        case .noSearchTerms:
            return "Add a few details to your question so NOVA can find relevant documents."
        case .noMatches:
            return "No matching documents found. Try a phrase or name that appears in the files."
        case .noGitRepository:
            return "Add the root folder of a Git repository to My Documents first."
        case .gitUnavailable:
            return "Git could not be started in this sandboxed app."
        case .gitFailed(let detail):
            return detail
        }
    }
}

@MainActor
final class DocumentLibraryStore: ObservableObject {
    static let shared = DocumentLibraryStore()

    @Published private(set) var folders: [DocumentLibraryFolder]
    @Published private(set) var isSearching = false

    private let storageKey = "com.novatech.NOVACompanion.documentFolders.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([DocumentLibraryFolder].self, from: data) {
            folders = decoded
        } else {
            folders = []
        }
    }

    func addFolders(at urls: [URL]) throws {
        for url in urls {
            guard url.isFileURL else { continue }
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            if folders.contains(where: { $0.name == url.lastPathComponent && $0.bookmarkData == bookmark }) {
                continue
            }
            folders.append(DocumentLibraryFolder(name: url.lastPathComponent, bookmarkData: bookmark))
        }
        save()
    }

    func removeFolder(_ folder: DocumentLibraryFolder) {
        folders.removeAll { $0.id == folder.id }
        save()
    }

    func retrieveRelevantDocuments(for query: String) async throws -> [ContextAttachment] {
        guard !folders.isEmpty else { throw DocumentLibraryError.noFolders }
        isSearching = true
        defer { isSearching = false }

        let savedFolders = folders
        return try await Task.detached(priority: .userInitiated) {
            try await DocumentLibrarySearch.retrieve(query: query, folders: savedFolders)
        }.value
    }

    func retrieveGitSummary() async throws -> String {
        guard !folders.isEmpty else { throw DocumentLibraryError.noFolders }
        let savedFolders = folders
        return try await Task.detached(priority: .userInitiated) {
            try DocumentLibrarySearch.gitSummary(folders: savedFolders)
        }.value
    }

    func openFirstFolderInXcode() throws {
        guard !folders.isEmpty else { throw DocumentLibraryError.noFolders }
        for folder in folders {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: folder.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess { url.stopAccessingSecurityScopedResource() }
            }
            guard didStartAccess else { continue }
            try CSAgentComputerTools.openXcodeProject(in: url)
            return
        }
        throw DocumentLibraryError.noFolders
    }

    private func save() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

private enum DocumentLibrarySearch {
    private struct RankedDocument {
        let attachment: ContextAttachment
        let score: Int
    }

    private static let ignoredTerms: Set<String> = [
        "about", "after", "again", "also", "and", "are", "can", "could", "did", "does", "for",
        "from", "give", "have", "help", "how", "into", "make", "more", "most", "need", "please",
        "that", "the", "their", "them", "there", "this", "what", "when", "where", "which", "with",
        "would", "your"
    ]

    static func retrieve(query: String, folders: [DocumentLibraryFolder]) async throws -> [ContextAttachment] {
        let terms = Set(query.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !ignoredTerms.contains($0) })
        guard !terms.isEmpty else { throw DocumentLibraryError.noSearchTerms }

        var roots: [URL] = []
        var activeRoots: [URL] = []
        for folder in folders {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: folder.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            if url.startAccessingSecurityScopedResource() { activeRoots.append(url) }
            roots.append(url)
        }
        defer { activeRoots.forEach { $0.stopAccessingSecurityScopedResource() } }

        let files = collectSupportedFiles(in: roots)
        guard !files.isEmpty else { throw DocumentLibraryError.noSupportedDocuments }

        let ranked = await withTaskGroup(of: RankedDocument?.self, returning: [RankedDocument].self) { group in
            var iterator = files.makeIterator()
            for _ in 0..<min(4, files.count) {
                if let url = iterator.next() {
                    group.addTask { await readAndRank(url, terms: terms) }
                }
            }

            var matches: [RankedDocument] = []
            while let document = await group.next() {
                if let document, document.score > 0 { matches.append(document) }
                if let url = iterator.next() {
                    group.addTask { await readAndRank(url, terms: terms) }
                }
            }
            return matches.sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.attachment.name.localizedStandardCompare($1.attachment.name) == .orderedAscending
            }
        }

        guard !ranked.isEmpty else { throw DocumentLibraryError.noMatches }
        return ranked.prefix(4).map { document in
            let excerpt = relevantExcerpt(from: document.attachment.extractedText, terms: terms)
            return ContextAttachment(
                name: document.attachment.name,
                kind: document.attachment.kind,
                extractedText: excerpt,
                previewData: nil,
                originalCharacterCount: document.attachment.originalCharacterCount,
                fromLibrary: true
            )
        }
    }

    static func gitSummary(folders: [DocumentLibraryFolder]) throws -> String {
        for folder in folders {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: folder.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess { url.stopAccessingSecurityScopedResource() }
            }
            guard didStartAccess else { continue }
            let gitDirectory = url.appendingPathComponent(".git", isDirectory: true)
            guard FileManager.default.fileExists(atPath: gitDirectory.path) else { continue }

            let status = try runGit(in: url, arguments: ["status", "--short", "--branch", "--no-optional-locks"])
            let changeSummary = try runGit(in: url, arguments: ["diff", "--stat", "--no-ext-diff"])
            let latestCommit = try runGit(in: url, arguments: ["log", "-1", "--oneline", "--no-decorate"])
            return [
                "Repository: \(folder.name)",
                "Git status (read-only):\n\(status.isEmpty ? "Clean working tree" : status)",
                "Unstaged change summary:\n\(changeSummary.isEmpty ? "No unstaged changes" : changeSummary)",
                "Latest commit:\n\(latestCommit.isEmpty ? "No commits found" : latestCommit)"
            ].joined(separator: "\n\n").prefix(8_000).description
        }
        throw DocumentLibraryError.noGitRepository
    }

    private static func runGit(in folder: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-C", folder.path] + arguments
        process.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/bin:/bin",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_OPTIONAL_LOCKS": "0"
        ]

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw DocumentLibraryError.gitUnavailable
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let stdout = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw DocumentLibraryError.gitFailed(detail.isEmpty ? "Git could not read this repository." : String(detail.prefix(240)))
        }
        return String(stdout.prefix(5_000))
    }

    private static func readAndRank(_ url: URL, terms: Set<String>) async -> RankedDocument? {
        guard let attachment = try? await ContextTextExtractor.readFile(at: url) else { return nil }
        let text = attachment.extractedText.lowercased()
        let name = attachment.name.lowercased()
        let score = terms.reduce(into: 0) { total, term in
            if name.contains(term) { total += 5 }
            if let range = text.range(of: term) {
                total += 1
                let afterFirst = text[range.upperBound...]
                if afterFirst.range(of: term) != nil { total += 1 }
            }
        }
        return RankedDocument(attachment: attachment, score: score)
    }

    private static func collectSupportedFiles(in roots: [URL]) -> [URL] {
        var files: [URL] = []
        var seenPaths = Set<String>()
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                guard ["pdf", "doc", "docx", "txt", "rtf", "md", "swift", "m", "h", "c", "cc", "cpp", "cxx", "py", "js", "jsx", "ts", "tsx", "java", "kt", "go", "rs", "rb", "php", "sh", "zsh", "json", "yaml", "yml", "toml", "xml", "plist", "html", "css", "scss", "sql", "gradle", "xcodeproj", "pbxproj"].contains(ext),
                      (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      seenPaths.insert(fileURL.standardizedFileURL.path).inserted else { continue }
                files.append(fileURL)
            }
        }
        return files
    }

    private static func relevantExcerpt(from text: String, terms: Set<String>) -> String {
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let match = terms
            .map { source.range(of: $0, options: [.caseInsensitive], range: fullRange) }
            .filter { $0.location != NSNotFound }
            .min { $0.location < $1.location }

        let start = max(0, (match?.location ?? 0) - 900)
        let length = min(3_500, source.length - start)
        var excerpt = source.substring(with: NSRange(location: start, length: length))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if start > 0 { excerpt = "…\(excerpt)" }
        if start + length < source.length { excerpt += "…" }
        return excerpt
    }
}
