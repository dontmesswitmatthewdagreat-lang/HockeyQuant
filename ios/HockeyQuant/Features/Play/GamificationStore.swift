import Foundation
import Observation
import Supabase

/// Talks to the gamification tables in Supabase (RLS-scoped to the signed-in
/// user). XP/grading are written only by server-side SECURITY DEFINER
/// functions — the app never writes stats directly.
@MainActor
@Observable
final class GamificationStore {

    private let client = Supa.client

    private(set) var stats: UserStats?
    private(set) var picksByGame: [String: UserPick] = [:]   // game_id -> pick
    private(set) var leaderboard: [LeaderboardEntry] = []
    private(set) var seasonStats = SeasonStats()
    private(set) var achievements: [Achievement] = []
    private(set) var earnedIds: Set<String> = []
    private(set) var submitting: Set<String> = []
    private(set) var lastError: String?

    /// Reward moments to celebrate (set when fresh data beats what we last saw).
    private(set) var pendingXpGain: Int = 0
    private(set) var pendingAchievements: [Achievement] = []

    private let defaults = UserDefaults.standard
    private func key(_ name: String) -> String { "\(name)_\(currentUserId ?? "anon")" }

    func clearCelebrations() {
        pendingXpGain = 0
        pendingAchievements = []
    }

    var currentUserId: String? { client.auth.currentUser?.id.uuidString }

    /// Stable per-game id derived from date + teams (the prediction API does
    /// not expose the NHL game id; grading matches on date + teams).
    static func gameId(date: String, away: String, home: String) -> String {
        "\(date)-\(away)-\(home)"
    }

    // MARK: - Loading

    func loadStats() async {
        do {
            let rows: [UserStats] = try await client.from("user_stats").select().execute().value
            let fresh = rows.first ?? .empty
            // Celebrate Cap Space earned since we last looked (skip first-ever load).
            let capKey = key("lastSeenCap")
            if let last = defaults.object(forKey: capKey) as? Int, fresh.capSpace > last {
                pendingXpGain = fresh.capSpace - last
            }
            defaults.set(fresh.capSpace, forKey: capKey)
            stats = fresh
        } catch {
            Log.error("loadStats failed", error)
            lastError = error.localizedDescription
        }
    }

    func loadPicks(date: String) async {
        do {
            let rows: [UserPick] = try await client
                .from("user_picks").select().eq("game_date", value: date).execute().value
            picksByGame = Dictionary(rows.map { ($0.gameId, $0) }, uniquingKeysWith: { a, _ in a })
        } catch {
            Log.error("loadPicks failed", error)
        }
    }

    /// GM-tier progress. The pick fields drive the season goals; the **XP that drives the
    /// GM tier is account-wide** (`user_stats.total_xp`), fed by the franchise (card
    /// collecting + nightly challenges).
    func loadSeason() async {
        let s = Season.current
        do {
            let rows: [UserPick] = try await client
                .from("user_picks")
                .select()
                .gte("game_date", value: s.start)
                .lte("game_date", value: s.end)
                .order("game_date", ascending: true)
                .execute()
                .value
            var computed = SeasonStats(from: rows)
            computed.xp = stats?.totalXp ?? computed.xp     // GM tier = account XP, not season pick XP
            seasonStats = computed
        } catch {
            Log.error("loadSeason failed", error)
        }
    }

    func loadLeaderboard() async {
        do {
            leaderboard = try await client
                .from("leaderboard").select().limit(100).execute().value
        } catch {
            Log.error("loadLeaderboard failed", error)
            lastError = error.localizedDescription
        }
    }

    func loadAchievements() async {
        do {
            achievements = try await client
                .from("achievements").select().order("sort").execute().value
            let earned: [UserAchievement] = try await client
                .from("user_achievements").select().execute().value
            let freshEarned = Set(earned.map(\.achievementId))
            // Celebrate badges earned since last seen (skip first-ever load).
            let seenKey = key("seenAchievements")
            if let seen = defaults.stringArray(forKey: seenKey) {
                let newly = freshEarned.subtracting(seen)
                if !newly.isEmpty {
                    pendingAchievements = achievements.filter { newly.contains($0.id) }
                }
            }
            defaults.set(Array(freshEarned), forKey: seenKey)
            earnedIds = freshEarned
        } catch {
            Log.error("loadAchievements failed", error)
        }
    }

    func pick(forGameId id: String) -> UserPick? { picksByGame[id] }

    // MARK: - Submitting

    /// Submit (or change) a moneyline pick for a game. No-op if already graded.
    func submitPick(game: GamePrediction, dateString: String, pick teamAbbrev: String) async {
        guard let uid = currentUserId else { return }
        let id = Self.gameId(date: dateString, away: game.away.team, home: game.home.team)
        if picksByGame[id]?.correct != nil { return } // locked once graded

        submitting.insert(id)
        defer { submitting.remove(id) }

        let payload = PickPayload(
            userId: uid,
            gameDate: dateString,
            gameId: id,
            awayTeam: game.away.team,
            homeTeam: game.home.team,
            pickType: "ML",
            pick: teamAbbrev,
            modelPick: game.pick
        )

        do {
            try await client.from("user_picks")
                .upsert(payload, onConflict: "user_id,game_id,pick_type")
                .execute()
            Haptics.success()
            await loadPicks(date: dateString)
        } catch {
            Log.error("submitPick failed", error)
            lastError = error.localizedDescription
        }
    }
}
