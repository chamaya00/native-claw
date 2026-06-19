import Foundation

#if canImport(Vision) && canImport(UIKit)
import Vision
import UIKit

/// On-device image → compact text pre-processing (Phase 2 multimodal capture).
///
/// Per IMPLEMENTATION_PLAN §Phase 2, we deliberately convert images to text *before*
/// feeding them to the model: a raw screenshot can consume a large share of the 4096-token
/// window, whereas its OCR'd text and barcode payloads are tiny. This keeps multimodal
/// viable on-device. Vision backs the recognition here, mirroring the framework's built-in
/// `OCRTool`/`BarcodeReaderTool`; raw image input is reserved for genuine visual reasoning
/// (a later seam) rather than the common "read this receipt/screenshot" case.
public struct ImageDigest: Sendable {
    public var recognizedText: String
    public var barcodes: [String]

    public var isEmpty: Bool { recognizedText.isEmpty && barcodes.isEmpty }

    /// A compact, model-ready rendering of what the image contains.
    public func promptContext(maxChars: Int = 2000) -> String {
        var parts: [String] = []
        if !recognizedText.isEmpty {
            let trimmed = recognizedText.count > maxChars
                ? String(recognizedText.prefix(maxChars)) + "…[truncated]"
                : recognizedText
            parts.append("Text recognized in the image:\n\(trimmed)")
        }
        if !barcodes.isEmpty {
            parts.append("Barcodes/QR codes:\n" + barcodes.map { "- \($0)" }.joined(separator: "\n"))
        }
        if parts.isEmpty {
            return "An image was attached but no text or barcodes were detected in it."
        }
        return parts.joined(separator: "\n\n")
    }
}

public enum ImageProcessor {

    public enum ProcessingError: LocalizedError {
        case undecodableImage

        public var errorDescription: String? {
            switch self {
            case .undecodableImage:
                return "That image couldn't be read. Try a different photo or screenshot."
            }
        }
    }

    /// Run OCR + barcode detection on image data, off the main actor. Returns a compact
    /// digest the caller folds into the next prompt instead of the raw pixels.
    public static func digest(from data: Data) async throws -> ImageDigest {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw ProcessingError.undecodableImage
        }
        return try await digest(from: cgImage)
    }

    public static func digest(from cgImage: CGImage) async throws -> ImageDigest {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let textRequest = VNRecognizeTextRequest()
                textRequest.recognitionLevel = .accurate
                textRequest.usesLanguageCorrection = true

                let barcodeRequest = VNDetectBarcodesRequest()

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([textRequest, barcodeRequest])
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let lines = (textRequest.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")

                let barcodes = (barcodeRequest.results ?? [])
                    .compactMap { $0.payloadStringValue }
                    .filter { !$0.isEmpty }

                continuation.resume(returning: ImageDigest(recognizedText: text, barcodes: barcodes))
            }
        }
    }
}

#else

/// Stub for platforms without Vision/UIKit so the module still compiles in CI/simulator
/// divergence paths (mirrors the `#if canImport(FoundationModels)` gating used elsewhere).
public struct ImageDigest: Sendable {
    public var recognizedText: String = ""
    public var barcodes: [String] = []
    public var isEmpty: Bool { true }
    public func promptContext(maxChars: Int = 2000) -> String { "" }
}

public enum ImageProcessor {
    public static func digest(from data: Data) async throws -> ImageDigest { ImageDigest() }
}

#endif
