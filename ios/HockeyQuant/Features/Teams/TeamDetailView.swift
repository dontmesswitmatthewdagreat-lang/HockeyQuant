import SwiftUI

/// Detailed team view: standings, advanced analytics, players, goalies, injuries.
struct TeamDetailView: View {
    @State private var model: TeamDetailViewModel
    @State private var skaters: [SkaterStats] = []
    @State private var showAllSkaters = false
    @State private var decomposition: TeamDecomposition?
    @State private var showStateSplit = false
    /// Advanced impact, keyed by name *and* position. The roster table and this
    /// endpoint are both built from MoneyPuck skater rows, so both fields match
    /// exactly — but name alone is not unique. Vancouver dresses two Elias
    /// Petterssons, a centre and a defenceman, and keying on name would open
    /// the forward's card from the defenceman's row.
    @State private var impacts: [String: SkaterImpact] = [:]
    @State private var selectedSkater: SkaterImpact?
    @State private var goalieImpacts: [String: GoalieImpact] = [:]
    @State private var selectedGoalie: GoalieImpact?
    private let api = APIClient()

    init(abbrev: String) {
        _model = State(initialValue: TeamDetailViewModel(abbrev: abbrev))
    }

    private var info: TeamInfo { TeamInfo.lookup(model.abbrev) }

    /// Both endpoints read the same MoneyPuck column for position, but only the
    /// roster one uppercases it — so normalize here rather than trust that.
    private static func impactKey(_ name: String, _ position: String) -> String {
        "\(name)|\(position.uppercased())"
    }

    /// Build a lookup that *drops* genuine duplicates instead of arbitrarily
    /// keeping one. If two rows still collide after keying, there is no way to
    /// tell which roster row means which player, and opening the wrong player's
    /// card is worse than the row not being tappable.
    private static func lookup<T>(_ rows: [T], key: (T) -> String) -> [String: T] {
        var counts: [String: Int] = [:]
        for row in rows { counts[key(row), default: 0] += 1 }
        return Dictionary(uniqueKeysWithValues:
            rows.filter { counts[key($0)] == 1 }.map { (key($0), $0) })
    }

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
        // Same for the advanced surfaces — a metrics outage must not take the
        // team page down with it.
        .task { decomposition = try? await api.teamDecomposition(model.abbrev) }
        .task {
            let rows = (try? await api.skaterImpact(team: model.abbrev)) ?? []
            impacts = Self.lookup(rows) { Self.impactKey($0.name, $0.position) }
        }
        .task {
            let rows = (try? await api.goalieImpact(team: model.abbrev)) ?? []
            // Goalies have no second field to disambiguate on, so a same-name
            // pair simply becomes untappable rather than wrong.
            goalieImpacts = Self.lookup(rows) { $0.name }
        }
        .floatingCard(item: $selectedSkater) { skater in
            PlayerImpactSheet(skater: skater, teamColor: info.color)
        }
        .floatingCard(item: $selectedGoalie) { goalie in
            GoalieImpactSheet(goalie: goalie, teamColor: info.color)
        }
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
                    if let decomposition {
                        decompositionCard(decomposition, officialDiff: detail.stats.goalDiff)
                    }
                    if !skaters.isEmpty {
                        playersCard
                    }
                    lineChemistryLink
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

    /// The roster table says who's on the team; this says who plays *together*.
    private var lineChemistryLink: some View {
        NavigationLink { LineChemistryView(team: model.abbrev) } label: {
            Card {
                HStack(spacing: Theme.Spacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .fill(info.color.opacity(0.16))
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(info.color)
                    }
                    .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Line chemistry")
                            .font(Theme.Font.headlineHeavy())
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text("Which combinations actually play, and which beat the sum of their parts.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Goal differential decomposition

    /// Why the goal differential is what it is. The three causes are mutually
    /// exclusive and sum back to the differential exactly, which is what makes
    /// a diverging-bar breakdown the honest shape for it.
    private func decompositionCard(_ d: TeamDecomposition, officialDiff: Int) -> some View {
        // Bars are scaled against the largest cause so the smallest one is
        // still visible rather than a hairline.
        let scale = max(d.causes.map { abs($0.value) }.max() ?? 1, 1)
        // The NHL awards a goal for winning a shootout; the play-by-play these
        // numbers come from doesn't. Left unexplained, the standings card above
        // and this one disagree by a couple of goals and both look wrong.
        let shootoutGap = officialDiff - Int(d.differential.rounded())
        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    sectionHeader("Goal differential")
                    Spacer()
                    Text(signedInt(Int(d.differential.rounded())))
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(d.differential >= 0 ? Theme.Palette.positive
                                                             : Theme.Palette.negative)
                }
                Text(verdict(d))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                if shootoutGap != 0 {
                    Text("Played hockey only — excludes shootout deciders, so this differs from the \(signedInt(officialDiff)) in the standings.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(d.causes, id: \.label) { cause in
                        causeRow(cause.label, cause.value, scale: scale)
                    }
                }
                // These are goals, not an index or a rating — worth saying, since
                // nothing else on the card carries a unit.
                Text("Goals over \(d.gamesPlayed) games. The three add up to the differential; bar length is relative to the biggest one.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textTertiary)

                if !d.addsUp {
                    // Only ever visible if MoneyPuck changes its strength states.
                    Text("Parts don't reconcile (residual \(String(format: "%.2f", d.residual ?? 0)))")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.moderate)
                }

                Divider().overlay(Theme.Palette.border)
                PressableButton(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showStateSplit.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(showStateSplit ? "Hide game states" : "By game state")
                        Image(systemName: showStateSplit ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(maxWidth: .infinity)
                }
                if showStateSplit {
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(d.splits) { split in
                            stateRow(split)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private func causeRow(_ label: String, _ value: Double, scale: Double) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 84, alignment: .leading)
            DivergingBar(edge: value / scale)
            Text(signed(value))
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(value >= 0 ? Theme.Palette.positive : Theme.Palette.negative)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func stateRow(_ s: StrengthSplit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(s.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Text(signedInt(Int(s.differential.rounded())))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(s.differential >= 0 ? Theme.Palette.positive
                                                         : Theme.Palette.negative)
            }
            Text("process \(signed(s.process))  ·  finishing \(signed(s.finishing))  ·  goaltending \(signed(s.goaltending))")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    /// One line on what's actually driving the record.
    private func verdict(_ d: TeamDecomposition) -> String {
        guard let top = d.causes.first else { return "" }
        let good = top.value >= 0
        switch top.label {
        case "Process":
            return good
                ? "Out-chancing opponents — the shot volume and quality are doing the work."
                : "Getting out-chanced. The results depend on finishing or goaltending covering for it."
        case "Finishing":
            return good
                ? "Shooting above what the chances were worth — the kind of edge that tends to regress."
                : "Scoring below what the chances were worth. The looks are there, the finish isn't."
        default:
            return good
                ? "Goaltending is stealing goals back — saving more than the shots faced were worth."
                : "Goaltending is leaking goals above expected, undoing work done elsewhere."
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
                    if let impact = impacts[Self.impactKey(skater.name, skater.position)] {
                        PressableButton(action: { selectedSkater = impact }) {
                            skaterRow(skater, tappable: true)
                        }
                    } else {
                        skaterRow(skater, tappable: false)
                    }
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

    private func skaterRow(_ s: SkaterStats, tappable: Bool) -> some View {
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
                if tappable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
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
        // The row is mostly whitespace between the name and the numbers; without
        // an explicit hit shape a tap in that gap falls straight through and the
        // row reads as dead.
        .contentShape(Rectangle())
    }

    // MARK: - Goalies

    private func goaliesCard(_ goalies: [GoalieStats]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionHeader("Goalies")
                ForEach(goalies) { goalie in
                    if let impact = goalieImpacts[goalie.name] {
                        PressableButton(action: { selectedGoalie = impact }) {
                            goalieRow(goalie, tappable: true)
                        }
                    } else {
                        goalieRow(goalie, tappable: false)
                    }
                    if goalie.id != goalies.last?.id {
                        Divider().overlay(Theme.Palette.border)
                    }
                }
            }
        }
    }

    private func goalieRow(_ goalie: GoalieStats, tappable: Bool) -> some View {
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
                    if tappable {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                Text("GSAX \(signed(goalie.gsax)) · SV% \(String(format: "%.3f", goalie.svPct)) · GAA \(String(format: "%.2f", goalie.gaa))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
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
