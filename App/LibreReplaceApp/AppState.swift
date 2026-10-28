import Combine
import Foundation
import LibreReplaceCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var catalog: Catalog?
    @Published private(set) var installed: [InstalledApplication] = []
    @Published private(set) var recommendations: [AppRecommendation] = []
    @Published private(set) var unsupported: [InstalledApplication] = []
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?
    @Published var annualCostText: [String: String] = [:]

    private var hasStarted = false

    var annualCostOverrides: [String: Decimal] {
        annualCostText.reduce(into: [:]) { result, item in
            let cleaned = item.value.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Decimal(string: cleaned), value >= 0 { result[item.key] = value }
        }
    }

    var summary: ReportSummary {
        ReportSummary(applicationsDetected: installed.count, recommendations: recommendations, annualCostOverrides: annualCostOverrides)
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            try loadCatalog()
            await scan()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadCatalog() throws {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
            throw CatalogError.unreadable
        }
        catalog = try CatalogLoader.load(from: url)
    }

    func scan() async {
        guard let catalog else { return }
        isScanning = true
        defer { isScanning = false }

        let apps = await Task.detached(priority: .userInitiated) {
            AppScanner().scan()
        }.value
        installed = apps
        let matcher = AppMatcher()
        let matches = matcher.match(installed: apps, catalog: catalog)
        recommendations = matches
            .map { ReplacementRanker().recommendation(for: $0) }
            .sorted { $0.match.catalogApp.name.localizedCaseInsensitiveCompare($1.match.catalogApp.name) == .orderedAscending }
        unsupported = matcher.unsupported(installed: apps, catalog: catalog)
    }

    func reportMarkdown(includeNames: Bool) -> String {
        ReportGenerator.markdown(summary: summary, includeApplicationNames: includeNames, recommendations: recommendations)
    }
}
