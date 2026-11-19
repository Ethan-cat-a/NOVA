import CryptoKit
import Foundation

struct ProjectPatchSnapshot: Codable, Identifiable {
    var id: String { relativePath }
    let relativePath: String
    let sha256: String
}

struct ProjectPatchContext: Codable, Identifiable {
    var id: UUID = UUID()
    let rootName: String
    let rootBookmarkData: Data
    let snapshots: [ProjectPatchSnapshot]
}

struct ProjectPatchCandidate: Identifiable {
    var id: String { relativePath }
    let relativePath: String
    let source: String
    let sha256: String
    let byteCount: Int
}

struct ProjectPatchDraft: Identifiable {
    var id: UUID = UUID()
    let rootName: String
    let rootBookmarkData: Data
    let candidates: [ProjectPatchCandidate]

    func context(including paths: Set<String>) -> ProjectPatchContext {
        ProjectPatchContext(
            rootName: rootName,
            rootBookmarkData: rootBookmarkData,
            snapshots: candidates
                .filter { paths.contains($0.relativePath) }
                .map { ProjectPatchSnapshot(relativePath: $0.relativePath, sha256: $0.sha256) }
        )
    }

    func sourcePreview(including paths: Set<String>) -> String {
        candidates
            .filter { paths.contains($0.relativePath) }
            .map { "FILE: \($0.relativePath)\n--- BEGIN PROJECT SOURCE ---\n\($0.source)\n--- END PROJECT SOURCE ---" }
            .joined(separator: "\n\n")
    }
}

struct ProposedProjectFilePatch: Identifiable {
    var id: String { relativePath }
    let relativePath: String
    let diff: String
    let originalHash: String
    let proposedData: Data
}

enum ProjectPatchError: LocalizedError {
    case noSupportedFiles
    case noSelectedFiles
    case unreadableFolder
    case malformedDiff(String)
    case unsupportedChange(String)
    case staleFile(String)
    case unsafePath(String)
    case backupFailed(String)
    case applyFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSupportedFiles:
            return "No supported source files were found. NOVA checks a limited set of code and text files and skips hidden, build, dependency and credential files."
        case .noSelectedFiles:
            return "Select at least one source file to send to NOVA."
        case .unreadableFolder:
            return "NOVA couldn’t access that project folder. Choose it again and retry."
        case .malformedDiff(let detail):
            return "NOVA’s patch could not be safely reviewed: \(detail)"
        case .unsupportedChange(let detail):
            return "This patch includes an unsupported change: \(detail)"
        case .staleFile(let path):
            return "\(path) changed after NOVA read it. Ask NOVA to prepare a fresh patch."
        case .unsafePath(let path):
            return "The patch points outside the selected project or to an unreviewed file: \(path)"
        case .backupFailed(let detail):
            return "NOVA couldn’t save a backup, so no project files were changed. \(detail)"
        case .applyFailed(let detail):
            return "NOVA couldn’t finish applying the patch. It restored any files it had already changed. \(detail)"
        }
    }
}

enum ProjectPatchEngine {
    private struct OutputLine {
        let text: String
        let originalIndex: Int?
        var hasNoNewlineMarker = false
    }

    static let maximumFiles = 12
    static let maximumFileBytes = 96 * 1024
    static let maximumPreviewCharacters = 15_000
    private static let maximumScannedEntries = 5_000
    private static let maximumResponseCharacters = 180_000
    private static let maximumResultBytes = 256 * 1024

    private static let supportedExtensions: Set<String> = [
        "swift", "m", "mm", "h", "c", "cc", "cpp", "cxx", "py", "js", "jsx", "ts", "tsx",
        "java", "kt", "go", "rs", "rb", "php", "sh", "zsh", "json", "yaml", "yml", "toml",
        "xml", "plist", "html", "css", "scss", "sql", "gradle", "pbxproj", "md", "txt"
    ]
    private static let ignoredDirectoryNames: Set<String> = [
        ".git", ".build", "build", "deriveddata", "node_modules", "pods", ".venv", "venv",
        "vendor", "dist", "target", "out", "coverage", "__pycache__"
    ]
    private static let blockedExtensions: Set<String> = ["pem", "key", "p12", "pfx", "mobileprovision", "cer", "crt"]

    static func makeDraft(for folder: URL) throws -> ProjectPatchDraft {
        let bookmark = try folder.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let didStartAccess = folder.startAccessingSecurityScopedResource()
        defer { if didStartAccess { folder.stopAccessingSecurityScopedResource() } }
        guard didStartAccess else { throw ProjectPatchError.unreadableFolder }

        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { throw ProjectPatchError.unreadableFolder }

        var candidateURLs: [(URL, String, Int)] = []
        var scanned = 0
        while let url = enumerator.nextObject() as? URL {
            scanned += 1
            if scanned > maximumScannedEntries { break }
            let name = url.lastPathComponent.lowercased()
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values?.isDirectory == true {
                if ignoredDirectoryNames.contains(name) { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true,
                  !isSensitiveName(url.lastPathComponent),
                  !blockedExtensions.contains(url.pathExtension.lowercased()),
                  supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(rootPath) else { continue }
            let size = values?.fileSize ?? 0
            guard size > 0, size <= maximumFileBytes else { continue }
            let relativePath = String(resolved.path.dropFirst(rootPath.count))
            guard isSafeRelativePath(relativePath) else { continue }
            candidateURLs.append((resolved, relativePath, size))
        }

        let chosen = candidateURLs.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }.prefix(maximumFiles)
        var candidates: [ProjectPatchCandidate] = []
        var totalCharacters = 0
        for (url, relativePath, expectedSize) in chosen {
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                  data.count == expectedSize,
                  data.count <= maximumFileBytes,
                  !data.contains(0),
                  let source = String(data: data, encoding: .utf8),
                  !containsLikelySecret(source) else { continue }
            let remaining = maximumPreviewCharacters - totalCharacters
            guard remaining > 0 else { break }
            let includedSource = String(source.prefix(remaining))
            // Do not offer a file for patching if the model would see only part of it.
            guard includedSource.count == source.count else { continue }
            totalCharacters += source.count
            candidates.append(ProjectPatchCandidate(
                relativePath: relativePath,
                source: source,
                sha256: sha256(data),
                byteCount: data.count
            ))
        }
        guard !candidates.isEmpty else { throw ProjectPatchError.noSupportedFiles }
        return ProjectPatchDraft(rootName: folder.lastPathComponent, rootBookmarkData: bookmark, candidates: candidates)
    }

    static func proposePatches(from response: String, context: ProjectPatchContext) throws -> [ProposedProjectFilePatch] {
        guard response.count <= maximumResponseCharacters else {
            throw ProjectPatchError.malformedDiff("the response is too large")
        }
        let scopedRoot = try resolveRoot(context)
        defer { scopedRoot.stop() }
        let root = scopedRoot.url
        let rawLines = response.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var lines = rawLines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        if lines.first?.trimmingCharacters(in: .whitespaces) == "```diff" || lines.first?.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeFirst()
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
        }
        let snapshots = Dictionary(uniqueKeysWithValues: context.snapshots.map { ($0.relativePath, $0) })
        var cursor = 0
        var patches: [ProposedProjectFilePatch] = []
        while cursor < lines.count {
            while cursor < lines.count && lines[cursor].isEmpty { cursor += 1 }
            guard cursor < lines.count else { break }
            if lines[cursor].hasPrefix("diff --git ") {
                let fields = lines[cursor].split(separator: " ")
                guard fields.count == 4, fields[2].hasPrefix("a/"), fields[3].hasPrefix("b/") else {
                    throw ProjectPatchError.malformedDiff("invalid Git diff header")
                }
                cursor += 1
            }
            while cursor < lines.count && isMetadataLine(lines[cursor]) { cursor += 1 }
            guard cursor + 1 < lines.count, lines[cursor].hasPrefix("--- "), lines[cursor + 1].hasPrefix("+++ ") else {
                throw ProjectPatchError.malformedDiff("expected an existing-file unified diff")
            }
            let diffStart = cursor
            let oldPath = try parseDiffPath(String(lines[cursor].dropFirst(4)))
            let newPath = try parseDiffPath(String(lines[cursor + 1].dropFirst(4)))
            guard oldPath == newPath else { throw ProjectPatchError.unsupportedChange("renames and new files are not allowed") }
            guard let snapshot = snapshots[oldPath] else { throw ProjectPatchError.unsafePath(oldPath) }
            cursor += 2

            let fileURL = try resolveFile(oldPath, under: root)
            let original = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            guard sha256(original) == snapshot.sha256 else { throw ProjectPatchError.staleFile(oldPath) }
            guard original.count <= maximumFileBytes, let originalText = String(data: original, encoding: .utf8) else {
                throw ProjectPatchError.malformedDiff("\(oldPath) is no longer a supported text file")
            }

            let oldLines = originalText.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            let originalHasFinalNewline = originalText.hasSuffix("\n")
            var sourceLines = oldLines
            if originalHasFinalNewline, sourceLines.last == "" { sourceLines.removeLast() }
            var outputLines: [OutputLine] = []
            var oldCursor = 0
            var sawHunk = false

            while cursor < lines.count, lines[cursor].hasPrefix("@@ ") {
                sawHunk = true
                let hunk = try parseHunkHeader(lines[cursor])
                cursor += 1
                let hunkStart = hunk.oldStart == 0 ? 0 : hunk.oldStart - 1
                guard hunkStart >= oldCursor, hunkStart <= sourceLines.count else {
                    throw ProjectPatchError.malformedDiff("hunk offsets overlap or exceed \(oldPath)")
                }
                let unchangedBeforeHunk = hunkStart - oldCursor
                let expectedNewStart = outputLines.count + unchangedBeforeHunk + (hunk.newCount == 0 ? 0 : 1)
                guard hunk.newStart == expectedNewStart else {
                    throw ProjectPatchError.malformedDiff("hunk offsets do not line up in \(oldPath)")
                }
                outputLines.append(contentsOf: (oldCursor..<hunkStart).map { OutputLine(text: sourceLines[$0], originalIndex: $0) })
                oldCursor = hunkStart
                var consumedOld = 0
                var consumedNew = 0
                var lastOutputKind: Character?
                while consumedOld < hunk.oldCount || consumedNew < hunk.newCount {
                    guard cursor < lines.count else { throw ProjectPatchError.malformedDiff("an incomplete hunk in \(oldPath)") }
                    let line = lines[cursor]
                    cursor += 1
                    guard let marker = line.first else { throw ProjectPatchError.malformedDiff("an empty hunk line in \(oldPath)") }
                    let body = String(line.dropFirst())
                    switch marker {
                    case " ":
                        guard consumedOld < hunk.oldCount, oldCursor < sourceLines.count, sourceLines[oldCursor] == body else {
                            throw ProjectPatchError.malformedDiff("context did not match \(oldPath)")
                        }
                        outputLines.append(OutputLine(text: body, originalIndex: oldCursor))
                        oldCursor += 1
                        consumedOld += 1
                        consumedNew += 1
                        lastOutputKind = " "
                    case "-":
                        guard consumedOld < hunk.oldCount, oldCursor < sourceLines.count, sourceLines[oldCursor] == body else {
                            throw ProjectPatchError.malformedDiff("removed text did not match \(oldPath)")
                        }
                        oldCursor += 1
                        consumedOld += 1
                        lastOutputKind = "-"
                    case "+":
                        guard consumedNew < hunk.newCount else { throw ProjectPatchError.malformedDiff("hunk counts did not match \(oldPath)") }
                        outputLines.append(OutputLine(text: body, originalIndex: nil))
                        consumedNew += 1
                        lastOutputKind = "+"
                    case "\\":
                        guard line == "\\ No newline at end of file" else { throw ProjectPatchError.malformedDiff("unsupported hunk marker") }
                        if (lastOutputKind == " " || lastOutputKind == "+"), !outputLines.isEmpty {
                            outputLines[outputLines.count - 1].hasNoNewlineMarker = true
                        }
                    default:
                        throw ProjectPatchError.malformedDiff("invalid hunk line in \(oldPath)")
                    }
                }
                if cursor < lines.count, lines[cursor] == "\\ No newline at end of file" {
                    cursor += 1
                    if (lastOutputKind == " " || lastOutputKind == "+"), !outputLines.isEmpty {
                        outputLines[outputLines.count - 1].hasNoNewlineMarker = true
                    }
                }
            }
            guard sawHunk else { throw ProjectPatchError.malformedDiff("\(oldPath) has no patch hunks") }
            outputLines.append(contentsOf: (oldCursor..<sourceLines.count).map { OutputLine(text: sourceLines[$0], originalIndex: $0) })
            let newline = originalText.contains("\r\n") ? "\r\n" : "\n"
            let finalNewline: Bool
            if let last = outputLines.last {
                if let originalIndex = last.originalIndex {
                    finalNewline = originalIndex < sourceLines.count - 1 || originalHasFinalNewline
                } else {
                    finalNewline = !last.hasNoNewlineMarker
                }
            } else {
                finalNewline = false
            }
            let proposedText = outputLines.map(\.text).joined(separator: newline) + (finalNewline ? newline : "")
            guard let proposedData = proposedText.data(using: .utf8), proposedData.count <= maximumResultBytes else {
                throw ProjectPatchError.malformedDiff("the proposed \(oldPath) is too large")
            }
            guard proposedData != original else { throw ProjectPatchError.malformedDiff("the patch does not change \(oldPath)") }
            let diff = lines[diffStart..<cursor].joined(separator: "\n")
            patches.append(ProposedProjectFilePatch(
                relativePath: oldPath,
                diff: diff,
                originalHash: snapshot.sha256,
                proposedData: proposedData
            ))
            guard patches.count <= maximumFiles else { throw ProjectPatchError.malformedDiff("too many files") }
        }
        guard !patches.isEmpty else { throw ProjectPatchError.malformedDiff("no file changes were included") }
        guard Set(patches.map(\.relativePath)).count == patches.count else {
            throw ProjectPatchError.malformedDiff("a file appears more than once")
        }
        return patches
    }

    static func apply(_ patches: [ProposedProjectFilePatch], context: ProjectPatchContext) throws -> URL {
        guard !patches.isEmpty else { throw ProjectPatchError.noSelectedFiles }
        let scopedRoot = try resolveRoot(context)
        defer { scopedRoot.stop() }
        let root = scopedRoot.url
        let snapshots = Dictionary(uniqueKeysWithValues: context.snapshots.map { ($0.relativePath, $0) })
        var staged: [(patch: ProposedProjectFilePatch, url: URL, original: Data, permissions: Any?)] = []
        for patch in patches {
            guard let snapshot = snapshots[patch.relativePath], snapshot.sha256 == patch.originalHash else {
                throw ProjectPatchError.unsafePath(patch.relativePath)
            }
            let url = try resolveFile(patch.relativePath, under: root)
            let original = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard sha256(original) == patch.originalHash else { throw ProjectPatchError.staleFile(patch.relativePath) }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            staged.append((patch, url, original, attributes[.posixPermissions]))
        }

        let backupRoot = try backupDirectory(for: context, root: root)
        do {
            var permissionManifest: [String: Int] = [:]
            for item in staged {
                let backupURL = backupRoot.appendingPathComponent(item.patch.relativePath)
                try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try item.original.write(to: backupURL, options: .atomic)
                if let permissions = item.permissions as? NSNumber {
                    permissionManifest[item.patch.relativePath] = permissions.intValue
                }
            }
            let manifest = try PropertyListSerialization.data(fromPropertyList: permissionManifest, format: .xml, options: 0)
            try manifest.write(to: backupRoot.appendingPathComponent(".nova-file-permissions.plist"), options: .atomic)
        } catch {
            throw ProjectPatchError.backupFailed(error.localizedDescription)
        }

        var applied: [Int] = []
        do {
            for (index, item) in staged.enumerated() {
                let current = try Data(contentsOf: item.url, options: [.mappedIfSafe])
                guard sha256(current) == item.patch.originalHash else { throw ProjectPatchError.staleFile(item.patch.relativePath) }
                try item.patch.proposedData.write(to: item.url, options: .atomic)
                applied.append(index)
                if let permissions = item.permissions {
                    try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: item.url.path)
                }
            }
        } catch {
            for index in applied.reversed() {
                let item = staged[index]
                try? item.original.write(to: item.url, options: .atomic)
                if let permissions = item.permissions {
                    try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: item.url.path)
                }
            }
            if let patchError = error as? ProjectPatchError { throw patchError }
            throw ProjectPatchError.applyFailed(error.localizedDescription)
        }
        return backupRoot
    }

    private static func resolveRoot(_ context: ProjectPatchContext) throws -> ScopedFolderURL {
        var isStale = false
        guard let bookmarked = try? URL(
            resolvingBookmarkData: context.rootBookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), bookmarked.startAccessingSecurityScopedResource() else {
            throw ProjectPatchError.unreadableFolder
        }
        return ScopedFolderURL(url: bookmarked)
    }

    private static func resolveFile(_ relativePath: String, under root: URL) throws -> URL {
        guard isSafeRelativePath(relativePath) else { throw ProjectPatchError.unsafePath(relativePath) }
        let rootURL = root.resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(rootPrefix),
              let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true else { throw ProjectPatchError.unsafePath(relativePath) }
        return candidate
    }

    private static func backupDirectory(for context: ProjectPatchContext, root: URL) throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ProjectPatchError.backupFailed("Application Support is unavailable.")
        }
        let folderHash = String(sha256(Data(root.path.utf8)).prefix(16))
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = support.appendingPathComponent("NOVA Copilot/Patch Backups/\(folderHash)/\(timestamp)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            throw ProjectPatchError.backupFailed(error.localizedDescription)
        }
    }

    private static func parseDiffPath(_ value: String) throws -> String {
        let path = value.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? value
        guard path.hasPrefix("a/") || path.hasPrefix("b/") else { throw ProjectPatchError.unsupportedChange("absolute paths and new files are not allowed") }
        let relative = String(path.dropFirst(2))
        guard isSafeRelativePath(relative) else { throw ProjectPatchError.unsafePath(relative) }
        return relative
    }

    private static func parseHunkHeader(_ line: String) throws -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int) {
        let pattern = "^@@ -(\\d+)(?:,(\\d+))? \\+(\\d+)(?:,(\\d+))? @@(?:.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            throw ProjectPatchError.malformedDiff("invalid unified diff hunk header")
        }
        func number(_ index: Int, default fallback: Int? = nil) -> Int? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: line) else { return fallback }
            return Int(line[swiftRange])
        }
        guard let oldStart = number(1), let oldCount = number(2, default: 1),
              let newStart = number(3), let newCount = number(4, default: 1) else {
            throw ProjectPatchError.malformedDiff("invalid unified diff hunk counts")
        }
        return (oldStart, oldCount, newStart, newCount)
    }

    private static func isMetadataLine(_ line: String) -> Bool {
        line.hasPrefix("index ")
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func isSensitiveName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower == ".env" || lower.hasPrefix(".env.") || lower.contains("credential") || lower.contains("secret")
            || lower == "id_rsa" || lower == "id_ed25519" || lower.hasSuffix(".lock")
    }

    private static func containsLikelySecret(_ source: String) -> Bool {
        let patterns = [
            #"(?i)\b(?:api[_-]?key|client[_-]?secret|access[_-]?token|password|secret|token)\b\s*[:=]\s*["'][A-Za-z0-9_./+=-]{12,}["']"#,
            #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
            #"\bgh[pousr]_[A-Za-z0-9]{30,}\b"#,
            #"\bsk-[A-Za-z0-9_-]{24,}\b"#
        ]
        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            return regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private final class ScopedFolderURL {
    let url: URL
    private var isAccessing = true

    init(url: URL) { self.url = url }

    func stop() {
        guard isAccessing else { return }
        isAccessing = false
        url.stopAccessingSecurityScopedResource()
    }

    deinit { stop() }
}
