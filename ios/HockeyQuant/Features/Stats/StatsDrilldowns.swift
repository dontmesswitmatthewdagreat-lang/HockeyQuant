import SwiftUI

// Drill-in destinations for the Statistics summary page: performance breakdown
// (confidence + bet types), daily parlay history, and the full recent results.

// MARK: - Breakdown (confidence + bet types)

struct BreakdownView: View {
    let stats: AccuracyStats

    /// The break‑even hit rate for a standard −110 bet.
    private let breakEven = 52.4

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    confidenceCard
                    betTypeCard
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle("Breakdown")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var confidenceCard: some View {
        SectionCard("By confidence") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                confidenceRow("Strong", pctVal: stats.strongPct, correct: stats.strongCorrect, total: stats.strongTotal, color: Theme.Palette.strong)
                confidenceRow("Moderate", pctVal: stats.moderatePct, correct: stats.moderateCorrect, total: stats.moderateTotal, color: Theme.Palette.moderate)
                confidenceRow("Close", pctVal: stats.closePct, correct: stats.closeCorrect, total: stats.closeTotal, color: Theme.Palette.close)
            }
        }
    }

    private func confidenceRow(_ label: String, pctVal: Double, correct: Int, total: Int, color: Color) -> some View {
        VStack(spacing: Theme.Spacing.xxs) {
            HStack {
                Text(label).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Text("\(correct)/\(total)  ·  \(pct(pctVal))")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
            }
            ProbBar(fraction: pctVal / 100, tint: color, height: 6)
        }
    }

    private var betTypeCard: some View {
        SectionCard("By bet type") {
            VStack(spacing: Theme.Spacing.md) {
                betTypeRow("Moneyline", stats.accuracyPct, stats.totalGames)
                betTypeRow("Puck line", stats.puckLinePct, stats.puckLineTotal)
                betTypeRow("Over / Under", stats.ouPct, stats.ouTotal)
            }
        }
    }

    private func betTypeRow(_ label: String, _ pctVal: Double, _ total: Int) -> some View {
        let hasData = total > 0
        let tint: Color = !hasData ? Theme.Palette.textTertiary
            : (pctVal >= breakEven ? Theme.Palette.positive
               : (pctVal >= 50 ? Theme.Palette.moderate : Theme.Palette.negative))
        return VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(label).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary)
                Text("\(total) bets").font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
                Spacer(minLength: 0)
                Text(hasData ? pct(pctVal) : "—")
                    .font(Theme.Font.statNumber()).foregroundStyle(Theme.Palette.textPrimary)
                betVerdict(pctVal, total)
            }
            ProbBar(fraction: pctVal / 100, tint: tint, reference: breakEven / 100, height: 7)
        }
    }

    private func betVerdict(_ pctVal: Double, _ total: Int) -> some View {
        if total == 0 { return AnyView(StatusPill(text: "No data", color: Theme.Palette.textTertiary)) }
        if pctVal >= breakEven {
            return AnyView(StatusPill(text: "Profitable", systemImage: "checkmark",
                                      color: Theme.Palette.positive, solid: pctVal >= 55))
        }
        if pctVal >= 50 { return AnyView(StatusPill(text: "Break-even", color: Theme.Palette.moderate)) }
        return AnyView(StatusPill(text: "Below", color: Theme.Palette.negative))
    }

    private func pct(_ value: Double) -> String { "\(Int(value.rounded()))%" }
}

// MARK: - Daily parlay

struct ParlayStatsView: View {
    let parlay: ParlayStats?

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    if let parlay, parlay.gradedParlays > 0 {
                        parlayCard(parlay)
                    } else {
                        EmptyStateView(
                            systemImage: "square.stack.3d.up",
                            title: "No graded parlays yet",
                            message: "The daily optimal parlay is tracked automatically — results show up here once parlays grade."
                        )
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle("Daily parlay")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func parlayCard(_ parlay: ParlayStats) -> some View {
        let pill = AnyView(StatusPill(text: "\(Int(parlay.hitPct.rounded()))% hit",
                                      color: parlay.hitPct >= 50 ? Theme.Palette.positive : Theme.Palette.textSecondary))
        return SectionCard("Daily parlay", accessory: pill) {
            VStack(spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    StatPill(label: "Hit rate", value: "\(Int(parlay.hitPct.rounded()))%")
                    Divider().frame(height: 32).overlay(Theme.Palette.border)
                    StatPill(label: "Hits", value: "\(parlay.hitCount)/\(parlay.gradedParlays)")
                    Divider().frame(height: 32).overlay(Theme.Palette.border)
                    StatPill(label: "Avg legs", value: String(format: "%.1f", parlay.avgLegs))
                }
                ProbBar(fraction: parlay.hitPct / 100, tint: Theme.Palette.accent, height: 7)
            }
        }
    }
}

// MARK: - Recent results (full list, bill-style rows)

struct RecentResultsView: View {
    let records: [PredictionRecord]

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    Card {
                        VStack(spacing: 0) {
                            ForEach(records) { record in
                                resultRow(record)
                                    .padding(.vertical, Theme.Spacing.xs)
                                if record.id != records.last?.id {
                                    Divider().overlay(Theme.Palette.border).padding(.leading, 64)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle("Recent results")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resultRow(_ record: PredictionRecord) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                CrestView(abbrev: record.awayTeam, size: 28).offset(x: -8)
                CrestView(abbrev: record.homeTeam, size: 28).offset(x: 8)
            }
            .frame(width: 48, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(record.awayTeam) @ \(record.homeTeam)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Pick: \(record.pick) · \(record.confidence.capitalized)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            if let af = record.awayFinal, let hf = record.homeFinal {
                Text("\(af)–\(hf)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            resultIcon(record.correct)
        }
    }

    private func resultIcon(_ correct: Bool?) -> some View {
        Group {
            switch correct {
            case .some(true):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.positive)
            case .some(false):
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Palette.negative)
            case .none:
                Image(systemName: "clock").foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .font(.system(size: 16))
    }
}

// MARK: - Calibration drill-in

struct CalibrationDetailView: View {
    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    CalibrationCard()
                    Text("Dots above the dashed line = the model wins more often than it predicted; below = overconfident. Bigger dots = more games in that bucket.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.horizontal, Theme.Spacing.xs)
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle("Calibration")
        .navigationBarTitleDisplayMode(.inline)
    }
}
