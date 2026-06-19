import SwiftUI
import Observation

/// State + actions for the Fantasy League feature. All operations go through the
/// FastAPI backend (service-key authoritative). Uses the user's JWT for auth.
@MainActor
@Observable
final class FantasyStore {
    private let api = APIClient(environment: .production)

    private(set) var leagues: [FantasyLeagueSummary] = []
    private(set) var loadingLeagues = false
    var error: String?

    private let auth: AuthStore

    init(auth: AuthStore) {
        self.auth = auth
    }

    private func token() async throws -> String {
        guard let t = await auth.accessToken() else {
            throw APIClient.APIError.message("Please sign in to play fantasy.")
        }
        return t
    }

    func loadLeagues() async {
        loadingLeagues = true
        defer { loadingLeagues = false }
        do {
            leagues = try await api.myLeagues(token: token())
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @discardableResult
    func create(name: String, teamName: String, leagueType: String, mode: String = "group", cpuCount: Int = 0, maxMembers: Int, draftPace: String) async -> FantasyLeagueSummary? {
        do {
            let league = try await api.createLeague(name: name, teamName: teamName, leagueType: leagueType, mode: mode, cpuCount: cpuCount, maxMembers: maxMembers, draftPace: draftPace, token: token())
            await loadLeagues()
            return league
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func join(inviteCode: String, teamName: String) async -> FantasyLeagueSummary? {
        do {
            let league = try await api.joinLeague(inviteCode: inviteCode, teamName: teamName, token: token())
            await loadLeagues()
            return league
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func detail(_ id: String) async throws -> LeagueDetail {
        try await api.leagueDetail(id, token: token())
    }

    func startDraft(_ id: String) async throws -> DraftResponse {
        try await api.startDraft(id, token: token())
    }

    func startOffseason(_ id: String) async throws -> FantasyLeagueSummary {
        try await api.startOffseason(id, token: token())
    }

    func runLottery(_ id: String) async throws -> LotteryResult {
        try await api.runLottery(id, token: token())
    }

    func offseasonTrade(_ id: String, toMemberId: String, myPlayerId: String, theirPlayerId: String, myCap: Int) async throws -> TradeResult {
        try await api.offseasonTrade(id, toMemberId: toMemberId, myPlayerId: myPlayerId, theirPlayerId: theirPlayerId, myCap: myCap, token: token())
    }

    func startSeason(_ id: String) async throws -> FantasyLeagueSummary {
        try await api.startSeason(id, token: token())
    }

    func draftState(_ id: String) async throws -> DraftResponse {
        try await api.draftState(id, token: token())
    }

    func pick(_ id: String, playerId: String) async throws -> DraftResponse {
        try await api.makePick(id, playerId: playerId, token: token())
    }

    func autopick(_ id: String, expectedPick: Int? = nil) async throws -> DraftResponse {
        try await api.autopick(id, expectedPick: expectedPick, token: token())
    }

    func players(slotType: String?, query: String?) async throws -> [FantasyPlayer] {
        try await api.fantasyPlayers(slotType: slotType, query: query)
    }

    func season(_ id: String) async throws -> FantasySeasonResponse {
        try await api.season(id, token: token())
    }

    func simulateWeek(_ id: String, week: Int) async throws {
        try await api.simulateWeek(id, week: week, token: token())
    }

    // Playoffs
    func startPlayoffs(_ id: String) async throws { try await api.startPlayoffs(id, token: token()) }
    func advancePlayoffs(_ id: String) async throws { try await api.advancePlayoffs(id, token: token()) }

    // Trades
    func rosters(_ id: String) async throws -> [DraftMember] { try await api.leagueRosters(id, token: token()) }
    func trades(_ id: String) async throws -> [TradeItem] { try await api.trades(id, token: token()) }
    func proposeTrade(_ id: String, toMemberId: String, myPlayerId: String, theirPlayerId: String) async throws {
        try await api.proposeTrade(id, toMemberId: toMemberId, myPlayerId: myPlayerId, theirPlayerId: theirPlayerId, token: token())
    }
    func respondTrade(_ id: String, tradeId: String, accept: Bool) async throws {
        try await api.respondTrade(id, tradeId: tradeId, accept: accept, token: token())
    }

    // Global league
    func global() async throws -> GlobalResponse { try await api.globalLeague(token: token()) }
    func globalJoin(teamName: String) async throws -> FantasyLeagueSummary { try await api.globalJoin(teamName: teamName, token: token()) }
    func globalSetSlot(slot: String, playerId: String) async throws { try await api.globalSetSlot(slot: slot, playerId: playerId, token: token()) }
    func globalLeaderboard() async throws -> [GlobalLeaderboardRow] { try await api.globalLeaderboard(token: token()) }
    func cupMatchup() async throws -> CupMatchupResponse { try await api.cupMatchup(token: token()) }
}
