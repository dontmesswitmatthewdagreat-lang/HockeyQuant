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

    var id: Int { overall }
}

/// A server-generated first-round mock draft, refreshed weekly.
struct MockDraft: Codable, Hashable {
    let draftYear: Int
    let edition: String          // ISO year-week, e.g. "2026-W25" — drives the "new" badge
    let generatedAt: String?
    let orderBasis: String?
    let picks: [MockPick]
}

struct MockDraftResponse: Codable { let mockDraft: MockDraft? }
