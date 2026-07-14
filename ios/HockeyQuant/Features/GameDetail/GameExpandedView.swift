import SwiftUI

/// The hero-expanded full breakdown for a game. Reached by tapping a Schedule
/// tile (it morphs up from the tile). Leads with the live scoreline grid, then
/// the shot map, then win prob / betting lines, the deterministic Edge breakdown,
/// and the quality-score factors. Live games keep the grid + shot map current.
struct GameExpandedView: View {
    let game: ScheduleGame
    let dateString: String
    let onClose: () -> Void

    @Environment(AuthStore.self) private var auth
    @State private var containerWidth: CGFloat = 0
    @State private var boardPicks: [ModelBoardPick] = []
    @State private var boardLoading = false
    @State private var boardLoaded = false

    private var pred: GamePrediction { game.prediction }
    private var away: TeamInfo { pred.away.info }
    private var home: TeamInfo { pred.home.info }
    private var score: GameScore? { game.score }
    private var active: Bool { game.isLive || game.isFinal }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                headerBar
                if boardLoading || !boardPicks.isEmpty {
                    SectionCard("Model board") { modelBoard }
                }
                if pred.bettingLines != nil {
                    SectionCard("Scoreline grid") { scorelineGrid }
                }
                SectionCard("Shot map") {
                    ShotMapView(date: dateString, away: pred.away.team, home: pred.home.team)
                }
                SectionCard("The Edge") { EdgeBreakdownView(game: pred) }
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
        .task { await loadBoard() }
    }

    // MARK: - Model board

    /// The user's own models weighing in next to the official call.
    private func loadBoard() async {
        guard !boardLoaded, let token = await auth.accessToken() else { return }
        boardLoaded = true
        boardLoading = true
        defer { boardLoading = false }
        boardPicks = (try? await APIClient(environment: .production).modelGameBoard(
            date: dateString, away: pred.away.team, home: pred.home.team, token: token)) ?? []
    }

    private var modelBoard: some View {
        VStack(spacing: Theme.Spacing.sm) {
            boardRow(name: "HockeyQuant Official", typeLabel: "OFFICIAL MODEL",
                     pick: pred.pick, confidence: pred.confidence)
            if boardLoading {
                HStack(spacing: Theme.Spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Running your models…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(boardPicks) { p in
                boardRow(name: p.name, typeLabel: p.typeLabel,
                         pick: p.pick, confidence: p.confidence ?? "CLOSE")
            }
        }
    }

    private func boardRow(name: String, typeLabel: String,
                          pick: String, confidence: String) -> some View {
        let hit: Bool? = winnerAbbrev.map { $0 == pick.uppercased() }
        return HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text(typeLabel)
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(0.6)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            CrestView(abbrev: pick, size: 24)
                .overlay {
                    if hit == true {
                        Circle().strokeBorder(Theme.Palette.positive, lineWidth: 1.5)
                            .frame(width: 29, height: 29)
                    }
                }
            Text(pick)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(hit == nil ? Theme.Palette.textPrimary
                                 : hit! ? Theme.Palette.positive : Theme.Palette.textTertiary)
                .frame(width: 38, alignment: .leading)
            ConfidenceChip(confidence: confidence)
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

    /// Final games ring the winner's crest in green.
    private var winnerAbbrev: String? {
        guard game.isFinal, let s = score else { return nil }
        return (s.homeScore > s.awayScore ? pred.home.team : pred.away.team).uppercased()
    }

    private func teamBadge(_ team: TeamAnalysis, isPick: Bool) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            CrestView(abbrev: team.team, size: 48)
                .overlay {
                    if winnerAbbrev == team.team.uppercased() {
                        Circle()
                            .strokeBorder(Theme.Palette.positive, lineWidth: 2.5)
                            .frame(width: 57, height: 57)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isPick && !game.isFinal {
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
            SectionCard("Betting lines") {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    moneylineBlock(lines)
                    puckLineBlock(lines)
                    totalBlock(lines)
                    Divider().overlay(Theme.Palette.border)
                    bestRow("Best spread", "\(signed(lines.optimalSpread)) \(lines.optimalSpreadSide)", lines.optimalSpreadProb)
                    bestRow("Best total", "\(lines.optimalTotalRec) \(trim(lines.optimalTotal))", lines.optimalTotalProb)
                }
            }
        }
    }

    /// A titled betting line: small header + optional verdict badge, then content.
    private func lineBlock<C: View>(_ title: String, badge: AnyView? = nil,
                                    @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                Spacer(minLength: 0)
                badge
            }
            content()
        }
    }

    private func moneylineBlock(_ l: BettingLines) -> some View {
        let aw = l.mlAwayProb ?? 0, hw = l.mlHomeProb ?? 0
        let total = max(aw + hw, 1)
        let badge: AnyView = abs(aw - hw) < 3
            ? AnyView(StatusPill(text: "Coin flip", color: Theme.Palette.textTertiary))
            : AnyView(StatusPill(text: "\(hw >= aw ? home.abbrev : away.abbrev) ML",
                                 color: hw >= aw ? home.color : away.color))
        return lineBlock("Moneyline · regulation", badge: badge) {
            VStack(spacing: 6) {
                SplitBar(leftFraction: aw / total, leftColor: away.color, rightColor: home.color)
                HStack {
                    Text("\(away.abbrev) \(pct(l.mlAwayProb))")
                    Spacer()
                    Text("\(pct(l.mlHomeProb)) \(home.abbrev)")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private func puckLineBlock(_ l: BettingLines) -> some View {
        let cover = l.puckLineHomeCoverProb
        let badge: AnyView = cover >= 55
            ? AnyView(StatusPill(text: "Cover edge", systemImage: "checkmark", color: Theme.Palette.positive))
            : (cover <= 45 ? AnyView(StatusPill(text: "No cover", color: Theme.Palette.negative))
                           : AnyView(StatusPill(text: "Toss-up", color: Theme.Palette.textTertiary)))
        return lineBlock("Puck line · \(l.puckLineSource)", badge: badge) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("\(home.abbrev) \(signed(l.puckLine))")
                    .font(Theme.Font.mono())
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(width: 82, alignment: .leading)
                ProbBar(fraction: cover / 100, tint: home.color)
                Text("cover \(pct(cover))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: 76, alignment: .trailing)
            }
        }
    }

    private func totalBlock(_ l: BettingLines) -> some View {
        let ov = l.overProb, un = l.underProb
        let total = max(ov + un, 1)
        let badge: AnyView = abs(ov - un) < 4
            ? AnyView(StatusPill(text: "Even", color: Theme.Palette.textTertiary))
            : AnyView(StatusPill(text: ov > un ? "Over lean" : "Under lean",
                                 systemImage: ov > un ? "arrow.up" : "arrow.down",
                                 color: ov > un ? Theme.Palette.moderate : Theme.Palette.accentAlt))
        return lineBlock("Total · \(l.overUnderSource)", badge: badge) {
            VStack(spacing: 6) {
                SplitBar(leftFraction: ov / total, leftColor: Theme.Palette.moderate, rightColor: Theme.Palette.accentAlt)
                HStack {
                    Text("O \(pct(ov)) · \(trim(l.overUnder))")
                    Spacer()
                    Text("\(pct(un)) U")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private func bestRow(_ label: String, _ value: String, _ prob: Double) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(label).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 90, alignment: .leading)
            Text(value).font(Theme.Font.mono()).foregroundStyle(Theme.Palette.textPrimary)
            Spacer(minLength: 0)
            StatusPill(text: pct(prob), color: Theme.Palette.accent, solid: prob >= 58)
        }
    }

    // MARK: - Factors

    private var factorsCard: some View {
        let a = pred.away, h = pred.home
        let leaderHome = h.finalScore >= a.finalScore
        let leader = AnyView(StatusPill(
            text: "\(leaderHome ? home.abbrev : away.abbrev) +\(fmt(abs(a.finalScore - h.finalScore)))",
            color: leaderHome ? home.color : away.color, solid: true))
        return SectionCard("Quality score", accessory: leader) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                scoreCompare(a, h)
                Divider().overlay(Theme.Palette.border)
                multiplierGrid(a, h)
                Divider().overlay(Theme.Palette.border)
                goalieRow(pred.away)
                goalieRow(pred.home)
            }
        }
    }

    // Base → Final headline, one column per team.
    private func scoreCompare(_ a: TeamAnalysis, _ h: TeamAnalysis) -> some View {
        HStack(alignment: .top) {
            scoreColumn(away.abbrev, base: a.baseScore, final: a.finalScore, color: away.color, alignment: .leading)
            Spacer(minLength: 0)
            scoreColumn(home.abbrev, base: h.baseScore, final: h.finalScore, color: home.color, alignment: .trailing)
        }
    }

    private func scoreColumn(_ abbrev: String, base: Double, final: Double,
                             color: Color, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(abbrev).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(color)
            Text(fmt(final)).font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("base \(fmt(base))").font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    // Each score multiplier as a boost/drag gauge centered at ×1.00.
    private func multiplierGrid(_ a: TeamAnalysis, _ h: TeamAnalysis) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Text("MULTIPLIERS").frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text(away.abbrev).foregroundStyle(away.color).frame(width: 88, alignment: .leading)
                Text(home.abbrev).foregroundStyle(home.color).frame(width: 88, alignment: .leading)
            }
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            multRow("Fatigue", a.fatigueMult, h.fatigueMult)
            multRow("Streak", a.streakMult, h.streakMult)
            multRow("Special teams", a.stMult, h.stMult)
            multRow("Injuries", a.injuryMult, h.injuryMult)
            multRow("Head-to-head", a.h2hMult, h.h2hMult)
        }
    }

    private func multRow(_ label: String, _ av: Double, _ hv: Double) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(label).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            gaugeCell(av)
            gaugeCell(hv)
        }
    }

    private func gaugeCell(_ v: Double) -> some View {
        // Color by the *displayed* (2‑decimal) value so a ×1.00 never reads red/green.
        let shown = (v * 100).rounded()
        let tone: Color = shown > 100 ? Theme.Palette.positive
            : (shown < 100 ? Theme.Palette.negative : Theme.Palette.textSecondary)
        return HStack(spacing: 5) {
            MultiplierGauge(value: v).frame(width: 38)
            Text(String(format: "×%.2f", v))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(tone)
        }
        .frame(width: 88, alignment: .leading)
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

    // MARK: - Formatting

    private func rounded(_ v: Double) -> String { String(Int(v.rounded())) }
    private func trim(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
    private func signed(_ v: Double) -> String { (v > 0 ? "+" : "") + trim(v) }
    private func signedNum(_ v: Double) -> String { String(format: "%+.1f", v) }
    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
    private func pct(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))%" } ?? "—" }
}
