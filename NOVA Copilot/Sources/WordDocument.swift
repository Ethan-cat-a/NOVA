import AppKit
import UniformTypeIdentifiers

enum WordDocument {
    static var docxType: UTType {
        UTType(filenameExtension: "docx") ?? UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
    }

    static var importTypes: [UTType] {
        [docxType, UTType(filenameExtension: "doc")].compactMap { $0 }
    }

    static func isWordFile(_ url: URL) -> Bool {
        ["docx", "doc"].contains(url.pathExtension.lowercased())
    }

    static func readText(from url: URL) throws -> String {
        let type: NSAttributedString.DocumentType = url.pathExtension.lowercased() == "doc"
            ? .docFormat : .officeOpenXML
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return try NSAttributedString(
                data: data,
                options: [.documentType: type],
                documentAttributes: nil
            ).string
        } catch {
            throw WordDocumentError.unreadable
        }
    }

    static func makeData(text: String) throws -> Data {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WordDocumentError.emptyDraft
        }
        let document = formattedDocument(from: text)
        guard document.length > 0 else { throw WordDocumentError.emptyDraft }
        return try document.data(
            from: NSRange(location: 0, length: document.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        )
    }

    private static func formattedDocument(from markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let lines = markdown.components(separatedBy: .newlines)
        var isCodeBlock = false

        for (index, sourceLine) in lines.enumerated() {
            if sourceLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                isCodeBlock.toggle()
                continue
            }

            var content = sourceLine
            var listPrefix = ""
            var font = NSFont.systemFont(ofSize: 11)
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 4

            if isCodeBlock {
                font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            } else {
                let headingLevel = sourceLine.prefix(while: { $0 == "#" }).count
                if (1...6).contains(headingLevel),
                   sourceLine.dropFirst(headingLevel).first == " " {
                    content = String(sourceLine.dropFirst(headingLevel + 1))
                    let size = max(12, 20 - CGFloat(headingLevel - 1) * 1.5)
                    font = NSFont.systemFont(ofSize: size, weight: .bold)
                    paragraph.paragraphSpacingBefore = headingLevel == 1 ? 10 : 6
                    paragraph.paragraphSpacing = 5
                } else if sourceLine.range(of: #"^\s*[-*+]\s+"#, options: .regularExpression) != nil {
                    content = sourceLine.replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "", options: .regularExpression)
                    listPrefix = "•\t"
                    paragraph.headIndent = 14
                    paragraph.paragraphSpacing = 2
                } else if let marker = sourceLine.range(of: #"^\s*\d+[.)]\s+"#, options: .regularExpression) {
                    listPrefix = String(sourceLine[marker]).trimmingCharacters(in: .whitespaces) + "\t"
                    content = String(sourceLine[marker.upperBound...])
                    paragraph.headIndent = 18
                    paragraph.paragraphSpacing = 2
                } else if sourceLine.hasPrefix("> ") {
                    content = String(sourceLine.dropFirst(2))
                    paragraph.headIndent = 14
                    paragraph.paragraphSpacing = 3
                    font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
            }

            let line = NSMutableAttributedString(string: listPrefix)
            line.append(formattedInline(content, baseFont: font, monospaced: isCodeBlock))
            if line.length > 0 {
                line.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: line.length))
            }
            result.append(line)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraph]))
            }
        }

        return result
    }

    private static func formattedInline(_ text: String, baseFont: NSFont, monospaced: Bool) -> NSAttributedString {
        guard !monospaced else {
            return NSAttributedString(string: text, attributes: [.font: baseFont])
        }

        let output = NSMutableAttributedString(string: "")
        let source = text as NSString
        let pattern = #"\*\*(.+?)\*\*|__(.+?)__|(?<!\*)\*([^*]+)\*(?!\*)|(?<![\w_])_([^_]+)_(?![\w_])|`([^`]+)`"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return NSAttributedString(string: text, attributes: [.font: baseFont])
        }

        var cursor = 0
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            guard match.range.location >= cursor else { continue }
            if match.range.location > cursor {
                output.append(NSAttributedString(
                    string: source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
                    attributes: [.font: baseFont]
                ))
            }

            let contentGroup = (1...5).first { match.range(at: $0).location != NSNotFound }
            if let contentGroup {
                let content = source.substring(with: match.range(at: contentGroup))
                let font: NSFont
                switch contentGroup {
                case 1, 2:
                    font = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
                case 3, 4:
                    font = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
                default:
                    font = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
                }
                output.append(NSAttributedString(string: content, attributes: [.font: font]))
            }
            cursor = NSMaxRange(match.range)
        }

        if cursor < source.length {
            output.append(NSAttributedString(
                string: source.substring(from: cursor),
                attributes: [.font: baseFont]
            ))
        }
        return output
    }
}

enum WordDocumentError: LocalizedError {
    case unreadable
    case emptyDraft

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "NOVA couldn’t read that Word document. Try an unprotected .docx file."
        case .emptyDraft:
            return "Add some text before saving your Word document."
        }
    }
}
