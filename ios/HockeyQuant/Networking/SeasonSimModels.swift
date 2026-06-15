import Foundation

/// A team's projected season outcome (season mode) and/or Cup odds (playoff mode).
struct ProjectedTeam: Decodable, Identifiable, Hashable {
    let team: String
    let division: String?
    let conference: String?
    let currentPoints: Int?
    let projPoints: Double?
    let playoffPct: Double?
    let cupPct: Double
    var id: String { team }
}

struct SeriesOdds: Decodable, Identifiable, Hashable {
    let away: String
    let home: String
    let awayPct: Double
    let homePct: Double
    let status: String
    var id: String { "\(away)@\(home)" }
}

struct SeasonProjection: Decodable {
    let mode: String          // "season" | "playoffs"
    let teams: [ProjectedTeam]
    let series: [SeriesOdds]?
}
