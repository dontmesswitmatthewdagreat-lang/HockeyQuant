import Foundation

// Models for the gamification tables. PostgREST decodes with exact key names,
// so snake_case columns are mapped via explicit CodingKeys.

struct UserStats: Decodable, Sendable {
    let totalXp: Int
    let level: Int
    let currentStreak: Int
    let bestStreak: Int
    let picksMade: Int
    let picksCorrect: Int
    let beatsModel: Int

    enum CodingKeys: String, CodingKey {
        case totalXp = "total_xp"
        case level
        case currentStreak = "current_streak"
        case bestStreak = "best_streak"
        case picksMade = "picks_made"
        case picksCorrect = "picks_correct"
        case beatsModel = "beats_model"
    }

    var accuracy: Double { picksMade > 0 ? Double(picksCorrect) / Double(picksMade) * 100 : 0 }
    var xpIntoLevel: Int { totalXp % 100 }
    var xpForNextLevel: Int { 100 }
    var progressToNextLevel: Double { Double(xpIntoLevel) / 100.0 }

    static let empty = UserStats(totalXp: 0, level: 1, currentStreak: 0, bestStreak: 0,
                                 picksMade: 0, picksCorrect: 0, beatsModel: 0)
}

struct UserPick: Decodable, Identifiable, Sendable {
    let id: String
    let gameId: String
    let gameDate: String
    let pick: String
    let modelPick: String?
    let correct: Bool?
    let xpAwarded: Int

    enum CodingKeys: String, CodingKey {
        case id, pick, correct
        case gameId = "game_id"
        case gameDate = "game_date"
        case modelPick = "model_pick"
        case xpAwarded = "xp_awarded"
    }
}

struct LeaderboardEntry: Decodable, Identifiable, Sendable {
    let userId: String
    let username: String?
    let totalXp: Int
    let level: Int
    let currentStreak: Int
    let picksMade: Int
    let picksCorrect: Int
    let accuracy: Double

    var id: String { userId }
    var displayName: String { username ?? "Player \(userId.prefix(4))" }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case totalXp = "total_xp"
        case level
        case currentStreak = "current_streak"
        case picksMade = "picks_made"
        case picksCorrect = "picks_correct"
        case accuracy
    }
}

struct Achievement: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let icon: String
}

struct UserAchievement: Decodable, Sendable {
    let achievementId: String

    enum CodingKeys: String, CodingKey {
        case achievementId = "achievement_id"
    }
}

/// Encodable payload for upserting a pick.
struct PickPayload: Encodable, Sendable {
    let userId: String
    let gameDate: String
    let gameId: String
    let awayTeam: String
    let homeTeam: String
    let pickType: String
    let pick: String
    let modelPick: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case gameDate = "game_date"
        case gameId = "game_id"
        case awayTeam = "away_team"
        case homeTeam = "home_team"
        case pickType = "pick_type"
        case pick
        case modelPick = "model_pick"
    }
}
