import Foundation

// MARK: - Weekly mock draft

/// One projected first-round selection. `prospect` reuses the `Prospect` model so
/// the card gets headshot / flag / subtitle helpers for free.
struct MockPick: Codable, Identifiable, Hashable {
    let overall: Int
    let round: Int
    let team: String
    let teamName: String
    let need: String        // F / D / G — the group this pick addresses
    let reason: String      // need-fit explanation, or "Best player available"
    let prospect: Prospect
    /// This prospect's slot in the previous edition (nil = new to round one).
    let previousOverall: Int?

    var id: Int { overall }

    /// Movement vs last week's edition (positive = rose up the board).
    var movement: Int? { previousOverall.map { $0 - overall } }
}

/// One non-playoff team's draft-lottery standing: its chance at the No. 1 pick,
/// computed from current standings (worst record = best odds). Shown as a bar
/// chart during the regular season; replaced by results once the lottery is in.
struct LotteryOdds: Codable, Hashable, Identifiable {
    let abbrev: String
    let teamName: String
    let odds: Double        // percent chance at the No. 1 overall pick
    let draftSlot: Int      // current draft position, 1 = worst record
    let points: Int
    let gamesPlayed: Int

    var id: String { abbrev }
}

/// A server-generated first-round mock draft, refreshed weekly.
struct MockDraft: Codable, Hashable {
    let draftYear: Int
    let edition: String          // ISO year-week, e.g. "2026-W25" — drives the "new" badge
    let generatedAt: String?
    let orderBasis: String?
    let lotteryOdds: [LotteryOdds]?
    let picks: [MockPick]

    /// Pre-lottery while the order is still a standings projection; once the order
    /// goes official (NHL API / post-lottery reporting) the odds card shows results.
    var lotteryIsOfficial: Bool { !(orderBasis ?? "").hasPrefix("Projected") }
}

struct MockDraftResponse: Codable { let mockDraft: MockDraft? }
