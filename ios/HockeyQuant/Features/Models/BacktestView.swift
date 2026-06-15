import SwiftUI
import Charts

/// Strategy backtester: toggle conditional rules and watch the official model's
/// historical hit rate, coverage, and accuracy curve recompute live — plus a
/// factor-signal importance panel (which signals actually predicted winners).
struct BacktestView: View {
    private let api = APIClient(environment: .production)
    @State private var data: BacktestData?
    @State private var loading = true

    // Rules
    @State private var minDiff = 0.0
    @State private var tiers: Set<String> = ["STRONG", "MODERATE", "CLOSE"]
    @State private var side = PickSide.any
    @State private var goalieAgree = false
    @State private var streakAgree = false
    @State private var h2hAgree = false
    @State private var rested = false

    private enum PickSide: String, CaseIterable { case any = "Any", home = "Home", away = "Away" }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                if loading {
                    ForEach(0..<3, id: \.self) { _ in LoadingShimmer(height: 130) }
                } else if let d = data {
                    rulesCard
                    resultCard(d)
                    factorCard(d)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Palette.background)
        .navigationTitle("Strategy Backtester")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            data = try? await api.backtestData()
            loading = false
        }
    }

    // MARK: - Filtering

    private func passes(_ g: BacktestGame) -> Bool {
        if g.diff < minDiff { return false }
        if !tiers.contains(g.confidence) { return false }
        if side == .home && !g.pickIsHome { return false }
        if side == .away && g.pickIsHome { return false }
        if goalieAgree && g.goalieEdge <= 0 { return false }
        if streakAgree && g.streakEdge <= 0 { return false }
        if h2hAgree && g.h2hEdge <= 0 { return false }
        if rested && g.pickFatigueMult < 0.99 { return false }
        return true
    }

    private func hitRate(_ games: [BacktestGame]) -> Double {
        games.isEmpty ? 0 : Double(games.filter { $0.correct }.count) / Double(games.count) * 100
    }

    // MARK: - Rules

    private var rulesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Strategy rules").font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)

                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text("Min confidence").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                        Spacer()
                        Text("diff ≥ \(minDiff, specifier: "%.0f")").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Slider(value: $minDiff, in: 0...20, step: 1).tint(Theme.Palette.accent)
                }

                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(["STRONG", "MODERATE", "CLOSE"], id: \.self) { t in
                        chip(t.capitalized, on: tiers.contains(t)) {
                            if tiers.contains(t) { tiers.remove(t) } else { tiers.insert(t) }
                        }
                    }
                }

                Picker("Pick side", selection: $side) {
                    ForEach(PickSide.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Theme.Spacing.xs)], alignment: .leading, spacing: Theme.Spacing.xs) {
                    chip("Goalie agrees", on: goalieAgree) { goalieAgree.toggle() }
                    chip("Form agrees", on: streakAgree) { streakAgree.toggle() }
                    chip("H2H agrees", on: h2hAgree) { h2hAgree.toggle() }
                    chip("Rested (no B2B)", on: rested) { rested.toggle() }
                }

                Button("Reset rules") {
                    minDiff = 0; tiers = ["STRONG", "MODERATE", "CLOSE"]; side = .any
                    goalieAgree = false; streakAgree = false; h2hAgree = false; rested = false
                }
                .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.accent)
            }
        }
    }

    private func chip(_ label: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(on ? Theme.Palette.accent.opacity(0.16) : Theme.Palette.surface)
                .foregroundStyle(on ? Theme.Palette.accent : Theme.Palette.textSecondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(on ? Theme.Palette.accent : Theme.Palette.border, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    // MARK: - Result

    private func resultCard(_ d: BacktestData) -> some View {
        let games = d.games.filter(passes)
        let hit = hitRate(games)
        let cover = d.count > 0 ? Double(games.count) / Double(d.count) * 100 : 0
        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(hit, specifier: "%.1f")%").font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(hit >= d.baseline ? Theme.Palette.strong : Theme.Palette.textPrimary)
                        Text("hit rate vs \(d.baseline, specifier: "%.1f")% baseline").font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(games.count)").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.Palette.textPrimary)
                        Text("of \(d.count) · \(cover, specifier: "%.0f")%").font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                if games.count >= 5 {
                    Chart {
                        RuleMark(y: .value("Baseline", d.baseline))
                            .foregroundStyle(Theme.Palette.textTertiary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        ForEach(Array(cumulative(games).enumerated()), id: \.offset) { i, pct in
                            LineMark(x: .value("Game", i + 1), y: .value("Accuracy", pct))
                                .foregroundStyle(Theme.Palette.accent)
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis { AxisMarks(values: [0, 50, 100]) }
                    .frame(height: 120)
                    Text("Cumulative accuracy over the \(games.count) matching games (chronological).")
                        .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                } else {
                    Text("Loosen the rules — too few games to chart.")
                        .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
    }

    private func cumulative(_ games: [BacktestGame]) -> [Double] {
        var c = 0
        return games.enumerated().map { i, g in
            if g.correct { c += 1 }
            return Double(c) / Double(i + 1) * 100
        }
    }

    // MARK: - Factor importance

    private func factorCard(_ d: BacktestData) -> some View {
        let factors = [
            ("Head-to-head", \BacktestGame.h2hEdge),
            ("Form / streak", \BacktestGame.streakEdge),
            ("Goalie", \BacktestGame.goalieEdge),
            ("Special teams", \BacktestGame.stEdge),
            ("Rest / fatigue", \BacktestGame.fatigueEdge),
        ]
        let stats = factors.map { (name, kp) -> (String, Double, Double, Int, Int) in
            let agree = d.games.filter { $0[keyPath: kp] > 0 }
            let dis = d.games.filter { $0[keyPath: kp] < 0 }
            return (name, hitRate(agree), hitRate(dis), agree.count, dis.count)
        }.sorted { abs($0.1 - $0.2) > abs($1.1 - $1.2) }

        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Signal strength").font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                Text("Hit rate when each factor agreed with the pick vs disagreed — bigger gap = more predictive.")
                    .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                ForEach(stats, id: \.0) { name, agree, dis, nA, nD in
                    VStack(spacing: 3) {
                        HStack {
                            Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.Palette.textPrimary)
                            Spacer()
                            Text("\(agree, specifier: "%.0f")% vs \(dis, specifier: "%.0f")%")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.Palette.textSecondary)
                            Text("+\(abs(agree - dis), specifier: "%.0f")")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(gapColor(abs(agree - dis)))
                                .frame(width: 30, alignment: .trailing)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.Palette.border)
                                Capsule().fill(gapColor(abs(agree - dis)))
                                    .frame(width: geo.size.width * CGFloat(min(abs(agree - dis) / 25, 1)))
                            }
                        }.frame(height: 4)
                    }
                }
            }
        }
    }

    private func gapColor(_ gap: Double) -> Color {
        gap >= 10 ? Theme.Palette.strong : (gap >= 4 ? Theme.Palette.accent : Theme.Palette.textTertiary)
    }
}
