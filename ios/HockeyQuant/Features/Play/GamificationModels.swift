import Foundation

// Models for the gamification tables. PostgREST decodes with exact key names,
// so snake_case columns are mapped via explicit CodingKeys.

struct UserStats: Decodable, Sendable {
    let totalXp: Int            // legacy (frozen since the Stanley Cup redesign)
    let level: Int             // legacy
    let currentStreak: Int
    let bestStreak: Int
    let picksMade: Int
    let picksCorrect: Int
    let beatsModel: Int
    let stanleyCups: Int       // trophy ladder — from weekly fantasy head-to-head
    let capSpace: Int          // salary-cap budget earned from correct picks
    /// Puck Freeze shields in hand. Earned every 7th consecutive correct pick,
    /// capped at 3; one absorbs a loss instead of resetting the streak.
    /// Optional so the app keeps decoding against a pre-030 database.
    let streakShields: Int?

    var shields: Int { streakShields ?? 0 }

    enum CodingKeys: String, CodingKey {
        case totalXp = "total_xp"
        case level
        case currentStreak = "current_streak"
        case bestStreak = "best_streak"
        case picksMade = "picks_made"
        case picksCorrect = "picks_correct"
        case beatsModel = "beats_model"
        case stanleyCups = "stanley_cups"
        case capSpace = "cap_space"
        case streakShields = "streak_shields"
    }

    // Tolerant decode: a missing column (e.g. before migration 015 is applied)
    // defaults to 0 instead of failing the whole stats load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalXp       = try c.decodeIfPresent(Int.self, forKey: .totalXp) ?? 0
        level         = try c.decodeIfPresent(Int.self, forKey: .level) ?? 1
        currentStreak = try c.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        bestStreak    = try c.decodeIfPresent(Int.self, forKey: .bestStreak) ?? 0
        picksMade     = try c.decodeIfPresent(Int.self, forKey: .picksMade) ?? 0
        picksCorrect  = try c.decodeIfPresent(Int.self, forKey: .picksCorrect) ?? 0
        beatsModel    = try c.decodeIfPresent(Int.self, forKey: .beatsModel) ?? 0
        stanleyCups   = try c.decodeIfPresent(Int.self, forKey: .stanleyCups) ?? 0
        capSpace      = try c.decodeIfPresent(Int.self, forKey: .capSpace) ?? 0
        streakShields = try c.decodeIfPresent(Int.self, forKey: .streakShields)
    }

    init(totalXp: Int, level: Int, currentStreak: Int, bestStreak: Int, picksMade: Int,
         picksCorrect: Int, beatsModel: Int, stanleyCups: Int, capSpace: Int,
         streakShields: Int? = nil) {
        self.totalXp = totalXp; self.level = level; self.currentStreak = currentStreak
        self.bestStreak = bestStreak; self.picksMade = picksMade; self.picksCorrect = picksCorrect
        self.beatsModel = beatsModel; self.stanleyCups = stanleyCups; self.capSpace = capSpace
        self.streakShields = streakShields
    }

    var accuracy: Double { picksMade > 0 ? Double(picksCorrect) / Double(picksMade) * 100 : 0 }

    static let empty = UserStats(totalXp: 0, level: 1, currentStreak: 0, bestStreak: 0,
                                 picksMade: 0, picksCorrect: 0, beatsModel: 0,
                                 stanleyCups: 0, capSpace: 0)
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
    let stanleyCups: Int
    let capSpace: Int
    let totalXp: Int
    let level: Int
    let currentStreak: Int
    let picksMade: Int
    let picksCorrect: Int
    let accuracy: Double

    var id: String { userId }
    var displayName: String { username ?? "Player \(userId.prefix(4))" }
    var arena: Arena { Arena.current(forCups: stanleyCups) }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case stanleyCups = "stanley_cups"
        case capSpace = "cap_space"
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
    /// Model win probability (0–1) for the picked team, as shown at pick time.
    /// XP scales by this and the grader cannot look it up afterwards — nothing
    /// stores per-game probabilities server-side. Capturing it here also means
    /// you're paid for the risk you took when you took it, rather than for a
    /// number that moved after a goalie was confirmed.
    let winProb: Double?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case gameDate = "game_date"
        case gameId = "game_id"
        case awayTeam = "away_team"
        case homeTeam = "home_team"
        case pickType = "pick_type"
        case pick
        case modelPick = "model_pick"
        case winProb = "win_prob"
    }
}
