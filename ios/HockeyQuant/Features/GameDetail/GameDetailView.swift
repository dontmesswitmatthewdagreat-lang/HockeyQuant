import SwiftUI

/// Full breakdown for a single game: matchup, live score, AI explanation,
/// betting lines, the Poisson scoreline grid, and the two-engine factor readout.
struct GameDetailView: View {
    @State private var model: GameDetailViewModel

    init(game: GamePrediction, dateString: String) {
        _model = State(initialValue: GameDetailViewModel(game: game, dateString: dateString))
    }

    private var game: GamePrediction { model.game }
    private var away: TeamInfo { game.away.info }
    private var home: TeamInfo { game.home.info }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                matchupCard
                if let score = model.liveScore, score.isActive {
                    liveScoreCard(score)
                }
                summaryCard
                bettingCard
                heatmapCard
                shotMapCard
                factorsCard
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Palette.background)
        .navigationTitle("\(away.abbrev) @ \(home.abbrev)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.loadScore()
        }
    }

    // MARK: - Matchup

    private var matchupCard: some View {
        Card {
            VStack(spacing: Theme.Spacing.md) {
                HStack {
                    ConfidenceChip(confidence: game.confidence)
                    Spacer()
                    Text(game.isOfficial == true ? "LOCKED" : "ESTIMATE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(game.isOfficial == true ? Theme.Palette.strong : Theme.Palette.moderate)
                }
                HStack(spacing: Theme.Spacing.sm) {
                    teamBadge(game.away, isPick: !game.pickIsHome)
                    VStack(spacing: 2) {
                        Text("@").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
                        if let lines = game.bettingLines {
                            Text("\(rounded(lines.awayExpectedGoals))–\(rounded(lines.homeExpectedGoals))")
                                .font(Theme.Font.mono())
                                .foregroundStyle(Theme.Palette.textSecondary)
                            Text("proj").font(.system(size: 9)).foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    .frame(width: 64)
                    teamBadge(game.home, isPick: game.pickIsHome)
                }
                WinProbBar(awayProb: game.awayWinProb, homeProb: game.homeWinProb,
                           awayColor: away.color, homeColor: home.color)
                HStack {
                    Text("\(away.abbrev) \(Int(game.awayWinProb.rounded()))%")
                    Spacer()
                    Text("\(Int(game.homeWinProb.rounded()))% \(home.abbrev)")
                }
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private func teamBadge(_ team: TeamAnalysis, isPick: Bool) -> some View {
        let info = team.info
        return VStack(spacing: Theme.Spacing.xs) {
            CrestView(abbrev: team.team, size: 64)
            .overlay(alignment: .topTrailing) {
                if isPick {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.Palette.accent)
                        .background(Circle().fill(Theme.Palette.surface))
                        .offset(x: 4, y: -4)
                }
            }
            Text(info.name)
                .font(Theme.Font.caption())
                .foregroundStyle(isPick ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Live score

    private func liveScoreCard(_ score: GameScore) -> some View {
        Card {
            VStack(spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    if score.isLive {
                        Circle().fill(Theme.Palette.live).frame(width: 8, height: 8)
                        Text("LIVE").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.live)
                    } else {
                        Text("FINAL").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    Text(statusText(score))
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                HStack {
                    Text(away.abbrev).font(Theme.Font.headline())
                    Spacer()
                    Text("\(score.awayScore) – \(score.homeScore)")
                        .font(Theme.Font.statNumber())
                    Spacer()
                    Text(home.abbrev).font(Theme.Font.headline())
                }
                .foregroundStyle(Theme.Palette.textPrimary)
            }
        }
    }

    private func statusText(_ score: GameScore) -> String {
        if score.isFinal {
            return score.periodType == "OT" ? "Final / OT" : "Final"
        }
        let p = score.period.map { "P\($0)" } ?? ""
        if score.inIntermission == true { return "\(p) INT" }
        return [p, score.timeRemaining].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: - AI summary

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Why \(game.pick)?")
                    .font(Theme.Font.headline())
                    .foregroundStyle(Theme.Palette.textPrimary)
                switch model.summaryState {
                case .idle:
                    PressableButton(action: { Task { await model.loadSummary() } }) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "sparkles")
                            Text("Explain the pick")
                        }
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.accent)
                    }
                case .loading:
                    HStack(spacing: Theme.Spacing.xs) {
                        ProgressView()
                        Text("Analyzing…").font(Theme.Font.caption())
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                case .loaded(let text):
                    Text(text)
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Palette.textSecondary)
                case .error(let message):
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(message)
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Palette.negative)
                        PressableButton(action: { Task { await model.loadSummary() } }) {
                            Text("Retry").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.accent)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Betting lines

    @ViewBuilder private var bettingCard: some View {
        if let lines = game.bettingLines {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    sectionHeader("Betting lines")
                    lineRow("Moneyline (reg.)",
                            "\(away.abbrev) \(pct(lines.mlAwayProb)) · \(home.abbrev) \(pct(lines.mlHomeProb))")
                    lineRow("Puck line (\(lines.puckLineSource))",
                            "\(home.abbrev) \(signed(lines.puckLine)) · cover \(pct(lines.puckLineHomeCoverProb))")
                    lineRow("Total (\(lines.overUnderSource))",
                            "\(trim(lines.overUnder)) · O \(pct(lines.overProb)) / U \(pct(lines.underProb))")
                    Divider().overlay(Theme.Palette.border)
                    lineRow("Best spread", "\(signed(lines.optimalSpread)) \(lines.optimalSpreadSide) · \(pct(lines.optimalSpreadProb))")
                    lineRow("Best total", "\(lines.optimalTotalRec) \(trim(lines.optimalTotal)) · \(pct(lines.optimalTotalProb))")
                }
            }
        }
    }

    private func lineRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text(value).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Heatmap

    @ViewBuilder private var heatmapCard: some View {
        if let lines = game.bettingLines {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    sectionHeader("Scoreline grid")
                    PoissonHeatmapView(
                        awayMean: lines.awayExpectedGoals,
                        homeMean: lines.homeExpectedGoals,
                        awayAbbrev: away.abbrev,
                        homeAbbrev: home.abbrev,
                        tint: home.color
                    )
                }
            }
        }
    }

    // MARK: - Shot map

    private var shotMapCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionHeader("Shot map")
                ShotMapView(date: model.dateString, away: game.away.team, home: game.home.team)
            }
        }
    }

    // MARK: - Two-engine factors

    private var factorsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionHeader("Quality-score factors")
                factorColumns
                Divider().overlay(Theme.Palette.border)
                goalieRow(game.away)
                goalieRow(game.home)
            }
        }
    }

    private var factorColumns: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                Text(away.abbrev).frame(width: 76)
                Text(home.abbrev).frame(width: 76)
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.Palette.textTertiary)

            factorRow("Base score", away: fmt(game.away.baseScore), home: fmt(game.home.baseScore))
            factorRow("Final score", away: fmt(game.away.finalScore), home: fmt(game.home.finalScore))
            factorRow("Fatigue", away: mult(game.away.fatigueMult), home: mult(game.home.fatigueMult))
            factorRow("Streak", away: mult(game.away.streakMult), home: mult(game.home.streakMult))
            factorRow("Special teams", away: mult(game.away.stMult), home: mult(game.home.stMult))
            factorRow("Injuries", away: mult(game.away.injuryMult), home: mult(game.home.injuryMult))
            factorRow("Head-to-head", away: mult(game.away.h2hMult), home: mult(game.home.h2hMult))
        }
    }

    private func factorRow(_ label: String, away: String, home: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(away).font(Theme.Font.mono()).frame(width: 76)
            Text(home).font(Theme.Font.mono()).frame(width: 76)
        }
        .foregroundStyle(Theme.Palette.textPrimary)
    }

    private func goalieRow(_ team: TeamAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(team.info.abbrev) · \(team.goalie)")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("GSAX \(signedNum(team.goalieGsax))  ·  SV% \(String(format: "%.3f", team.goalieSvPct))  ·  GAA \(String(format: "%.2f", team.goalieGaa))")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.Palette.textTertiary)
    }

    private func rounded(_ v: Double) -> String { String(Int(v.rounded())) }
    private func trim(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
    private func signed(_ v: Double) -> String { (v > 0 ? "+" : "") + trim(v) }
    private func signedNum(_ v: Double) -> String { String(format: "%+.1f", v) }
    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
    private func mult(_ v: Double) -> String { String(format: "×%.3f", v) }
    private func pct(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))%" } ?? "—" }
}
