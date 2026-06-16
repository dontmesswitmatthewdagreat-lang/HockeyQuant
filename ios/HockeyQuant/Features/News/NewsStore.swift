import SwiftUI
import Observation

/// Loads the daily AI news digest (league + favorite team) from the backend.
@MainActor
@Observable
final class NewsStore {
    private let api = APIClient(environment: .production)

    private(set) var digests: [NewsDigest] = []
    private(set) var prospects: [Prospect] = []
    private(set) var loading = false
    private(set) var loadingProspects = false
    var error: String?

    func loadLatest(team: String?) async {
        loading = true
        defer { loading = false }
        do {
            digests = try await api.newsLatest(team: team)
            if let kp = digests.compactMap(\.keyPoints).first(where: { !$0.isEmpty }) {
                DigestNotifier.updatePoints(kp)
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func search(_ query: String) async -> NewsSearchResponse? {
        do { return try await api.newsSearch(query: query) }
        catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func loadProspects(team: String?) async {
        loadingProspects = true
        defer { loadingProspects = false }
        do {
            prospects = try await api.prospects(team: team)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
