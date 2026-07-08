import Foundation

// MARK: - Offseason GM market data (real Spotrac-backed FAs + cap sheets)

struct OffseasonMarket: Decodable {
    let capCeiling: Double
    let teams: [TeamCapInfo]
    let freeAgents: [FreeAgent]
    let updated: String?
}

struct TeamCapInfo: Decodable, Identifiable, Hashable {
    let abbrev: String
    let capSpace: Double
    let capHit: Double
    var id: String { abbrev }
}

struct FreeAgent: Decodable, Identifiable, Hashable {
    let name: String
    let position: String
    let age: Int?
    let prevTeam: String?
    let prevAav: Double?
    let type: String            // "UFA" | "RFA"
    var id: String { name }

    var isForward: Bool { ["C", "LW", "RW", "W", "F"].contains(position) }
}

struct TeamRosterResponse: Decodable {
    let abbrev: String
    let players: [ContractPlayer]
}

struct ContractPlayer: Decodable, Identifiable, Hashable {
    let name: String
    let position: String
    let aav: Double
    var id: String { name }
}

extension Double {
    /// "$8.7M" / "-$2.8M" — mirrors Int.asCapMoney but keeps the sign.
    var asCapMoney: String {
        (self < 0 ? "-" : "") + String(format: "$%.1fM", abs(self) / 1_000_000)
    }
}

// MARK: - News article quick summary

struct ArticleSummary: Decodable {
    let summary: String
    let cached: Bool?
}
