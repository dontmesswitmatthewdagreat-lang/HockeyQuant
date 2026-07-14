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
    private(set) var mocks: [MockDraft] = []           // all sources (internal + insiders)
    private(set) var draftClass: [DraftedPick] = []    // favorite team's actual picks
    private(set) var calder: CalderResponse?           // rookie race (dormant offseason)
    private(set) var pipelineStats: [String: PipelineStat] = [:]  // name -> junior line
    private(set) var marketPulse: MarketOverview?  // FA market temperature for the feed
    private(set) var leaguePulses: [LeaguePulse] = []  // luck / race / deadline / playoffs
    private(set) var feedItems: [NewsFeedItem] = []    // The Wire (archive stream)
    private(set) var feedCursor: String?
    private(set) var feedLoadingOlder = false
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
            mocks = try await api.mockDrafts()
            mockDraft = mocks.first(where: \.isInternal) ?? mocks.first
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadDraftClass(team: String) async {
        draftClass = (try? await api.draftResults(team: team).picks) ?? []
    }

    func loadCalder() async {
        calder = try? await api.calderWatch()
    }

    func loadMarketPulse() async {
        marketPulse = try? await api.marketOverview()
    }

    func loadLeaguePulses() async {
        leaguePulses = (try? await api.leaguePulses()) ?? []
    }

    func loadFeed(team: String?) async {
        guard let resp = try? await api.newsFeed(team: team) else { return }
        feedItems = resp.items
        feedCursor = resp.nextCursor
    }

    func loadOlderFeed(team: String?) async {
        guard let cursor = feedCursor, !feedLoadingOlder else { return }
        feedLoadingOlder = true
        defer { feedLoadingOlder = false }
        guard let resp = try? await api.newsFeed(team: team, cursor: cursor) else { return }
        let known = Set(feedItems.map(\.id))
        feedItems += resp.items.filter { !known.contains($0.id) }
        feedCursor = resp.nextCursor
    }

    func loadPipelineStats(team: String) async {
        let stats = (try? await api.pipelineStats(team: team)) ?? []
        pipelineStats = Dictionary(stats.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
    }
}
