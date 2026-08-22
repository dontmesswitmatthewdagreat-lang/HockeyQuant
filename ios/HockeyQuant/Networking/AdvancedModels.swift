import Foundation

// MARK: - Goal-differential decomposition

/// Why a team's goal differential is what it is.
///
/// Every field past the identity itself is optional so the screen still renders
/// against a backend that predates it — the same rule the rest of the app
/// follows.
struct TeamDecomposition: Decodable, Sendable {
    let team: String
    let gamesPlayed: Int
    let goalsFor: Double
    let goalsAgainst: Double
    let differential: Double
    let splits: [StrengthSplit]

    /// Totals across every strength state.
    let process: Double
    let finishing: Double
    let goaltending: Double

    /// Zero by construction. If the states stop accounting for the whole
    /// differential — MoneyPuck adding or renaming one — this goes non-zero and
    /// the card says so rather than showing a breakdown that doesn't add up.
    let residual: Double?

    var addsUp: Bool { abs(residual ?? 0) < 0.01 }

    /// The three causes, largest absolute first — the card leads with whichever
    /// one is actually driving the record.
    var causes: [(label: String, value: Double)] {
        [("Process", process), ("Finishing", finishing), ("Goaltending", goaltending)]
            .sorted { abs($0.value) > abs($1.value) }
    }
}

/// One strength state's differential, split into its three causes.
struct StrengthSplit: Decodable, Sendable, Identifiable {
    let state: String            // 5on5 | 5on4 | 4on5 | other
    let label: String
    let differential: Double
    let process: Double
    let finishing: Double
    let goaltending: Double
    let residual: Double?

    var id: String { state }
}

// MARK: - Skater impact

/// A skater's season: production summarised as Game Score, plus what happens to
/// the run of play while he's on the ice.
struct SkaterImpact: Decodable, Sendable, Identifiable {
    let playerId: Int
    let name: String
    let team: String
    let position: String
    let positionGroup: String    // F | D
    let gamesPlayed: Int
    let icetime: Double          // seconds
    let toiPerGame: Double       // minutes

    let gameScore: Double
    let gameScorePer60: Double
    let goals: Double
    let primaryAssists: Double
    let secondaryAssists: Double
    let points: Double
    /// Goals above or below what his shots were worth — finishing, or luck.
    let finishing: Double
    let penaltyDifferential: Double

    // 5-on-5 run of play. Absent for a skater with no even-strength row.
    let evIcetime: Double?
    let xgfPer60: Double?
    let xgaPer60: Double?
    let xgfPct: Double?
    /// The honest one: share of expected goals with him on the ice, minus the
    /// same share when he's off it.
    let xgfPctRel: Double?
    let corsiPct: Double?
    let zoneStartPct: Double?

    /// League percentile within his position group, keyed by metric name.
    /// Absent for anyone under the ice-time floor, where a rate is noise.
    let percentiles: [String: Int]?

    var id: Int { playerId }
    var isRanked: Bool { percentiles?.isEmpty == false }

    func percentile(_ metric: String) -> Int? { percentiles?[metric] }
}

struct SkaterImpactResponse: Decodable, Sendable {
    let team: String
    let skaters: [SkaterImpact]
}

// MARK: - Goalie impact

/// A goalie's season. GSAx leads because it's the only fair comparison across
/// teams: goals saved relative to what the shots he actually faced were worth,
/// so a goalie behind a leaky defence isn't punished for the volume.
struct GoalieImpact: Decodable, Sendable, Identifiable {
    let playerId: Int
    let name: String
    let team: String
    let gamesPlayed: Int
    let icetime: Double
    let toiPerGame: Double

    let gsax: Double
    let gsaxPer60: Double
    let shotsAgainst: Double
    let goalsAgainst: Double
    let savePct: Double?
    let hdShots: Double
    let hdSavePct: Double?
    /// Goals saved above expected on high-danger shots alone — where goalies
    /// actually separate from each other.
    let hdGsax: Double
    /// ⚠️ Rank-only. MoneyPuck's expected-rebound baseline isn't calibrated to
    /// actual rebounds, so this is negative for nearly every goalie and the raw
    /// value is meaningless. The percentile is fine; never show the number.
    let reboundControl: Double
    let workloadPer60: Double

    let percentiles: [String: Int]?

    var id: Int { playerId }
    var isRanked: Bool { percentiles?.isEmpty == false }
    func percentile(_ metric: String) -> Int? { percentiles?[metric] }
}

struct GoalieImpactResponse: Decodable, Sendable {
    let team: String
    let goalies: [GoalieImpact]
}

// MARK: - Line chemistry

/// A real forward line or defence pair and how it performed at 5-on-5.
struct LineUnit: Decodable, Sendable, Identifiable {
    let players: [UnitPlayer]
    let minutes: Int
    let gamesPlayed: Int
    let xgfPct: Double?
    let xgfPer60: Double
    let xgaPer60: Double
    let gfPct: Double?
    let hdcfPct: Double?
    /// Goals above or below what the unit's chances were worth.
    let finishing: Double
    /// Unit xGF% minus what its members manage in their other minutes.
    /// Absent when a member has too little time away from this unit to compare.
    let chemistry: Double?

    var id: String { players.map { String($0.playerId) }.joined(separator: "-") }
    var label: String { players.map(\.lastName).joined(separator: " – ") }
}

struct UnitPlayer: Decodable, Sendable, Hashable {
    let playerId: Int
    let name: String
    let position: String?
    // Present only on With/Without rows.
    let apartXgfPct: Double?
    let apartMinutes: Int?

    var lastName: String { name.split(separator: " ").last.map(String.init) ?? name }
}

/// A defence pair together vs. apart. Forwards are excluded upstream — their
/// "apart" minutes are too contaminated by unlisted short-lived trios to mean
/// anything.
struct PairWowy: Decodable, Sendable, Identifiable {
    let players: [UnitPlayer]
    let togetherXgfPct: Double
    let togetherMinutes: Int
    /// Share of both players' ice time that listed combinations account for.
    let coverage: Int
    /// Together minus the better man's apart number — positive means the pair
    /// beats what either of them does away from it.
    let lift: Double

    var id: String { players.map { String($0.playerId) }.joined(separator: "-") }
}

struct LineChemistryResponse: Decodable, Sendable {
    let available: Bool
    let team: String
    let lines: [LineUnit]
    let pairs: [LineUnit]
    let wowy: [PairWowy]
}
