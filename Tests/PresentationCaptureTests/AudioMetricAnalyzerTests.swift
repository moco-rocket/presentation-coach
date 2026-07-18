import Foundation
import Testing
@testable import PresentationCapture

@Test func detectsSpeechAndResetsSilence() {
    var analyzer = AudioMetricAnalyzer(speechThresholdDB: -40)

    let silence = analyzer.analyze(samples: Array(repeating: 0, count: 480), sampleRate: 48_000)
    #expect(!silence.isSpeech)
    #expect(silence.silenceDurationMs == 10)

    let speech = analyzer.analyze(samples: Array(repeating: 0.1, count: 480), sampleRate: 48_000)
    #expect(speech.isSpeech)
    #expect(speech.silenceDurationMs == 0)
}

@Test func emptyFramesAreSafe() {
    var analyzer = AudioMetricAnalyzer()
    let metric = analyzer.analyze(samples: [], sampleRate: 48_000)
    #expect(metric.rmsDB == -120)
    #expect(!metric.isSpeech)
}
