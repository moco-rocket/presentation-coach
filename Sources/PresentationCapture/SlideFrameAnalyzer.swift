import CoreVideo
import Foundation
import PresentationContracts
import Vision

public struct FrameChangeResult: Equatable, Sendable {
    public let changed: Bool
    public let fingerprint: UInt64
}

public struct FrameChangeDetector: Sendable {
    public var threshold: Double
    private var previousSamples: [UInt8]?

    public init(threshold: Double = 0.06) {
        self.threshold = threshold
    }

    public mutating func evaluate(_ pixelBuffer: CVPixelBuffer) throws -> FrameChangeResult {
        let samples = try Self.samples(from: pixelBuffer)
        let fingerprint = Self.fingerprint(samples)
        defer { previousSamples = samples }
        guard let previousSamples, previousSamples.count == samples.count else {
            return FrameChangeResult(changed: true, fingerprint: fingerprint)
        }

        let totalDifference = zip(previousSamples, samples).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        let normalizedDifference = Double(totalDifference) / Double(samples.count * 255)
        return FrameChangeResult(
            changed: normalizedDifference >= threshold,
            fingerprint: fingerprint
        )
    }

    private static func samples(from pixelBuffer: CVPixelBuffer) throws -> [UInt8] {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            throw FrameChangeDetectorError.unsupportedPixelFormat
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw FrameChangeDetectorError.missingBaseAddress
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let columns = min(32, max(1, width))
        let rows = min(18, max(1, height))
        var result: [UInt8] = []
        result.reserveCapacity(columns * rows)

        for row in 0..<rows {
            let y = min(height - 1, row * height / rows)
            for column in 0..<columns {
                let x = min(width - 1, column * width / columns)
                let offset = y * bytesPerRow + x * 4
                let blue = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let red = Int(bytes[offset + 2])
                result.append(UInt8((red * 77 + green * 150 + blue * 29) >> 8))
            }
        }
        return result
    }

    private static func fingerprint(_ bytes: [UInt8]) -> UInt64 {
        bytes.reduce(14_695_981_039_346_656_037) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

public enum FrameChangeDetectorError: Error, Equatable {
    case unsupportedPixelFormat
    case missingBaseAddress
}

public protocol ScreenTextRecognizing: Sendable {
    func recognizeText(in frame: ScreenFrame) async throws -> [String]
}

public struct VisionScreenTextRecognizer: ScreenTextRecognizing {
    public init() {}

    public func recognizeText(in frame: ScreenFrame) async throws -> [String] {
        try await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["ja-JP", "en-US"]
            let handler = VNImageRequestHandler(cvPixelBuffer: frame.pixelBuffer, options: [:])
            try handler.perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}

public actor SlideFrameAnalyzer {
    private var changeDetector: FrameChangeDetector
    private let recognizer: any ScreenTextRecognizing

    public init(
        changeDetector: FrameChangeDetector = FrameChangeDetector(),
        recognizer: any ScreenTextRecognizing = VisionScreenTextRecognizer()
    ) {
        self.changeDetector = changeDetector
        self.recognizer = recognizer
    }

    public func analyze(_ frame: ScreenFrame) async throws -> SlideChange? {
        let result = try changeDetector.evaluate(frame.pixelBuffer)
        guard result.changed else { return nil }
        let lines = try await recognizer.recognizeText(in: frame)
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let characterCount = text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }.count
        let density = min(1, Double(characterCount) / 600)
        return SlideChange(
            slideID: String(format: "%016llx", result.fingerprint),
            ocrText: text.isEmpty ? nil : text,
            textDensity: density
        )
    }
}
