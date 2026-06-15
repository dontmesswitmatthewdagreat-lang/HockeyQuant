import Foundation

/// One graded official pick, enriched with the picked team's factor *edges*
/// (picked minus opponent) at prediction time — for client-side backtesting.
struct BacktestGame: Decodable, Identifiable {
    let date: String
    let pick: String
    let correct: Bool
    let diff: Double
    let confidence: String
    let pickIsHome: Bool
    let goalieEdge: Double
    let streakEdge: Double
    let stEdge: Double
    let fatigueEdge: Double
    let h2hEdge: Double
    let pickFatigueMult: Double
    var id: String { "\(date)-\(pick)" }
}

struct BacktestData: Decodable {
    let baseline: Double
    let count: Int
    let games: [BacktestGame]
}
