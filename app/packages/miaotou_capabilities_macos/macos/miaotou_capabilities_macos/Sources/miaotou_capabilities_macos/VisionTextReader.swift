import CoreGraphics
import Foundation
import Vision

/// One recognised line, in the frame's own pixel coordinates.
struct RecognisedLine {
    let text: String
    let confidence: Double

    /// Top-origin, so it is the same space `normaliseBlocks` reads on the Dart side.
    let left: Double
    let top: Double
    let right: Double
    let bottom: Double

    var dictionary: [String: Any] {
        [
            "text": text,
            "confidence": confidence,
            "left": left,
            "top": top,
            "right": right,
            "bottom": bottom,
        ]
    }
}

/// Apple Vision, asked for text and nothing else.
///
/// **Recognition is all this does.** Deciding who spoke a line is geometry, and
/// geometry calibrated against one window's layout lives in `perception.dart` on
/// the Dart side, next to the numbers it was measured against. Splitting the two
/// would put the thresholds somewhere no test can reach.
final class VisionTextReader {
    static let shared = VisionTextReader()

    /// The chat pane, normalised with a bottom-left origin: everything left of it
    /// is the conversation list, and reading it costs about half the time for text
    /// that is never a message.
    ///
    /// The same two numbers appear in `perception.dart`. They are the same
    /// measurement of the same window, and changing one without the other is the
    /// kind of drift the header comment there is about.
    static let regionOfInterest = CGRect(x: 0.32, y: 0.24, width: 0.68, height: 0.66)

    /// Reads the text in [image].
    ///
    /// The languages are the caller's ordered preference, never this class's
    /// choice: the same screenshot must not read differently depending on which
    /// port took it. A language this build of Vision does not have is dropped
    /// rather than passed through, because Vision throws on an unknown one at
    /// perform time — which would turn a preference into a failure.
    func recognize(image: CGImage, languages: [String]) throws -> [RecognisedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = VisionTextReader.available(languages)
        request.regionOfInterest = VisionTextReader.regionOfInterest

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let roi = VisionTextReader.regionOfInterest
        let width = Double(image.width)
        let height = Double(image.height)

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            // Vision reports a box relative to the region of interest, normalised
            // with a bottom-left origin. Both are undone here, once, and nowhere
            // else in the file.
            let box = observation.boundingBox
            let x = roi.minX + box.minX * roi.width
            let y = roi.minY + box.minY * roi.height
            let boxWidth = box.width * roi.width
            let boxHeight = box.height * roi.height

            return RecognisedLine(
                text: text,
                confidence: Double(candidate.confidence),
                left: x * width,
                top: (1 - y - boxHeight) * height,
                right: (x + boxWidth) * width,
                bottom: (1 - y) * height
            )
        }
    }

    /// The caller's languages, narrowed to what this system can actually read.
    static func available(_ requested: [String]) -> [String] {
        // The instance form is the one Apple kept; the class method with an
        // explicit revision has been deprecated since macOS 12.
        let supported = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []
        let usable = requested.filter { supported.contains($0) }
        return usable.isEmpty ? supported : usable
    }
}
