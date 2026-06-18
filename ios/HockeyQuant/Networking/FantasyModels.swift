import Foundation

// MARK: - Leagues

struct FantasyLeagueSummary: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let leagueType: String      // group | global
    let status: String          // open | drafting | active | playoffs | complete
    let maxMembers: Int
    let uniquePlayers: Bool
    let inviteCode: String
    let seasonYear: Int
    let draftPace: String
    let pickClockSeconds: Int
    let isCommissioner: Bool
    let memberCount: Int
    let myTeamName: String?

    var isGroup: Bool { leagueType == "group" }
}

struct MyLeaguesResponse: Codable { let leagues: [FantasyLeagueSummary] }

struct LeagueMember: Codable, Identifiable, Hashable {
    let id: String
    let userId: String
    let teamName: String
    let draftOrder: Int?
    let username: String?
    let isMe: Bool
}

struct DraftStatus: Codable, Hashable { let status: String }

struct LeagueDetail: Codable {
    let league: FantasyLeagueSummary
    let members: [LeagueMember]
    let draft: DraftStatus?
}

// MARK: - Players

struct FantasyPlayer: Codable, Identifiable, Hashable {
    let id: String
    let nhlId: Int?
    let fullName: String
    let team: String
    let position: String?
    let shoots: String?
    let rosterPos: String        // LW | RW | C | LHD | RHD | G
    let isGoalie: Bool?
    let sweater: Int?
    let headshot: String?
    let cost: Int?               // salary-cap price, from real production
}

struct FantasyPlayersResponse: Codable { let players: [FantasyPlayer]; let count: Int }

// MARK: - Draft

struct DraftState: Codable, Hashable {
    let status: String           // not_started | in_progress | complete
    let pickNumber: Int
    let totalPicks: Int
    let round: Int
    let requiredSlotType: String?
    let currentMemberId: String?
    let currentTeamName: String?
    let currentUsername: String?
    let isMyPick: Bool
    let pickDeadline: String?
}

struct RosterSlot: Codable, Hashable, Identifiable {
    var id: String { slot }
    let slot: String
    let slotType: String
    let player: FantasyPlayer?
}

struct DraftMember: Codable, Identifiable, Hashable {
    let id: String
    let teamName: String
    let draftOrder: Int?
    let username: String?
    let isMe: Bool
    let roster: [RosterSlot]
}

struct DraftResponse: Codable {
    let league: FantasyLeagueSummary
    let state: DraftState
    let members: [DraftMember]
    let availablePlayers: [FantasyPlayer]
}

// MARK: - In-season

struct StandingRow: Codable, Identifiable, Hashable {
    var id: String { memberId }
    let memberId: String
    let teamName: String
    let username: String?
    let isMe: Bool
    let wins: Int
    let losses: Int
    let ties: Int
    let pf: Double
}

struct ScheduleItem: Codable, Identifiable, Hashable {
    var id: String { "\(week)-\(memberA)" }
    let week: Int
    let memberA: String
    let memberB: String?
    let aTeam: String?
    let bTeam: String?
    let isGhost: Bool
    let scoreA: Double?
    let scoreB: Double?
    let winnerMemberId: String?
    let graded: Bool
    let involvesMe: Bool
}

struct FantasySeasonResponse: Codable {
    let league: FantasyLeagueSummary
    let currentWeek: Int
    let myMemberId: String
    let standings: [StandingRow]
    let myRoster: [RosterSlot]
    let schedule: [ScheduleItem]
}

// MARK: - Trades

struct TradePlayer: Codable, Hashable {
    let id: String
    let fullName: String
    let team: String
}

struct TradeItem: Codable, Identifiable, Hashable {
    let id: String
    let status: String          // pending | accepted | rejected | cancelled
    let slotType: String
    let incoming: Bool
    let proposerTeam: String?
    let receiverTeam: String?
    let proposerPlayer: TradePlayer?
    let receiverPlayer: TradePlayer?
}

struct TradesResponse: Codable { let trades: [TradeItem] }

// MARK: - Global league

struct GlobalResponse: Codable {
    let league: FantasyLeagueSummary
    let joined: Bool
    let myRoster: [RosterSlot]
    let capSpace: Int?           // your salary-cap budget (earned from picks)
    let rosterCost: Int?         // total cost of your current roster

    var cap: Int { capSpace ?? 0 }
    var spent: Int { rosterCost ?? 0 }
    var remaining: Int { max(0, cap - spent) }
}

struct GlobalLeaderboardRow: Codable, Identifiable, Hashable {
    var id: String { memberId }
    let memberId: String
    let teamName: String
    let username: String?
    let isMe: Bool
    let goals: Int
    let points: Double
}

struct GlobalLeaderboardResponse: Codable { let leaderboard: [GlobalLeaderboardRow] }

// MARK: - Request bodies

struct CreateLeagueBody: Encodable {
    let name: String
    let teamName: String
    let leagueType: String
    let maxMembers: Int
    let draftPace: String
}

/// The three draft-pace modes offered at league setup.
enum DraftPace: String, CaseIterable, Identifiable {
    case rapid, standard, slow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rapid: return "Rapid Fire"
        case .standard: return "Standard"
        case .slow: return "Slow"
        }
    }
    var blurb: String {
        switch self {
        case .rapid: return "Live draft — everyone picks together, 2 minutes per pick."
        case .standard: return "Asynchronous — 1 hour per pick, usually wraps same day."
        case .slow: return "Relaxed — 6 hours per pick; draft over a day or two."
        }
    }
    var icon: String {
        switch self {
        case .rapid: return "bolt.fill"
        case .standard: return "clock.fill"
        case .slow: return "tortoise.fill"
        }
    }
}

struct JoinLeagueBody: Encodable {
    let inviteCode: String
    let teamName: String
}

struct PickBody: Encodable { let playerId: String }

struct ProposeTradeBody: Encodable {
    let toMemberId: String
    let myPlayerId: String
    let theirPlayerId: String
}

struct RespondTradeBody: Encodable { let accept: Bool }

struct SetSlotBody: Encodable { let slot: String; let playerId: String }

struct DeviceTokenBody: Encodable { let token: String; let platform: String }

// MARK: - Slot display helpers

enum FantasySlot {
    /// Human label for a roster slot type.
    static func label(_ slotType: String) -> String {
        switch slotType {
        case "LW": return "Left Wing"
        case "RW": return "Right Wing"
        case "C": return "Center"
        case "LHD": return "Left D"
        case "RHD": return "Right D"
        case "G": return "Goalie"
        default: return slotType
        }
    }

    /// Display name for an individual slot id (e.g. G_START → "Starter").
    static func slotName(_ slot: String) -> String {
        switch slot {
        case "G_START": return "Starter (G)"
        case "G_BACKUP": return "Backup (G)"
        default:
            // LW1 → "LW 1"
            let letters = slot.prefix { !$0.isNumber }
            let number = slot.drop { !$0.isNumber }
            return number.isEmpty ? String(letters) : "\(letters) \(number)"
        }
    }
}
