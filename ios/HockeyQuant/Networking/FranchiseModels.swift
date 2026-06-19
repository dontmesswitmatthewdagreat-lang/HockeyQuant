import SwiftUI

// MARK: - My Franchise (card-collection mode)

/// A player card: a `fantasy_players` row valued + rarity-rated by production. Used in the
/// collection, the shop, and lineups.
struct PlayerCard: Codable, Identifiable, Hashable {
    let playerId: String
    let fullName: String
    let team: String
    let rosterPos: String
    let isGoalie: Bool?
    let sweater: Int?
    let headshot: String?
    let cost: Int
    let rarity: String          // common | uncommon | rare | epic | legend
    let price: Int              // Coin price (shop)
    let cardId: String?         // owned-card id (nil for shop/catalog entries)
    let acquiredVia: String?

    var id: String { cardId ?? playerId }
}

struct CollectionResponse: Codable { let cards: [PlayerCard] }

struct ShopResponse: Codable {
    let cards: [PlayerCard]
    let coins: Int
    let rotationDate: String
}

struct BuyResponse: Codable { let coins: Int; let bought: String }

struct ChallengeSummary: Codable, Hashable {
    let opponentTeam: String
    let won: Bool?
    let graded: Bool
    let myScore: Double?
    let oppScore: Double?
}

struct FranchiseSummary: Codable {
    let coins: Int
    let seasonYear: Int?
    let collectionCount: Int
    let byRarity: [String: Int]
    let lineupFilled: Int
    let lineupSlots: Int
    let todayChallenge: ChallengeSummary?
    let dailyReward: Int
}

// MARK: - Rarity styling

enum CardRarity {
    static let order = ["common", "uncommon", "rare", "epic", "legend"]

    static func color(_ rarity: String) -> Color {
        switch rarity {
        case "legend":   return Color(hex: 0xFFD23F)   // gold
        case "epic":     return Color(hex: 0xAF52DE)   // purple
        case "rare":     return Color(hex: 0x0A84FF)   // blue
        case "uncommon": return Color(hex: 0x14CA64)   // green
        default:         return Color(hex: 0x8A93A1)   // common gray
        }
    }

    static func label(_ rarity: String) -> String { rarity.capitalized }
}

extension Int {
    /// Coin amount, grouped: 12000 → "12,000".
    var asCoins: String { NumberFormatter.localizedString(from: NSNumber(value: self), number: .decimal) }
}
