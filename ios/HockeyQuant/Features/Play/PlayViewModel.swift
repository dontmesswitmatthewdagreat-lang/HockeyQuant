import Foundation
import Observation

@MainActor
@Observable
final class PlayViewModel {

    enum GamesState {
        case loading
        case loaded([GamePrediction])
        case empty
        case error(String)
    }

    private let api: APIClient

    private(set) var gamesState: GamesState = .loading
    var selectedDate: Date {
        didSet { Task { await loadGames() } }
    }

    init(api: APIClient = APIClient(), date: Date = Date()) {
        self.api = api
        self.selectedDate = Calendar.current.startOfDay(for: date)
    }

    var dateString: String { APIClient.apiDateString(selectedDate) }

    var dateLabel: String {
        if Calendar.current.isDateInToday(selectedDate) { return "Today" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "Yesterday" }
        if Calendar.current.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: selectedDate)
    }

    func step(days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        selectedDate = next
    }

    func loadGames() async {
        gamesState = .loading
        do {
            let response = try await api.predictions(for: selectedDate)
            gamesState = response.predictions.isEmpty ? .empty : .loaded(response.predictions)
        } catch APIClient.APIError.noGames {
            gamesState = .empty
        } catch {
            Log.error("Play: failed to load games", error)
            gamesState = .error(error.localizedDescription)
        }
    }
}
