import AppKit
import PresentationFeedback
import SwiftUI

private struct SessionResultView: View {
    let report: SessionReport

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 4) {
                    Text("おつかれさま！")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                    Text(report.session.title)
                        .foregroundStyle(.secondary)
                }

                ZStack {
                    Circle().fill(Color.yellow)
                    Circle().stroke(.black, lineWidth: 4)
                    VStack(spacing: 0) {
                        Text(String(format: "%.0f", report.score.totalScore))
                            .font(.system(size: 54, weight: .black, design: .rounded))
                        Text("/ 100").font(.headline)
                    }
                }
                .frame(width: 150, height: 150)
                .shadow(color: .black.opacity(0.2), radius: 0, x: 5, y: 6)

                VStack(spacing: 12) {
                    ForEach(Array(report.score.categories.enumerated()), id: \.offset) { _, category in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(category.category).font(.headline)
                                Spacer()
                                Text(String(format: "%.1f / %.0f", category.score, category.maximumScore))
                                    .font(.system(.body, design: .rounded).bold())
                            }
                            ProgressView(value: category.score, total: category.maximumScore)
                                .tint(category.score / max(1, category.maximumScore) >= 0.7 ? .green : .orange)
                            ForEach(category.evidence, id: \.self) { evidence in
                                Text("・\(evidence)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black, lineWidth: 2))
                    }
                }

                if let evaluation = report.qualitativeEvaluation {
                    VStack(spacing: 12) {
                        insightSection("よかった点", icon: "hand.thumbsup.fill", color: .green, insights: evaluation.strengths)
                        insightSection("改善ポイント", icon: "wrench.and.screwdriver.fill", color: .orange, insights: evaluation.improvements)
                        insightSection("次回のミッション", icon: "flag.checkered", color: .blue, insights: evaluation.nextActions)
                    }
                } else {
                    Text("AI講評は利用できませんでした。計測スコアと根拠は保存されています。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .frame(width: 560, height: 680)
        .background(Color(red: 0.94, green: 0.97, blue: 1))
    }

    private func insightSection(
        _ title: String,
        icon: String,
        color: Color,
        insights: [EvaluatedInsight]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.title3.bold())
                .foregroundStyle(color)
            ForEach(insights) { insight in
                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.text).font(.body.weight(.semibold))
                    Text("\(timestamp(insight.evidence.timestampMs))  \(insight.evidence.text)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black, lineWidth: 2))
    }

    private func timestamp(_ milliseconds: Int64) -> String {
        let seconds = max(0, milliseconds / 1_000)
        return String(format: "%02lld:%02lld", seconds / 60, seconds % 60)
    }
}

@MainActor
final class SessionResultWindowController: NSWindowController {
    init(report: SessionReport) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 560, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Presentation Coach — 結果"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SessionResultView(report: report))
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
