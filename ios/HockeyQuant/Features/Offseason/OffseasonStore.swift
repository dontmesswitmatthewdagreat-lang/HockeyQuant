import Foundation

/// One asset moving in a trade (a contracted player, or a draft-pick token).
struct TradePiece: Codable, Hashable, Identifiable {
    let name: String            // "Connor McDavid" or "2027 1st Round Pick"
    let position: String        // "C" / "D" / "G" / "PICK"
    let aav: Double             // 0 for picks
    /// Fraction of the AAV the sending team keeps on its books (0 or 0.5).
    var retainedPct: Double? = nil
    var id: String { name }
    var isPick: Bool { position == "PICK" }
    /// Cap hit that actually moves to the receiving team.
    var transferredAav: Double { aav * (1 - (retainedPct ?? 0)) }
}

/// One hypothetical move in the user's offseason timeline.
struct GMMove: Codable, Identifiable {
    enum Kind: String, Codable { case signing, trade }
    let id: UUID
    let date: Date
    let kind: Kind
    // Signing
    var player: String?
    var position: String?
    var team: String?
    var aav: Double?
    var years: Int?
    var fairAav: Double?    // market value at signing time (grades the move)
    // Trade
    var teamA: String?
    var teamB: String?
    var piecesAtoB: [TradePiece]?
    var piecesBtoA: [TradePiece]?

    /// steal / fair / overpay vs the market model (signings only).
    var verdict: String? {
        guard kind == .signing, let aav, let fairAav, fairAav > 0 else { return nil }
        let prem = (aav - fairAav) / fairAav
        return prem < -0.15 ? "steal" : (prem > 0.15 ? "overpay" : "fair")
    }

    var headline: String {
        switch kind {
        case .signing:
            let yrs = years ?? 1
            return "\(team ?? "?") sign \(player ?? "?") — \(yrs) yr\(yrs == 1 ? "" : "s") × \((aav ?? 0).asCapMoney)"
        case .trade:
            return "\(teamA ?? "?") ↔ \(teamB ?? "?") trade"
        }
    }
}

/// Market data + the user's hypothetical moves ledger. Cap effects are
/// recomputed from the base Spotrac numbers every time, so deleting a move in
/// the middle of the timeline just works.
@Observable @MainActor
final class OffseasonStore {
    enum LoadState { case idle, loading, loaded, error(String) }

    private let api = APIClient()
    private static let movesKey = "offseasonMoves.v1"

    var state: LoadState = .idle
    private(set) var market: OffseasonMarket?
    private(set) var rosters: [String: [ContractPlayer]] = [:]
    private(set) var loadingRoster: Set<String> = []
    private(set) var moves: [GMMove] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.movesKey),
           let saved = try? JSONDecoder().decode([GMMove].self, from: data) {
            moves = saved
        }
    }

    func load() async {
        if case .loading = state { return }
        if market == nil { state = .loading }
        do {
            market = try await api.offseasonMarket()
            state = .loaded
        } catch {
            if market == nil { state = .error("Couldn't load the market. Pull to retry.") }
        }
    }

    func roster(for team: String) async -> [ContractPlayer] {
        if let cached = rosters[team] { return cached }
        guard !loadingRoster.contains(team) else { return [] }
        loadingRoster.insert(team)
        defer { loadingRoster.remove(team) }
        if let resp = try? await api.offseasonRoster(team: team) {
            rosters[team] = resp.players
            return resp.players
        }
        return []
    }

    // MARK: - Moves

    func addSigning(agent: FreeAgent, team: String, aav: Double, years: Int) {
        moves.append(GMMove(id: UUID(), date: Date(), kind: .signing,
                            player: agent.name, position: agent.position,
                            team: team, aav: aav, years: years, fairAav: agent.fairAav,
                            teamA: nil, teamB: nil, piecesAtoB: nil, piecesBtoA: nil))
        persist()
    }

    func addTrade(teamA: String, teamB: String, aToB: [TradePiece], bToA: [TradePiece]) {
        moves.append(GMMove(id: UUID(), date: Date(), kind: .trade,
                            player: nil, position: nil, team: nil, aav: nil, years: nil, fairAav: nil,
                            teamA: teamA, teamB: teamB, piecesAtoB: aToB, piecesBtoA: bToA))
        persist()
    }

    func removeMove(_ id: UUID) {
        moves.removeAll { $0.id == id }
        persist()
    }

    func clearMoves() {
        moves = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(moves) {
            UserDefaults.standard.set(data, forKey: Self.movesKey)
        }
    }

    // MARK: - Cap math

    /// Net cap-hit change from the user's moves (positive = more money on the books).
    func capDelta(for team: String) -> Double {
        var delta = 0.0
        for move in moves {
            switch move.kind {
            case .signing:
                if move.team == team { delta += move.aav ?? 0 }
            case .trade:
                // Only the transferred share moves; retained salary stays with
                // the sender (so the sender is relieved of less).
                let out = move.piecesAtoB ?? []
                let inbound = move.piecesBtoA ?? []
                if move.teamA == team {
                    delta += inbound.reduce(0) { $0 + $1.transferredAav } - out.reduce(0) { $0 + $1.transferredAav }
                } else if move.teamB == team {
                    delta += out.reduce(0) { $0 + $1.transferredAav } - inbound.reduce(0) { $0 + $1.transferredAav }
                }
            }
        }
        return delta
    }

    func effectiveSpace(for team: String) -> Double? {
        guard let base = market?.teams.first(where: { $0.abbrev == team }) else { return nil }
        return base.capSpace - capDelta(for: team)
    }

    func effectiveHit(for team: String) -> Double? {
        guard let base = market?.teams.first(where: { $0.abbrev == team }) else { return nil }
        return base.capHit + capDelta(for: team)
    }

    /// FA name → team that signed them in this playground (hides them from the pool).
    var signedAgents: [String: String] {
        var out: [String: String] = [:]
        for move in moves where move.kind == .signing {
            if let p = move.player, let t = move.team { out[p] = t }
        }
        return out
    }

    /// Players already moved in a trade, so the trade builder can gray them out.
    func tradedAway(from team: String) -> Set<String> {
        var out: Set<String> = []
        for move in moves where move.kind == .trade {
            if move.teamA == team { for p in move.piecesAtoB ?? [] where !p.isPick { out.insert(p.name) } }
            if move.teamB == team { for p in move.piecesBtoA ?? [] where !p.isPick { out.insert(p.name) } }
        }
        return out
    }
}
