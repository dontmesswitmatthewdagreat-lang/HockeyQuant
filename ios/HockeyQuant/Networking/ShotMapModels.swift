import Foundation

/// One shot, normalized so each team attacks a fixed net (home → +x, away → −x).
/// Rink coords: x ∈ [−100, 100], y ∈ [−42.5, 42.5].
struct ShotEvent: Decodable, Hashable, Identifiable {
    let x: Double
    let y: Double
    let team: String
    let result: String   // "goal" | "shot" | "miss"
    let period: Int
    let shotType: String?
    let shooter: String?

    var id: String { "\(team)-\(period)-\(x)-\(y)-\(result)" }
    var isGoal: Bool { result == "goal" }
    var isMiss: Bool { result == "miss" }
}

struct ShotTeamSummary: Decodable, Hashable { let sog: Int; let goals: Int }
struct ShotSummary: Decodable, Hashable { let home: ShotTeamSummary; let away: ShotTeamSummary }

struct GameShotMap: Decodable {
    let available: Bool
    let gameState: String?
    let home: String?
    let away: String?
    let shots: [ShotEvent]
    let summary: ShotSummary?
}

/// A team's shots aggregated over its recent games (all mirrored to the +x half).
struct TeamAggSummary: Decodable, Hashable {
    let games: Int; let shots: Int; let goals: Int; let shotsPerGame: Double
}
struct TeamShotMap: Decodable {
    let available: Bool
    let team: String?
    let games: Int?
    let shots: [ShotEvent]
    let summary: TeamAggSummary?
}
