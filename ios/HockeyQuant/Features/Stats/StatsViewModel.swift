import Foundation
import Observation

@MainActor
@Observable
final class StatsViewModel {

    enum State {
        case loading
        case loaded
        case error(String)
    }

    private let api: APIClient

    private(set) var state: State = .loading
    private(set) var stats: AccuracyStats?
    private(set) var recent: [PredictionRecord] = []
    private(set) var trend: [TrendDataPoint] = []
    private(set) var parlay: ParlayStats?

    var window: Int = 30 {
        didSet { Task { await loadTrend() } }
    }

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func load() async {
        state = .loading
        do {
            async let statsCall = api.accuracyStats()
            async let trendCall = api.trend(window: window)
            let (accuracy, trendResponse) = try await (statsCall, trendCall)
            stats = accuracy.stats
            recent = accuracy.recentPredictions
            trend = trendResponse.dataPoints
            state = .loaded
        } catch {
            Log.error("Failed to load accuracy stats", error)
            state = .error(error.localizedDescription)
        }
        // Parlay stats are best-effort — don't fail the whole screen for them.
        parlay = try? await api.parlayStats()
    }

    private func loadTrend() async {
        do {
            trend = try await api.trend(window: window).dataPoints
        } catch {
            Log.error("Failed to load trend", error)
        }
    }
}
