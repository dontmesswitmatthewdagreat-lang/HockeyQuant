import Foundation
import Observation

/// A prediction merged with its live/final score (when available).
struct ScheduleGame: Identifiable, Sendable {
    let prediction: GamePrediction
    var score: GameScore?

    var id: String { prediction.id }
    var isLive: Bool { score?.isLive == true }
    var isFinal: Bool { score?.isFinal == true }
    var isUpcoming: Bool { !(isLive || isFinal) }
    /// Live games float to the top, then upcoming, then finals.
    var sortRank: Int { isLive ? 0 : (isFinal ? 2 : 1) }
}

@MainActor
@Observable
final class TodayViewModel {

    enum State {
        case loading
        case loaded([ScheduleGame])
        case empty
        case error(String)
    }

    private let api: APIClient

    private(set) var state: State = .loading
    /// Number of games per day (keyed by API date string) for the day-strip dots.
    private(set) var gameCounts: [String: Int] = [:]

    var selectedDate: Date {
        didSet {
            guard !Calendar.current.isDate(oldValue, inSameDayAs: selectedDate) else { return }
            stopPolling()
            Task { await load() }
        }
    }

    private var pollTask: Task<Void, Never>?

    init(api: APIClient = APIClient(), date: Date = Date()) {
        self.api = api
        self.selectedDate = Calendar.current.startOfDay(for: date)
    }

    // MARK: - Day strip

    /// A rolling window of days around the *selected* day for the horizontal strip,
    /// so the strip always contains and centers whatever date you're viewing.
    var stripDays: [Date] {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: selectedDate)
        return (-21...21).compactMap { cal.date(byAdding: .day, value: $0, to: anchor) }
    }

    func dots(for date: Date) -> Int {
        min(gameCounts[APIClient.apiDateString(date)] ?? 0, 3)
    }

    func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    func select(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
    }

    var dateLabel: String {
        if Calendar.current.isDateInToday(selectedDate) { return "Today" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "Yesterday" }
        if Calendar.current.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: selectedDate)
    }

    var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: selectedDate)
    }

    func step(days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        selectedDate = next
    }

    func warmUp() {
        Task { await api.warmUp() }
    }

    // MARK: - Load

    func load() async {
        state = .loading
        let dateStr = APIClient.apiDateString(selectedDate)
        // Results for a stale date must never clobber the screen (fast day-taps
        // race: the slower earlier request can finish last).
        func stillCurrent() -> Bool { APIClient.apiDateString(selectedDate) == dateStr }
        do {
            // Predictions + scores in parallel; scores enrich/sort but never block.
            async let predsTask = api.predictions(dateString: dateStr)
            async let scoresTask = api.scores(forDate: dateStr)
            let response = try await predsTask
            let scores = (try? await scoresTask) ?? []
            guard stillCurrent() else { return }
            Log.info("Loaded \(response.gamesCount) games for \(response.date)")
            Task { await loadStripCounts() }

            guard !response.predictions.isEmpty else {
                gameCounts[dateStr] = 0
                state = .empty
                return
            }
            state = .loaded(merge(response.predictions, scores: scores))
            gameCounts[dateStr] = response.predictions.count
            startPollingIfLive()
        } catch APIClient.APIError.noGames {
            if stillCurrent() { state = .empty }
        } catch {
            Log.error("Failed to load predictions", error)
            if stillCurrent() { state = .error(error.localizedDescription) }
        }
    }

    /// Fill game-count dots for a whole visible calendar month (cached per day).
    func loadMonthCounts(for month: Date) async {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month),
              let dayCount = cal.range(of: .day, in: .month, for: month)?.count else { return }
        let days = (0..<dayCount).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
        await withTaskGroup(of: (String, Int)?.self) { group in
            for day in days {
                let ds = APIClient.apiDateString(day)
                if gameCounts[ds] != nil { continue }
                group.addTask { [api] in
                    guard let scores = try? await api.scores(forDate: ds) else { return nil }
                    return (ds, scores.count)
                }
            }
            for await result in group {
                if let (ds, count) = result { gameCounts[ds] = count }
            }
        }
    }

    /// Refresh only the scores (used while a game is live) without reloading the
    /// heavier prediction analysis.
    func refreshScores() async {
        guard case .loaded(let games) = state else { return }
        let dateStr = APIClient.apiDateString(selectedDate)
        guard let scores = try? await api.scores(forDate: dateStr) else { return }
        state = .loaded(merge(games.map(\.prediction), scores: scores))
    }

    private func merge(_ preds: [GamePrediction], scores: [GameScore]) -> [ScheduleGame] {
        let byMatchup = Dictionary(scores.map { ($0.matchupKey, $0) }, uniquingKeysWith: { a, _ in a })
        let merged = preds.enumerated().map { idx, p -> (Int, ScheduleGame) in
            let key = "\(p.away.team.uppercased())@\(p.home.team.uppercased())"
            return (idx, ScheduleGame(prediction: p, score: byMatchup[key]))
        }
        // Stable sort: live → upcoming → final, keeping schedule order within a group.
        return merged.sorted { l, r in
            l.1.sortRank != r.1.sortRank ? l.1.sortRank < r.1.sortRank : l.0 < r.0
        }.map(\.1)
    }

    // MARK: - Live polling

    private var hasLive: Bool {
        if case .loaded(let games) = state { return games.contains(where: \.isLive) }
        return false
    }

    private func startPollingIfLive() {
        guard hasLive, pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard let self, !Task.isCancelled else { return }
                await self.refreshScores()
                if !self.hasLive { self.stopPolling(); return }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Best-effort game counts for the days near the selected date (for the dots),
    /// fetched in the background (missing days only) so the strip renders immediately.
    func loadStripCounts() async {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: selectedDate)
        let window = (-10...10).compactMap { cal.date(byAdding: .day, value: $0, to: anchor) }
        await withTaskGroup(of: (String, Int)?.self) { group in
            for day in window {
                let ds = APIClient.apiDateString(day)
                if gameCounts[ds] != nil { continue }
                group.addTask { [api] in
                    guard let scores = try? await api.scores(forDate: ds) else { return nil }
                    return (ds, scores.count)
                }
            }
            for await result in group {
                if let (ds, count) = result { gameCounts[ds] = count }
            }
        }
    }
}
