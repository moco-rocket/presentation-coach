import Accelerate
import Foundation
import PresentationContracts

public struct AudioMetricAnalyzer: Sendable {
    public var speechThresholdDB: Double
    public var accumulatedSilenceMs: Int

    public init(speechThresholdDB: Double = -42, accumulatedSilenceMs: Int = 0) {
        self.speechThresholdDB = speechThresholdDB
        self.accumulatedSilenceMs = accumulatedSilenceMs
    }

    public mutating func analyze(samples: [Float], sampleRate: Double) -> AudioMetric {
        guard !samples.isEmpty, sampleRate > 0 else {
            return AudioMetric(
                rmsDB: -120,
                peakDB: -120,
                isSpeech: false,
                silenceDurationMs: accumulatedSilenceMs
            )
        }

        var meanSquare: Float = 0
        vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(samples.count))
        let rms = sqrt(max(meanSquare, Float.leastNonzeroMagnitude))

        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))

        let rmsDB = max(-120, 20 * log10(Double(rms)))
        let peakDB = max(-120, 20 * log10(Double(max(peak, Float.leastNonzeroMagnitude))))
        let isSpeech = rmsDB >= speechThresholdDB
        let frameDurationMs = Int((Double(samples.count) / sampleRate * 1_000).rounded())

        if isSpeech {
            accumulatedSilenceMs = 0
        } else {
            accumulatedSilenceMs += max(0, frameDurationMs)
        }

        return AudioMetric(
            rmsDB: rmsDB,
            peakDB: peakDB,
            isSpeech: isSpeech,
            silenceDurationMs: accumulatedSilenceMs
        )
    }
}
