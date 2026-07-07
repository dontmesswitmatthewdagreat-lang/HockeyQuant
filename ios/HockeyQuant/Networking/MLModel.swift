import Foundation

/// A learned (standardized) feature weight from the trained model.
struct MLWeight: Decodable, Identifiable {
    let id: String
    let label: String
    let weight: Double
}

/// One point on the learning curve: CV accuracy when training on the most
/// recent `games` games.
struct MLCurvePoint: Decodable, Identifiable {
    let games: Int
    let accuracy: Double
    var id: Int { games }
}

struct MLSaveResponse: Decodable {
    let modelId: String
    let name: String
    let kind: String
    let backfilled: Int
    let accuracy: Double
}

struct MLModelResponse: Decodable {
    let n: Int                    // games actually trained on (the window)
    let homeRate: Double
    let officialAccuracy: Double
    let kind: String              // "logistic" | "boosted"
    let accuracy: Double          // 5-fold CV
    let accuracyStd: Double
    let auc: Double
    let featuresUsed: [String]
    let weights: [MLWeight]
    // Optional until the backend deploy lands.
    let totalGames: Int?          // all graded games available
    let dateRange: [String]?      // [first, last] yyyy-MM-dd of the window
    let curve: [MLCurvePoint]?    // learning curve across window sizes
}
