import SwiftUI

/// The hero-expanded full breakdown for a game. Reached by tapping a Schedule
/// tile (it morphs up from the tile). Leads with the live scoreline grid, then
/// the shot map, then win prob / betting lines, the deterministic Edge breakdown,
/// and the quality-score factors. Live games keep the grid + shot map current.
struct GameExpandedView: View {
    let game: ScheduleGame
    let dateString: String
    let onClose: () -> Void

    @State private var containerWidth: CGFloat = 0

    private var pred: GamePrediction { game.prediction }
    private var away: TeamInfo { pred.away.info }
    private var home: TeamInfo { pred.home.info }
    private var score: GameScore? { game.score }
    private var active: Bool { game.isLive || game.isFinal }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                headerBar
                if pred.bettingLines != nil {
                    sectionCard("Scoreline grid") { scorelineGrid }
                }
                sectionCard("Shot map") {
                    ShotMapView(date: dateString, away: pred.away.team, home: pred.home.team)
                }
                sectionCard("The Edge") { EdgeBreakdownView(game: pred) }
                bettingCard
                factorsCard
            }
            // `.padding(.horizontal)` is dropped here, so cap the column with an
            // explicit maxWidth from the measured container width (a hard cap the
            // cards honour). ScrollView stays the root so it scrolls normally.
            .frame(maxWidth: containerWidth > 0 ? containerWidth - 2 * Theme.Spacing.md : .infinity)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
        }
        .background {
            GeometryReader { geo in
                Theme.Palette.background
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in containerWidth = w }
            }
        }
        .overlay(alignment: .topTrailing) {
            closeButton.padding(.trailing, Theme.Spacing.md).padding(.top, Theme.Spacing.xs)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 34, height: 34)
                .background(Theme.Palette.surface)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.Palette.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .accessibilityLabel("Close")
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                ConfidenceChip(confidence: pred.confidence)
                Spacer()
                statusPill
            }
            HStack(spacing: Theme.Spacing.sm) {
                teamBadge(pred.away, isPick: !pred.pickIsHome)
                centerColumn
                teamBadge(pred.home, isPick: pred.pickIsHome)
            }
            WinProbBar(awayProb: pred.awayWinProb, homeProb: pred.homeWinProb,
                       awayColor: away.color, homeColor: home.color)
            HStack {
                Text("\(away.abbrev) \(Int(pred.awayWinProb.rounded()))%")
                Spacer()
                Text("\(Int(pred.homeWinProb.rounded()))% \(home.abbrev)")
            }
            .font(Theme.Font.caption())
            .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).stroke(Theme.Palette.cardBorder, lineWidth: 1.5))
    }

    @ViewBuilder private var centerColumn: some View {
        if active, let s = score {
            VStack(spacing: 2) {
                Text("\(s.awayScore)–\(s.homeScore)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(.numericText())
            }
            .frame(width: 64)
        } else if let lines = pred.bettingLines {
            VStack(spacing: 2) {
                Text("@").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
                Text("\(rounded(lines.awayExpectedGoals))–\(rounded(lines.homeExpectedGoals))")
                    .font(Theme.Font.mono()).foregroundStyle(Theme.Palette.textSecondary)
                Text("proj").font(.system(size: 9)).foregroundStyle(Theme.Palette.textTertiary)
            }
            .frame(width: 72)
        } else {
            Text("@").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary).frame(width: 72)
        }
    }

    private func teamBadge(_ team: TeamAnalysis, isPick: Bool) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            CrestView(abbrev: team.team, size: 48)
                .overlay(alignment: .topTrailing) {
                    if isPick {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Palette.accent)
                            .background(Circle().fill(Theme.Palette.surface))
                            .offset(x: 3, y: -3)
                    }
                }
            Text(team.info.name)
                .font(Theme.Font.caption())
                .foregroundStyle(isPick ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var statusPill: some View {
        if game.isLive {
            HStack(spacing: 4) {
                Circle().fill(Theme.Palette.live).frame(width: 7, height: 7)
                Text("LIVE \(liveClock)").font(.system(size: 11, weight: .heavy, design: .rounded))
            }.foregroundStyle(Theme.Palette.live)
        } else if game.isFinal {
            Text(score?.periodType == "OT" ? "FINAL / OT" : "FINAL")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textSecondary)
        } else {
            Text(pred.isOfficial == true ? "LOCKED" : "ESTIMATE")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(pred.isOfficial == true ? Theme.Palette.strong : Theme.Palette.moderate)
        }
    }

    private var liveClock: String {
        guard let s = score else { return "" }
        let p = s.period.map { "P\($0)" } ?? ""
        if s.inIntermission == true { return "\(p) INT" }
        return [p, s.timeRemaining].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: - Scoreline grid

    @ViewBuilder private var scorelineGrid: some View {
        if let lines = pred.bettingLines {
            PoissonHeatmapView(
                awayMean: lines.awayExpectedGoals,
                homeMean: lines.homeExpectedGoals,
                awayAbbrev: away.abbrev,
                homeAbbrev: home.abbrev,
                tint: home.color,
                liveAway: active ? score?.awayScore : nil,
                liveHome: active ? score?.homeScore : nil,
                fractionElapsed: score?.fractionElapsed ?? 0,
                isFinal: game.isFinal
            )
        }
    }

    // MARK: - Betting lines

    @ViewBuilder private var bettingCard: some View {
        if let lines = pred.bettingLines {
            sectionCard("Betting lines") {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    lineRow("Moneyline (reg.)", "\(away.abbrev) \(pct(lines.mlAwayProb)) · \(home.abbrev) \(pct(lines.mlHomeProb))")
                    lineRow("Puck line (\(lines.puckLineSource))", "\(home.abbrev) \(signed(lines.puckLine)) · cover \(pct(lines.puckLineHomeCoverProb))")
                    lineRow("Total (\(lines.overUnderSource))", "\(trim(lines.overUnder)) · O \(pct(lines.overProb)) / U \(pct(lines.underProb))")
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
            Text(value).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary).multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Factors

    private var factorsCard: some View {
        sectionCard("Quality-score factors") {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                factorColumns
                Divider().overlay(Theme.Palette.border)
                goalieRow(pred.away)
                goalieRow(pred.home)
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
            factorRow("Base score", away: fmt(pred.away.baseScore), home: fmt(pred.home.baseScore))
            factorRow("Final score", away: fmt(pred.away.finalScore), home: fmt(pred.home.finalScore))
            factorRow("Fatigue", away: mult(pred.away.fatigueMult), home: mult(pred.home.fatigueMult))
            factorRow("Streak", away: mult(pred.away.streakMult), home: mult(pred.home.streakMult))
            factorRow("Special teams", away: mult(pred.away.stMult), home: mult(pred.home.stMult))
            factorRow("Injuries", away: mult(pred.away.injuryMult), home: mult(pred.home.injuryMult))
            factorRow("Head-to-head", away: mult(pred.away.h2hMult), home: mult(pred.home.h2hMult))
        }
    }

    private func factorRow(_ label: String, away: String, home: String) -> some View {
        HStack {
            Text(label).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(away).font(Theme.Font.mono()).frame(width: 76)
            Text(home).font(Theme.Font.mono()).frame(width: 76)
        }
        .foregroundStyle(Theme.Palette.textPrimary)
    }

    private func goalieRow(_ team: TeamAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(team.info.abbrev) · \(team.goalie)")
                .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary)
            Text("GSAX \(signedNum(team.goalieGsax))  ·  SV% \(String(format: "%.3f", team.goalieSvPct))  ·  GAA \(String(format: "%.2f", team.goalieGaa))")
                .font(.system(size: 11)).foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Section scaffold

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Formatting

    private func rounded(_ v: Double) -> String { String(Int(v.rounded())) }
    private func trim(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
    private func signed(_ v: Double) -> String { (v > 0 ? "+" : "") + trim(v) }
    private func signedNum(_ v: Double) -> String { String(format: "%+.1f", v) }
    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
    private func mult(_ v: Double) -> String { String(format: "×%.3f", v) }
    private func pct(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))%" } ?? "—" }
}
