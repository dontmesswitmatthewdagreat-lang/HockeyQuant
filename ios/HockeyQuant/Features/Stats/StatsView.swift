import SwiftUI
import Charts

/// Accuracy dashboard: headline hit rate, the rolling/cumulative trend chart,
/// confidence + bet-type breakdowns, parlay stats, and recent results.
struct StatsView: View {
    @State private var model = StatsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundView().ignoresSafeArea()
                content
            }
            .navigationTitle("Statistics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        TeamsView()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.3.fill")
                            Text("Teams")
                        }
                        .font(Theme.Font.caption())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { AvatarButton() }
            }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(0..<4, id: \.self) { _ in LoadingShimmer(height: 140) }
                }
                .padding(Theme.Spacing.md)
            }
        case .error(let message):
            ErrorStateView(message: message) { Task { await model.load() } }
        case .loaded:
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    modelBadge
                    if let stats = model.stats {
                        headlineCard(stats)
                        trendCard
                        confidenceCard(stats)
                        CalibrationCard()
                        betTypeCard(stats)
                    }
                    if let parlay = model.parlay, parlay.gradedParlays > 0 {
                        parlayCard(parlay)
                    }
                    if !model.recent.isEmpty {
                        recentCard
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .refreshable { await model.load() }
        }
    }

    // MARK: - Official model badge

    private var modelBadge: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.accent)
            Text("Generated & tracked by the official HockeyQuant model")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Palette.accent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }

    // MARK: - Headline

    private func headlineCard(_ stats: AccuracyStats) -> some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                Text("MONEYLINE ACCURACY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text("\(pct(stats.allTime?.pct ?? stats.accuracyPct))")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.accent)
                Text("\(stats.allTime?.correct ?? stats.correctPicks) of \(stats.allTime?.total ?? stats.totalGames) correct")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
                HStack(spacing: Theme.Spacing.sm) {
                    miniStat("Last 30", stats.rolling30)
                    Divider().frame(height: 32).overlay(Theme.Palette.border)
                    miniStat("Season", stats.currentSeason)
                    Divider().frame(height: 32).overlay(Theme.Palette.border)
                    miniStat("All-time", stats.allTime)
                }
                .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    private func miniStat(_ label: String, _ window: WindowStats?) -> some View {
        VStack(spacing: 2) {
            Text(window.map { pct($0.pct) } ?? "—")
                .font(Theme.Font.statNumber())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(label)
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Trend chart

    private var trendCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    sectionHeader("Accuracy trend")
                    Spacer()
                    Picker("Window", selection: Binding(
                        get: { model.window },
                        set: { model.window = $0 }
                    )) {
                        ForEach([10, 20, 30, 50], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                if model.trend.count < 2 {
                    Text("Not enough graded games yet to chart a trend.")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Theme.Spacing.md)
                } else {
                    chart
                    legend
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            RuleMark(y: .value("Even", 50))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Theme.Palette.textTertiary.opacity(0.5))
            ForEach(chartPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Rolling", point.rolling),
                    series: .value("Series", "Rolling")
                )
                .foregroundStyle(Theme.Palette.accent)
                .interpolationMethod(.catmullRom)
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Cumulative", point.cumulative),
                    series: .value("Series", "Cumulative")
                )
                .foregroundStyle(Theme.Palette.accentAlt)
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine().foregroundStyle(Theme.Palette.border)
                AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)%") } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.Palette.border.opacity(0.5))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 200)
    }

    private var legend: some View {
        HStack(spacing: Theme.Spacing.md) {
            legendDot(Theme.Palette.accent, "Rolling \(model.window)")
            legendDot(Theme.Palette.accentAlt, "Cumulative")
        }
        .font(Theme.Font.caption())
        .foregroundStyle(Theme.Palette.textSecondary)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let rolling: Double
        let cumulative: Double
    }

    private var chartPoints: [ChartPoint] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return model.trend.compactMap { point in
            guard let date = formatter.date(from: point.date) else { return nil }
            return ChartPoint(date: date, rolling: point.rollingAccuracy, cumulative: point.cumulativeAccuracy)
        }
    }

    // MARK: - Confidence breakdown

    private func confidenceCard(_ stats: AccuracyStats) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionHeader("By confidence")
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
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.background)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * CGFloat(min(max(pctVal, 0), 100) / 100))
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Bet types

    private func betTypeCard(_ stats: AccuracyStats) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionHeader("By bet type")
                HStack(spacing: Theme.Spacing.sm) {
                    betTypePill("Moneyline", pctVal: stats.accuracyPct, total: stats.totalGames)
                    Divider().frame(height: 40).overlay(Theme.Palette.border)
                    betTypePill("Puck line", pctVal: stats.puckLinePct, total: stats.puckLineTotal)
                    Divider().frame(height: 40).overlay(Theme.Palette.border)
                    betTypePill("Over/Under", pctVal: stats.ouPct, total: stats.ouTotal)
                }
            }
        }
    }

    private func betTypePill(_ label: String, pctVal: Double, total: Int) -> some View {
        VStack(spacing: 2) {
            Text(total > 0 ? pct(pctVal) : "—")
                .font(Theme.Font.statNumber())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(label).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
            Text("\(total) bets").font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Parlay

    private func parlayCard(_ parlay: ParlayStats) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionHeader("Daily parlay")
                HStack(spacing: Theme.Spacing.sm) {
                    StatPill(label: "Hit rate", value: pct(parlay.hitPct))
                    Divider().frame(height: 32).overlay(Theme.Palette.border)
                    StatPill(label: "Hits", value: "\(parlay.hitCount)/\(parlay.gradedParlays)")
                    Divider().frame(height: 32).overlay(Theme.Palette.border)
                    StatPill(label: "Avg legs", value: String(format: "%.1f", parlay.avgLegs))
                }
            }
        }
    }

    // MARK: - Recent results

    private var recentCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionHeader("Recent results")
                ForEach(model.recent.prefix(12)) { record in
                    recentRow(record)
                    if record.id != model.recent.prefix(12).last?.id {
                        Divider().overlay(Theme.Palette.border)
                    }
                }
            }
        }
    }

    private func recentRow(_ record: PredictionRecord) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            resultIcon(record.correct)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(record.awayTeam) @ \(record.homeTeam)")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Pick: \(record.pick) · \(record.confidence.capitalized)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer()
            if let af = record.awayFinal, let hf = record.homeFinal {
                Text("\(af)–\(hf)").font(Theme.Font.mono()).foregroundStyle(Theme.Palette.textSecondary)
            } else {
                Text("—").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
            }
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

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.Palette.textTertiary)
    }

    private func pct(_ value: Double) -> String { "\(Int(value.rounded()))%" }
}
