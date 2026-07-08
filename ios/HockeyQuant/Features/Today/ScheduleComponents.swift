import SwiftUI

// The redesigned Schedule vocabulary: a slate ring for the hero band's
// centerpiece, a big Game-of-the-Night card, and slim sectioned rows whose
// spine is the win-probability split.

// MARK: - Slate ring (band centerpiece)

/// Circular badge straddling the band curve: a ring filled by how much of the
/// slate the model calls with conviction, or a pulsing LIVE state.
struct SlateRingBadge: View {
    let games: Int
    let strongCalls: Int
    let liveCount: Int
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(Theme.Palette.surfaceRaised)
            Circle().stroke(.white, lineWidth: 3)
            if liveCount > 0 {
                VStack(spacing: 0) {
                    Circle().fill(Theme.Palette.live)
                        .frame(width: 9, height: 9)
                        .scaleEffect(pulse ? 1.25 : 0.8)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                    Text("\(liveCount)")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .contentTransition(.numericText())
                    Text("LIVE")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Theme.Palette.live)
                }
                .onAppear { pulse = true }
            } else if games > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(strongCalls) / CGFloat(max(games, 1)))
                    .stroke(Theme.Palette.strong, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(6)
                VStack(spacing: 0) {
                    Text("\(strongCalls)")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("STRONG")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            } else {
                Image(systemName: "hockey.puck")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .frame(width: 72, height: 72)
        .shadow(color: .black.opacity(0.30), radius: 6, y: 2)
    }
}

// MARK: - Game of the Night (hero card)

/// The one game the page leads with: the model's strongest upcoming call, or
/// the closest live game. Big crests, the pick spelled out, and the split bar.
struct HeroGameCard: View {
    let game: ScheduleGame
    let onTap: () -> Void

    private var pred: GamePrediction { game.prediction }
    private var away: TeamInfo { pred.away.info }
    private var home: TeamInfo { pred.home.info }
    private var pickInfo: TeamInfo { pred.pickIsHome ? home : away }
    private var pickProb: Double { pred.pickIsHome ? pred.homeWinProb : pred.awayWinProb }

    var body: some View {
        PressableButton(action: onTap) {
            VStack(spacing: Theme.Spacing.sm) {
                HStack {
                    scheduleStatusPill(game)
                    Spacer()
                    ConfidenceChip(confidence: pred.confidence)
                }
                HStack(spacing: Theme.Spacing.md) {
                    heroTeam(pred.away, isPick: !pred.pickIsHome)
                    centerBlock
                    heroTeam(pred.home, isPick: pred.pickIsHome)
                }
                SplitBar(leftFraction: pred.awayWinProb / 100,
                         leftColor: away.color, rightColor: home.color, height: 7)
                Text(callLine)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let lines = pred.bettingLines {
                    HStack(spacing: Theme.Spacing.xs) {
                        StatusPill(text: "O/U \(trim(lines.overUnder))", color: Theme.Palette.textSecondary)
                        StatusPill(text: "PL \(trim(lines.puckLine))", color: Theme.Palette.textSecondary)
                        goaliePill(pred.goalieStatusAway, team: pred.away.team)
                        goaliePill(pred.goalieStatusHome, team: pred.home.team)
                        Spacer()
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [pickInfo.color.opacity(0.8), Theme.Palette.border],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var callLine: String {
        if game.isFinal, let s = game.score {
            let winner = s.homeScore > s.awayScore ? pred.home.team : pred.away.team
            let hit = winner.uppercased() == pred.pick.uppercased()
            return hit ? "Model called \(pred.pick) — got it ✓" : "Model called \(pred.pick) — missed"
        }
        if game.isLive {
            return "Model: \(pred.pick) · \(Int(pickProb.rounded()))% before puck drop"
        }
        return "Model: \(pred.pick) · \(Int(pickProb.rounded()))% — the strongest call on this slate"
    }

    private func heroTeam(_ team: TeamAnalysis, isPick: Bool) -> some View {
        VStack(spacing: 5) {
            CrestView(abbrev: team.team, size: 56)
                .overlay(alignment: .topTrailing) {
                    if isPick {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.Palette.accent)
                            .background(Circle().fill(Theme.Palette.surface))
                            .offset(x: 4, y: -4)
                    }
                }
            Text(team.info.abbrev)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var centerBlock: some View {
        if let s = game.score, game.isLive || game.isFinal {
            VStack(spacing: 2) {
                Text("\(s.awayScore)–\(s.homeScore)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(.numericText())
                Text(game.isLive ? liveClock(s) : (s.periodType == "OT" ? "FINAL/OT" : "FINAL"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(game.isLive ? Theme.Palette.live : Theme.Palette.textTertiary)
            }
        } else {
            VStack(spacing: 2) {
                Text("@")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text(startTime(pred))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func goaliePill(_ status: String?, team: String) -> some View {
        if status?.lowercased() == "confirmed" {
            StatusPill(text: "\(team) G ✓", color: Theme.Palette.positive)
        }
    }

    private func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - Schedule row

/// One slim game row: overlapping crests, matchup + context line, the
/// win-probability split as the spine, and a state-aware trailing block.
struct ScheduleRow: View {
    let game: ScheduleGame
    let onTap: () -> Void

    private var pred: GamePrediction { game.prediction }
    private var away: TeamInfo { pred.away.info }
    private var home: TeamInfo { pred.home.info }

    var body: some View {
        PressableButton(action: onTap) {
            HStack(spacing: Theme.Spacing.sm) {
                crestPair
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("\(away.abbrev) @ \(home.abbrev)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        if game.isLive {
                            HStack(spacing: 3) {
                                Circle().fill(Theme.Palette.live).frame(width: 5, height: 5)
                                Text("LIVE").font(.system(size: 9, weight: .heavy, design: .rounded))
                            }
                            .foregroundStyle(Theme.Palette.live)
                        }
                    }
                    Text(contextLine)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                    SplitBar(leftFraction: pred.awayWinProb / 100,
                             leftColor: away.color, rightColor: home.color, height: 5)
                        .frame(maxWidth: 190)
                }
                Spacer(minLength: Theme.Spacing.xs)
                trailing
            }
            .padding(Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(game.isLive ? Theme.Palette.live.opacity(0.55) : Theme.Palette.cardBorder,
                                  lineWidth: game.isLive ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var crestPair: some View {
        ZStack {
            CrestView(abbrev: pred.away.team, size: 30).offset(x: -9)
            CrestView(abbrev: pred.home.team, size: 30).offset(x: 9)
        }
        .frame(width: 52)
    }

    private var contextLine: String {
        if game.isLive, let s = game.score { return liveClock(s) }
        if game.isFinal { return "Model: \(pred.pick)" }
        let prob = pred.pickIsHome ? pred.homeWinProb : pred.awayWinProb
        return "Model: \(pred.pick) · \(Int(prob.rounded()))% · \(startTime(pred))"
    }

    @ViewBuilder private var trailing: some View {
        if let s = game.score, game.isLive || game.isFinal {
            HStack(spacing: Theme.Spacing.xs) {
                Text("\(s.awayScore)–\(s.homeScore)")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(.numericText())
                if game.isFinal {
                    let winner = s.homeScore > s.awayScore ? pred.home.team : pred.away.team
                    let hit = winner.uppercased() == pred.pick.uppercased()
                    Image(systemName: hit ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(hit ? Theme.Palette.positive : Theme.Palette.negative)
                }
            }
        } else {
            ConfidenceChip(confidence: pred.confidence)
        }
    }
}

// MARK: - Shared bits

@MainActor @ViewBuilder
func scheduleStatusPill(_ game: ScheduleGame) -> some View {
    if game.isLive {
        HStack(spacing: 4) {
            Circle().fill(Theme.Palette.live).frame(width: 6, height: 6)
            Text("LIVE NOW").font(.system(size: 10, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(Theme.Palette.live)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.Palette.live.opacity(0.12)).clipShape(Capsule())
    } else if game.isFinal {
        Text("GAME OF THE NIGHT · FINAL")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.Palette.textSecondary.opacity(0.12)).clipShape(Capsule())
    } else {
        HStack(spacing: 4) {
            Image(systemName: "star.fill").font(.system(size: 9, weight: .heavy))
            Text("GAME OF THE NIGHT").font(.system(size: 10, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(Theme.Palette.accent)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.Palette.accent.opacity(0.12)).clipShape(Capsule())
    }
}

func liveClock(_ s: GameScore) -> String {
    let p = s.period.map { "P\($0)" } ?? ""
    if s.inIntermission == true { return "\(p) INT" }
    return [p, s.timeRemaining].compactMap { $0 }.joined(separator: " ")
}

@MainActor private enum ScheduleFmt {
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
}

@MainActor
func startTime(_ pred: GamePrediction) -> String {
    guard let iso = pred.gameTime, let date = ScheduleFmt.iso.date(from: iso) else { return "—" }
    return ScheduleFmt.time.string(from: date)
}
