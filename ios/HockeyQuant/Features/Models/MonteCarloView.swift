import SwiftUI
import Charts

/// Monte-Carlo: pick a matchup, run thousands of simulated games (or a best-of-7
/// series) and watch the outcome distribution + odds build up live.
struct MonteCarloView: View {
    private let api = APIClient(environment: .production)
    private let target = 10_000

    @State private var date = Date()
    @State private var games: [GamePrediction] = []
    @State private var loadingGames = true
    @State private var selected: GamePrediction?
    @State private var inputs: SimInputs?
    @State private var tab = 0   // 0 = Game, 1 = Series

    // Game accumulators
    @State private var ranG = 0
    @State private var awayWins = 0
    @State private var totals: [Int: Int] = [:]
    @State private var scores: [String: Int] = [:]
    @State private var gameTask: Task<Void, Never>?

    // Series accumulators
    @State private var ranS = 0
    @State private var aSeriesWins = 0
    @State private var lengths: [Int: Int] = [4: 0, 5: 0, 6: 0, 7: 0]
    @State private var aHasHomeIce = false   // default: home team hosts
    @State private var seriesTask: Task<Void, Never>?

    private var away: String { inputs?.a ?? selected?.away.team ?? "" }
    private var home: String { inputs?.b ?? selected?.home.team ?? "" }
    private var awayColor: Color { TeamInfo.lookup(away).color }
    private var homeColor: Color { TeamInfo.lookup(home).color }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                gamePicker
                if let inp = inputs {
                    Picker("", selection: $tab) { Text("Game").tag(0); Text("Series").tag(1) }
                        .pickerStyle(.segmented)
                    if tab == 0 { gameTab(inp) } else { seriesTab(inp) }
                } else if selected != nil {
                    ProgressView().padding(Theme.Spacing.lg)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Palette.background)
        .navigationTitle("Monte-Carlo Sims")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadGames() }
    }

    // MARK: - Game tab

    private func gameTab(_ inp: SimInputs) -> some View {
        let la = inp.bHome.aXg, lh = inp.bHome.bXg   // game at the home team's venue
        return Card {
            VStack(spacing: Theme.Spacing.sm) {
                runButton(running: ranG > 0 && ranG < target) { runGame(la, lh) }
                if ranG > 0 {
                    let aw = pct(awayWins, ranG), hw = 100 - aw
                    WinProbBar(awayProb: aw, homeProb: hw, awayColor: awayColor, homeColor: homeColor)
                    HStack {
                        Text("\(away) \(Int(aw.rounded()))%").font(Theme.Font.caption())
                        Spacer()
                        Text("\(Int(hw.rounded()))% \(home)").font(Theme.Font.caption())
                    }.foregroundStyle(Theme.Palette.textSecondary)

                    label("TOTAL GOALS")
                    Chart {
                        ForEach(totals.sorted(by: { $0.key < $1.key }), id: \.key) { tot, c in
                            BarMark(x: .value("Goals", tot), y: .value("Count", c))
                                .foregroundStyle(Theme.Palette.accent.gradient)
                        }
                    }
                    .chartXScale(domain: 0...12)
                    .frame(height: 110)

                    label("MOST LIKELY SCORES")
                    HStack {
                        ForEach(topScores, id: \.key) { kv in
                            VStack(spacing: 1) {
                                Text(kv.key.replacingOccurrences(of: "-", with: "–")).font(.system(size: 14, weight: .heavy, design: .rounded))
                                Text("\(Int(pct(kv.value, ranG).rounded()))%").font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(Theme.Palette.background).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        }
                    }
                }
            }
        }
    }

    private var topScores: [(key: String, value: Int)] {
        scores.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) }
    }

    // MARK: - Series tab

    private func seriesTab(_ inp: SimInputs) -> some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                Picker("", selection: $aHasHomeIce) {
                    Text("\(home) home ice").tag(false)
                    Text("\(away) home ice").tag(true)
                }.pickerStyle(.segmented)
                Text("Best of 7 · 2-2-1-1-1").font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)

                runButton(running: ranS > 0 && ranS < target) { runSeries(inp) }
                if ranS > 0 {
                    let aw = pct(aSeriesWins, ranS), hw = 100 - aw
                    WinProbBar(awayProb: aw, homeProb: hw, awayColor: awayColor, homeColor: homeColor)
                    HStack {
                        Text("\(away) \(Int(aw.rounded()))%").font(Theme.Font.caption())
                        Spacer()
                        Text("\(Int(hw.rounded()))% \(home)").font(Theme.Font.caption())
                    }.foregroundStyle(Theme.Palette.textSecondary)

                    label("SERIES LENGTH")
                    Chart {
                        ForEach([4, 5, 6, 7], id: \.self) { len in
                            BarMark(x: .value("Games", "\(len)"), y: .value("%", pct(lengths[len] ?? 0, ranS)))
                                .foregroundStyle(Theme.Palette.accent.gradient)
                                .annotation(position: .top) {
                                    Text("\(Int(pct(lengths[len] ?? 0, ranS).rounded()))%").font(.system(size: 9)).foregroundStyle(Theme.Palette.textTertiary)
                                }
                        }
                    }
                    .frame(height: 120)
                }
            }
        }
    }

    // MARK: - Shared UI

    private func runButton(running: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: running ? "hourglass" : "dice.fill")
                Text(running ? "Running… \(tab == 0 ? ranG : ranS)/\(target)" : "Run \(target.formatted())×")
            }
            .font(Theme.Font.headline()).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Palette.accent).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .disabled(running)
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gamePicker: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                step("chevron.left") { shift(-1) }
                Spacer()
                Text(date.formatted(.dateTime.weekday().month().day())).font(Theme.Font.headline())
                Spacer()
                step("chevron.right") { shift(1) }
            }
            if loadingGames {
                LoadingShimmer(height: 40)
            } else if games.isEmpty {
                Text("No games this day — use ‹ › to find one.").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) { ForEach(games) { chip($0) } }
                }
            }
        }
    }

    private func chip(_ g: GamePrediction) -> some View {
        let sel = selected?.id == g.id
        return Button { pick(g) } label: {
            HStack(spacing: 4) {
                CrestView(abbrev: g.away.team, size: 18)
                Text("\(g.away.team)@\(g.home.team)").font(.system(size: 12, weight: .bold))
                CrestView(abbrev: g.home.team, size: 18)
            }
            .padding(.horizontal, Theme.Spacing.sm).padding(.vertical, 7)
            .background(sel ? Theme.Palette.accent.opacity(0.15) : Theme.Palette.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(sel ? Theme.Palette.accent : Theme.Palette.border, lineWidth: sel ? 1.5 : 1))
        }
        .buttonStyle(.plain).foregroundStyle(Theme.Palette.textPrimary)
    }

    private func step(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold))
                .frame(width: 34, height: 34).background(Theme.Palette.surface).clipShape(Circle()).foregroundStyle(Theme.Palette.textPrimary)
        }
    }

    // MARK: - Actions

    private func pct(_ x: Int, _ n: Int) -> Double { n > 0 ? Double(x) / Double(n) * 100 : 0 }

    private func loadGames() async {
        loadingGames = true; defer { loadingGames = false }
        games = (try? await api.predictions(for: date).predictions) ?? []
        if let first = games.first { pick(first) } else { selected = nil; inputs = nil }
    }

    private func shift(_ days: Int) {
        date = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
        Task { await loadGames() }
    }

    private func pick(_ g: GamePrediction) {
        selected = g; inputs = nil; resetGame(); resetSeries()
        Task {
            guard let inp = try? await api.simInputs(away: g.away.team, home: g.home.team), selected?.id == g.id else { return }
            inputs = inp
        }
    }

    private func resetGame() { gameTask?.cancel(); ranG = 0; awayWins = 0; totals = [:]; scores = [:] }
    private func resetSeries() { seriesTask?.cancel(); ranS = 0; aSeriesWins = 0; lengths = [4: 0, 5: 0, 6: 0, 7: 0] }

    private func runGame(_ la: Double, _ lh: Double) {
        resetGame()
        gameTask = Task {
            let batch = 800
            while ranG < target && !Task.isCancelled {
                for _ in 0..<batch {
                    let r = MonteCarlo.simGame(la, lh)
                    if r.awayWon { awayWins += 1 }
                    totals[r.away + r.home, default: 0] += 1
                    scores["\(r.away)-\(r.home)", default: 0] += 1
                }
                ranG = min(ranG + batch, target)
                try? await Task.sleep(nanoseconds: 32_000_000)
            }
        }
    }

    private func runSeries(_ inp: SimInputs) {
        resetSeries()
        let aHome = (a: inp.aHome.aXg, b: inp.aHome.bXg)
        let bHome = (a: inp.bHome.aXg, b: inp.bHome.bXg)
        let hosts = MonteCarlo.aHostsByGame(aHasHomeIce: aHasHomeIce)
        seriesTask = Task {
            let batch = 600
            while ranS < target && !Task.isCancelled {
                for _ in 0..<batch {
                    let r = MonteCarlo.simSeries(aHome: aHome, bHome: bHome, hosts: hosts)
                    if r.aWon { aSeriesWins += 1 }
                    lengths[r.length, default: 0] += 1
                }
                ranS = min(ranS + batch, target)
                try? await Task.sleep(nanoseconds: 32_000_000)
            }
        }
    }
}
