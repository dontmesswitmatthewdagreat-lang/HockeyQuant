import SwiftUI

/// Who a team actually plays together, and whether those combinations are more
/// than the sum of their parts.
///
/// Chemistry is the interesting column: a line can post a great share of the
/// chances simply by containing a star. The number here asks a harder question —
/// does the unit beat what its own members manage in their *other* minutes?
struct LineChemistryView: View {
    let team: String

    @State private var data: LineChemistryResponse?
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var segment = 0   // 0 = lines, 1 = pairs

    private let api = APIClient()
    private var color: Color { TeamInfo.lookup(team).color }

    var body: some View {
        ZStack {
            Theme.backgroundView()
            content
        }
        .navigationTitle("Line Chemistry")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading && data == nil {
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(0..<5, id: \.self) { _ in LoadingShimmer(height: 84) }
                }
                .padding(Theme.Spacing.md)
            }
        } else if let errorMessage, data == nil {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if let data, data.available, !(data.lines.isEmpty && data.pairs.isEmpty) {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    intro
                    BigSegment(selection: $segment, options: ["Forward lines", "D pairs"])
                    ForEach(Array(units.enumerated()), id: \.element.id) { index, unit in
                        unitCard(unit)
                            .staggeredEntrance(index: index)
                    }
                    if segment == 1 && !data.wowy.isEmpty { wowySection(data.wowy) }
                    footnote
                }
                .padding(Theme.Spacing.md)
            }
        } else {
            EmptyStateView(
                systemImage: "person.2.slash",
                title: "No combination data",
                message: "MoneyPuck publishes 5-on-5 line and pair data once a season is under way."
            )
        }
    }

    private var units: [LineUnit] {
        guard let data else { return [] }
        return segment == 0 ? data.lines : data.pairs
    }

    private var intro: some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                CrestView(abbrev: team, size: 36)
                Text("Combinations that played at least 100 minutes together at 5-on-5, most-used first.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - A line or pair

    private func unitCard(_ unit: LineUnit) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(unit.label)
                            .font(Theme.Font.headline())
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(2).minimumScaleFactor(0.8)
                        Text("\(unit.minutes) min · \(unit.gamesPlayed) games")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer(minLength: Theme.Spacing.xs)
                    if let chem = unit.chemistry { chemistryPill(chem) }
                }

                if let xgf = unit.xgfPct {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("SHARE OF EXPECTED GOALS")
                                .font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.5)
                                .foregroundStyle(Theme.Palette.textTertiary)
                            Spacer()
                            Text(String(format: "%.1f%%", xgf))
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(xgf >= 50 ? Theme.Palette.positive : Theme.Palette.negative)
                        }
                        // 50% is the break-even every one of these is judged against.
                        ProbBar(fraction: xgf / 100, tint: color, reference: 0.5)
                    }
                }

                HStack(spacing: Theme.Spacing.md) {
                    metric("xGF/60", String(format: "%.2f", unit.xgfPer60))
                    metric("xGA/60", String(format: "%.2f", unit.xgaPer60))
                    if let hd = unit.hdcfPct { metric("HD chances", String(format: "%.0f%%", hd)) }
                    metric("Finishing", signed(unit.finishing),
                           tint: unit.finishing >= 0 ? Theme.Palette.positive : Theme.Palette.negative)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chemistryPill(_ chem: Double) -> some View {
        let strong = abs(chem) >= 3
        let tint: Color = chem >= 0 ? Theme.Palette.positive : Theme.Palette.negative
        return VStack(spacing: 1) {
            Text(signed(chem))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(strong ? tint : Theme.Palette.textSecondary)
            Text("chemistry")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    private func metric(_ label: String, _ value: String,
                        tint: Color = Theme.Palette.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    // MARK: - With / Without

    private func wowySection(_ rows: [PairWowy]) -> some View {
        SectionCard("With / without") {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Each pair together, against how those same two do apart. Defence only — forwards get rotated through too many short-lived combinations for their apart minutes to mean anything.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textTertiary)
                ForEach(rows) { row in wowyRow(row) }
            }
        }
    }

    private func wowyRow(_ row: PairWowy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.players.map(\.lastName).joined(separator: " + "))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                StatusPill(text: row.lift >= 0 ? "+\(String(format: "%.1f", row.lift))"
                                               : String(format: "%.1f", row.lift),
                           systemImage: row.lift >= 0 ? "arrow.up" : "arrow.down",
                           color: row.lift >= 0 ? Theme.Palette.positive : Theme.Palette.negative)
            }
            togetherRow("Together", row.togetherXgfPct, row.togetherMinutes, emphasis: true)
            ForEach(row.players, id: \.playerId) { p in
                if let apart = p.apartXgfPct {
                    togetherRow("\(p.lastName) apart", apart, p.apartMinutes ?? 0, emphasis: false)
                }
            }
            Text("\(row.coverage)% of their ice time is accounted for by listed pairings.")
                .font(.system(size: 9))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(.bottom, 2)
    }

    private func togetherRow(_ label: String, _ pct: Double, _ minutes: Int,
                             emphasis: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(label)
                .font(.system(size: 11, weight: emphasis ? .heavy : .regular))
                .foregroundStyle(emphasis ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                .frame(width: 108, alignment: .leading)
            ProbBar(fraction: pct / 100,
                    tint: emphasis ? color : Theme.Palette.textTertiary.opacity(0.6),
                    reference: 0.5, height: emphasis ? 8 : 6)
            Text(String(format: "%.1f%%", pct))
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(pct >= 50 ? Theme.Palette.positive : Theme.Palette.negative)
                .frame(width: 44, alignment: .trailing)
            Text("\(minutes)m")
                .font(.system(size: 9))
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var footnote: some View {
        Text("Chemistry compares a unit to what its own members do in their other minutes. Those other minutes still include time with each other elsewhere, so read it as a lean, not a verdict.")
            .font(.system(size: 10))
            .foregroundStyle(Theme.Palette.textTertiary)
            .padding(.top, Theme.Spacing.xxs)
    }

    private func signed(_ v: Double) -> String {
        String(format: v >= 0 ? "+%.1f" : "%.1f", v)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            data = try await api.lineChemistry(team: team)
            errorMessage = nil
        } catch {
            Log.error("line chemistry", error)
            errorMessage = error.localizedDescription
        }
    }
}
