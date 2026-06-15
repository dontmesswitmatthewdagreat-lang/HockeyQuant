import SwiftUI

/// A collapsible prediction card for the Schedule feed. Collapsed shows crests,
/// matchup, pick and win-probability; tapping expands betting lines, goalies,
/// projected score, and a link to the full breakdown. Collapsing fits more
/// games on screen.
struct GameCardView: View {
    let game: GamePrediction
    var dateString: String = ""

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var away: TeamInfo { game.away.info }
    private var home: TeamInfo { game.home.info }

    var body: some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                Button(action: toggle) { collapsedRow }
                    .buttonStyle(.plain)
                if expanded {
                    expandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func toggle() {
        Haptics.tap()
        withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.85)) {
            expanded.toggle()
        }
    }

    // MARK: - Collapsed

    private var collapsedRow: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                crest(game.away, size: 34)
                Text(away.abbrev)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("@").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
                Text(home.abbrev)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                crest(game.home, size: 34)
                Spacer()
                ConfidenceChip(confidence: game.confidence)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            HStack(spacing: Theme.Spacing.xs) {
                Text("\(Int(game.awayWinProb.rounded()))%")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                WinProbBar(awayProb: game.awayWinProb, homeProb: game.homeWinProb,
                           awayColor: away.color, homeColor: home.color)
                Text("\(Int(game.homeWinProb.rounded()))%")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func crest(_ team: TeamAnalysis, size: CGFloat) -> some View {
        let isPick = game.pick.uppercased() == team.team.uppercased()
        return CrestView(abbrev: team.team, size: size)
            .overlay(alignment: .topTrailing) {
                if isPick {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: size * 0.32))
                        .foregroundStyle(Theme.Palette.accent)
                        .background(Circle().fill(Theme.Palette.surface))
                        .offset(x: 3, y: -3)
                }
            }
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Divider().overlay(Theme.Palette.border)

            HStack {
                statusBadge
                Spacer()
                if let lines = game.bettingLines {
                    Text("Proj \(rounded(lines.awayExpectedGoals))–\(rounded(lines.homeExpectedGoals))")
                        .font(Theme.Font.mono())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                goalieBadge(game.away)
                Spacer()
                goalieBadge(game.home)
            }

            if let lines = game.bettingLines {
                HStack(spacing: Theme.Spacing.sm) {
                    StatPill(label: "PUCK LINE", value: formattedSpread(lines.puckLine))
                    Divider().frame(height: 28).overlay(Theme.Palette.border)
                    StatPill(label: "TOTAL", value: trimmed(lines.overUnder))
                    Divider().frame(height: 28).overlay(Theme.Palette.border)
                    StatPill(label: "PROJ. TOTAL", value: String(format: "%.1f", lines.predictedTotal))
                }
            }

            NavigationLink {
                GameDetailView(game: game, dateString: dateString)
            } label: {
                HStack {
                    Text("Full breakdown")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(Theme.Font.headline())
                .foregroundStyle(Theme.Palette.accent)
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }

    private var statusBadge: some View {
        let official = game.isOfficial == true
        return Text(official ? "LOCKED" : "ESTIMATE")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(official ? Theme.Palette.strong : Theme.Palette.moderate)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, 3)
            .background((official ? Theme.Palette.strong : Theme.Palette.moderate).opacity(0.12))
            .clipShape(Capsule())
    }

    private func goalieBadge(_ team: TeamAnalysis) -> some View {
        let confirmed = (team.team == game.home.team ? game.goalieStatusHome : game.goalieStatusAway) == "confirmed"
        return HStack(spacing: 3) {
            Image(systemName: confirmed ? "checkmark.circle.fill" : "questionmark.circle")
                .font(.system(size: 10))
                .foregroundStyle(confirmed ? Theme.Palette.strong : Theme.Palette.textTertiary)
            Text(team.goalie.split(separator: " ").last.map(String.init) ?? team.goalie)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
        }
    }

    // MARK: - Formatting

    private func rounded(_ v: Double) -> String { String(Int(v.rounded())) }
    private func trimmed(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
    private func formattedSpread(_ v: Double) -> String { (v > 0 ? "+" : "") + trimmed(v) }
}
