import Foundation

/// A private Pick'em friend league (invite-code group).
struct PickemLeague: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let inviteCode: String
    let seasonYear: Int
    let maxMembers: Int
    let memberCount: Int
    let isCommissioner: Bool
}

/// One member's standing within a league, scored by this season's XP.
struct PickemStanding: Codable, Identifiable, Hashable {
    let userId: String
    let username: String?
    let seasonXp: Int
    let picks: Int
    let correct: Int
    let accuracy: Double
    let rank: Int

    var id: String { userId }
    var displayName: String { (username?.isEmpty == false) ? username! : "Player \(userId.prefix(4))" }
}

struct PickemLeagueDetail: Codable { let league: PickemLeague; let standings: [PickemStanding] }
struct PickemLeaguesResponse: Codable { let leagues: [PickemLeague] }
