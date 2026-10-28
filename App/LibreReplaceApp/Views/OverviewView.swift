import SwiftUI
import LibreReplaceCore

struct OverviewView: View {
    @EnvironmentObject private var state: AppState
    @State private var includeNames = false
    @State private var exportError: String?

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Replace paid Mac apps without losing what matters.")
                        .font(.largeTitle.bold())
                    Text("LibreReplace matches supported apps already on this Mac with evidence-backed open-source alternatives, then shows the tradeoffs before you switch.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 780, alignment: .leading)
                }

                LazyVGrid(columns: columns, spacing: 14) {
                    MetricCard(title: "Apps detected", value: "\(state.summary.applicationsDetected)", icon: "square.stack.3d.up")
                    MetricCard(title: "Supported apps found", value: "\(state.summary.paidApplicationsDetected)", icon: "checkmark.seal")
                    MetricCard(title: "Strong replacements", value: "\(state.summary.strongReplacements)", icon: "arrow.triangle.swap")
                    MetricCard(title: "Partial", value: "\(state.summary.partialReplacements)", icon: "circle.lefthalf.filled")
                    MetricCard(title: "Keep", value: "\(state.summary.keepApps)", icon: "hand.thumbsup")
                    MetricCard(title: "Coverage", value: "\(state.summary.openSourceCoverageScore)%", icon: "chart.bar")
                }

                GroupBox("Savings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("$\(NSDecimalNumber(decimal: state.summary.annualSavingsUSD).stringValue) / year")
                            .font(.title2.bold())
                        Text("Only recurring costs you enter yourself are counted. LibreReplace never guesses which subscription, bundle, lifetime license, student plan, or Setapp plan you have.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("Privacy-safe report") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Include recognized application names", isOn: $includeNames)
                        Text(includeNames ? "The exported report will list only recognized catalog apps, not your complete inventory." : "The exported report contains aggregate counts only and does not reveal app names.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Copy Markdown") {
                                ReportExporter.copyToClipboard(state.reportMarkdown(includeNames: includeNames))
                            }
                            Button("Export Markdown…") {
                                do {
                                    try ReportExporter.saveMarkdown(state.reportMarkdown(includeNames: includeNames))
                                } catch {
                                    exportError = error.localizedDescription
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .padding(28)
        }
        .navigationTitle("Overview")
        .alert("Could not export report", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.title2.bold())
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(value)")
        }
    }
}
