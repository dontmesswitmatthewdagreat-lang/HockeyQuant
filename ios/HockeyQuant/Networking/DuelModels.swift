import Foundation

// MARK: - Global League weekly duels

/// One player on the board you're currently choosing from.
struct DuelBoardPlayer: Decodable, Identifiable, Hashable {
    let nhlId: Int
    let name: String
    let team: String?
    let pos: String?
    let headshot: String?
    let cost: Int?
    var id: Int { nhlId }

    var headshotURL: URL? { headshot.flatMap(URL.init(string:)) }
}

/// Depth-slot codes ("1C", "4D", "G2") in the one place that knows how to read
/// them — the draft board and the scoreboard have to name a slot identically.
enum DuelSlot {
    /// "1C" → "1st line C"; "G2" → "Backup G".
    static func label(_ slot: String) -> String {
        if slot.hasPrefix("G") { return slot == "G1" ? "Starting G" : "Backup G" }
        guard let tier = slot.first, let n = Int(String(tier)) else { return slot }
        let position = String(slot.dropFirst())
        let ordinal = ["", "1st", "2nd", "3rd", "4th"]
        let line = n < ordinal.count ? ordinal[n] : "\(n)th"
        return "\(line) \(position == "D" ? "pair" : "line") \(position)"
    }
}

/// A pick in the draft order — filled in once chosen.
struct DuelPick: Decodable, Identifiable, Hashable {
    let id: Int
    let pickNo: Int
    let userId: String
    let slot: String                 // "1C", "4D", "G2" …
    let chosenNhlId: Int?
    let autoPicked: Bool
    /// Resolved server-side — the pick row itself only stores the id.
    let chosenName: String?
    let chosenTeam: String?
    let chosenPosition: String?

    var isDone: Bool { chosenNhlId != nil }

    var slotLabel: String { DuelSlot.label(slot) }
}

struct Duel: Decodable, Identifiable, Hashable {
    let id: Int
    let weekStart: String
    let weekEnd: String
    let userA: String
    let userB: String
    let state: String                // drafting | live | final
    /// "weekly" or "flash". Optional so the app keeps decoding against a
    /// backend that predates the mode column.
    let mode: String?
    let turnUser: String?
    let pickNo: Int
    let scoreA: Double?
    let scoreB: Double?
    let bonusA: Double?
    let bonusB: Double?
    let winner: String?

    var isDrafting: Bool { state == "drafting" }
    var isFinal: Bool { state == "final" }
    var isFlash: Bool { mode == "flash" }
    /// Six picks a side over a week, four over a single night.
    var rosterSize: Int { isFlash ? 4 : 6 }
    var totalPicks: Int { rosterSize * 2 }
    var modeLabel: String { isFlash ? "Flash Slate" : "Weekly Duel" }
}

/// `GET /api/duels/current`
struct DuelCurrent: Decodable {
    let duel: Duel?
    let picks: [DuelPick]?
    let board: [DuelBoardPlayer]?
    let onTheClock: Bool?
    let turnDeadline: String?
    let rosterSlots: [String]?
    let queued: Bool?
    let queuedFor: String?

    /// When the current pick expires, for the countdown.
    var deadline: Date? {
        turnDeadline.flatMap { ISO8601DateFormatter.duelParser.date(from: $0) }
    }
}

struct DuelPickResult: Decodable {
    let picked: Int
    let nextUser: String?
    let complete: Bool
}

struct DuelRanking: Decodable, Identifiable, Hashable {
    let userId: String
    let username: String?
    let rating: Int
    let wins: Int
    let losses: Int
    let ties: Int
    let streak: Int
    let duelsPlayed: Int
    let rank: Int?
    var id: String { userId }

    /// "W3" / "L2" — blank when the streak is fresh.
    var streakLabel: String? {
        if streak == 0 { return nil }
        return streak > 0 ? "W\(streak)" : "L\(-streak)"
    }
}

struct DuelRankingsResponse: Decodable { let rankings: [DuelRanking] }

// MARK: - Scoreboard

/// `GET /api/duels/{id}/scoreboard` — what each drafted player has produced.
/// Both sides are null until the draft finishes and someone has been picked.
struct DuelScoreboard: Decodable {
    let duel: Duel
    let names: [String: String]?     // user id → username
    let a: DuelSide?
    let b: DuelSide?

    func side(for userId: String?) -> DuelSide? {
        guard let userId else { return nil }
        return duel.userA.lowercased() == userId.lowercased() ? a : b
    }

    func opponentSide(for userId: String?) -> DuelSide? {
        guard let userId else { return nil }
        return duel.userA.lowercased() == userId.lowercased() ? b : a
    }

    /// Usernames are keyed by the Postgres (lowercase) id; `AuthStore.userId`
    /// is uppercased, so every lookup here has to case-fold.
    func name(for userId: String?) -> String? {
        guard let userId else { return nil }
        return names?.first { $0.key.lowercased() == userId.lowercased() }?.value
    }
}

/// One drafter's roster and its two score components.
struct DuelSide: Decodable {
    /// Skater points — goals and assists.
    let base: Double
    /// The defensive/goaltending layer: plus-minus, shorthanded play, goalie work.
    let bonus: Double
    let players: [DuelScoredPlayer]

    var total: Double { base + bonus }
}

struct DuelScoredPlayer: Decodable, Identifiable {
    let nhlId: Int
    let games: Int
    let base: Double
    let bonus: Double
    /// Raw counting stats, keyed differently for skaters ("g", "a", "+/-", "sh")
    /// and goalies ("wins", "saves", "ga", "shutouts").
    let line: [String: Int]?
    let slot: String?
    let fullName: String?
    let team: String?
    let position: String?

    var id: Int { nhlId }
    var total: Double { base + bonus }
    var isGoalie: Bool { (position ?? "").uppercased() == "G" }
    var slotLabel: String { slot.map(DuelSlot.label) ?? (position ?? "") }
    var name: String { fullName ?? "Player \(nhlId)" }

    private func stat(_ key: String) -> Int { line?[key] ?? 0 }

    /// The week in counting stats — "2G 3A · +4" or "2W · 61 SV · 3 GA".
    var statLine: String {
        guard games > 0 else { return "Yet to play" }
        var parts: [String] = []
        if isGoalie {
            if stat("wins") > 0 { parts.append("\(stat("wins"))W") }
            parts.append("\(stat("saves")) SV")
            parts.append("\(stat("ga")) GA")
            if stat("shutouts") > 0 { parts.append("\(stat("shutouts")) SO") }
        } else {
            parts.append("\(stat("g"))G \(stat("a"))A")
            let pm = stat("+/-")
            parts.append(pm >= 0 ? "+\(pm)" : "\(pm)")
            if stat("sh") > 0 { parts.append("\(stat("sh")) SH") }
        }
        return parts.joined(separator: " · ")
    }
}

extension ISO8601DateFormatter {
    /// Postgres hands back fractional seconds; the default parser rejects them.
    nonisolated(unsafe) static let duelParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
