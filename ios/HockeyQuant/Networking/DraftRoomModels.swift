import Foundation

// MARK: - Interactive draft room

/// Everything needed to run a first round locally: the order, the whole board,
/// and what each team needs. One payload, because the draft itself happens on
/// device — see `DraftRoomEngine`.
struct DraftRoom: Decodable, Sendable {
    let draftYear: Int
    /// 32 team abbrevs, pick 1 first. Mutable because re-running the lottery
    /// reorders the top of it.
    private(set) var order: [String]
    let orderBasis: String?
    let board: [DraftBoardEntry]
    let lotteryOdds: [LotteryOdds]?
    /// Reverse-standings order, before any lottery. The re-roll starts from
    /// this, not from `order` — that one already has a lottery baked in.
    let standingsOrder: [String]?
    // Everything below is optional so the room still opens against a backend
    // that predates it — the same rule the rest of the app follows. Without it
    // one added field turns the whole screen into a decode error.
    private let needs: [String: DraftNeed]?
    private let teamNames: [String: String]?
    private let weights: DraftWeights?
    /// True when this class has already been drafted, so the room is a re-draft
    /// that can be scored against what the league actually did.
    private let isRedraft: Bool?
    private let actualFirstRound: [ActualPick]?

    var isRedraftMode: Bool { isRedraft ?? false }
    var realFirstRound: [ActualPick] { actualFirstRound ?? [] }
    var pickWeights: DraftWeights { weights ?? .standard }

    func teamName(_ abbrev: String) -> String { teamNames?[abbrev] ?? abbrev }

    /// Always interpolate the year through this. `Text("\(someInt)")` goes via
    /// LocalizedStringKey and groups the digits, which renders 2026 as "2,026".
    var yearLabel: String { String(draftYear) }

    /// Adopt a re-run lottery. The board and needs are untouched — only who
    /// picks where changes.
    mutating func applyLottery(_ outcome: DraftLottery.Outcome) {
        order = outcome.order
    }

    /// A team with no computed need still has to draft; best-available with no
    /// tilt is the honest default. (MoneyPuck being down drops the needs map.)
    func need(for abbrev: String) -> DraftNeed { needs?[abbrev] ?? .none }

    var actualByOverall: [Int: ActualPick] {
        Dictionary(realFirstRound.map { ($0.overall, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

/// A team's positional need: which group it's worst at, and how it ranks
/// league-wide (1 = best, 32 = worst) in each.
struct DraftNeed: Decodable, Sendable, Hashable {
    let primary: String                     // "F" | "D" | "G"
    let secondary: String
    let ranks: [String: Int]

    static let none = DraftNeed(primary: "", secondary: "", ranks: [:])
}

/// One prospect on the board. `value` is board position (lower = better);
/// `actual` is where the league really took him, absent before the draft.
struct DraftBoardEntry: Decodable, Identifiable, Sendable, Hashable {
    let group: String                       // F | D | G
    let value: Double
    let actual: ActualPick?
    let prospect: Prospect

    var id: String { prospect.id }
    var name: String { prospect.name }
    var position: String? { prospect.position }

    static func == (a: DraftBoardEntry, b: DraftBoardEntry) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ActualPick: Decodable, Sendable, Hashable {
    let overall: Int
    let round: Int?
    let team: String?
    let player: String?
    let position: String?
}

/// The AI's pick weights, sent with the board so tuning them server-side takes
/// effect without an app release.
struct DraftWeights: Decodable, Sendable {
    let primaryBonus: Double
    let secondaryBonus: Double
    let goalieReachPenalty: Double
    let window: Int

    /// Mirrors `draft_simulator.py`'s constants, for a backend that doesn't
    /// send them yet. Keep in step with that file if they're ever retuned.
    static let standard = DraftWeights(primaryBonus: 1.5, secondaryBonus: 0.75,
                                       goalieReachPenalty: 6.0, window: 5)
}
