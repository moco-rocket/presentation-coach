import AppKit
import PresentationFeedback
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SessionHistoryViewModel: ObservableObject {
    @Published private(set) var reports: [StoredSessionReport] = []
    @Published var selectedID: UUID?
    @Published private(set) var errorMessage: String?
    private let store: SessionReportStore

    init(store: SessionReportStore = SessionReportStore()) {
        self.store = store
        reload()
    }

    var selected: StoredSessionReport? {
        reports.first { $0.id == selectedID }
    }

    func reload() {
        do {
            reports = try store.loadAll()
            if selectedID == nil || !reports.contains(where: { $0.id == selectedID }) {
                selectedID = reports.first?.id
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportSelected() {
        guard let selected else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(safeFilename(selected.report.session.title)).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportMarkdown(selected, to: url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func safeFilename(_ title: String) -> String {
        let cleaned = title.replacingOccurrences(of: "/", with: "-")
        return cleaned.isEmpty ? "presentation-report" : cleaned
    }
}

private struct SessionHistoryView: View {
    @ObservedObject var viewModel: SessionHistoryViewModel

    var body: some View {
        NavigationSplitView {
            List(viewModel.reports, selection: $viewModel.selectedID) { stored in
                VStack(alignment: .leading, spacing: 3) {
                    Text(stored.report.session.title).font(.headline)
                    Text(stored.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(stored.id)
            }
            .navigationTitle("練習履歴")
            .overlay {
                if viewModel.reports.isEmpty {
                    ContentUnavailableView("まだ履歴がありません", systemImage: "clock.arrow.circlepath")
                }
            }
        } detail: {
            if let stored = viewModel.selected {
                reportDetail(stored)
            } else {
                ContentUnavailableView("レポートを選択", systemImage: "doc.text.magnifyingglass")
            }
        }
        .toolbar {
            Button("更新", systemImage: "arrow.clockwise") { viewModel.reload() }
            Button("Markdownを書き出す", systemImage: "square.and.arrow.up") {
                viewModel.exportSelected()
            }
            .disabled(viewModel.selected == nil)
        }
        .overlay(alignment: .bottom) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .padding(8)
                    .background(.red.opacity(0.12), in: Capsule())
                    .padding()
            }
        }
        .frame(minWidth: 850, minHeight: 580)
    }

    private func reportDetail(_ stored: StoredSessionReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(stored.report.session.title).font(.largeTitle.bold())
                        Text(stored.createdAt.formatted(date: .long, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.0f点", stored.report.score.totalScore))
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .padding(14)
                        .background(.yellow, in: RoundedRectangle(cornerRadius: 16))
                }

                ForEach(Array(stored.report.score.categories.enumerated()), id: \.offset) { _, category in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(category.category).bold()
                            Spacer()
                            Text(String(format: "%.1f / %.0f", category.score, category.maximumScore))
                        }
                        ProgressView(value: category.score, total: category.maximumScore)
                        Text(category.evidence.joined(separator: " / "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let evaluation = stored.report.qualitativeEvaluation {
                    insightList("よかった点", evaluation.strengths, color: .green)
                    insightList("改善ポイント", evaluation.improvements, color: .orange)
                    insightList("次回のミッション", evaluation.nextActions, color: .blue)
                }
            }
            .padding(24)
        }
    }

    private func insightList(_ title: String, _ insights: [EvaluatedInsight], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold()).foregroundStyle(color)
            ForEach(insights) { insight in
                Text("• \(insight.text)（\(timestamp(insight.evidence.timestampMs))）")
            }
        }
    }

    private func timestamp(_ milliseconds: Int64) -> String {
        let seconds = max(0, milliseconds / 1_000)
        return String(format: "%02lld:%02lld", seconds / 60, seconds % 60)
    }
}

@MainActor
final class SessionHistoryWindowController: NSWindowController {
    let viewModel: SessionHistoryViewModel

    init(viewModel: SessionHistoryViewModel = SessionHistoryViewModel()) {
        self.viewModel = viewModel
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 950, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Presentation Coach — 練習履歴"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SessionHistoryView(viewModel: viewModel))
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        viewModel.reload()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
