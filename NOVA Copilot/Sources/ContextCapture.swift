import AppKit
import ImageIO
import PDFKit
import ScreenCaptureKit
import UniformTypeIdentifiers
import Vision

struct ContextAttachment: Identifiable {
    enum Kind: Equatable {
        case image
        case pdf
        case screenshot
        case word

        var label: String {
            switch self {
            case .image: return "Image"
            case .pdf: return "PDF"
            case .screenshot: return "Screenshot"
            case .word: return "Word document"
            }
        }

        var icon: String {
            switch self {
            case .image: return "photo"
            case .pdf: return "doc.richtext"
            case .screenshot: return "viewfinder"
            case .word: return "doc.text"
            }
        }
    }

    let id = UUID()
    let name: String
    let kind: Kind
    let extractedText: String
    let previewData: Data?
    let originalCharacterCount: Int

    var wasTruncated: Bool { extractedText.count < originalCharacterCount }
}

enum ContextCaptureError: LocalizedError {
    case unsupportedFile
    case fileTooLarge
    case noReadableText
    case systemCaptureUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "Choose an image, PDF or Word document."
        case .fileTooLarge:
            return "This file is too large to read. Choose a file smaller than 20 MB."
        case .noReadableText:
            return "NOVA couldn’t find readable text. Try a clearer image or a document containing text."
        case .systemCaptureUnavailable:
            return "Screen capture requires macOS 14 or later. You can still add an image or PDF."
        }
    }
}

enum ContextTextExtractor {
    static let maximumCharacters = 15_000
    private static let maximumFileBytes = 20 * 1024 * 1024
    private static let maximumPDFPages = 12

    static func readFile(at url: URL) async throws -> ContextAttachment {
        try await Task.detached(priority: .userInitiated) {
            try extractFile(at: url)
        }.value
    }

    static func readScreenshot(_ image: CGImage, name: String) async throws -> ContextAttachment {
        try await Task.detached(priority: .userInitiated) {
            let text = try recognizeText(in: image)
            return try makeAttachment(
                name: name,
                kind: .screenshot,
                text: text,
                previewData: pngData(from: image)
            )
        }.value
    }

    private static func extractFile(at url: URL) throws -> ContextAttachment {
        guard url.isFileURL else { throw ContextCaptureError.unsupportedFile }
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > maximumFileBytes {
            throw ContextCaptureError.fileTooLarge
        }

        if WordDocument.isWordFile(url) {
            return try makeAttachment(
                name: url.lastPathComponent,
                kind: .word,
                text: WordDocument.readText(from: url),
                previewData: nil
            )
        }
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            return try extractPDF(at: url)
        }
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
            return try extractImage(at: url)
        }
        throw ContextCaptureError.unsupportedFile
    }

    private static func extractImage(at url: URL) throws -> ContextAttachment {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ContextCaptureError.unsupportedFile
        }
        let text = try recognizeText(in: image)
        return try makeAttachment(
            name: url.lastPathComponent,
            kind: .image,
            text: text,
            previewData: thumbnailData(from: source)
        )
    }

    private static func extractPDF(at url: URL) throws -> ContextAttachment {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw ContextCaptureError.unsupportedFile
        }

        var sections: [String] = []
        let pageLimit = min(document.pageCount, maximumPDFPages)
        for pageIndex in 0..<pageLimit {
            guard let page = document.page(at: pageIndex) else { continue }
            let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if pageText.count > 30 {
                sections.append("Page \(pageIndex + 1)\n\(pageText)")
            } else {
                let image = page.thumbnail(of: NSSize(width: 1700, height: 1700), for: .cropBox)
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    let recognized = try recognizeText(in: cgImage)
                    if !recognized.isEmpty {
                        sections.append("Page \(pageIndex + 1)\n\(recognized)")
                    }
                }
            }
            if sections.joined(separator: "\n\n").count >= maximumCharacters { break }
        }

        let previewImage = document.page(at: 0)?.thumbnail(of: NSSize(width: 520, height: 680), for: .cropBox)
        let previewData = previewImage.flatMap(pngData(from:))
        return try makeAttachment(
            name: url.lastPathComponent,
            kind: .pdf,
            text: sections.joined(separator: "\n\n"),
            previewData: previewData
        )
    }

    private static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        try VNImageRequestHandler(cgImage: image).perform([request])
        let observations = (request.results ?? []).sorted {
            $0.boundingBox.midY > $1.boundingBox.midY
        }
        return observations.compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeAttachment(
        name: String,
        kind: ContextAttachment.Kind,
        text: String,
        previewData: Data?
    ) throws -> ContextAttachment {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ContextCaptureError.noReadableText }
        return ContextAttachment(
            name: name,
            kind: kind,
            extractedText: String(cleaned.prefix(maximumCharacters)),
            previewData: previewData,
            originalCharacterCount: cleaned.count
        )
    }

    private static func thumbnailData(from source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 900,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return pngData(from: thumbnail)
    }

    private static func pngData(from image: CGImage) -> Data? {
        let representation = NSBitmapImageRep(cgImage: image)
        return representation.representation(using: .png, properties: [:])
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff) else { return nil }
        return representation.representation(using: .png, properties: [:])
    }
}

@MainActor
protocol ScreenContextCapturing: AnyObject {
    func present(completion: @escaping (Result<ContextAttachment, Error>) -> Void) throws
}

@available(macOS 14.0, *)
@MainActor
final class ScreenContextPicker: NSObject, @preconcurrency SCContentSharingPickerObserver, ScreenContextCapturing {
    private var completion: ((Result<ContextAttachment, Error>) -> Void)?
    private var isRegistered = false

    func present(completion: @escaping (Result<ContextAttachment, Error>) -> Void) throws {
        self.completion = completion

        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleDisplay, .singleWindow]
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "com.novatechnologies.novacopilot"]
        configuration.allowsChangingSelectedContent = false
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        isRegistered = true
        picker.present()
    }

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor in
            do {
                let configuration = SCStreamConfiguration()
                configuration.width = 1920
                configuration.height = 1080
                configuration.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                let attachment = try await ContextTextExtractor.readScreenshot(image, name: "Screen capture")
                finish(.success(attachment), picker: picker)
            } catch {
                finish(.failure(error), picker: picker)
            }
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        finish(.failure(CancellationError()), picker: picker)
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        finish(.failure(error), picker: .shared)
    }

    private func finish(_ result: Result<ContextAttachment, Error>, picker: SCContentSharingPicker) {
        if isRegistered {
            picker.remove(self)
            picker.isActive = false
            isRegistered = false
        }
        let callback = completion
        completion = nil
        callback?(result)
    }
}
