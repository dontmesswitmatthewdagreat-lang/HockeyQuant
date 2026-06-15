import Foundation

/// Client-side Monte-Carlo: sample games from the matchup's Poisson means.
enum MonteCarlo {
    /// One game: sample both teams; a regulation tie is resolved in OT (λ-weighted).
    static func simGame(_ awayLambda: Double, _ homeLambda: Double) -> (away: Int, home: Int, awayWon: Bool) {
        let a = Poisson.sample(awayLambda)
        let h = Poisson.sample(homeLambda)
        if a != h { return (a, h, a > h) }
        let pAway = awayLambda / max(awayLambda + homeLambda, 0.0001)
        return (a, h, Double.random(in: 0..<1) < pAway)
    }

    /// Home team per game in a 2-2-1-1-1 best-of-7 (true = team A hosts).
    static func aHostsByGame(aHasHomeIce: Bool) -> [Bool] {
        aHasHomeIce ? [true, true, false, false, true, false, true]
                    : [false, false, true, true, false, true, false]
    }

    /// One best-of-7 series → (did A win, games played 4...7).
    static func simSeries(aHome: (a: Double, b: Double), bHome: (a: Double, b: Double), hosts: [Bool]) -> (aWon: Bool, length: Int) {
        var aw = 0, bw = 0, g = 0
        while aw < 4 && bw < 4 {
            let aIsHome = hosts[g]
            let awayL = aIsHome ? aHome.b : bHome.a
            let homeL = aIsHome ? aHome.a : bHome.b
            let r = simGame(awayL, homeL)
            let aWonGame = aIsHome ? !r.awayWon : r.awayWon
            if aWonGame { aw += 1 } else { bw += 1 }
            g += 1
        }
        return (aw == 4, g)
    }
}
