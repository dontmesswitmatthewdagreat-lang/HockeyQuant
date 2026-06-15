import Foundation
import Observation

@MainActor
@Observable
final class TeamDetailViewModel {

    enum State {
        case loading
        case loaded(TeamDetailResponse)
        case error(String)
    }

    private let api: APIClient
    let abbrev: String
    private(set) var state: State = .loading

    init(abbrev: String, api: APIClient = APIClient()) {
        self.abbrev = abbrev
        self.api = api
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await api.teamDetail(abbrev))
        } catch {
            Log.error("Failed to load team \(abbrev)", error)
            state = .error(error.localizedDescription)
        }
    }
}
