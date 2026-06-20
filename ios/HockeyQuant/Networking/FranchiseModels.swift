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
    let prospectRanking: Int?   // rookie-board rank (rookie draft only)
    let listingId: String?      // marketplace listing id
    let seller: String?         // seller username (marketplace)
    let status: String?         // listing status (mine: open|sold|cancelled)

    var id: String { listingId ?? cardId ?? playerId }
}

struct CollectionResponse: Codable { let cards: [PlayerCard] }

struct ShopResponse: Codable {
    let cards: [PlayerCard]
    let coins: Int
    let rotationDate: String
}

struct BuyResponse: Codable { let coins: Int; let bought: String }

struct LineupSlot: Codable, Identifiable, Hashable {
    let slot: String
    let slotType: String
    let card: PlayerCard?
    var id: String { slot }
}

struct LineupResponse: Codable { let lineup: [LineupSlot]; let rating: Int }

struct ChallengeDetail: Codable, Hashable {
    let gameDate: String?
    let opponentTeam: String
    let myScore: Double?
    let oppScore: Double?
    let won: Bool?
    let coinsAwarded: Int?
    let xpAwarded: Int?
    let graded: Bool
}

struct ChallengeResponse: Codable { let challenge: ChallengeDetail?; let today: String }
struct ChallengeOptions: Codable { let date: String; let teams: [String] }

struct RookieDraftResponse: Codable {
    let picksRemaining: Int
    let picksTotal: Int
    let seasonYear: Int
    let board: [PlayerCard]
}

struct MarketResponse: Codable { let listings: [PlayerCard]; let coins: Int }
struct MyListingsResponse: Codable { let listings: [PlayerCard] }

/// A direct card-for-card trade offer. `fromCard` (+ `fromCoins`) is given for `toCard`.
struct TradeOffer: Codable, Identifiable, Hashable {
    let offerId: String
    let fromCard: PlayerCard?
    let toCard: PlayerCard?
    let fromCoins: Int
    let toCoins: Int
    let fromUser: String?
    let toUser: String?
    let status: String?
    var id: String { offerId }
}

struct OffersResponse: Codable { let incoming: [TradeOffer]; let outgoing: [TradeOffer]; let coins: Int }

struct FranchiseSummary: Codable {
    let coins: Int
    let seasonYear: Int?
    let collectionCount: Int
    let byRarity: [String: Int]
    let lineupFilled: Int
    let lineupSlots: Int
    let todayChallenge: ChallengeDetail?
    let dailyReward: Int
    let accountXp: Int?
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
