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
        let document = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        return try document.data(
            from: NSRange(location: 0, length: document.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        )
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
