import SwiftUI
import Observation

/// State + actions for My Franchise (card collection). All operations go through the
/// FastAPI backend using the user's JWT.
@MainActor
@Observable
final class FranchiseStore {
    private let api = APIClient(environment: .production)
    private let auth: AuthStore

    private(set) var summary: FranchiseSummary?
    private(set) var collection: [PlayerCard] = []
    var error: String?

    init(auth: AuthStore) { self.auth = auth }

    private func token() async throws -> String {
        guard let t = await auth.accessToken() else {
            throw APIClient.APIError.message("Please sign in to play.")
        }
        return t
    }

    func load() async {
        do { summary = try await api.franchise(token: token()) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func loadCollection() async {
        do { collection = try await api.franchiseCollection(token: token()) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}
