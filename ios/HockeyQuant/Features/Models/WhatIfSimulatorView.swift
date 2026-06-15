import SwiftUI

/// Interactive what-if: pick a game, adjust each team's goalie / fatigue / injuries
/// / special teams, and watch the win probability + expected score + scoreline grid
/// recompute live (debounced calls to /api/what-if).
struct WhatIfSimulatorView: View {
    private let api = APIClient(environment: .production)

    @State private var date = Date()
    @State private var games: [GamePrediction] = []
    @State private var loadingGames = true
    @State private var selected: GamePrediction?

    @State private var result: WhatIfResult?
    @State private var simTask: Task<Void, Never>?

    // Per-team levers (set from the base result's `applied` factors).
    @State private var aw = Levers()
    @State private var hm = Levers()
    private struct Levers { var goalie = "starter"; var fatigue = 1.0; var injury = 1.0; var st = 1.0 }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                gamePicker
                if selected != nil {
                    if let r = result {
                        resultPanel(r)
                        teamCard(isAway: true, r.applied.away)
                        teamCard(isAway: false, r.applied.home)
                        Button("Reset to actual") { reset(r) }
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.accent)
                    } else {
                        ProgressView().padding(Theme.Spacing.lg)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Palette.background)
        .navigationTitle("What-If Simulator")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadGames() }
    }

    // MARK: - Game picker

    private var gamePicker: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                stepButton("chevron.left") { shift(-1) }
                Spacer()
                Text(date.formatted(.dateTime.weekday().month().day())).font(Theme.Font.headline())
                Spacer()
                stepButton("chevron.right") { shift(1) }
            }
            if loadingGames {
                LoadingShimmer(height: 40)
            } else if games.isEmpty {
                Text("No games this day — use ‹ › to find one.")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(games) { g in gameChip(g) }
                    }
                }
            }
        }
    }

    private func gameChip(_ g: GamePrediction) -> some View {
        let isSel = selected?.id == g.id
        return Button { pick(g) } label: {
            HStack(spacing: 4) {
                CrestView(abbrev: g.away.team, size: 18)
                Text("\(g.away.team)@\(g.home.team)").font(.system(size: 12, weight: .bold))
                CrestView(abbrev: g.home.team, size: 18)
            }
            .padding(.horizontal, Theme.Spacing.sm).padding(.vertical, 7)
            .background(isSel ? Theme.Palette.accent.opacity(0.15) : Theme.Palette.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSel ? Theme.Palette.accent : Theme.Palette.border, lineWidth: isSel ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Palette.textPrimary)
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold))
                .frame(width: 34, height: 34).background(Theme.Palette.surface).clipShape(Circle())
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }

    // MARK: - Result panel

    private func resultPanel(_ r: WhatIfResult) -> some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                HStack {
                    teamHead(r.awayTeam)
                    Spacer()
                    Text(String(format: "%.2f – %.2f", r.awayXg, r.homeXg))
                        .font(Theme.Font.mono()).foregroundStyle(Theme.Palette.textSecondary)
                    Spacer()
                    teamHead(r.homeTeam)
                }
                WinProbBar(awayProb: r.mlAwayProb, homeProb: r.mlHomeProb,
                           awayColor: TeamInfo.lookup(r.awayTeam).color, homeColor: TeamInfo.lookup(r.homeTeam).color)
                HStack {
                    Text("\(r.awayTeam) \(Int(r.mlAwayProb.rounded()))%").font(Theme.Font.caption())
                    Spacer()
                    Text("\(Int(r.mlHomeProb.rounded()))% \(r.homeTeam)").font(Theme.Font.caption())
                }
                .foregroundStyle(Theme.Palette.textSecondary)
                PoissonHeatmapView(awayMean: r.awayXg, homeMean: r.homeXg,
                                   awayAbbrev: r.awayTeam, homeAbbrev: r.homeTeam, tint: TeamInfo.lookup(r.homeTeam).color)
            }
        }
    }

    private func teamHead(_ abbrev: String) -> some View {
        VStack(spacing: 2) { CrestView(abbrev: abbrev, size: 30); Text(abbrev).font(.system(size: 12, weight: .bold)) }
            .foregroundStyle(Theme.Palette.textPrimary)
    }

    // MARK: - Team controls

    private func teamCard(isAway: Bool, _ f: WhatIfFactors) -> some View {
        let abbrev = isAway ? (result?.awayTeam ?? "") : (result?.homeTeam ?? "")
        let lever = Binding(get: { isAway ? aw : hm }, set: { if isAway { aw = $0 } else { hm = $0 } })
        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: 6) {
                    CrestView(abbrev: abbrev, size: 22)
                    Text(abbrev).font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                }
                if let backup = f.backupGoalie, !backup.isEmpty {
                    HStack {
                        Text("GOALIE").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                        Spacer()
                        Picker("", selection: Binding(get: { lever.wrappedValue.goalie },
                                                      set: { lever.wrappedValue.goalie = $0; scheduleSim() })) {
                            Text("Starter").tag("starter")
                            Text("Backup").tag("backup")
                        }.pickerStyle(.segmented).frame(width: 150)
                    }
                    Text(lever.wrappedValue.goalie == "backup"
                         ? "\(backup) · GSAX \(f.backupGoalieGsax.map { String(format: "%+.1f", $0) } ?? "—")"
                         : "\(f.goalie ?? "—") · GSAX \(String(format: "%+.1f", f.goalieGsax))")
                        .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                }
                slider("Fatigue", Binding(get: { lever.wrappedValue.fatigue }, set: { lever.wrappedValue.fatigue = $0; scheduleSim() }), 0.88...1.06)
                slider("Health", Binding(get: { lever.wrappedValue.injury }, set: { lever.wrappedValue.injury = $0; scheduleSim() }), 0.90...1.00)
                slider("Special teams", Binding(get: { lever.wrappedValue.st }, set: { lever.wrappedValue.st = $0; scheduleSim() }), 0.95...1.05)
            }
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(label).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                Text(String(format: "×%.2f", value.wrappedValue)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.Palette.textTertiary)
            }
            Slider(value: value, in: range).tint(Theme.Palette.accent)
        }
    }

    // MARK: - Actions

    private func loadGames() async {
        loadingGames = true
        defer { loadingGames = false }
        games = (try? await api.predictions(for: date).predictions) ?? []
        if let first = games.first { pick(first) } else { selected = nil; result = nil }
    }

    private func shift(_ days: Int) {
        date = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
        Task { await loadGames() }
    }

    private func pick(_ g: GamePrediction) {
        selected = g
        result = nil
        Task {
            guard let r = try? await api.whatIf(WhatIfRequest(away: g.away.team, home: g.home.team)) else { return }
            guard selected?.id == g.id else { return }
            reset(r)
        }
    }

    private func reset(_ r: WhatIfResult) {
        aw = Levers(goalie: "starter", fatigue: r.applied.away.fatigueMult, injury: r.applied.away.injuryMult, st: r.applied.away.stMult)
        hm = Levers(goalie: "starter", fatigue: r.applied.home.fatigueMult, injury: r.applied.home.injuryMult, st: r.applied.home.stMult)
        result = r
    }

    private func scheduleSim() {
        guard let g = selected else { return }
        simTask?.cancel()
        let req = WhatIfRequest(
            away: g.away.team, home: g.home.team,
            awayOverrides: WhatIfTeamOverride(goalie: aw.goalie, fatigueMult: aw.fatigue, injuryMult: aw.injury, stMult: aw.st),
            homeOverrides: WhatIfTeamOverride(goalie: hm.goalie, fatigueMult: hm.fatigue, injuryMult: hm.injury, stMult: hm.st))
        simTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            if let r = try? await api.whatIf(req), selected?.id == g.id {
                withAnimation(.easeOut(duration: 0.2)) { result = r }
            }
        }
    }
}
