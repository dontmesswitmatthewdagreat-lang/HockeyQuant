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
    private(set) var shop: [PlayerCard] = []
    private(set) var lineup: [LineupSlot] = []
    private(set) var lineupRating: Int = 0
    private(set) var coins: Int = 0
    private(set) var challenge: ChallengeDetail?
    private(set) var challengeTeams: [String] = []
    private(set) var today: String = ""
    private(set) var rookieBoard: [PlayerCard] = []
    private(set) var rookiePicksRemaining = 0
    private(set) var rookieSeason = 0
    var error: String?

    init(auth: AuthStore) { self.auth = auth }

    private func token() async throws -> String {
        guard let t = await auth.accessToken() else {
            throw APIClient.APIError.message("Please sign in to play.")
        }
        return t
    }

    func load() async {
        do { let s = try await api.franchise(token: token()); summary = s; coins = s.coins }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func loadCollection() async {
        do { collection = try await api.franchiseCollection(token: token()) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func loadShop() async {
        do { let r = try await api.franchiseShop(token: token()); shop = r.cards; coins = r.coins }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    /// Buy a shop card; returns true on success and updates the Coin balance.
    func buy(_ playerId: String) async -> Bool {
        do { coins = try await api.franchiseBuy(playerId: playerId, token: token()); return true }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription; return false }
    }

    func loadLineup() async {
        do { let r = try await api.franchiseLineup(token: token()); lineup = r.lineup; lineupRating = r.rating }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func setLineupSlot(_ slot: String, cardId: String?) async {
        do { try await api.franchiseSetLineup(slot: slot, cardId: cardId, token: token()); await loadLineup() }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func loadChallenge() async {
        do {
            let r = try await api.franchiseChallenge(token: token()); challenge = r.challenge; today = r.today
            let o = try await api.franchiseChallengeOptions(token: token()); challengeTeams = o.teams
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func lockChallenge(_ team: String) async -> Bool {
        do { try await api.franchiseLockChallenge(opponentTeam: team, token: token()); await loadChallenge(); return true }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription; return false }
    }

    func loadRookieDraft() async {
        do {
            let r = try await api.franchiseRookieDraft(token: token())
            rookieBoard = r.board; rookiePicksRemaining = r.picksRemaining; rookieSeason = r.seasonYear
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func draftRookie(_ playerId: String) async -> Bool {
        do { try await api.franchiseRookiePick(playerId: playerId, token: token()); await loadRookieDraft(); return true }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription; return false }
    }
}
