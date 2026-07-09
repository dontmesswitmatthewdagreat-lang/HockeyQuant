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
    var id: String { name }

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
