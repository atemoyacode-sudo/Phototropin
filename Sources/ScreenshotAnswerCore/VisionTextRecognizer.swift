import AppKit
import Foundation
import Vision

public protocol ScreenshotTextRecognizing: Sendable {
    func recognizeText(in imageURL: URL) async throws -> String
}

public struct VisionTextRecognizer: ScreenshotTextRecognizing {
    public let recognitionLanguages: [String]

    public init(recognitionLanguages: [String] = ["ja-JP", "en-US"]) {
        self.recognitionLanguages = recognitionLanguages
    }

    public func recognizeText(in imageURL: URL) async throws -> String {
        let languages = recognitionLanguages
        return try await Task.detached(priority: .userInitiated) {
            guard let image = NSImage(contentsOf: imageURL),
                  let imageData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: imageData),
                  let cgImage = bitmap.cgImage else {
                throw ScreenshotAnswerError.unreadableImage
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            let observations = (request.results ?? []).compactMap { observation -> OCRLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return OCRLine(text: text, box: observation.boundingBox)
            }

            let text = OCRReadingOrder.lines(from: observations)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw ScreenshotAnswerError.noTextFound }
            return text
        }.value
    }
}

struct OCRLine: Sendable, Equatable {
    let text: String
    let box: CGRect
}

enum OCRReadingOrder {
    static func lines(from observations: [OCRLine]) -> [String] {
        // First establish a strict order, then group against a fixed row anchor.
        // Pairwise vertical tolerances are non-transitive and cannot be used
        // directly as a sorting comparator.
        let ordered = observations.sorted {
            if $0.box.midY != $1.box.midY { return $0.box.midY > $1.box.midY }
            if $0.box.minX != $1.box.minX { return $0.box.minX < $1.box.minX }
            if $0.box.height != $1.box.height { return $0.box.height < $1.box.height }
            if $0.box.width != $1.box.width { return $0.box.width < $1.box.width }
            return $0.text < $1.text
        }
        var rows: [[OCRLine]] = []
        for observation in ordered {
            if let anchor = rows.last?.first,
               abs(anchor.box.midY - observation.box.midY)
                <= max(anchor.box.height, observation.box.height) * 0.45 {
                rows[rows.count - 1].append(observation)
            } else {
                rows.append([observation])
            }
        }
        return rows.flatMap { row in
            row.sorted {
                if $0.box.minX != $1.box.minX { return $0.box.minX < $1.box.minX }
                if $0.box.midY != $1.box.midY { return $0.box.midY > $1.box.midY }
                return $0.text < $1.text
            }.map(\.text)
        }
    }
}
