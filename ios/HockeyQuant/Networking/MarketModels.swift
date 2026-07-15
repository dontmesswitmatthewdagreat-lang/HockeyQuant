import Foundation

// MARK: - Player market (fair values + market heat)

struct MarketPlayer: Decodable, Identifiable, Hashable {
    let name: String
    let team: String?
    let position: String
    let age: Double
    let gp: Int
    let ppg: Double
    let aav: Double?
    let modelValue: Double
    let marketValue: Double
    let valueLow: Double
    let valueHigh: Double
    let verdict: String?     // steal | fair | overpay (nil = unsigned/ELC)
    let gsax: Double?        // goalies only: goals saved above expected
    let svPct: Double?       // goalies only
    let actionPhoto: String? // real NHL landscape action shot (full-bleed hero)
    let portrait: String?    // Wikipedia photo or headshot (portrait hero) when no action shot
    let headshot: String?    // last-resort portrait
    var id: String { name }

    var actionPhotoURL: URL? { actionPhoto.flatMap(URL.init(string:)) }
    var portraitURL: URL? { (portrait ?? headshot).flatMap(URL.init(string:)) }

    var isGoalie: Bool { position == "G" }

    /// Position-appropriate stat line for rows/headers.
    var statLine: String {
        if isGoalie {
            let g = gsax.map { String(format: "%+.1f GSAX", $0) } ?? ""
            let sv = svPct.map { String(format: "%.3f SV%%", $0) } ?? ""
            return [g, sv].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return String(format: "%.2f P/GP", ppg)
    }
}

struct MarketIndexPoint: Decodable, Identifiable {
    let date: String
    let value: Double
    var id: String { date }
}

struct MarketMover: Decodable, Identifiable {
    let name: String
    let marketValue: Double
    let deltaPct: Double
    var id: String { name }
}

struct GradedSigning: Decodable, Identifiable {
    let name: String
    let team: String
    let position: String
    let aav: Double
    let years: Int?
    let fairValue: Double
    let verdict: String?
    var id: String { name }
}

struct MarketOverview: Decodable {
    let heat: [String: Double]        // "F"/"D" → percent over fair value
    let trainedOn: Int
    let index: [MarketIndexPoint]
    let movers: [MarketMover]
    let signings: [GradedSigning]
}

struct MarketPlayersResponse: Decodable { let players: [MarketPlayer] }

// MARK: - League pulses (the News tab's pulse deck)

struct PulseSubline: Decodable, Hashable {
    let label: String
    let value: String
    let tint: String?    // "hot" | "cold" | nil
}

struct PulseRow: Decodable, Hashable {
    let team: String?
    let title: String
    let detail: String?
    let value: String
    let positive: Bool?
}

/// One dial-style league read (luck, race, deadline, playoffs). Dormant
/// pulses keep their spot in the deck with a note about when they light up.
struct LeaguePulse: Decodable, Identifiable, Hashable {
    let id: String
    let kicker: String
    let active: Bool
    let score: Int?
    let label: String?
    let season: String?
    let note: String?
    let explainer: String?
    let sublines: [PulseSubline]
    let rows: [PulseRow]
}

struct LeaguePulseResponse: Decodable { let pulses: [LeaguePulse] }

struct ValueHistoryPoint: Decodable, Identifiable {
    let date: String
    let modelValue: Double
    let marketValue: Double
    var id: String { date }
}

struct TeamFit: Decodable, Identifiable {
    let team: String
    let needMatch: Int
    let capSpace: Double
    var id: String { team }
}

struct PlayerMarketDetail: Decodable {
    let player: MarketPlayer
    let heatPct: Double
    let history: [ValueHistoryPoint]
    let comparables: [MarketPlayer]
    let fits: [TeamFit]
}

extension String {
    /// Shared styling for market verdicts.
    var verdictLabel: String {
        switch self {
        case "steal": return "STEAL"
        case "overpay": return "OVERPAY"
        default: return "FAIR"
        }
    }
}

// MARK: - Offseason report card

struct ReportCardFactor: Decodable, Hashable, Identifiable {
    let label: String
    let detail: String
    let positive: Bool
    var id: String { label }
}

struct ReportCardMove: Decodable, Hashable, Identifiable {
    let name: String
    let position: String
    let aav: Double
    let years: Int?
    let fairValue: Double?
    let verdict: String?
    let otherTeam: String?
    var id: String { name }

    var termLine: String {
        let money = String(format: "$%.1fM", aav / 1_000_000)
        return years.map { "\(money) × \($0) yr" } ?? money
    }
}

struct ReportCardDraft: Decodable, Hashable {
    let picks: Int
    let firstOverall: Int?
    let firstPlayer: String?
    let elcSigned: Int
}

struct OffseasonReportCard: Decodable {
    let team: String
    let grade: String
    let score: Int?
    let headline: String
    let committed: Double
    let surplus: Double
    let factors: [ReportCardFactor]
    let arrivals: [ReportCardMove]
    let resigned: [ReportCardMove]
    let departures: [ReportCardMove]
    let draft: ReportCardDraft
    let capSpace: Double?

    /// Green (A) → accent (B) → amber (C) → red (D/F).
    var gradeHex: UInt32 {
        switch grade.first {
        case "A": return 0x1F8A5B
        case "B": return 0x2F80C8
        case "C": return 0xE8842A
        case "D": return 0xD46A2A
        default:  return 0xD64545
        }
    }
}
