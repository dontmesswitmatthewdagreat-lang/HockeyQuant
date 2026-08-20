import Foundation

// MARK: - Model marketplace

/// A published model as `GET /api/marketplace/models` returns it.
///
/// That endpoint serves raw `user_models` rows, not the shaped `UserModel` the
/// owner's own list returns — so the weights arrive as their individual DB
/// columns and have to be reassembled here. Everything is optional: a row from
/// a schema that has since gained columns must still decode.
struct MarketplaceModel: Decodable, Identifiable, Sendable {
    let id: String
    let userId: String
    let name: String
    let description: String?
    /// Resolved server-side from `profiles`; falls back to "GM" there.
    let author: String?
    let forkCount: Int?
    let publishedAt: String?
    let forkedFrom: String?
    let createdAt: String?
    let modelType: String?
    let mlMeta: MarketplaceMLMeta?

    // Raw weight columns.
    let weightOffensive: Double?
    let weightDefensive: Double?
    let weightGoaltending: Double?
    let weightPointsPct: Double?
    let weightWinRate: Double?

    var forks: Int { forkCount ?? 0 }
    var isML: Bool { modelType == "ml" }
    var authorName: String { author ?? "GM" }
    var mlKindLabel: String { mlMeta?.kind == "boosted" ? "Boosted" : "Logistic" }
    var mlFeatures: [String] { (mlMeta?.features ?? []).map { Self.featureLabel($0) } }

    /// A hand-tuned model's weights, rebuilt from the raw columns. Defaults
    /// match the official model so a row missing a column still renders.
    var weights: ModelWeights {
        ModelWeights(offense: weightOffensive ?? 40,
                     defense: weightDefensive ?? 15,
                     goaltending: weightGoaltending ?? 30,
                     pointsPct: weightPointsPct ?? 10,
                     winRate: weightWinRate ?? 5)
    }

    /// Mirrors the backend's `_ML_FEATURE_LABELS` — the marketplace hands back
    /// the raw row, so the ids aren't humanized for us the way `/models` does.
    static func featureLabel(_ id: String) -> String {
        switch id {
        case "goalie": "Goalie (GSAX)"
        case "fatigue": "Fatigue / rest"
        case "streak": "Form / streak"
        case "st": "Special teams"
        case "injury": "Injuries"
        case "h2h": "Head-to-head"
        case "base_score": "Quality score"
        case "xg_diff": "Expected goals"
        default: id
        }
    }
}

/// Only the descriptive part of `ml_meta`. The rest of that blob is the trained
/// model itself (coefficients, standardization, decision stumps) — the app has
/// no use for it and decoding it would break the moment a model type is added.
struct MarketplaceMLMeta: Decodable, Sendable {
    let kind: String?
    let features: [String]?
    let window: Int?
    let trainedRange: [String]?
}

struct MarketplaceResponse: Decodable, Sendable { let models: [MarketplaceModel] }

/// `POST /api/models/{id}/publish`
struct PublishResult: Decodable, Sendable {
    let id: String
    let isPublic: Bool
    let publishedAt: String?
}

/// `POST /api/models/{id}/fork`
struct ForkResult: Decodable, Sendable {
    let id: String
    let name: String
    let forkedFrom: String?
}
