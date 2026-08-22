import SwiftUI

/// The duel scoreboard: what every drafted player has actually produced.
///
/// A duel is decided by numbers the player never sees being calculated, so the
/// screen leads with the margin and then shows its whole derivation — each
/// roster spot, the counting stats behind it, and the points they bought. The
/// scoring key at the bottom is part of that: points with no stated rate are
/// just a number to be suspicious of.
struct DuelScoreboardView: View {
    let duelId: Int

    @Environment(AuthStore.self) private var auth

    @State private var board: DuelScoreboard?
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.backgroundView()
            content
        }
        .navigationTitle("Scoreboard")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading && board == nil {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    LoadingShimmer(height: 150)
                    LoadingShimmer(height: 240)
                    LoadingShimmer(height: 240)
                }
                .padding(Theme.Spacing.md)
            }
        } else if let errorMessage, board == nil {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if let board {
            if let mine = mySide(board), let theirs = theirSide(board) {
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        header(board, mine: mine, theirs: theirs)
                        rosterCard(title: "Your roster", side: mine, mine: true)
                        rosterCard(title: opponentName(board), side: theirs, mine: false)
                        scoringKey
                    }
                    .padding(Theme.Spacing.md)
                }
            } else {
                EmptyStateView(
                    systemImage: "hourglass",
                    title: "Nothing to score yet",
                    message: "The scoreboard fills in once both rosters are drafted."
                )
            }
        }
    }

    // MARK: - Header

    private func header(_ board: DuelScoreboard, mine: DuelSide, theirs: DuelSide) -> some View {
        let duel = board.duel
        return Card {
            VStack(spacing: Theme.Spacing.sm) {
                Text(duel.isFlash ? "TONIGHT · \(duel.weekStart)" : "WEEK OF \(duel.weekStart)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.8)
                    .foregroundStyle(Theme.Palette.textTertiary)

                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    scoreColumn(title: "You", side: mine, tint: Theme.Palette.accent)
                    Text("vs")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.top, 10)
                    scoreColumn(title: opponentName(board), side: theirs,
                                tint: Theme.Palette.textSecondary)
                }

                SplitBar(leftFraction: share(mine, theirs),
                         leftColor: Theme.Palette.accent,
                         rightColor: Theme.Palette.textTertiary.opacity(0.5))

                verdict(duel, mine: mine, theirs: theirs)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func scoreColumn(title: String, side: DuelSide, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(String(format: "%.1f", side.total))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(String(format: "%.1f skating · %.1f bonus", side.base, side.bonus))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func verdict(_ duel: Duel, mine: DuelSide, theirs: DuelSide) -> some View {
        let margin = mine.total - theirs.total
        let final = duel.isFinal
        if abs(margin) < 0.05 {
            StatusPill(text: final ? "Final · tied" : "Dead even",
                       systemImage: "equal.circle.fill", color: Theme.Palette.moderate)
        } else if margin > 0 {
            StatusPill(text: final
                       ? String(format: "Won by %.1f", margin)
                       : String(format: "Leading by %.1f", margin),
                       systemImage: final ? "trophy.fill" : "arrow.up.right",
                       color: Theme.Palette.positive, solid: final)
        } else {
            StatusPill(text: final
                       ? String(format: "Lost by %.1f", -margin)
                       : String(format: "Trailing by %.1f", -margin),
                       systemImage: final ? "xmark.circle.fill" : "arrow.down.right",
                       color: Theme.Palette.negative, solid: final)
        }
    }

    // MARK: - Rosters

    private func rosterCard(title: String, side: DuelSide, mine: Bool) -> some View {
        SectionCard(title, accessory: AnyView(
            Text(String(format: "%.1f", side.total))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(mine ? Theme.Palette.accent : Theme.Palette.textSecondary)
        )) {
            VStack(spacing: Theme.Spacing.xs) {
                // Best week first: the scoreboard's job is to explain the margin,
                // and the players who built it should be at the top.
                ForEach(side.players.sorted { $0.total > $1.total }) { player in
                    playerRow(player, mine: mine)
                }
            }
        }
    }

    private func playerRow(_ player: DuelScoredPlayer, mine: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            CrestView(abbrev: player.team ?? "", size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text("\(player.slotLabel) · \(player.statLine)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.xs)
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.1f", player.total))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(player.total > 0
                                     ? (mine ? Theme.Palette.accent : Theme.Palette.textPrimary)
                                     : Theme.Palette.textTertiary)
                Text("\(player.games) GP")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Scoring key

    private var scoringKey: some View {
        SectionCard("How it scores") {
            VStack(alignment: .leading, spacing: 6) {
                keyRow("Skaters", "Goal 3 · Assist 2")
                keyRow("Bonus", "Plus/minus 1 each · shorthanded point 2")
                keyRow("Goalies", "Win 3 · save 0.15 · goal against −1 · shutout 3")
                Text("Hits, blocks and takeaways aren't in the NHL's per-game log, so the defensive read is plus/minus and penalty-kill production.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.top, 2)
            }
        }
    }

    private func keyRow(_ label: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 58, alignment: .leading)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    // MARK: - Helpers

    /// Falls back to side A when the viewer isn't one of the two drafters, so a
    /// shared duel still renders instead of showing an empty screen.
    private func mySide(_ board: DuelScoreboard) -> DuelSide? {
        board.side(for: auth.userId) ?? board.a
    }

    private func theirSide(_ board: DuelScoreboard) -> DuelSide? {
        board.opponentSide(for: auth.userId) ?? board.b
    }

    private func opponentName(_ board: DuelScoreboard) -> String {
        let opponentId = board.duel.userA.lowercased() == auth.userId?.lowercased()
            ? board.duel.userB : board.duel.userA
        return board.name(for: opponentId) ?? "Opponent"
    }

    private func share(_ mine: DuelSide, _ theirs: DuelSide) -> Double {
        // Negative totals are possible (a goalie can have a bad enough night),
        // so shift both sides above zero before taking a proportion.
        let floor = min(0, min(mine.total, theirs.total))
        let a = mine.total - floor, b = theirs.total - floor
        return a + b > 0 ? a / (a + b) : 0.5
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            board = try await APIClient().duelScoreboard(duelId: duelId)
            errorMessage = nil
        } catch {
            Log.error("duel scoreboard", error)
            errorMessage = error.localizedDescription
        }
    }
}
