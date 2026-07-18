import Foundation

public struct StoredSessionReport: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var report: SessionReport

    public init(id: UUID = UUID(), createdAt: Date = Date(), report: SessionReport) {
        self.id = id
        self.createdAt = createdAt
        self.report = report
    }
}

public struct SessionReportStore: Sendable {
    public let directory: URL

    public init(directory: URL = Self.defaultDirectory()) {
        self.directory = directory
    }

    @discardableResult
    public func save(_ stored: StoredSessionReport) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(stored.id.uuidString).report.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(stored).write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    public func save(_ report: SessionReport, createdAt: Date = Date()) throws -> StoredSessionReport {
        let stored = StoredSessionReport(createdAt: createdAt, report: report)
        try save(stored)
        return stored
    }

    public func loadAll() throws -> [StoredSessionReport] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.lastPathComponent.hasSuffix(".report.json") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try urls.map { try decoder.decode(StoredSessionReport.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func exportMarkdown(_ stored: StoredSessionReport, to url: URL) throws {
        try markdown(for: stored).write(to: url, atomically: true, encoding: .utf8)
    }

    public func markdown(for stored: StoredSessionReport) -> String {
        let report = stored.report
        let date = stored.createdAt.formatted(date: .numeric, time: .shortened)
        let categories = report.score.categories.map { category in
            let evidence = category.evidence.map { "  - \($0)" }.joined(separator: "\n")
            return "- \(category.category): \(format(category.score)) / \(format(category.maximumScore))\n\(evidence)"
        }.joined(separator: "\n")
        let evaluation = report.qualitativeEvaluation.map { evaluation in
            """
            ## よかった点
            \(insightsMarkdown(evaluation.strengths))

            ## 改善ポイント
            \(insightsMarkdown(evaluation.improvements))

            ## 次回のミッション
            \(insightsMarkdown(evaluation.nextActions))
            """
        } ?? "## AI講評\n\n講評は利用できませんでした。"
        return """
        # \(report.session.title)

        - 実施日時: \(date)
        - 対象: \(report.session.audience.isEmpty ? "未設定" : report.session.audience)
        - 目的: \(report.session.goal.isEmpty ? "未設定" : report.session.goal)
        - 総合点: \(format(report.score.totalScore)) / \(format(report.score.maximumScore))

        ## 採点

        \(categories)

        \(evaluation)
        """
    }

    public static func defaultDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("PresentationCoach", isDirectory: true)
            .appendingPathComponent("Reports", isDirectory: true)
    }

    private func insightsMarkdown(_ insights: [EvaluatedInsight]) -> String {
        insights.map {
            "- \($0.text)（\(timestamp($0.evidence.timestampMs)) — \($0.evidence.text)）"
        }.joined(separator: "\n")
    }

    private func timestamp(_ milliseconds: Int64) -> String {
        let seconds = max(0, milliseconds / 1_000)
        return String(format: "%02lld:%02lld", seconds / 60, seconds % 60)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
