import Foundation
import Observation

@MainActor
@Observable
final class TodayViewModel {

    enum State {
        case loading
        case loaded([GamePrediction])
        case empty
        case error(String)
    }

    private let api: APIClient

    private(set) var state: State = .loading
    var selectedDate: Date {
        didSet { Task { await load() } }
    }

    init(api: APIClient = APIClient(), date: Date = Date()) {
        self.api = api
        self.selectedDate = Calendar.current.startOfDay(for: date)
    }

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

    func warmUp() {
        Task { await api.warmUp() }
    }

    func load() async {
        state = .loading
        do {
            let response = try await api.predictions(for: selectedDate)
            Log.info("Loaded \(response.gamesCount) games for \(response.date)")
            state = response.predictions.isEmpty ? .empty : .loaded(response.predictions)
        } catch APIClient.APIError.noGames {
            state = .empty
        } catch {
            Log.error("Failed to load predictions", error)
            state = .error(error.localizedDescription)
        }
    }
}
