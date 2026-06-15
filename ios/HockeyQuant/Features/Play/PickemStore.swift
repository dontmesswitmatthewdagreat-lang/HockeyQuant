import SwiftUI
import Observation

/// Pick'em friend leagues — invite-code groups with season-XP standings.
/// Goes through the FastAPI backend (service-key authoritative) with the user's JWT.
@MainActor
@Observable
final class PickemStore {
    private let api = APIClient(environment: .production)
    private let auth: AuthStore

    init(auth: AuthStore) { self.auth = auth }

    private(set) var leagues: [PickemLeague] = []
    private(set) var loading = false
    var error: String?

    private func token() async throws -> String {
        guard let t = await auth.accessToken() else {
            throw APIClient.APIError.message("Please sign in to play in a league.")
        }
        return t
    }

    func load() async {
        loading = true
        defer { loading = false }
        do { leagues = try await api.pickemLeagues(token: try await token()) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func create(name: String) async -> PickemLeague? {
        do {
            let lg = try await api.createPickemLeague(name: name, token: try await token())
            await load()
            return lg
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func join(code: String) async -> PickemLeague? {
        do {
            let lg = try await api.joinPickemLeague(code: code, token: try await token())
            await load()
            return lg
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func standings(id: String) async -> PickemLeagueDetail? {
        do { return try await api.pickemLeague(id: id, token: try await token()) }
        catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }
}
