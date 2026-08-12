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

    /// "1C" → "1st line C"; "G2" → "Backup G".
    var slotLabel: String {
        if slot.hasPrefix("G") { return slot == "G1" ? "Starting G" : "Backup G" }
        guard let tier = slot.first, let n = Int(String(tier)) else { return slot }
        let position = String(slot.dropFirst())
        let ordinal = ["", "1st", "2nd", "3rd", "4th"]
        let line = n < ordinal.count ? ordinal[n] : "\(n)th"
        return "\(line) \(position == "D" ? "pair" : "line") \(position)"
    }
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

extension ISO8601DateFormatter {
    /// Postgres hands back fractional seconds; the default parser rejects them.
    nonisolated(unsafe) static let duelParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
