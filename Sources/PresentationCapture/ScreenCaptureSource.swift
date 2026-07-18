import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

public struct ScreenFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    public let timestampMs: Int64
    public let width: Int
    public let height: Int

    public init(pixelBuffer: CVPixelBuffer, timestampMs: Int64, width: Int, height: Int) {
        self.pixelBuffer = pixelBuffer
        self.timestampMs = timestampMs
        self.width = width
        self.height = height
    }
}

/// Captures at a deliberately low rate for slide analysis. Frames wait in a
/// single-slot mailbox, so slow OCR can never build an unbounded backlog.
@MainActor
public final class ScreenCaptureSource {
    public typealias FrameHandler = @Sendable (ScreenFrame) async -> Void

    private var stream: SCStream?
    private var output: ScreenFrameOutput?
    private var consumerTask: Task<Void, Never>?

    public init() {}

    public func start(displayID: UInt32, handler: @escaping FrameHandler) async throws {
        guard stream == nil else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureSourceError.displayNotFound(displayID)
        }

        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let excludedApplications = content.applications.filter {
            $0.bundleIdentifier == ownBundleIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        let configuration = Self.configuration(for: display)
        let mailbox = BoundedNewestStream<ScreenFrame>(limit: 1)
        let output = ScreenFrameOutput { frame in mailbox.yield(frame) }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(
            output,
            type: .screen,
            sampleHandlerQueue: DispatchQueue(label: "presentation-coach.screen-frames", qos: .userInitiated)
        )

        consumerTask = Task {
            for await frame in mailbox.stream {
                guard !Task.isCancelled else { return }
                await handler(frame)
            }
        }
        self.output = output
        self.stream = stream

        do {
            try await stream.startCapture()
        } catch {
            await stop()
            throw error
        }
    }

    public func stop() async {
        consumerTask?.cancel()
        consumerTask = nil
        output?.finish()
        output = nil
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    private static func configuration(for display: SCDisplay) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let maximumWidth = 1_280
        let scale = min(1, Double(maximumWidth) / Double(max(1, display.width)))
        configuration.width = max(1, Int(Double(display.width) * scale))
        configuration.height = max(1, Int(Double(display.height) * scale))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        configuration.queueDepth = 2
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false
        return configuration
    }
}

public enum ScreenCaptureSourceError: Error, Equatable {
    case displayNotFound(UInt32)
}

final class ScreenFrameOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let handler: @Sendable (ScreenFrame) -> Void
    private var firstTimestampSeconds: Double?

    init(handler: @escaping @Sendable (ScreenFrame) -> Void) {
        self.handler = handler
        super.init()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let timestamp = sampleBuffer.presentationTimeStamp.seconds
        if firstTimestampSeconds == nil, timestamp.isFinite {
            firstTimestampSeconds = timestamp
        }
        let relativeTimestamp = timestamp - (firstTimestampSeconds ?? timestamp)
        handler(ScreenFrame(
            pixelBuffer: pixelBuffer,
            timestampMs: relativeTimestamp.isFinite ? Int64((relativeTimestamp * 1_000).rounded()) : 0,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        ))
    }

    func finish() {}
}

struct BoundedNewestStream<Element: Sendable>: Sendable {
    let stream: AsyncStream<Element>
    private let continuation: AsyncStream<Element>.Continuation

    init(limit: Int) {
        let pair = AsyncStream<Element>.makeStream(
            bufferingPolicy: .bufferingNewest(max(1, limit))
        )
        stream = pair.stream
        continuation = pair.continuation
    }

    func yield(_ element: Element) { continuation.yield(element) }
    func finish() { continuation.finish() }
}
