import SwiftUI
import Charts

/// Statistics as a summary-first dashboard: an accuracy hero (switchable between
/// the official model and your custom models), the trend chart, a Teams browser
/// (tap a crest → full team + player stats), and grouped drill-in rows for the
/// deep dives (calibration, breakdown, parlay, recent results).
struct StatsView: View {
    @Environment(AuthStore.self) private var auth
    @State private var model = StatsViewModel()

    // Model-accuracy selector: nil = the official HockeyQuant model.
    @State private var userModels: [UserModel] = []
    @State private var selectedModelId: String?
    @State private var segment = 0   // 0 = Overview, 1 = Teams
    private let api = APIClient()

    private var selectedModel: UserModel? {
        selectedModelId.flatMap { id in userModels.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundView().ignoresSafeArea()
                content
            }
            // The curved hero band carries the top controls (avatar).
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await model.load() }
        .task(id: auth.isSignedIn) {
            guard auth.isSignedIn, let token = await auth.accessToken() else { return }
            userModels = (try? await api.models(token: token)) ?? []
        }
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
                VStack(spacing: Theme.Spacing.lg) {
                    statsBand   // full-bleed curved header
                    VStack(spacing: Theme.Spacing.lg) {
                        BigSegment(selection: $segment, options: ["Overview", "Teams"])
                        ZStack {
                            if segment == 0 {
                                overviewSegment.transition(.opacity)
                            } else {
                                teamsSection.transition(.opacity)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
                .padding(.bottom, Theme.Spacing.md)
            }
            .refreshable { await model.load() }
        }
    }

    // MARK: - Hero band (curved header)

    private var statsBand: some View {
        HeroBand(tint: Theme.Palette.accent) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack { Spacer(); AvatarButton() }
                Text("Statistics")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
                Text("Every pick tracked, graded & scored honestly")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var overviewSegment: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.md) {
                if let stats = model.stats {
                    heroCard(stats)
                }
                if selectedModel == nil {
                    trendCard
                }
            }
            deepDivesSection
        }
    }

    // MARK: - Hero (accuracy + model selector)

    private func heroCard(_ stats: AccuracyStats) -> some View {
        SectionCard("Moneyline accuracy", accessory: AnyView(modelMenu)) {
            if let m = selectedModel {
                customModelHero(m)
            } else {
                officialHero(stats)
            }
        }
    }

    /// Selector between the official model and the user's custom models.
    @ViewBuilder private var modelMenu: some View {
        if userModels.isEmpty {
            StatusPill(text: "Official model", color: Theme.Palette.accent)
        } else {
            Menu {
                Button {
                    selectedModelId = nil
                } label: {
                    Label("Official model", systemImage: selectedModelId == nil ? "checkmark" : "seal")
                }
                ForEach(userModels) { m in
                    Button {
                        selectedModelId = m.id
                    } label: {
                        Label(m.name, systemImage: selectedModelId == m.id ? "checkmark" : "slider.horizontal.3")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedModel?.name ?? "Official model").lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .heavy))
                }
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.accent)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Theme.Palette.accent.opacity(0.14))
                .clipShape(Capsule())
            }
        }
    }

    private func officialHero(_ stats: AccuracyStats) -> some View {
        let acc = stats.allTime?.pct ?? stats.accuracyPct
        let correct = stats.allTime?.correct ?? stats.correctPicks
        let total = stats.allTime?.total ?? stats.totalGames
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pct(acc))
                        .font(.system(size: 48, weight: .heavy))
                        .foregroundStyle(Theme.Palette.accent)
                    Text("\(correct) of \(total) correct")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textSecondary)
                    accuracyVerdict(acc)
                }
                Spacer()
                if cumulativeSpark.count > 1 {
                    Sparkline(values: cumulativeSpark, tint: sparkTint)
                        .frame(width: 128, height: 46)
                }
            }
            Divider().overlay(Theme.Palette.border)
            HStack(spacing: Theme.Spacing.sm) {
                miniStat("Last 30", stats.rolling30?.pct)
                Divider().frame(height: 32).overlay(Theme.Palette.border)
                miniStat("Season", stats.currentSeason?.pct)
                Divider().frame(height: 32).overlay(Theme.Palette.border)
                miniStat("All-time", stats.allTime?.pct)
            }
        }
    }

    private func customModelHero(_ m: UserModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let acc = m.accuracy, acc.totalPredictions > 0 {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pct(acc.accuracyPct))
                            .font(.system(size: 48, weight: .heavy))
                            .foregroundStyle(Theme.Palette.accent)
                        Text("\(acc.correctPredictions) of \(acc.totalPredictions) correct")
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Palette.textSecondary)
                        accuracyVerdict(acc.accuracyPct)
                    }
                    Spacer()
                }
                Divider().overlay(Theme.Palette.border)
                HStack(spacing: Theme.Spacing.sm) {
                    miniStat("Strong", confPct(acc.strongCorrect, acc.strongTotal))
                    Divider().frame(height: 32).overlay(Theme.Palette.border)
                    miniStat("Moderate", confPct(acc.moderateCorrect, acc.moderateTotal))
                    Divider().frame(height: 32).overlay(Theme.Palette.border)
                    miniStat("Close", confPct(acc.closeCorrect, acc.closeTotal))
                }
            } else {
                Text("No graded picks yet — this model's accuracy shows up once its official predictions grade.")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.vertical, Theme.Spacing.sm)
            }
        }
    }

    private func confPct(_ correct: Int, _ total: Int) -> Double? {
        total > 0 ? Double(correct) / Double(total) * 100 : nil
    }

    private func accuracyVerdict(_ acc: Double) -> some View {
        let d = acc - 50
        if d >= 2 { return AnyView(StatusPill(text: "+\(Int(d.rounded())) vs even",
                                              color: Theme.Palette.positive, solid: d >= 8)) }
        if d <= -2 { return AnyView(StatusPill(text: "\(Int(d.rounded())) vs even", color: Theme.Palette.negative)) }
        return AnyView(StatusPill(text: "Coin flip", color: Theme.Palette.textTertiary))
    }

    /// Cumulative accuracy series for the hero sparkline + its up/down tint.
    private var cumulativeSpark: [Double] { model.trend.map(\.cumulativeAccuracy) }
    private var sparkTint: Color {
        guard let f = cumulativeSpark.first, let l = cumulativeSpark.last else { return Theme.Palette.accent }
        return l >= f ? Theme.Palette.positive : Theme.Palette.negative
    }

    private func miniStat(_ label: String, _ value: Double?) -> some View {
        VStack(spacing: 2) {
            Text(value.map { pct($0) } ?? "—")
                .font(Theme.Font.statNumber())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(label)
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Trend chart (official model)

    private var trendCard: some View {
        SectionCard("Accuracy trend", accessory: AnyView(windowPicker)) {
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

    private var windowPicker: some View {
        Picker("Window", selection: Binding(get: { model.window }, set: { model.window = $0 })) {
            ForEach([10, 20, 30, 50], id: \.self) { Text("\($0)").tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: 148)
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

    // MARK: - Teams browser

    private let teamColumns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 6)
    private var teamAbbrevs: [String] { TeamInfo.all.keys.sorted() }

    private var teamsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel("Teams") {
                NavigationLink { TeamsView() } label: {
                    HStack(spacing: 3) {
                        Text("All")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.accent)
                }
            }
            Card {
                LazyVGrid(columns: teamColumns, spacing: Theme.Spacing.sm) {
                    ForEach(teamAbbrevs, id: \.self) { abbrev in
                        NavigationLink { TeamDetailView(abbrev: abbrev) } label: {
                            VStack(spacing: 3) {
                                CrestView(abbrev: abbrev, size: 36)
                                Text(abbrev)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Deep dives (drill-in rows)

    private var deepDivesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel("Deep Dives")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    NavigationLink { CalibrationDetailView() } label: {
                        ModeRow(icon: "scope", tint: Theme.Palette.accent, title: "Calibration",
                                subtitle: "When it says X%, does X% happen?")
                    }
                    .buttonStyle(.plain)
                    rowDivider
                    if let stats = model.stats {
                        NavigationLink { BreakdownView(stats: stats) } label: {
                            ModeRow(icon: "chart.bar.fill", tint: Theme.Palette.accentAlt, title: "Breakdown",
                                    subtitle: "By confidence & bet type",
                                    value: pct(stats.accuracyPct))
                        }
                        .buttonStyle(.plain)
                        rowDivider
                    }
                    NavigationLink { ParlayStatsView(parlay: model.parlay) } label: {
                        ModeRow(icon: "square.stack.3d.up.fill", tint: Theme.Palette.moderate, title: "Daily parlay",
                                subtitle: "The optimizer's track record",
                                value: model.parlay.map { "\(Int($0.hitPct.rounded()))%" })
                    }
                    .buttonStyle(.plain)
                    rowDivider
                    NavigationLink { RecentResultsView(records: model.recent) } label: {
                        ModeRow(icon: "clock.arrow.circlepath", tint: Theme.Palette.positive, title: "Recent results",
                                subtitle: "Every graded pick, latest first",
                                value: "\(model.recent.count)")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, Theme.Spacing.xxs)
            }
        }
    }

    private var rowDivider: some View {
        Divider().overlay(Theme.Palette.border).padding(.leading, 66)
    }

    // MARK: - Helpers

    private func pct(_ value: Double) -> String { "\(Int(value.rounded()))%" }
}
