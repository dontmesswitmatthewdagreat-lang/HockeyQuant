import SwiftUI
import Observation

/// Loads the daily AI news digest (league + favorite team) from the backend.
@MainActor
@Observable
final class NewsStore {
    private let api = APIClient(environment: .production)

    private(set) var digests: [NewsDigest] = []
    private(set) var draftProspects: [Prospect] = []   // league draft board
    private(set) var teamProspects: [Prospect] = []    // favorite team's pool
    private(set) var mockDraft: MockDraft?             // weekly first-round projection
    private(set) var loading = false
    private(set) var loadingDraft = false
    private(set) var loadingTeam = false
    private(set) var loadingMock = false
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

    func loadDraftProspects() async {
        loadingDraft = true
        defer { loadingDraft = false }
        do {
            draftProspects = try await api.prospects(team: nil)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadTeamProspects(team: String) async {
        loadingTeam = true
        defer { loadingTeam = false }
        do {
            teamProspects = try await api.prospects(team: team)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMockDraft() async {
        loadingMock = true
        defer { loadingMock = false }
        do {
            mockDraft = try await api.mockDraft()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
