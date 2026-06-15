import Foundation

/// One predicted-probability bucket: the model's avg predicted win % (`mid`) vs the
/// actual win rate (`actualPct`) over `n` predictions.
struct CalibrationBucket: Decodable, Identifiable {
    let lo: Int
    let hi: Int
    let mid: Double
    let actualPct: Double
    let n: Int
    var id: Int { lo }
}

struct CalibrationResponse: Decodable {
    let buckets: [CalibrationBucket]
    let calibrationError: Double
    let games: Int
    let points: Int
    let verdict: String
}
