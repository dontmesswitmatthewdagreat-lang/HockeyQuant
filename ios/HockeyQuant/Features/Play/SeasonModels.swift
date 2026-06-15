import SwiftUI

/// An NHL season window (Oct 1 – Jun 30). The season meta-game scopes all
/// progress to the current season.
struct Season: Sendable {
    let id: String      // "2025-26"
    let label: String   // "2025–26 Season"
    let start: String   // "2025-10-01"
    let end: String     // "2026-06-30"

    static var current: Season {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        let startYear = month >= 10 ? year : year - 1
        let endYear = startYear + 1
        let shortEnd = String(format: "%02d", endYear % 100)
        return Season(
            id: "\(startYear)-\(shortEnd)",
            label: "\(startYear)–\(endYear) Season",
            start: "\(startYear)-10-01",
            end: "\(endYear)-06-30"
        )
    }
}

/// Season-scoped aggregates, computed from the user's graded picks in range.
struct SeasonStats: Sendable {
    var xp = 0
    var picks = 0
    var correct = 0
    var beatsModel = 0
    var bestStreak = 0

    var accuracy: Double { picks > 0 ? Double(correct) / Double(picks) * 100 : 0 }

    init() {}

    init(from picks: [UserPick]) {
        let graded = picks.filter { $0.correct != nil }
        xp = graded.reduce(0) { $0 + $1.xpAwarded }
        self.picks = graded.count
        correct = graded.filter { $0.correct == true }.count
        beatsModel = graded.filter { p in
            p.correct == true && (p.modelPick?.uppercased() ?? "") != p.pick.uppercased()
        }.count

        var run = 0
        var best = 0
        for p in graded {
            if p.correct == true { run += 1; best = max(best, run) } else { run = 0 }
        }
        bestStreak = best
    }
}

/// The "GM track" — a season-long progression ladder driven by season XP.
struct GMTier: Identifiable, Sendable {
    let name: String
    let icon: String
    let colorHex: UInt32
    let threshold: Int

    var id: String { name }
    var color: Color { Color(hex: colorHex) }

    static let ladder: [GMTier] = [
        GMTier(name: "Rookie GM",            icon: "person.fill",            colorHex: 0x8A93A1, threshold: 0),
        GMTier(name: "Scout",                icon: "binoculars.fill",        colorHex: 0x14CA64, threshold: 150),
        GMTier(name: "Pro Scout",            icon: "magnifyingglass",        colorHex: 0x0A84FF, threshold: 400),
        GMTier(name: "Assistant GM",         icon: "person.2.fill",          colorHex: 0x5E5CE6, threshold: 800),
        GMTier(name: "General Manager",      icon: "briefcase.fill",         colorHex: 0xAF52DE, threshold: 1400),
        GMTier(name: "Hockey Ops President", icon: "building.columns.fill",  colorHex: 0xFF9F0A, threshold: 2400),
        GMTier(name: "Hall of Fame GM",      icon: "crown.fill",             colorHex: 0xFFD23F, threshold: 4000),
    ]

    static func current(forXp xp: Int) -> GMTier {
        ladder.last { xp >= $0.threshold } ?? ladder[0]
    }

    static func next(forXp xp: Int) -> GMTier? {
        ladder.first { $0.threshold > xp }
    }

    /// Progress 0–1 from the current tier toward the next.
    static func progress(forXp xp: Int) -> Double {
        let cur = current(forXp: xp)
        guard let nxt = next(forXp: xp) else { return 1 }
        let span = Double(nxt.threshold - cur.threshold)
        guard span > 0 else { return 1 }
        return min(1, max(0, Double(xp - cur.threshold) / span))
    }
}

/// A season-long objective shown on the meta-game screen.
struct SeasonGoal: Identifiable, Sendable {
    let name: String
    let icon: String
    let current: Int
    let target: Int

    var id: String { name }
    var isComplete: Bool { current >= target }
    var progress: Double { target > 0 ? min(1, Double(current) / Double(target)) : 0 }

    static func all(for s: SeasonStats) -> [SeasonGoal] {
        [
            SeasonGoal(name: "Make 50 picks", icon: "hockey.puck.fill", current: s.picks, target: 50),
            SeasonGoal(name: "Reach 500 XP", icon: "bolt.fill", current: s.xp, target: 500),
            SeasonGoal(name: "Beat the model 10×", icon: "crown.fill", current: s.beatsModel, target: 10),
            SeasonGoal(name: "Hit a 5-pick streak", icon: "flame.fill", current: s.bestStreak, target: 5),
            SeasonGoal(name: "Land 30 correct calls", icon: "checkmark.seal.fill", current: s.correct, target: 30),
        ]
    }
}
