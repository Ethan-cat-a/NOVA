import AppKit
import Foundation

enum CSAgentComputerTools {
    static func searchGoogleInChrome(_ query: String) throws {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CSAgentComputerToolError.emptyQuery }
        guard let chromeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            throw CSAgentComputerToolError.appNotInstalled("Google Chrome")
        }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: String(trimmed.prefix(300)))]
        guard let searchURL = components.url else { throw CSAgentComputerToolError.invalidURL }
        NSWorkspace.shared.open([searchURL], withApplicationAt: chromeURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { NSLog("NOVA could not open Google Chrome: %@", error.localizedDescription) }
        }
    }

    static func openMicrosoftWord() throws {
        guard let wordURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.Word") else {
            throw CSAgentComputerToolError.appNotInstalled("Microsoft Word")
        }
        NSWorkspace.shared.openApplication(at: wordURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { NSLog("NOVA could not open Microsoft Word: %@", error.localizedDescription) }
        }
    }

    static func openXcodeProject(in folder: URL) throws {
        guard let xcodeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") else {
            throw CSAgentComputerToolError.appNotInstalled("Xcode")
        }
        let project = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.first(where: { ["xcworkspace", "xcodeproj"].contains($0.pathExtension.lowercased()) }) ?? folder
        NSWorkspace.shared.open([project], withApplicationAt: xcodeURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { NSLog("NOVA could not open Xcode project: %@", error.localizedDescription) }
        }
    }

    @MainActor
    static func readCurrentChromePage() throws -> ContextAttachment {
        let source = #"""
        tell application "Google Chrome"
            if (count of windows) is 0 then return ""
            set currentTab to active tab of front window
            set pageTitle to title of currentTab
            set pageURL to URL of currentTab
            set pageText to execute currentTab javascript "document.body ? document.body.innerText : ''"
            return pageTitle & linefeed & pageURL & linefeed & pageText
        end tell
        """#
        guard let script = NSAppleScript(source: source) else {
            throw CSAgentComputerToolError.chromeScriptUnavailable
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let detail = errorInfo["NSAppleScriptErrorMessage"] as? String ?? "macOS denied access to Google Chrome."
            throw CSAgentComputerToolError.chromeReadFailed(detail)
        }
        let raw = result.stringValue ?? ""
        let lines = raw.components(separatedBy: .newlines)
        guard lines.count >= 3, let pageURL = lines.dropFirst().first, pageURL.hasPrefix("http") else {
            throw CSAgentComputerToolError.noActiveChromePage
        }
        let title = String(lines[0].prefix(180)).trimmingCharacters(in: .whitespacesAndNewlines)
        let pageText = lines.dropFirst(2).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pageText.isEmpty else { throw CSAgentComputerToolError.noReadablePageText }
        let excerpt = String(pageText.prefix(ContextTextExtractor.maximumCharacters))
        let safeTitle = title.isEmpty ? "Untitled page" : title
        let sourceText = "Page title: \(safeTitle)\nPage URL: \(pageURL)\n\n\(excerpt)"
        return ContextAttachment(
            name: "Chrome · \(safeTitle)",
            kind: .textDocument,
            extractedText: sourceText,
            previewData: nil,
            originalCharacterCount: pageText.count
        )
    }
}

enum CSAgentComputerToolError: LocalizedError {
    case emptyQuery
    case invalidURL
    case appNotInstalled(String)
    case chromeScriptUnavailable
    case chromeReadFailed(String)
    case noActiveChromePage
    case noReadablePageText

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Type a question before opening Google Search."
        case .invalidURL:
            return "NOVA couldn’t make that Google Search link."
        case .appNotInstalled(let name):
            return "\(name) isn’t installed in the Applications folder."
        case .chromeScriptUnavailable:
            return "NOVA couldn’t prepare the Google Chrome page reader."
        case .chromeReadFailed(let detail):
            return "Couldn’t read the current Chrome page. Allow NOVA to control Google Chrome in System Settings. In Chrome, also enable View → Developer → Allow JavaScript from Apple Events. (\(detail))"
        case .noActiveChromePage:
            return "Open a web page in Google Chrome, then try Share Chrome page again."
        case .noReadablePageText:
            return "The current Chrome page has no readable text to share."
        }
    }
}
