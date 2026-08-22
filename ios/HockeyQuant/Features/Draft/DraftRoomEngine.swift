import Foundation
import Observation

/// Runs a first round on device: you pick for your team, the AI GMs pick for
/// the other 31.
///
/// This is a port of the mock-draft simulator's pick rule (`draft_simulator.py`),
/// not a second opinion — the AI here has to behave like the mock the user has
/// been reading all season, or the room feels arbitrary. It lives on device
/// because the alternative is a network round trip between a user and their
/// next pick, and a Render cold start in that gap would end the session.
///
/// The scoring weights arrive with the board rather than being hardcoded, so
/// retuning the mock retunes the room.
@MainActor
@Observable
final class DraftRoomEngine {

    /// A completed selection.
    struct Selection: Identifiable, Sendable {
        let overall: Int
        let team: String
        let entry: DraftBoardEntry
        let byUser: Bool
        let reason: String

        var id: Int { overall }
    }

    let room: DraftRoom
    let userTeam: String

    private(set) var selections: [Selection] = []
    private(set) var available: [DraftBoardEntry]
    /// Who owns each slot. Starts as the room's order and changes with trades,
    /// which is why the engine keeps its own copy rather than reading the room.
    private(set) var order: [String]
    /// Future picks still in the user's pocket, for the trade sheet.
    private(set) var userFutures: [DraftTrades.Asset]
    private(set) var tradeLog: [String] = []

    init(room: DraftRoom, userTeam: String) {
        self.room = room
        self.userTeam = userTeam
        self.order = room.order
        // Board order is the whole point of a board — sort once, then every
        // pick is a prefix scan.
        self.available = room.board.sorted { $0.value < $1.value }
        // One round is simulated, so anything beyond it is an abstract chip.
        self.userFutures = (1...3).map { .future(round: $0, year: room.draftYear + 1) }
    }

    // MARK: - State

    var pickNumber: Int { selections.count + 1 }
    var totalPicks: Int { order.count }
    var isComplete: Bool { selections.count >= order.count }
    var onTheClock: String? {
        selections.count < order.count ? order[selections.count] : nil
    }
    var isUserTurn: Bool { onTheClock == userTeam }
    var userSelections: [Selection] { selections.filter(\.byUser) }

    /// The picks this user owns, so the screen can say "you're up again at #14".
    var userPickNumbers: [Int] {
        order.enumerated().compactMap { $0.element == userTeam ? $0.offset + 1 : nil }
    }

    // MARK: - Trades

    /// Slots not yet used, with their current owner. A pick that's already been
    /// made is not an asset.
    var openPicks: [(overall: Int, team: String)] {
        order.enumerated()
            .filter { $0.offset >= selections.count }
            .map { (overall: $0.offset + 1, team: $0.element) }
    }

    var userOpenPicks: [DraftTrades.Asset] {
        openPicks.filter { $0.team == userTeam }.map { .pick(overall: $0.overall) }
    }

    /// Assets the user can currently offer.
    var userAssets: [DraftTrades.Asset] { userOpenPicks + userFutures }

    /// Move ownership. Rejects anything already drafted — a trade must not be
    /// able to rewrite a pick that's on the board.
    @discardableResult
    func applyTrade(with partner: String,
                    userGives: [DraftTrades.Asset],
                    userGets: [DraftTrades.Asset]) -> Bool {
        let slots = (userGives + userGets).compactMap { asset -> Int? in
            if case .pick(let overall) = asset { return overall }
            return nil
        }
        guard slots.allSatisfy({ $0 > selections.count }) else { return false }

        for asset in userGets {
            if case .pick(let overall) = asset { order[overall - 1] = userTeam }
        }
        for asset in userGives {
            switch asset {
            case .pick(let overall): order[overall - 1] = partner
            case .future: userFutures.removeAll { $0 == asset }
            }
        }
        tradeLog.append("Traded \(userGives.map(\.label).joined(separator: " + ")) to \(partner) for \(userGets.map(\.label).joined(separator: " + "))")
        return true
    }

    var nextUserPick: Int? { userPickNumbers.first { $0 >= pickNumber } }

    // MARK: - Picking

    /// Take a player for the user. Ignored unless it's actually their turn —
    /// the UI shouldn't be the only thing enforcing turn order.
    @discardableResult
    func userSelect(_ entry: DraftBoardEntry) -> Selection? {
        guard isUserTurn, let team = onTheClock,
              let index = available.firstIndex(of: entry) else { return nil }
        available.remove(at: index)
        let pick = Selection(overall: pickNumber, team: team, entry: entry,
                             byUser: true, reason: "Your pick")
        selections.append(pick)
        return pick
    }

    /// One AI selection for whoever is on the clock.
    @discardableResult
    func aiSelect() -> Selection? {
        guard !isComplete, let team = onTheClock, !isUserTurn else { return nil }
        guard let choice = bestAvailable(for: team) else { return nil }
        available.removeAll { $0.id == choice.id }
        let pick = Selection(overall: pickNumber, team: team, entry: choice,
                             byUser: false, reason: reason(for: choice, team: team))
        selections.append(pick)
        return pick
    }

    /// Best-available with a need tilt, over a short window of the board. The
    /// window is what stops need from ever outweighing a real talent gap: the
    /// consensus No. 1 goes first no matter who is picking.
    private func bestAvailable(for team: String) -> DraftBoardEntry? {
        let need = room.need(for: team)
        let window = available.prefix(max(1, room.pickWeights.window))
        return window.max { a, b in score(a, need) < score(b, need) }
    }

    private func score(_ entry: DraftBoardEntry, _ need: DraftNeed) -> Double {
        var s = -entry.value
        if entry.group == need.primary {
            s += room.pickWeights.primaryBonus
        } else if entry.group == need.secondary {
            s += room.pickWeights.secondaryBonus
        }
        // Goalies essentially never reach the first round.
        if entry.group == "G" && need.primary != "G" {
            s -= room.pickWeights.goalieReachPenalty
        }
        return s
    }

    private func reason(for entry: DraftBoardEntry, team: String) -> String {
        let need = room.need(for: team)
        guard entry.group == need.primary || entry.group == need.secondary,
              let rank = need.ranks[entry.group] else { return "Best player available" }
        let area: String
        switch entry.group {
        case "F": area = "offense (xGF) — needs scoring"
        case "D": area = "defense (xGA) — needs a defenseman"
        default:  area = "goaltending (GSAx) — needs a goalie"
        }
        return "\(Self.ordinal(rank)) in \(area)"
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 100 {
        case 11...13: suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    // MARK: - Scoring the finished draft (re-draft only)

    /// How the user's picks compare to where the league actually took them.
    /// Positive means value: you landed players the league valued more highly
    /// than the slot you spent.
    struct Verdict {
        let graded: Int              // picks with a real outcome to compare to
        let steals: Int              // taken later than the league took them
        let reaches: Int
        let averageEdge: Double      // mean (actual overall − your overall)
    }

    func verdict() -> Verdict? {
        guard room.isRedraftMode else { return nil }
        let edges: [Double] = userSelections.compactMap { pick in
            guard let actual = pick.entry.actual else { return nil }
            return Double(actual.overall - pick.overall)
        }
        guard !edges.isEmpty else { return nil }
        return Verdict(graded: edges.count,
                       steals: edges.filter { $0 > 0 }.count,
                       reaches: edges.filter { $0 < 0 }.count,
                       averageEdge: edges.reduce(0, +) / Double(edges.count))
    }

    /// What the league actually did with this slot, for a side-by-side.
    func actualPick(at overall: Int) -> ActualPick? { room.actualByOverall[overall] }
}
