import SwiftUI
import Charts

// MARK: - Market temperature (fear & greed for the FA market)

/// A 0–100 read on how the free-agent market is pricing players against the
/// same valuation model that powers the GM tab: 50 = signings landing on fair
/// value, higher = teams paying up, lower = bargains everywhere.
struct MarketTemperature {
    let score: Int
    let label: String
    let color: Color

    init?(_ o: MarketOverview) {
        // Prefer real graded signings; fall back to positional heat when the
        // signing sample is too thin to call a trend.
        let premiums = o.signings.map { ($0.aav - $0.fairValue) / $0.fairValue }
        let raw: Double
        if premiums.count >= 3 {
            raw = premiums.reduce(0, +) / Double(premiums.count)
        } else if !o.heat.isEmpty {
            raw = o.heat.values.reduce(0, +) / Double(o.heat.count) / 100
        } else {
            return nil
        }
        // ±25% premium pins the ends of the dial.
        score = max(2, min(98, Int((50 + raw * 200).rounded())))
        switch score {
        case ..<20:  label = "ICE COLD";   color = Color(hex: 0x3D8BDD)
        case ..<42:  label = "COOL";       color = Color(hex: 0x2FA6A0)
        case ...58:  label = "FAIR VALUE"; color = Color(hex: 0x8E9AA9)
        case ...80:  label = "HOT";        color = Color(hex: 0xE8842A)
        default:     label = "OVERHEATED"; color = Color(hex: 0xD64545)
        }
    }
}

// MARK: - Gauge

/// The deck's shared five-step color ramp (cold → hot) and subline tints.
enum PulseTone {
    static let ramp: [Color] = [
        Color(hex: 0x3D8BDD), Color(hex: 0x2FA6A0), Color(hex: 0x8E9AA9),
        Color(hex: 0xE8842A), Color(hex: 0xD64545),
    ]

    static func color(for score: Int) -> Color {
        switch score {
        case ..<20: return ramp[0]
        case ..<42: return ramp[1]
        case ...58: return ramp[2]
        case ...80: return ramp[3]
        default:    return ramp[4]
        }
    }

    static func tint(_ name: String?) -> Color {
        switch name {
        case "hot":  return Color(hex: 0xE8842A)
        case "cold": return Color(hex: 0x4FB6E8)
        default:     return .white
        }
    }
}

/// Semicircular fear-&-greed dial: five color segments, a needle, and a big
/// count-up score. The arc is a fixed-size Canvas so the news feed never has
/// to negotiate its layout.
private struct PulseGauge: View {
    let score: Int
    let label: String
    let color: Color
    let reveal: Bool
    var diameter: CGFloat = 150

    init(temp: MarketTemperature, reveal: Bool, diameter: CGFloat = 150) {
        self.score = temp.score; self.label = temp.label
        self.color = temp.color; self.reveal = reveal; self.diameter = diameter
    }

    init(score: Int, label: String, reveal: Bool, diameter: CGFloat = 150) {
        self.score = score; self.label = label
        self.color = PulseTone.color(for: score)
        self.reveal = reveal; self.diameter = diameter
    }

    private var shownScore: Int { reveal ? score : 50 }

    private static let segments: [Color] = PulseTone.ramp

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                Canvas { ctx, size in
                    let center = CGPoint(x: size.width / 2, y: size.height - 3)
                    let radius = size.width / 2 - 6
                    for (i, color) in Self.segments.enumerated() {
                        let lead = i == 0 ? 0.0 : 2.5
                        let trail = i == Self.segments.count - 1 ? 0.0 : 2.5
                        var p = Path()
                        p.addArc(center: center, radius: radius,
                                 startAngle: .degrees(180 + Double(i) * 36 + lead),
                                 endAngle: .degrees(180 + Double(i + 1) * 36 - trail),
                                 clockwise: false)
                        ctx.stroke(p, with: .color(color),
                                   style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    }
                }
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: diameter / 2 - 18)
                    .offset(y: -3)
                    .rotationEffect(.degrees(Double(shownScore) / 100 * 180 - 90),
                                    anchor: .bottom)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                Circle().fill(.white).frame(width: 9, height: 9).offset(y: 1)
            }
            .frame(width: diameter, height: diameter / 2 + 6)

            VStack(spacing: 1) {
                Text("\(shownScore)")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(shownScore)))
                Text(label)
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.2)
                    .foregroundStyle(color)
            }
        }
        .frame(width: diameter)
    }
}

// MARK: - Feed card

/// Compact market read tucked into the news feed — tap for the full desk.
struct MarketPulseCard: View {
    let overview: MarketOverview
    let onExpand: () -> Void

    @State private var reveal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let temp = MarketTemperature(overview) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Text("MARKET PULSE")
                        .font(.system(size: 12, weight: .heavy))
                        .kerning(1.4)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    HStack(spacing: 3) {
                        Text("DETAILS")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(0.8)
                    .foregroundStyle(.white.opacity(0.35))
                }

                HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                    PulseGauge(temp: temp, reveal: reveal)
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        heatLine("FORWARDS", overview.heat["F"])
                        heatLine("DEFENSE", overview.heat["D"])
                        VStack(alignment: .leading, spacing: 1) {
                            Text("SIGNINGS GRADED")
                                .font(.system(size: 9, weight: .heavy))
                                .kerning(0.8)
                                .foregroundStyle(.white.opacity(0.45))
                            Text("\(overview.signings.count)")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.top, 2)
                    Spacer(minLength: 0)
                }

                if overview.index.count >= 2 {
                    indexSparkline
                }

                Spacer(minLength: 0)

                Text("HOCKEYQUANT · MARKET DESK")
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.2)
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(hex: 0x10141B))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .onTapGesture { onExpand() }
            // One tappable unit — also keeps the AX walk from descending into
            // the dial/sparkline subtree (which can wedge lazy-stack audits).
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Market pulse: \(temp.score), \(temp.label). Tap for details.")
            .task {
                guard !reveal else { return }
                try? await Task.sleep(nanoseconds: 300_000_000)
                withAnimation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.75)) {
                    reveal = true
                }
            }
        }
    }

    private func heatLine(_ label: String, _ pct: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .kerning(0.8)
                .foregroundStyle(.white.opacity(0.45))
            Text(pct.map { String(format: "%+.1f%% vs model", $0) } ?? "—")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(heatColor(pct))
        }
    }

    private func heatColor(_ pct: Double?) -> Color {
        guard let pct else { return .white.opacity(0.5) }
        if pct > 5 { return Color(hex: 0xE8842A) }
        if pct < -5 { return Color(hex: 0x4FB6E8) }
        return .white
    }

    private var indexSparkline: some View {
        let values = overview.index.map(\.value)
        return VStack(alignment: .leading, spacing: 4) {
            // Hand-rolled: Swift Charts fought the lazy feed (layout loop);
            // a Path is plenty for a sparkline.
            ZStack {
                SparklineShape(values: values, closed: true)
                    .fill(LinearGradient(colors: [Color(hex: 0x35C489).opacity(0.25), .clear],
                                         startPoint: .top, endPoint: .bottom))
                SparklineShape(values: values)
                    .stroke(Color(hex: 0x35C489),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .padding(.vertical, 2)
            .frame(height: 46)
            HStack {
                Text("TOP-100 VALUE INDEX")
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(0.8)
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                if let delta = indexDelta {
                    Text(String(format: "%+.1f%%", delta))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(delta >= 0 ? Color(hex: 0x35C489) : Color(hex: 0xD64545))
                }
            }
        }
    }

    /// Change in the index across the snapshot window.
    private var indexDelta: Double? {
        guard let first = overview.index.first?.value,
              let last = overview.index.last?.value, first > 0 else { return nil }
        return (last - first) / first * 100
    }
}

// MARK: - League pulse card (luck / race / deadline / playoffs)

/// One page of the pulse deck for a league-wide read. Dormant pulses keep
/// their spot with a note about when they light up instead of disappearing.
struct LeaguePulseCard: View {
    let pulse: LeaguePulse
    let onExpand: () -> Void

    @State private var reveal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let icons: [String: String] = [
        "luck": "dice.fill", "race": "flag.checkered",
        "deadline": "arrow.left.arrow.right", "playoffs": "trophy.fill",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text(pulse.kicker)
                    .font(.system(size: 12, weight: .heavy))
                    .kerning(1.4)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if pulse.active {
                    HStack(spacing: 3) {
                        Text("DETAILS")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(0.8)
                    .foregroundStyle(.white.opacity(0.35))
                } else if let season = pulse.season {
                    Text(season)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            if pulse.active, let score = pulse.score, let label = pulse.label {
                HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                    PulseGauge(score: score, label: label, reveal: reveal)
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ForEach(pulse.sublines, id: \.self) { sub in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(sub.label)
                                    .font(.system(size: 9, weight: .heavy))
                                    .kerning(0.8)
                                    .foregroundStyle(.white.opacity(0.45))
                                Text(sub.value)
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundStyle(PulseTone.tint(sub.tint))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }
                    .padding(.top, 2)
                    Spacer(minLength: 0)
                }
                if let note = pulse.note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            } else {
                Spacer(minLength: 0)
                VStack(spacing: Theme.Spacing.sm) {
                    ZStack {
                        Circle().fill(.white.opacity(0.08)).frame(width: 56, height: 56)
                        Image(systemName: Self.icons[pulse.id] ?? "hourglass")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Text(pulse.note ?? "Back soon.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.md)
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)

            Text("HOCKEYQUANT · LEAGUE DESK")
                .font(.system(size: 10, weight: .heavy))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: 0x10141B))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .onTapGesture { if pulse.active { onExpand() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(pulse.active ? .isButton : [])
        .accessibilityLabel(pulse.active && pulse.score != nil
                            ? "\(pulse.kicker): \(pulse.score!), \(pulse.label ?? ""). Tap for details."
                            : "\(pulse.kicker): \(pulse.note ?? "dormant")")
        .task {
            guard !reveal else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.75)) {
                reveal = true
            }
        }
    }
}

/// Floating-card detail for a league pulse: dial, explainer, and the ranked
/// team rows behind the score.
struct LeaguePulseSheet: View {
    let pulse: LeaguePulse

    @State private var reveal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(pulse.kicker.capitalized)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)

                if let score = pulse.score, let label = pulse.label {
                    VStack(spacing: Theme.Spacing.sm) {
                        PulseGauge(score: score, label: label, reveal: reveal, diameter: 170)
                        if let explainer = pulse.explainer {
                            Text(explainer)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.65))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.md)
                    .background(Color(hex: 0x10141B))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                }

                if !pulse.rows.isEmpty {
                    SectionCard("The numbers") {
                        VStack(spacing: Theme.Spacing.sm) {
                            ForEach(Array(pulse.rows.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: Theme.Spacing.sm) {
                                    if let team = row.team {
                                        CrestView(abbrev: team, size: 26)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(row.title)
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(Theme.Palette.textPrimary)
                                            .lineLimit(1)
                                        if let detail = row.detail {
                                            Text(detail)
                                                .font(.system(size: 11))
                                                .foregroundStyle(Theme.Palette.textSecondary)
                                        }
                                    }
                                    Spacer(minLength: Theme.Spacing.xs)
                                    Text(row.value)
                                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                                        .foregroundStyle(row.positive == nil ? Theme.Palette.textPrimary
                                                         : row.positive! ? Theme.Palette.positive
                                                         : Theme.Palette.negative)
                                }
                            }
                        }
                    }
                }

                if let note = pulse.note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .frame(maxHeight: 620)
        .task {
            guard !reveal else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.75)) {
                reveal = true
            }
        }
    }
}

// MARK: - Pulse deck (swipeable)

/// The News tab's vitals: Market Pulse plus the league pulses as swipeable
/// pages of one fixed-height card, with pager dots underneath.
struct PulseDeck: View {
    let overview: MarketOverview?
    let pulses: [LeaguePulse]
    let onMarketDetail: () -> Void
    let onLeagueDetail: (LeaguePulse) -> Void

    @State private var page = 0

    private var pageCount: Int { (overview != nil ? 1 : 0) + pulses.count }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            TabView(selection: $page) {
                if let overview {
                    MarketPulseCard(overview: overview, onExpand: onMarketDetail)
                        .tag(0)
                }
                ForEach(Array(pulses.enumerated()), id: \.element.id) { i, pulse in
                    LeaguePulseCard(pulse: pulse) { onLeagueDetail(pulse) }
                        .tag(i + (overview != nil ? 1 : 0))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 312)

            if pageCount > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Theme.Palette.accent : Theme.Palette.textTertiary.opacity(0.4))
                            .frame(width: i == page ? 16 : 5, height: 5)
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
            }
        }
    }
}

/// Minimal min–max normalized line; `closed` adds the baseline for area fills.
private struct SparklineShape: Shape {
    let values: [Double]
    var closed = false

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard values.count >= 2, let lo = values.min(), let hi = values.max() else { return p }
        let span = hi - lo
        let pts = values.enumerated().map { i, v in
            CGPoint(x: rect.minX + CGFloat(i) / CGFloat(values.count - 1) * rect.width,
                    y: span > 0 ? rect.maxY - CGFloat((v - lo) / span) * rect.height : rect.midY)
        }
        p.move(to: pts[0])
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        if closed {
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }
}

// MARK: - Detail sheet (floating card)

/// The full market desk: dial, positional heat, index chart, movers, and the
/// latest signings graded against model fair value.
struct MarketPulseSheet: View {
    let overview: MarketOverview

    @State private var reveal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Market Pulse")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)

                if let temp = MarketTemperature(overview) {
                    VStack(spacing: Theme.Spacing.sm) {
                        PulseGauge(temp: temp, reveal: reveal, diameter: 170)
                        Text("How this offseason's signings are pricing against the model — 50 means deals land on fair value, higher means teams are paying up.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.md)
                    .background(Color(hex: 0x10141B))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                }

                if overview.index.count >= 2 {
                    SectionCard("Top-100 value index") {
                        Chart(overview.index) { pt in
                            LineMark(x: .value("Date", pt.date), y: .value("Value", pt.value / 1_000_000))
                                .foregroundStyle(Color(hex: 0x1F8A5B))
                                .interpolationMethod(.monotone)
                            AreaMark(x: .value("Date", pt.date), y: .value("Value", pt.value / 1_000_000))
                                .foregroundStyle(Color(hex: 0x1F8A5B).opacity(0.12))
                        }
                        .chartXAxis(.hidden)
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 110)
                    }
                }

                if !overview.movers.isEmpty {
                    SectionCard("Today's movers") {
                        VStack(spacing: Theme.Spacing.xs) {
                            ForEach(overview.movers.prefix(5)) { m in
                                HStack {
                                    Text(m.name)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(Theme.Palette.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(m.marketValue.asCapMoney)
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Theme.Palette.textSecondary)
                                    Text(String(format: "%+.1f%%", m.deltaPct))
                                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                                        .foregroundStyle(m.deltaPct >= 0 ? Theme.Palette.positive : Theme.Palette.negative)
                                        .frame(width: 58, alignment: .trailing)
                                }
                            }
                        }
                    }
                }

                if !overview.signings.isEmpty {
                    SectionCard("Latest signings, graded") {
                        VStack(spacing: Theme.Spacing.sm) {
                            ForEach(overview.signings.prefix(6)) { s in
                                HStack(spacing: Theme.Spacing.sm) {
                                    CrestView(abbrev: s.team, size: 26)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(s.name)
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(Theme.Palette.textPrimary)
                                            .lineLimit(1)
                                        Text("\(s.aav.asCapMoney)\(s.years.map { " × \($0) yr" } ?? "") · model \(s.fairValue.asCapMoney)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.Palette.textSecondary)
                                    }
                                    Spacer(minLength: Theme.Spacing.xs)
                                    if let v = s.verdict {
                                        StatusPill(text: v.verdictLabel,
                                                   color: v == "steal" ? Theme.Palette.positive
                                                        : v == "overpay" ? Theme.Palette.negative
                                                        : Theme.Palette.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Text("Same ridge-regression player market that powers the GM tab — see any player's full valuation there.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Spacing.md)
        }
        .frame(maxHeight: 620)
        .task {
            guard !reveal else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.75)) {
                reveal = true
            }
        }
    }
}
