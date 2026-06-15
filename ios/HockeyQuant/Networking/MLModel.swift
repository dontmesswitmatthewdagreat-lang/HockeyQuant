import Foundation

/// A learned (standardized) feature weight from the trained model.
struct MLWeight: Decodable, Identifiable {
    let id: String
    let label: String
    let weight: Double
}

struct MLSaveResponse: Decodable {
    let modelId: String
    let name: String
    let kind: String
    let backfilled: Int
    let accuracy: Double
}

struct MLModelResponse: Decodable {
    let n: Int
    let homeRate: Double
    let officialAccuracy: Double
    let kind: String              // "logistic" | "boosted"
    let accuracy: Double          // 5-fold CV
    let accuracyStd: Double
    let auc: Double
    let featuresUsed: [String]
    let weights: [MLWeight]
}
