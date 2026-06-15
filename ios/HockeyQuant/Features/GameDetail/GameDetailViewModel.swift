import Foundation
import Observation

@MainActor
@Observable
final class GameDetailViewModel {

    enum SummaryState {
        case idle
        case loading
        case loaded(String)
        case error(String)
    }

    private let api: APIClient
    let game: GamePrediction
    let dateString: String

    private(set) var summaryState: SummaryState = .idle
    private(set) var liveScore: GameScore?

    init(game: GamePrediction, dateString: String, api: APIClient = APIClient()) {
        self.game = game
        self.dateString = dateString
        self.api = api
    }

    /// Load the AI "Why [pick]?" explanation on demand.
    func loadSummary() async {
        if case .loading = summaryState { return }
        if case .loaded = summaryState { return }
        summaryState = .loading
        do {
            let text = try await api.summary(for: game)
            summaryState = .loaded(text)
        } catch {
            Log.error("Failed to load summary", error)
            summaryState = .error(error.localizedDescription)
        }
    }

    /// Fetch the live/final score for this matchup, if any.
    func loadScore() async {
        do {
            let scores = try await api.scores(forDate: dateString)
            liveScore = scores.first { score in
                score.awayTeam == game.away.team && score.homeTeam == game.home.team
            }
        } catch {
            Log.error("Failed to load live score", error)
        }
    }
}
