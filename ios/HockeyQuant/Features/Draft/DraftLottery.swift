import Foundation

/// Re-runs the NHL draft lottery and reorders the top of the first round.
///
/// The real system, faithfully: two weighted draws (first and second overall)
/// among the non-playoff teams, and **a team can move up at most 10 places** —
/// which is why only lottery positions 1–11 can win the first pick and 1–12 the
/// second. Everyone else slots in by record. Getting that cap right is the
/// difference between a lottery and a raffle: it's the rule that stops the
/// 16th-worst team from ever picking first.
///
/// Traded picks survive the re-roll. A pick belongs to the team whose record
/// earned it, so when that team's lottery ball moves, the pick moves — carrying
/// whoever currently owns it. Slot *p* of the incoming order is the pick of the
/// team sitting *p*th in the lottery standings, so permuting the standings
/// permutes the owners with them.
///
/// Known simplification: restricting each draw to the teams that can legally
/// reach that pick means the odds are renormalized over them, so an eligible
/// team wins slightly more often here than its published number (18.5% becomes
/// ~19.7%). The published table is a chance at the No. 1 pick for all 16, but
/// under the 10-place cap the bottom five cannot actually reach it. Simulated
/// counts will therefore not line up exactly with the odds chart the app shows.
enum DraftLottery {

    struct Outcome {
        let order: [String]          // the full first round after the draw
        let firstWinner: String      // team whose ball came up for No. 1
        let secondWinner: String
        /// Places each lottery team moved, positive = moved up.
        let movement: [String: Int]
    }

    /// Max places a team can climb — the rule that bounds the whole thing.
    static let maxClimb = 10

    static func reroll(odds: [LotteryOdds], order: [String],
                       using generator: inout some RandomNumberGenerator) -> Outcome? {
        // Lottery field in record order: position 1 = worst record.
        let field = odds.sorted { $0.draftSlot < $1.draftSlot }
        guard field.count >= 2, order.count >= field.count else { return nil }

        // Owner of each lottery position's pick — index 0 is position 1.
        let owners = Array(order.prefix(field.count))

        var remaining = Array(field.indices)          // positions still in the draw
        guard let first = draw(from: remaining, field: field,
                               eligibleThrough: maxClimb + 1, using: &generator)
        else { return nil }
        remaining.removeAll { $0 == first }
        // The second draw is for the second pick, so a team may sit one place
        // lower and still be inside the same 10-place climb.
        guard let second = draw(from: remaining, field: field,
                                eligibleThrough: maxClimb + 2, using: &generator)
        else { return nil }
        remaining.removeAll { $0 == second }

        let newPositions = [first, second] + remaining.sorted()
        var movement: [String: Int] = [:]
        for (newIndex, oldIndex) in newPositions.enumerated() {
            movement[field[oldIndex].abbrev] = oldIndex - newIndex
        }

        // The pick travels with the team that earned it, so the owner rides along.
        let reordered = newPositions.map { owners[$0] }
        return Outcome(order: reordered + Array(order.dropFirst(field.count)),
                       firstWinner: field[first].abbrev,
                       secondWinner: field[second].abbrev,
                       movement: movement)
    }

    /// Convenience for callers that don't need a seeded generator.
    static func reroll(odds: [LotteryOdds], order: [String]) -> Outcome? {
        var generator = SystemRandomNumberGenerator()
        return reroll(odds: odds, order: order, using: &generator)
    }

    /// One weighted draw, restricted to teams close enough to the top to be
    /// allowed to win it.
    private static func draw(from positions: [Int], field: [LotteryOdds],
                             eligibleThrough: Int,
                             using generator: inout some RandomNumberGenerator) -> Int? {
        let eligible = positions.filter { $0 < eligibleThrough }
        guard !eligible.isEmpty else { return positions.first }
        let total = eligible.reduce(0.0) { $0 + max(field[$1].odds, 0) }
        guard total > 0 else { return eligible.randomElement(using: &generator) }
        var roll = Double.random(in: 0..<total, using: &generator)
        for index in eligible {
            roll -= max(field[index].odds, 0)
            if roll <= 0 { return index }
        }
        return eligible.last
    }
}
