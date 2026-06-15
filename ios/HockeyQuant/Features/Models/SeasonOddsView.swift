import SwiftUI

/// Season & playoff odds. Default shows the live/postseason picture (right now: a
/// playoff Cup-odds view); a "Demo" toggle runs a full mock-season projection.
struct SeasonOddsView: View {
    private let api = APIClient(environment: .production)

    @State private var demo = false
    @State private var result: SeasonProjection?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                Toggle("Demo: full-season projection", isOn: $demo)
                    .font(Theme.Font.caption()).tint(Theme.Palette.accent)
                    .padding(.horizontal, Theme.Spacing.xs)

                if loading {
                    VStack(spacing: Theme.Spacing.sm) {
                        ProgressView().tint(Theme.Palette.accent)
                        Text("Simulating thousands of seasons…").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.xl)
                } else if let r = result {
                    if r.mode == "playoffs" { playoffView(r) } else { seasonView(r) }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Palette.background)
        .navigationTitle("Season & Playoff Odds")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: demo) { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        result = try? await api.seasonSim(mock: demo)
    }

    // MARK: - Season mode

    @ViewBuilder
    private func seasonView(_ r: SeasonProjection) -> some View {
        ForEach(["Eastern", "Western"], id: \.self) { conf in
            let teams = r.teams.filter { $0.conference == conf }.sorted {
                ($0.playoffPct ?? 0, $0.projPoints ?? 0) > ($1.playoffPct ?? 0, $1.projPoints ?? 0)
            }
            if !teams.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(conf.uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.accent)
                        ForEach(Array(teams.enumerated()), id: \.element.id) { i, t in
                            seasonRow(t, rank: i + 1)
                            if i < teams.count - 1 { Divider().background(Theme.Palette.border) }
                        }
                    }
                }
            }
        }
        Text("Projected from current team strength ratings.")
            .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
    }

    private func seasonRow(_ t: ProjectedTeam, rank: Int) -> some View {
        let madePlayoffs = rank <= 8
        return HStack(spacing: Theme.Spacing.sm) {
            CrestView(abbrev: t.team, size: 24).opacity(madePlayoffs ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.team).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.Palette.textPrimary)
                bar(t.playoffPct ?? 0)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int((t.projPoints ?? 0).rounded()))").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.textPrimary)
                Text("PTS").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
            }
            .frame(width: 36)
            stat("\(Int((t.playoffPct ?? 0).rounded()))%", "PLAYOFF")
            stat(t.cupPct >= 0.05 ? String(format: "%.0f%%", t.cupPct) : "—", "CUP")
        }
        .padding(.vertical, 3)
    }

    private func bar(_ pct: Double) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.border)
                Capsule().fill(Theme.Palette.accent).frame(width: g.size.width * CGFloat(pct / 100))
            }
        }
        .frame(height: 4)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.Palette.textPrimary)
            Text(label).font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(width: 46)
    }

    // MARK: - Playoff mode

    @ViewBuilder
    private func playoffView(_ r: SeasonProjection) -> some View {
        if let series = r.series, !series.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("ACTIVE SERIES").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.accent)
                    ForEach(series) { s in seriesRow(s) }
                }
            }
        }
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("CUP ODDS").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.accent)
                ForEach(r.teams) { t in
                    HStack(spacing: Theme.Spacing.sm) {
                        CrestView(abbrev: t.team, size: 24)
                        Text(t.team).font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                        Spacer()
                        Text("\(t.cupPct, specifier: "%.0f")%").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.accent)
                    }
                }
            }
        }
        Text("Win probability of the remaining best-of-7 series.")
            .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
    }

    private func seriesRow(_ s: SeriesOdds) -> some View {
        VStack(spacing: 4) {
            HStack {
                HStack(spacing: 5) { CrestView(abbrev: s.away, size: 22); Text(s.away).font(.system(size: 13, weight: .bold)) }
                Spacer()
                HStack(spacing: 5) { Text(s.home).font(.system(size: 13, weight: .bold)); CrestView(abbrev: s.home, size: 22) }
            }
            .foregroundStyle(Theme.Palette.textPrimary)
            WinProbBar(awayProb: s.awayPct, homeProb: s.homePct, awayColor: TeamInfo.lookup(s.away).color, homeColor: TeamInfo.lookup(s.home).color)
            HStack {
                Text("\(Int(s.awayPct.rounded()))%").font(Theme.Font.caption())
                Spacer()
                Text("\(Int(s.homePct.rounded()))%").font(Theme.Font.caption())
            }
            .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
