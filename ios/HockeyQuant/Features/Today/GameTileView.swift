import SwiftUI

/// A compact matchup tile for the 2-column Schedule grid. Shows live/final status
/// and score (or start time), both crests, the model's pick, and the win-prob
/// split. Tapping triggers the hero-expand into the full breakdown.
struct GameTileView: View {
    let game: ScheduleGame
    var namespace: Namespace.ID
    var isExpanded: Bool
    let onTap: () -> Void

    private var pred: GamePrediction { game.prediction }
    private var away: TeamInfo { pred.away.info }
    private var home: TeamInfo { pred.home.info }
    private var score: GameScore? { game.score }
    private var active: Bool { game.isLive || game.isFinal }

    var body: some View {
        PressableButton(action: onTap) {
            VStack(spacing: Theme.Spacing.sm) {
                topRow
                teamsRow
                winProbRow
            }
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(tileBackground)
            .opacity(isExpanded ? 0 : 1)   // hide the source tile while its hero is expanded
        }
        .buttonStyle(.plain)
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
            .fill(Theme.Palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .stroke(game.isLive ? Theme.Palette.live.opacity(0.6) : Theme.Palette.cardBorder,
                            lineWidth: game.isLive ? 2 : 1.5)
            )
            .matchedGeometryEffect(id: pred.id, in: namespace, isSource: !isExpanded)
    }

    // MARK: - Rows

    private var topRow: some View {
        HStack(spacing: Theme.Spacing.xs) {
            statusPill
            Spacer(minLength: 0)
            ConfidenceChip(confidence: pred.confidence)
        }
    }

    private var teamsRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            teamColumn(pred.away)
            centerColumn
            teamColumn(pred.home)
        }
    }

    private func teamColumn(_ team: TeamAnalysis) -> some View {
        let isPick = pred.pick.uppercased() == team.team.uppercased()
        return VStack(spacing: 4) {
            CrestView(abbrev: team.team, size: 40)
                .overlay(alignment: .topTrailing) {
                    if isPick {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Palette.accent)
                            .background(Circle().fill(Theme.Palette.surface))
                            .offset(x: 3, y: -3)
                    }
                }
            Text(team.info.abbrev)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var centerColumn: some View {
        if active, let s = score {
            VStack(spacing: 1) {
                Text("\(s.awayScore)–\(s.homeScore)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(.numericText())
                Text(game.isLive ? liveClock(s) : finalLabel(s))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(game.isLive ? Theme.Palette.live : Theme.Palette.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 52)
            .padding(.top, 10)
        } else {
            Text("@")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: 52)
                .padding(.top, 18)
        }
    }

    private var winProbRow: some View {
        HStack(spacing: 6) {
            Text("\(Int(pred.awayWinProb.rounded()))%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
            WinProbBar(awayProb: pred.awayWinProb, homeProb: pred.homeWinProb,
                       awayColor: away.color, homeColor: home.color)
            Text("\(Int(pred.homeWinProb.rounded()))%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    // MARK: - Status pill

    @ViewBuilder private var statusPill: some View {
        if game.isLive {
            HStack(spacing: 4) {
                Circle().fill(Theme.Palette.live).frame(width: 6, height: 6)
                Text("LIVE").font(.system(size: 10, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Theme.Palette.live)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.Palette.live.opacity(0.12)).clipShape(Capsule())
        } else if game.isFinal {
            Text(score?.periodType == "OT" ? "FINAL/OT" : "FINAL")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Theme.Palette.textSecondary.opacity(0.12)).clipShape(Capsule())
        } else {
            Text(startTime)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    // MARK: - Formatting

    private func liveClock(_ s: GameScore) -> String {
        let p = s.period.map { "P\($0)" } ?? ""
        if s.inIntermission == true { return "\(p) INT" }
        return [p, s.timeRemaining].compactMap { $0 }.joined(separator: " ")
    }

    private func finalLabel(_ s: GameScore) -> String { "FINAL" }

    private var startTime: String {
        guard let iso = pred.gameTime, let date = Self.isoParser.date(from: iso) else { return "—" }
        return Self.timeFmt.string(from: date)
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
}
