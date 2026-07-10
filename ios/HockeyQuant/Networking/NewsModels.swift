import Foundation

/// One curated story in a digest — AI headline + blurb + the real source link.
struct DigestItem: Codable, Identifiable, Hashable {
    var id: String { url }
    let headline: String
    let blurb: String
    let tag: String
    let source: String
    let url: String
    let publishedAt: String?
    let imageUrl: String?

    // Many image URLs (e.g. Yahoo's s.yimg.com transforms) embed another
    // "https://…" in the path, which iOS 17's strict URL(string:) rejects.
    // `encodingInvalidCharacters` keeps those URLs valid so they load.
    var image: URL? {
        guard let s = imageUrl, !s.isEmpty else { return nil }
        return URL(string: s, encodingInvalidCharacters: true)
    }
}

/// A generated digest: morning (league) or pre/post-game (a team).
struct NewsDigest: Codable, Identifiable, Hashable {
    let id: String
    let digestDate: String
    let kind: String       // morning | pregame | postgame
    let scope: String      // "league" or a team abbrev
    let title: String
    let intro: String?
    let keyPoints: [String]?
    let items: [DigestItem]
    let createdAt: String?

    var kindLabel: String {
        switch kind {
        case "morning": return "Morning"
        case "evening": return "Evening"
        case "pregame": return "Pre-Game"
        case "postgame": return "Post-Game"
        default: return kind.capitalized
        }
    }
    var isLeague: Bool { scope == "league" }

    /// "Thu, Jun 12 · 9:04 AM" from `createdAt` (UTC ISO), in the local timezone.
    var asOf: String? {
        guard let createdAt else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: createdAt) ?? {
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: createdAt)
        }()
        guard let date else { return nil }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f.string(from: date)
    }
}

struct NewsLatestResponse: Codable { let digests: [NewsDigest] }

struct NewsSearchResponse: Codable {
    let answer: String
    let sources: [DigestItem]
    let pastMatches: [DigestItem]
}

// MARK: - Prospects

struct ProspectInfo: Codable, Hashable {
    let headshot: String?
    let country: String?
    let club: String?
    let category: String?   // NHL Central Scouting list (draft board only)
}

struct Prospect: Codable, Identifiable, Hashable {
    let id: String
    let nhlId: Int?
    let name: String
    let team: String?
    let position: String?
    let draftYear: Int?
    let league: String?
    let ranking: Int?
    let notable: Bool
    let info: ProspectInfo?
    /// Rank change vs the previous Central Scouting list (positive = riser).
    let rankDelta: Int?

    var subtitle: String {
        var parts: [String] = []
        if let position { parts.append(position) }
        if let league, !league.isEmpty { parts.append(league) }
        if let draftYear { parts.append("\(draftYear) draft") }
        return parts.joined(separator: " · ")
    }

    var headshotURL: URL? {
        guard let s = info?.headshot, !s.isEmpty else { return nil }
        // NHL serves `/mugs/nhl/latest/<id>.png` as a 302 → default-skater
        // silhouette for prospects without a real mug. Skip those so the card
        // falls back to the clean initials monogram instead of a gray blank.
        if s.contains("/latest/") || s.contains("default") { return nil }
        return URL(string: s)
    }

    var initials: String {
        name.split(separator: " ").compactMap { $0.first.map(String.init) }.prefix(2).joined()
    }

    /// The NHL ranks four separate Central Scouting lists, each numbered from 1.
    /// These drive the draft-board section headers so the "restart at 1" reads
    /// clearly (e.g. Ivar Stenberg is the #1 *international* skater, not #1 overall).
    var categoryLabel: String? {
        switch info?.category {
        case "north-american-skater": return "North American Skaters"
        case "international-skater":   return "International Skaters"
        case "north-american-goalie": return "North American Goalies"
        case "international-goalie":   return "International Goalies"
        default:                      return nil
        }
    }

    var categoryOrder: Int {
        switch info?.category {
        case "north-american-skater": return 0
        case "international-skater":   return 1
        case "north-american-goalie": return 2
        case "international-goalie":   return 3
        default:                      return 9
        }
    }

    /// Nationality flag emoji from NHL's ISO-3166 alpha-3 birthCountry.
    var flag: String? {
        guard let c3 = info?.country?.uppercased() else { return nil }
        let iso2: String? = Self.iso3to2[c3] ?? (c3.count == 2 ? c3 : nil)
        guard let iso2 else { return nil }
        return String(iso2.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value).map(Character.init) })
    }

    private static let iso3to2: [String: String] = [
        "CAN": "CA", "USA": "US", "SWE": "SE", "FIN": "FI", "RUS": "RU", "CZE": "CZ",
        "SVK": "SK", "DEU": "DE", "GER": "DE", "CHE": "CH", "SUI": "CH", "AUT": "AT",
        "DNK": "DK", "DEN": "DK", "NOR": "NO", "LVA": "LV", "LAT": "LV", "BLR": "BY",
        "SVN": "SI", "SLO": "SI", "FRA": "FR", "GBR": "GB", "NLD": "NL", "NED": "NL",
        "KAZ": "KZ", "UKR": "UA", "AUS": "AU", "POL": "PL", "HUN": "HU", "ITA": "IT",
        "EST": "EE", "LTU": "LT", "IRL": "IE", "JAM": "JM", "JPN": "JP", "CHN": "CN",
    ]
}

struct ProspectsResponse: Codable { let prospects: [Prospect] }

// MARK: - Prospect detail sheet

struct RankPoint: Codable, Hashable, Identifiable {
    let listDate: String
    let rank: Int
    var id: String { listDate }
}

struct ProspectProjection: Codable, Hashable {
    let overall: Int?
    let team: String?
    let reason: String?
    let edition: String?
}

struct ProspectNewsItem: Codable, Hashable, Identifiable {
    let headline: String
    let source: String?
    let url: String
    let publishedAt: String?
    let blurb: String?
    var id: String { url }
}

struct ProspectDetailResponse: Codable {
    let prospect: Prospect
    let rankHistory: [RankPoint]
    let projection: ProspectProjection?
    let drafted: DraftedPick?
    let news: [ProspectNewsItem]
}

/// An actual (post-draft) selection from the NHL API.
struct DraftedPick: Codable, Hashable, Identifiable {
    let round: Int?
    let overall: Int
    let team: String?
    let player: String
    let position: String?
    let league: String?
    let club: String?
    /// True once the player appears on his team's real cap sheet (ELC signed).
    let signedElc: Bool?
    var id: Int { overall }
}

struct DraftResultsResponse: Codable {
    let year: Int
    let picks: [DraftedPick]
}


// MARK: - Live pipeline (CHL stats + Calder Watch)

struct PipelineStat: Codable, Hashable, Identifiable {
    let name: String
    let league: String
    let gp: Int
    let goals: Int
    let assists: Int
    let points: Int
    var id: String { name }

    var line: String { "\(league) · \(goals)G \(assists)A · \(points) PTS" }
}

struct PipelineStatsResponse: Codable { let stats: [PipelineStat] }

struct CalderPlayer: Codable, Hashable, Identifiable {
    let name: String
    let team: String
    let position: String
    let gamesPlayed: Int
    let goals: Int
    let assists: Int
    let points: Int
    let headshot: String?
    var id: String { name }
}

struct CalderResponse: Codable {
    let active: Bool
    let season: String
    let players: [CalderPlayer]
}
