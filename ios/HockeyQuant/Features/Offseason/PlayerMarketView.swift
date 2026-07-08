import SwiftUI
import Charts

/// The player stock market: fair values from the production model, a market
/// line that moves with real signings, movers, and graded contracts.
struct PlayerMarketView: View {
    @State private var overview: MarketOverview?
    @State private var failed = false
    @State private var search = ""
    @State private var results: [MarketPlayer] = []
    @State private var topOfMarket: [MarketPlayer] = []
    @State private var detailSelection: MarketSelection?
    private let api = APIClient()

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    heroBand
                    VStack(spacing: Theme.Spacing.md) {
                        searchField
                        if !search.isEmpty {
                            resultsList(results)
                        } else if let overview {
                            heatCard(overview)
                            if overview.index.count >= 2 { indexCard(overview.index) }
                            if !overview.movers.isEmpty { moversCard(overview.movers) }
                            if !overview.signings.isEmpty { signingsCard(overview.signings) }
                            if !topOfMarket.isEmpty { topCard }
                        } else if failed {
                            ErrorStateView(message: "The market model is warming up — pull to retry.") {
                                Task { await load() }
                            }
                        } else {
                            VStack(spacing: Theme.Spacing.sm) {
                                ForEach(0..<4, id: \.self) { _ in LoadingShimmer(height: 90) }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
            .refreshable { await load() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .task(id: search) {
            guard !search.isEmpty else { results = []; return }
            try? await Task.sleep(nanoseconds: 300_000_000)   // debounce
            if Task.isCancelled { return }
            results = (try? await api.marketPlayers(query: search, limit: 25)) ?? []
        }
        .sheet(item: $detailSelection) { sel in
            PlayerValueSheet(name: sel.name)
                .presentationDetents([.large])
        }
    }

    private func load() async {
        do {
            overview = try await api.marketOverview()
            topOfMarket = (try? await api.marketPlayers(limit: 15)) ?? []
        } catch {
            failed = true
        }
    }

    // MARK: - Chrome

    private var heroBand: some View {
        HeroBand(tint: Color(hex: 0x1F8A5B)) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    BackChip()
                    Spacer()
                    if let n = overview?.trainedOn {
                        BandPill(text: "Model: \(n) contracts", systemImage: "cpu")
                    }
                }
                Text("Player Market")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Fair values from production · market prices from real signings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
            TextField("Value any skater", text: $search)
                .font(.system(size: 15))
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 11)
        .background(Theme.Palette.surface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Theme.Palette.border, lineWidth: 1))
    }

    // MARK: - Sections

    private func heatCard(_ o: MarketOverview) -> some View {
        SectionCard("Market heat — what signings are paying vs fair value") {
            HStack(spacing: Theme.Spacing.sm) {
                heatPill("Forwards", o.heat["F"] ?? 0)
                heatPill("Defensemen", o.heat["D"] ?? 0)
            }
            Text("A big overpay (like an $18M offer sheet) lifts these — and every comparable player's market price with it.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    private func heatPill(_ label: String, _ pct: Double) -> some View {
        VStack(spacing: 3) {
            Text(String(format: "%+.1f%%", pct))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(pct > 2 ? Theme.Palette.negative : (pct < -2 ? Theme.Palette.positive : Theme.Palette.textPrimary))
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Palette.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private func indexCard(_ index: [MarketIndexPoint]) -> some View {
        SectionCard("Market index — avg top-100 value") {
            Chart(index) { pt in
                LineMark(x: .value("Date", pt.date), y: .value("Value", pt.value / 1_000_000))
                    .foregroundStyle(Color(hex: 0x1F8A5B))
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("Date", pt.date), y: .value("Value", pt.value / 1_000_000))
                    .foregroundStyle(Color(hex: 0x1F8A5B).opacity(0.12))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis(.hidden)
            .frame(height: 120)
        }
    }

    private func moversCard(_ movers: [MarketMover]) -> some View {
        SectionCard("Today's movers") {
            VStack(spacing: 0) {
                ForEach(movers.prefix(6)) { m in
                    Button { detailSelection = MarketSelection(name: m.name) } label: {
                        HStack {
                            Text(m.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Spacer()
                            Text(m.marketValue.asCapMoney)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.Palette.textSecondary)
                            Text(String(format: "%+.1f%%", m.deltaPct))
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(m.deltaPct >= 0 ? Theme.Palette.positive : Theme.Palette.negative)
                                .frame(width: 62, alignment: .trailing)
                        }
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if m.id != movers.prefix(6).last?.id { Divider().overlay(Theme.Palette.border) }
                }
            }
        }
    }

    private func signingsCard(_ signings: [GradedSigning]) -> some View {
        SectionCard("Signings, graded by the model") {
            VStack(spacing: 0) {
                ForEach(signings.prefix(10)) { s in
                    Button { detailSelection = MarketSelection(name: s.name) } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            CrestView(abbrev: s.team, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                Text("\(s.aav.asCapMoney)\(s.years.map { " × \($0) yrs" } ?? "") · fair \(s.fairValue.asCapMoney)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                            Spacer()
                            if let v = s.verdict { verdictPill(v) }
                        }
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if s.id != signings.prefix(10).last?.id { Divider().overlay(Theme.Palette.border) }
                }
            }
        }
    }

    private var topCard: some View {
        SectionCard("Top of the market") {
            VStack(spacing: 0) {
                ForEach(Array(topOfMarket.enumerated()), id: \.element.id) { i, p in
                    Button { detailSelection = MarketSelection(name: p.name) } label: {
                        marketRow(p, rank: i + 1)
                    }
                    .buttonStyle(.plain)
                    if p.id != topOfMarket.last?.id { Divider().overlay(Theme.Palette.border) }
                }
            }
        }
    }

    private func resultsList(_ players: [MarketPlayer]) -> some View {
        SectionCard("Results") {
            if players.isEmpty {
                Text("No valued skaters match. (Goalies and <10 GP players aren't modeled yet.)")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(players) { p in
                        Button { detailSelection = MarketSelection(name: p.name) } label: { marketRow(p, rank: nil) }
                            .buttonStyle(.plain)
                        if p.id != players.last?.id { Divider().overlay(Theme.Palette.border) }
                    }
                }
            }
        }
    }

    private func marketRow(_ p: MarketPlayer, rank: Int?) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let rank {
                Text("\(rank)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: 20)
            }
            if let team = p.team, TeamInfo.all[team.uppercased()] != nil {
                CrestView(abbrev: team, size: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text("\(p.position) · \(Int(p.age)) yrs\(p.aav.map { " · paid \($0.asCapMoney)" } ?? " · unsigned")")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(p.marketValue.asCapMoney)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let v = p.verdict { verdictPill(v) }
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

/// Shared verdict chip (steal / fair / overpay).
@MainActor @ViewBuilder
func verdictPill(_ verdict: String) -> some View {
    let color: Color = verdict == "steal" ? Theme.Palette.positive
        : (verdict == "overpay" ? Theme.Palette.negative : Theme.Palette.textSecondary)
    StatusPill(text: verdict.verdictLabel, color: color, solid: verdict != "fair")
}

/// Sheet-selection wrapper (String itself isn't Identifiable).
struct MarketSelection: Identifiable {
    let name: String
    var id: String { name }
}

// MARK: - Player value sheet

struct PlayerValueSheet: View {
    let name: String
    @State private var detail: PlayerMarketDetail?
    @State private var failed = false
    private let api = APIClient()

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    if let d = detail {
                        header(d)
                        valueCard(d)
                        if d.history.count >= 2 { historyCard(d.history) }
                        if !d.comparables.isEmpty { compsCard(d.comparables) }
                        if !d.fits.isEmpty { fitsCard(d.fits) }
                    } else if failed {
                        EmptyStateView(systemImage: "chart.line.downtrend.xyaxis",
                                       title: "Not valued",
                                       message: "Goalies and players with under 10 games aren't in the model yet.")
                            .padding(.top, Theme.Spacing.xl)
                    } else {
                        VStack(spacing: Theme.Spacing.sm) {
                            ForEach(0..<4, id: \.self) { _ in LoadingShimmer(height: 90) }
                        }
                    }
                }
                .padding(Theme.Spacing.md)
                .padding(.top, Theme.Spacing.lg)
            }
        }
        .task {
            do { detail = try await api.marketPlayer(name: name) }
            catch { failed = true }
        }
    }

    private func header(_ d: PlayerMarketDetail) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                if let team = d.player.team, TeamInfo.all[team.uppercased()] != nil {
                    CrestView(abbrev: team, size: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.player.name)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("\(d.player.position) · \(Int(d.player.age)) yrs · \(d.player.gp) GP · \(String(format: "%.2f", d.player.ppg)) P/GP")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                if let v = d.player.verdict { verdictPill(v) }
            }
        }
    }

    private func valueCard(_ d: PlayerMarketDetail) -> some View {
        SectionCard("Value") {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.player.marketValue.asCapMoney)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("market price · fundamentals \(d.player.modelValue.asCapMoney)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
            }
            valueRange(d.player)
            if let aav = d.player.aav {
                Text("Currently paid \(aav.asCapMoney) — \(premiumLine(aav: aav, value: d.player.modelValue))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Text(String(format: "Position market trading %+.1f%% vs fair value", d.heatPct))
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    /// Low–high band with ticks for model value, market value, and actual AAV.
    private func valueRange(_ p: MarketPlayer) -> some View {
        let lo = p.valueLow, hi = max(p.valueHigh, p.aav ?? 0, p.marketValue)
        func frac(_ v: Double) -> CGFloat { CGFloat(min(max((v - lo) / max(hi - lo, 1), 0), 1)) }
        return VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.border.opacity(0.5)).frame(height: 8)
                    Capsule().fill(Color(hex: 0x1F8A5B).opacity(0.35))
                        .frame(width: geo.size.width * frac(p.valueHigh), height: 8)
                    tick(at: frac(p.modelValue), width: geo.size.width, color: Color(hex: 0x1F8A5B))
                    tick(at: frac(p.marketValue), width: geo.size.width, color: Theme.Palette.accentAlt)
                    if let aav = p.aav {
                        tick(at: frac(aav), width: geo.size.width, color: Theme.Palette.negative)
                    }
                }
            }
            .frame(height: 14)
            HStack {
                legendDot(Color(hex: 0x1F8A5B), "fair")
                legendDot(Theme.Palette.accentAlt, "market")
                if p.aav != nil { legendDot(Theme.Palette.negative, "paid") }
                Spacer()
                Text("range \(p.valueLow.asCapMoney)–\(p.valueHigh.asCapMoney)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    private func tick(at f: CGFloat, width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: 3, height: 14)
            .offset(x: width * f - 1.5)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    private func premiumLine(aav: Double, value: Double) -> String {
        let diff = aav - value
        if abs(diff) < 400_000 { return "right at fair value" }
        return diff > 0 ? "\(diff.asCapMoney) above fair value" : "\((-diff).asCapMoney) below fair value"
    }

    private func historyCard(_ history: [ValueHistoryPoint]) -> some View {
        SectionCard("Value over time") {
            Chart {
                ForEach(history) { h in
                    LineMark(x: .value("Date", h.date), y: .value("Fair", h.modelValue / 1_000_000),
                             series: .value("Series", "Fair"))
                        .foregroundStyle(Color(hex: 0x1F8A5B))
                    LineMark(x: .value("Date", h.date), y: .value("Market", h.marketValue / 1_000_000),
                             series: .value("Series", "Market"))
                        .foregroundStyle(Theme.Palette.accentAlt)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis(.hidden)
            .frame(height: 110)
            Text("Green = fundamentals. Blue = market (moves when comparable players sign).")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    private func compsCard(_ comps: [MarketPlayer]) -> some View {
        SectionCard("Comparables") {
            VStack(spacing: 0) {
                ForEach(comps) { c in
                    HStack {
                        Text(c.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Spacer()
                        Text(c.aav.map { "paid \($0.asCapMoney)" } ?? "unsigned")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Text(c.marketValue.asCapMoney)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .frame(width: 66, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                    if c.id != comps.last?.id { Divider().overlay(Theme.Palette.border) }
                }
            }
        }
    }

    private func fitsCard(_ fits: [TeamFit]) -> some View {
        SectionCard("Best fits — need + cap space") {
            VStack(spacing: 0) {
                ForEach(fits) { f in
                    HStack(spacing: Theme.Spacing.sm) {
                        CrestView(abbrev: f.team, size: 28)
                        Text(TeamInfo.lookup(f.team).name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        if f.needMatch == 2 {
                            StatusPill(text: "PRIMARY NEED", color: Theme.Palette.accent)
                        }
                        Spacer()
                        Text("\(f.capSpace.asCapMoney) space")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.Palette.positive)
                    }
                    .padding(.vertical, 6)
                    if f.id != fits.last?.id { Divider().overlay(Theme.Palette.border) }
                }
            }
        }
    }
}
