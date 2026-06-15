import SwiftUI

// Local copy of the app's hex initializer (the widget is a separate target).
extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - A game for the widgets

struct LiveGame: Identifiable, Sendable {
    let id = UUID()
    let away: String
    let home: String
    let awayScore: Int
    let homeScore: Int
    let state: String       // LIVE | CRIT | FINAL | OFF | FUT | PRE
    let status: String      // "2nd 12:34" | "Final" | "7:00 PM"
    var isLive: Bool { state == "LIVE" || state == "CRIT" }
    var isFinal: Bool { state == "FINAL" || state == "OFF" }
}

// MARK: - NHL / app decodables

private struct ScoreResponse: Decodable { let games: [ScoreGame] }
private struct ScoreGame: Decodable {
    let gameState: String
    let startTimeUTC: String?
    let awayTeam: ScoreSide
    let homeTeam: ScoreSide
    let periodDescriptor: PeriodDesc?
    let clock: GameClock?
}
private struct ScoreSide: Decodable { let abbrev: String?; let score: Int? }
private struct PeriodDesc: Decodable { let number: Int?; let periodType: String? }
private struct GameClock: Decodable { let timeRemaining: String?; let inIntermission: Bool? }

private struct ClubSchedule: Decodable { let games: [ScoreGame] }

private struct NewsResp: Decodable { let digests: [Dig] }
private struct Dig: Decodable { let keyPoints: [String]?; let items: [Itm]? }
private struct Itm: Decodable { let headline: String }

// MARK: - Fetcher (all public data — no auth)

enum WidgetFetcher {
    static let prod = "https://hockeyquant.onrender.com"
    static let nhl = "https://api-web.nhle.com/v1"

    private static func etDate() -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func season() -> String {
        let cal = Calendar(identifier: .gregorian)
        let m = cal.component(.month, from: Date()), y = cal.component(.year, from: Date())
        let sy = m >= 9 ? y : y - 1
        return "\(sy)\(sy + 1)"
    }

    private static func get<T: Decodable>(_ urlString: String, _ type: T.Type) async -> T? {
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Today's games as LiveGames (live first, then upcoming, then finals).
    static func scoreboard() async -> [LiveGame] {
        guard let r = await get("\(nhl)/score/\(etDate())", ScoreResponse.self) else { return [] }
        return r.games.map(toLive)
    }

    /// A team's relevant game: today's (live/final) or the next scheduled one.
    static func teamGame(_ team: String) async -> LiveGame? {
        let today = await scoreboard()
        if let g = today.first(where: { $0.away == team || $0.home == team }) { return g }
        guard let sched = await get("\(nhl)/club-schedule-season/\(team)/\(season())", ClubSchedule.self) else { return nil }
        let upcoming = sched.games.filter { $0.gameState == "FUT" || $0.gameState == "PRE" }
        if let next = upcoming.first { return toLive(next) }
        return nil
    }

    /// Top "what matters today" lines for the no-games news fallback.
    static func topNews(_ n: Int = 4) async -> [String] {
        guard let r = await get("\(prod)/api/news/latest", NewsResp.self), let d = r.digests.first else { return [] }
        if let kp = d.keyPoints, !kp.isEmpty { return Array(kp.prefix(n)) }
        return Array((d.items ?? []).prefix(n).map { $0.headline })
    }

    private static func toLive(_ g: ScoreGame) -> LiveGame {
        LiveGame(away: g.awayTeam.abbrev ?? "—", home: g.homeTeam.abbrev ?? "—",
                 awayScore: g.awayTeam.score ?? 0, homeScore: g.homeTeam.score ?? 0,
                 state: g.gameState, status: statusText(g))
    }

    private static func statusText(_ g: ScoreGame) -> String {
        switch g.gameState {
        case "LIVE", "CRIT":
            if g.clock?.inIntermission == true { return "INT" }
            let p = ordinal(g.periodDescriptor?.number ?? 1)
            return "\(p) \(g.clock?.timeRemaining ?? "")".trimmingCharacters(in: .whitespaces)
        case "FINAL", "OFF":
            let n = g.periodDescriptor?.number ?? 3
            return n > 3 ? "Final/OT" : "Final"
        default:
            return startTime(g.startTimeUTC)
        }
    }

    private static func ordinal(_ n: Int) -> String {
        switch n { case 1: return "1st"; case 2: return "2nd"; case 3: return "3rd"; default: return "OT" }
    }

    private static func startTime(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "TBD" }
        let f = DateFormatter(); f.dateFormat = "E h:mm a"
        return f.string(from: date)
    }
}
