import Foundation

/// Independent-Poisson score grid derived from the model's expected goals.
/// This is a client-side *visualization* of the scoreline distribution — the
/// backend uses a Dixon-Coles model with low-score corrections, so this is a
/// faithful approximation, not the exact server matrix.
enum Poisson {

    /// Probability mass for exactly `k` events given Poisson mean `lambda`.
    static func pmf(_ k: Int, mean lambda: Double) -> Double {
        guard lambda > 0, k >= 0 else { return k == 0 ? 1 : 0 }
        var result = exp(-lambda)
        if k > 0 {
            for i in 1...k { result *= lambda / Double(i) }
        }
        return result
    }

    /// Draw a Poisson(`lambda`) sample (Knuth's algorithm) — for Monte-Carlo sims.
    static func sample(_ lambda: Double) -> Int {
        guard lambda > 0 else { return 0 }
        let limit = exp(-lambda)
        var k = 0
        var p = 1.0
        repeat { k += 1; p *= Double.random(in: 0..<1) } while p > limit
        return k - 1
    }

    /// Grid `[awayGoals][homeGoals]` of joint probabilities, goals `0...maxGoals`.
    static func matrix(awayMean: Double, homeMean: Double, maxGoals: Int = 6) -> [[Double]] {
        (0...maxGoals).map { a in
            (0...maxGoals).map { h in
                pmf(a, mean: awayMean) * pmf(h, mean: homeMean)
            }
        }
    }
}
