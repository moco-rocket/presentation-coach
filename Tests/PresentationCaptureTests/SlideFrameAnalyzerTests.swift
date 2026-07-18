import CoreVideo
import PresentationContracts
import Testing
@testable import PresentationCapture

private actor TextRecognizerStub: ScreenTextRecognizing {
    private(set) var callCount = 0
    let lines: [String]

    init(lines: [String]) { self.lines = lines }

    func recognizeText(in frame: ScreenFrame) async throws -> [String] {
        callCount += 1
        return lines
    }
}

@Test func frameChangeDetectorIgnoresEquivalentFrames() throws {
    var detector = FrameChangeDetector(threshold: 0.05)
    let dark = try makePixelBuffer(value: 10)
    let sameDark = try makePixelBuffer(value: 10)
    let light = try makePixelBuffer(value: 240)

    #expect(try detector.evaluate(dark).changed)
    #expect(try detector.evaluate(sameDark).changed == false)
    #expect(try detector.evaluate(light).changed)
}

@Test func slideAnalyzerRunsOCROnlyWhenFrameChanges() async throws {
    let recognizer = TextRecognizerStub(lines: ["売上", "30%改善"])
    let analyzer = SlideFrameAnalyzer(
        changeDetector: FrameChangeDetector(threshold: 0.05),
        recognizer: recognizer
    )
    let buffer = try makePixelBuffer(value: 80)
    let frame = ScreenFrame(pixelBuffer: buffer, timestampMs: 0, width: 64, height: 36)

    let first = try await analyzer.analyze(frame)
    let second = try await analyzer.analyze(frame)

    #expect(first?.ocrText == "売上\n30%改善")
    #expect(first?.textDensity != nil)
    #expect(second == nil)
    #expect(await recognizer.callCount == 1)
}

private func makePixelBuffer(value: UInt8) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        nil,
        64,
        36,
        kCVPixelFormatType_32BGRA,
        nil,
        &pixelBuffer
    )
    #expect(status == kCVReturnSuccess)
    let buffer = try #require(pixelBuffer)
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let byteCount = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
    let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    for index in 0..<byteCount { bytes[index] = value }
    return buffer
}
