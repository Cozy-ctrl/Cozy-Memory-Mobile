import Foundation
import PDFKit
import UIKit
import Vision

/// On-device text extraction for attachments: Vision OCR for images,
/// PDFKit text for documents. Runs everywhere (simulator included) —
/// this is the baseline that keeps attachments searchable even before
/// the vision model is downloaded.
nonisolated enum OCRService {
    static func extractText(from attachmentURL: URL, kind: AttachmentKind) async -> String? {
        switch kind {
        case .image:
            return await recognizeText(inImageAt: attachmentURL)
        case .document:
            return documentText(at: attachmentURL)
        }
    }

    private static func recognizeText(inImageAt url: URL) async -> String? {
        guard let image = UIImage(contentsOfFile: url.path),
              let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func documentText(at url: URL) -> String? {
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url) else { return nil }
            let text = document.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let text, !text.isEmpty else { return nil }
            return String(text.prefix(6000))
        }
        // Plain-text-ish files.
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(6000))
        }
        return nil
    }
}
