import Foundation
import Observation

@MainActor
@Observable
final class TeamsViewModel {

    enum State {
        case loading
        case loaded([TeamListItem])
        case error(String)
    }

    private let api: APIClient
    private(set) var state: State = .loading

    /// Fixed division display order (Eastern then Western).
    static let divisionOrder = ["Atlantic", "Metropolitan", "Central", "Pacific"]

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await api.teams())
        } catch {
            Log.error("Failed to load teams", error)
            state = .error(error.localizedDescription)
        }
    }

    /// Teams grouped by division, in display order, each sorted by points.
    func grouped(_ teams: [TeamListItem]) -> [(division: String, teams: [TeamListItem])] {
        let byDivision = Dictionary(grouping: teams, by: \.division)
        let known = Self.divisionOrder.compactMap { div -> (String, [TeamListItem])? in
            guard let group = byDivision[div] else { return nil }
            return (div, group.sorted { $0.points > $1.points })
        }
        let others = byDivision.keys
            .filter { !Self.divisionOrder.contains($0) }
            .sorted()
            .map { ($0, byDivision[$0]!.sorted { $0.points > $1.points }) }
        return (known + others).map { (division: $0.0, teams: $0.1) }
    }
}
