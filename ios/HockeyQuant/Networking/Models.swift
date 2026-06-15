import Foundation

// Codable models mirroring the FastAPI response models in
// `backend/routers/predictions.py`. The backend is the source of truth for
// field names. Decoding uses `.convertFromSnakeCase`, so snake_case JSON keys
// map to camelCase Swift properties automatically.

struct PredictionsResponse: Decodable, Sendable {
    let date: String
    let gamesCount: Int
    let predictions: [GamePrediction]
    let status: PredictionStatus?
}

struct PredictionStatus: Decodable, Sendable {
    let lastUpdated: String?
    let nextUpdate: String?
    let firstGameTime: String?
    let isCached: Bool?
}

struct GamePrediction: Decodable, Sendable, Identifiable {
    let away: TeamAnalysis
    let home: TeamAnalysis
    let pick: String
    let diff: Double
    let confidence: String
    let factors: [String]?
    let gameTime: String?
    let isOfficial: Bool?
    let officialAt: String?
    let goalieStatusAway: String?
    let goalieStatusHome: String?
    let bettingLines: BettingLines?

    var id: String { "\(away.team)@\(home.team)-\(gameTime ?? "tbd")" }

    var pickIsHome: Bool { pick.uppercased() == home.team.uppercased() }

    /// Win probabilities prefer the Poisson moneyline output; fall back to a
    /// quality-score split so the bar always renders.
    var awayWinProb: Double {
        if let p = bettingLines?.mlAwayProb, p > 0 { return p }
        return qualityScoreSplit.away
    }
    var homeWinProb: Double {
        if let p = bettingLines?.mlHomeProb, p > 0 { return p }
        return qualityScoreSplit.home
    }

    private var qualityScoreSplit: (away: Double, home: Double) {
        let a = away.finalScore
        let h = home.finalScore
        let total = a + h
        guard total > 0 else { return (50, 50) }
        return (a / total * 100, h / total * 100)
    }
}

struct TeamAnalysis: Decodable, Sendable {
    let team: String
    let finalScore: Double
    let baseScore: Double
    let goalie: String
    let goalieGsax: Double
    let goalieSvPct: Double
    let goalieGaa: Double
    let backupGoalie: String?
    let backupGoalieGsax: Double?
    let backupGoalieSvPct: Double?
    let backupGoalieGaa: Double?
    let fatigue: String
    let fatigueMult: Double
    let streak: String
    let streakMult: Double
    let specialTeams: String
    let stMult: Double
    let injuries: String
    let injuryMult: Double
    let h2h: String
    let h2hMult: Double

    var info: TeamInfo { TeamInfo.lookup(team) }
}

struct BettingLines: Decodable, Sendable {
    let awayExpectedGoals: Double
    let homeExpectedGoals: Double
    let predictedTotal: Double
    let predictedMargin: Double
    // Puck line
    let puckLine: Double
    let puckLineSource: String
    let puckLineHomeCoverProb: Double
    let puckLineAwayCoverProb: Double
    let optimalSpread: Double
    let optimalSpreadProb: Double
    let optimalSpreadSide: String
    // Over / under
    let overUnder: Double
    let overUnderSource: String
    let overProb: Double
    let underProb: Double
    let pushProb: Double?
    let optimalTotal: Double
    let optimalTotalProb: Double
    let optimalTotalRec: String
    // Moneyline (regulation) win probabilities
    let mlHomeProb: Double?
    let mlAwayProb: Double?
}

// MARK: - AI summary ("Why [team]?")

struct SummaryResponse: Decodable, Sendable {
    let summary: String
}

/// Mirrors `TeamSummaryData` in backend/routers/summary.py.
struct TeamSummaryData: Encodable, Sendable {
    let team: String
    let finalScore: Double
    let goalie: String
    let goalieGsax: Double
    let goalieSvPct: Double
    let fatigue: String
    let streak: String
    let injuries: String
    let h2h: String

    init(_ t: TeamAnalysis) {
        team = t.team
        finalScore = t.finalScore
        goalie = t.goalie
        goalieGsax = t.goalieGsax
        goalieSvPct = t.goalieSvPct
        fatigue = t.fatigue
        streak = t.streak
        injuries = t.injuries
        h2h = t.h2h
    }
}

/// Mirrors `SummaryRequest` in backend/routers/summary.py.
struct SummaryRequest: Encodable, Sendable {
    let away: TeamSummaryData
    let home: TeamSummaryData
    let pick: String
    let diff: Double
    let confidence: String
    let factors: [String]
    let gameTime: String?

    init(game: GamePrediction) {
        away = TeamSummaryData(game.away)
        home = TeamSummaryData(game.home)
        pick = game.pick
        diff = game.diff
        confidence = game.confidence
        factors = game.factors ?? []
        gameTime = game.gameTime
    }
}

// MARK: - Live / final scores (GET /api/games/{date}/scores)

struct ScoresResponse: Decodable, Sendable {
    let games: [GameScore]
}

// MARK: - Accuracy (GET /api/accuracy/stats, /trend, /parlay-stats)

struct WindowStats: Decodable, Sendable {
    let correct: Int
    let total: Int
    let pct: Double
}

struct AccuracyStats: Decodable, Sendable {
    let totalGames: Int
    let correctPicks: Int
    let accuracyPct: Double
    let strongTotal: Int
    let strongCorrect: Int
    let strongPct: Double
    let moderateTotal: Int
    let moderateCorrect: Int
    let moderatePct: Double
    let closeTotal: Int
    let closeCorrect: Int
    let closePct: Double
    let rolling30: WindowStats?
    let currentSeason: WindowStats?
    let allTime: WindowStats?
    // Bet-type accuracy
    let puckLineTotal: Int
    let puckLineCorrectCount: Int
    let puckLinePct: Double
    let ouTotal: Int
    let ouCorrectCount: Int
    let ouPct: Double
}

struct PredictionRecord: Decodable, Sendable, Identifiable {
    let gameDate: String
    let gameId: String
    let awayTeam: String
    let homeTeam: String
    let pick: String
    let confidence: String
    let awayFinal: Int?
    let homeFinal: Int?
    let actualWinner: String?
    let correct: Bool?

    var id: String { "\(gameId)-\(gameDate)" }
}

struct AccuracyResponse: Decodable, Sendable {
    let stats: AccuracyStats
    let recentPredictions: [PredictionRecord]
}

struct TrendDataPoint: Decodable, Sendable, Identifiable {
    let date: String
    let rollingAccuracy: Double
    let gamesInWindow: Int
    let cumulativeAccuracy: Double
    let cumulativeGames: Int

    var id: String { date }
}

struct TrendResponse: Decodable, Sendable {
    let windowSize: Int
    let totalGames: Int
    let dataPoints: [TrendDataPoint]
}

struct ParlayStats: Decodable, Sendable {
    let totalParlays: Int
    let gradedParlays: Int
    let hitCount: Int
    let hitPct: Double
    let avgLegs: Double
    let avgCombinedProb: Double
    let avgLegsCorrect: Double
}

// MARK: - Teams (GET /api/teams, /api/teams/{abbrev})

struct TeamListItem: Decodable, Sendable, Identifiable {
    let abbrev: String
    let name: String
    let division: String
    let conference: String
    let wins: Int
    let losses: Int
    let otl: Int
    let points: Int
    let pointsPct: Double
    let goalsFor: Int
    let goalsAgainst: Int

    var id: String { abbrev }
    var info: TeamInfo { TeamInfo.lookup(abbrev) }
    var record: String { "\(wins)-\(losses)-\(otl)" }
}

struct TeamBasicInfo: Decodable, Sendable {
    let abbrev: String
    let name: String
    let division: String
    let conference: String
}

struct TeamStandingStats: Decodable, Sendable {
    let wins: Int
    let losses: Int
    let otl: Int
    let points: Int
    let pointsPct: Double
    let goalsFor: Int
    let goalsAgainst: Int
    let goalDiff: Int
    let xgf: Double?
    let xga: Double?
}

struct GoalieStats: Decodable, Sendable, Identifiable {
    let name: String
    let gamesPlayed: Int
    let gsax: Double
    let svPct: Double
    let gaa: Double
    let isStarter: Bool

    var id: String { name }
}

struct AdvancedStats: Decodable, Sendable {
    let corsiPct: Double
    let fenwickPct: Double
    let xgFor: Double
    let xgAgainst: Double
    let xgPct: Double
    let pdo: Double
    let shootingPct: Double
    let savePct: Double
    let hdCfPct: Double
    let ppPct: Double
    let pkPct: Double
    let shotsForPg: Double
    let shotsAgainstPg: Double
    let gamesPlayed: Int
}

struct TeamDetailResponse: Decodable, Sendable {
    let team: TeamBasicInfo
    let stats: TeamStandingStats
    let goalies: [GoalieStats]
    let injuries: [String]
    let recentForm: String
    let advancedStats: AdvancedStats?
}

// MARK: - Custom models (/api/models, auth required)

struct ModelWeights: Codable, Sendable, Equatable {
    var offense: Double
    var defense: Double
    var goaltending: Double
    var pointsPct: Double
    var winRate: Double

    var total: Double { offense + defense + goaltending + pointsPct + winRate }

    static let official = ModelWeights(offense: 40, defense: 15, goaltending: 30, pointsPct: 10, winRate: 5)

    /// Labeled rows for sliders / display.
    var rows: [(label: String, value: Double, key: WritableKeyPath<ModelWeights, Double>)] {
        [("Offense", offense, \.offense),
         ("Defense", defense, \.defense),
         ("Goaltending", goaltending, \.goaltending),
         ("Points %", pointsPct, \.pointsPct),
         ("Win rate", winRate, \.winRate)]
    }
}

struct ModelMultipliers: Codable, Sendable, Equatable {
    var fatigue: Double
    var streak: Double
    var specialTeams: Double
    var injuries: Double
    var h2h: Double

    static let official = ModelMultipliers(fatigue: 1, streak: 1, specialTeams: 1, injuries: 1, h2h: 1)

    var isOfficial: Bool { self == .official }

    var rows: [(label: String, value: Double, key: WritableKeyPath<ModelMultipliers, Double>)] {
        [("Fatigue & travel", fatigue, \.fatigue),
         ("Streak / form", streak, \.streak),
         ("Special teams", specialTeams, \.specialTeams),
         ("Injuries", injuries, \.injuries),
         ("Head-to-head", h2h, \.h2h)]
    }
}

struct ModelAccuracyStats: Decodable, Sendable {
    let totalPredictions: Int
    let correctPredictions: Int
    let accuracyPct: Double
    let strongTotal: Int
    let strongCorrect: Int
    let moderateTotal: Int
    let moderateCorrect: Int
    let closeTotal: Int
    let closeCorrect: Int
}

struct UserModel: Decodable, Identifiable, Sendable {
    let id: String
    let userId: String
    let name: String
    let description: String?
    let weights: ModelWeights
    let multipliers: ModelMultipliers?   // optional: absent until backend is deployed
    let isActive: Bool
    let createdAt: String
    let updatedAt: String
    let accuracy: ModelAccuracyStats?

    var resolvedMultipliers: ModelMultipliers { multipliers ?? .official }
}

struct ModelsListResponse: Decodable, Sendable {
    let models: [UserModel]
    let total: Int
}

struct CreateModelRequest: Encodable, Sendable {
    let name: String
    let description: String?
    let weights: ModelWeights
    let multipliers: ModelMultipliers
}

/// Response from `GET /api/models/{id}/predictions/{date}` — the model's picks.
struct ModelPredictionsResponse: Decodable, Sendable {
    let date: String
    let modelName: String
    let gamesCount: Int
    let predictions: [GamePrediction]
}

struct ModelLeaderboardEntry: Decodable, Identifiable, Sendable {
    let modelId: String
    let modelName: String
    let username: String?
    let userId: String
    let weights: ModelWeights?
    let totalPredictions: Int
    let correctPredictions: Int
    let accuracyPct: Double?
    let modelType: String?
    let mlKind: String?

    var id: String { modelId }
    var displayUser: String { username ?? "Player \(userId.prefix(4))" }
    var isML: Bool { modelType == "ml" }
}

struct GameScore: Decodable, Sendable, Identifiable {
    let awayTeam: String?
    let homeTeam: String?
    let awayScore: Int
    let homeScore: Int
    let gameState: String
    let period: Int?
    let periodType: String?
    let timeRemaining: String?
    let inIntermission: Bool?

    var id: String { "\(awayTeam ?? "?")@\(homeTeam ?? "?")" }

    /// True when the game is in progress or finished (i.e. has a real score).
    var isActive: Bool {
        ["LIVE", "CRIT", "FINAL", "OFF"].contains(gameState.uppercased())
    }
    var isLive: Bool { ["LIVE", "CRIT"].contains(gameState.uppercased()) }
    var isFinal: Bool { ["FINAL", "OFF"].contains(gameState.uppercased()) }
}
