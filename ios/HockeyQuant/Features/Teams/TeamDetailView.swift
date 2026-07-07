import SwiftUI

/// Detailed team view: standings, advanced analytics, players, goalies, injuries.
struct TeamDetailView: View {
    @State private var model: TeamDetailViewModel
    @State private var skaters: [SkaterStats] = []
    @State private var showAllSkaters = false
    private let api = APIClient()

    init(abbrev: String) {
        _model = State(initialValue: TeamDetailViewModel(abbrev: abbrev))
    }

    private var info: TeamInfo { TeamInfo.lookup(model.abbrev) }

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            content
        }
        .navigationTitle(info.abbrev)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        // Player stats load separately (best-effort) so the page never blocks on them.
        .task { skaters = (try? await api.skaters(team: model.abbrev)) ?? [] }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(0..<4, id: \.self) { _ in LoadingShimmer(height: 120) }
                }
                .padding(Theme.Spacing.md)
            }
        case .error(let message):
            ErrorStateView(message: message) { Task { await model.load() } }
        case .loaded(let detail):
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    headerCard(detail)
                    standingsCard(detail.stats)
                    if let advanced = detail.advancedStats {
                        advancedCard(advanced)
                    }
                    if !skaters.isEmpty {
                        playersCard
                    }
                    if !detail.goalies.isEmpty {
                        goaliesCard(detail.goalies)
                    }
                    shotMapCard
                    if !detail.injuries.isEmpty {
                        injuriesCard(detail.injuries)
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
    }

    private var shotMapCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("SHOT MAP · RECENT GAMES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                TeamShotMapView(team: model.abbrev)
            }
        }
    }

    // MARK: - Header

    private func headerCard(_ detail: TeamDetailResponse) -> some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                CrestView(abbrev: model.abbrev, size: 72)
                Text(detail.team.name)
                    .font(Theme.Font.title())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("\(detail.team.division) · \(detail.team.conference)")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
                HStack(spacing: Theme.Spacing.sm) {
                    StatPill(label: "Record", value: "\(detail.stats.wins)-\(detail.stats.losses)-\(detail.stats.otl)")
                    Divider().frame(height: 32).overlay(Theme.Palette.border)
                    StatPill(label: "Points", value: "\(detail.stats.points)")
                    Divider().frame(height: 32).overlay(Theme.Palette.border)
                    StatPill(label: "Pts %", value: String(format: "%.3f", detail.stats.pointsPct))
                }
                if !detail.recentForm.isEmpty {
                    Text(detail.recentForm)
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
    }

    // MARK: - Standings

    private func standingsCard(_ stats: TeamStandingStats) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionHeader("Scoring")
                HStack(spacing: Theme.Spacing.sm) {
                    StatPill(label: "Goals for", value: "\(stats.goalsFor)")
                    StatPill(label: "Goals against", value: "\(stats.goalsAgainst)")
                    StatPill(label: "Diff", value: signedInt(stats.goalDiff))
                }
                if let xgf = stats.xgf, let xga = stats.xga {
                    Divider().overlay(Theme.Palette.border)
                    HStack(spacing: Theme.Spacing.sm) {
                        StatPill(label: "xGF", value: String(format: "%.1f", xgf))
                        StatPill(label: "xGA", value: String(format: "%.1f", xga))
                        StatPill(label: "xG diff", value: signed(xgf - xga))
                    }
                }
            }
        }
    }

    // MARK: - Advanced

    private func advancedCard(_ a: AdvancedStats) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionHeader("Advanced (\(a.gamesPlayed) GP)")
                HStack(spacing: Theme.Spacing.sm) {
                    StatPill(label: "xG%", value: pct(a.xgPct))
                    StatPill(label: "Corsi%", value: pct(a.corsiPct))
                    StatPill(label: "Fenwick%", value: pct(a.fenwickPct))
                }
                Divider().overlay(Theme.Palette.border)
                HStack(spacing: Theme.Spacing.sm) {
                    StatPill(label: "PDO", value: String(format: "%.1f", a.pdo))
                    StatPill(label: "HD CF%", value: pct(a.hdCfPct))
                    StatPill(label: "Sh%", value: pct(a.shootingPct))
                }
                Divider().overlay(Theme.Palette.border)
                HStack(spacing: Theme.Spacing.sm) {
                    StatPill(label: "PP%", value: pct(a.ppPct))
                    StatPill(label: "PK%", value: pct(a.pkPct))
                    StatPill(label: "Shots/GP", value: String(format: "%.1f", a.shotsForPg))
                }
            }
        }
    }

    // MARK: - Players (skater season stats)

    private var playersCard: some View {
        let visible = showAllSkaters ? skaters : Array(skaters.prefix(10))
        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionHeader("Players (\(skaters.count))")
                skaterHeaderRow
                ForEach(visible) { skater in
                    skaterRow(skater)
                    if skater.id != visible.last?.id {
                        Divider().overlay(Theme.Palette.border)
                    }
                }
                if skaters.count > 10 {
                    PressableButton(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showAllSkaters.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(showAllSkaters ? "Show top 10" : "Show all \(skaters.count)")
                            Image(systemName: showAllSkaters ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.xxs)
                    }
                }
            }
        }
    }

    private var skaterHeaderRow: some View {
        HStack(spacing: 0) {
            Text("SKATER").frame(maxWidth: .infinity, alignment: .leading)
            Text("GP").frame(width: 36, alignment: .trailing)
            Text("G").frame(width: 32, alignment: .trailing)
            Text("A").frame(width: 32, alignment: .trailing)
            Text("P").frame(width: 36, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Theme.Palette.textTertiary)
    }

    private func skaterRow(_ s: SkaterStats) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(s.position)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(info.color)
                    .frame(width: 16)
                Text(s.name)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(s.gamesPlayed)").frame(width: 36, alignment: .trailing)
                .foregroundStyle(Theme.Palette.textSecondary)
            Text("\(s.goals)").frame(width: 32, alignment: .trailing)
                .foregroundStyle(Theme.Palette.textSecondary)
            Text("\(s.assists)").frame(width: 32, alignment: .trailing)
                .foregroundStyle(Theme.Palette.textSecondary)
            Text("\(s.points)").frame(width: 36, alignment: .trailing)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .font(.system(size: 13, weight: .medium, design: .monospaced))
    }

    // MARK: - Goalies

    private func goaliesCard(_ goalies: [GoalieStats]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionHeader("Goalies")
                ForEach(goalies) { goalie in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Text(goalie.name)
                                    .font(Theme.Font.caption())
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                if goalie.isStarter {
                                    Text("STARTER")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Theme.Palette.accent)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Theme.Palette.accent.opacity(0.14))
                                        .clipShape(Capsule())
                                }
                            }
                            Text("GSAX \(signed(goalie.gsax)) · SV% \(String(format: "%.3f", goalie.svPct)) · GAA \(String(format: "%.2f", goalie.gaa))")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        Spacer()
                    }
                    if goalie.id != goalies.last?.id {
                        Divider().overlay(Theme.Palette.border)
                    }
                }
            }
        }
    }

    // MARK: - Injuries

    private func injuriesCard(_ injuries: [String]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionHeader("Injuries (\(injuries.count))")
                ForEach(injuries, id: \.self) { injury in
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.negative)
                        Text(injury)
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.Palette.textTertiary)
    }

    private func pct(_ v: Double) -> String { String(format: "%.1f%%", v) }
    private func signed(_ v: Double) -> String { String(format: "%+.1f", v) }
    private func signedInt(_ v: Int) -> String { (v > 0 ? "+" : "") + "\(v)" }
}
