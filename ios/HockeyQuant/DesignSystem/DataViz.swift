import SwiftUI

/// Data‑visualization kit — the shared vocabulary for presenting numbers as
/// verdicts (inspired by fintech dashboards): status badges, titled section
/// cards, diverging/multiplier gauges, and proportion bars. Built once here so
/// the game breakdown, Models, Statistics, and Play can all speak the same
/// visual language.

// MARK: - Status pill (verdict badge)

/// A small color‑coded badge that states a conclusion + magnitude at a glance
/// (e.g. "LAK ML", "Cover edge", "Over lean"). `soft` = tinted background;
/// `solid` = filled for extra emphasis (a strong pick).
struct StatusPill: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = Theme.Palette.textSecondary
    var solid: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .heavy))
            }
            Text(text).font(.system(size: 11, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(solid ? AnyShapeStyle(.white) : AnyShapeStyle(color))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(solid ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.15)))
        .clipShape(Capsule())
    }
}

// MARK: - Section card (titled card chrome)

/// A titled card: small‑caps section header on the left, an optional accessory
/// (a verdict badge / control) on the right, then the content. The repeatable
/// dashboard chrome every screen reuses.
struct SectionCard<Content: View>: View {
    let title: String
    var accessory: AnyView?
    @ViewBuilder var content: () -> Content

    init(_ title: String, accessory: AnyView? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.Palette.textTertiary)
                    Spacer(minLength: 0)
                    accessory
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Diverging bar (center‑anchored)

/// Fills left (edge < 0) or right (edge > 0) from the center by `|edge|`, over an
/// inset groove with a center tick. The core "who leans which way, by how much"
/// primitive.
struct DivergingBar: View {
    let edge: Double                 // −1 (left) … +1 (right)
    var leftColor: Color = Theme.Palette.negative
    var rightColor: Color = Theme.Palette.positive
    var height: CGFloat = 9

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let mag = min(abs(edge), 1)
            let fillW = half * mag
            ZStack {
                Capsule().fill(Theme.Palette.background)
                Rectangle().fill(Theme.Palette.border).frame(width: 1)      // center tick
                Capsule()
                    .fill(edge >= 0 ? rightColor : leftColor)
                    .frame(width: max(fillW, mag > 0.001 ? 4 : 0))
                    .position(x: edge >= 0 ? half + fillW / 2 : half - fillW / 2,
                              y: geo.size.height / 2)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Multiplier gauge (centered at ×1.00)

/// Shows a score multiplier as a boost (green, right) or drag (red, left) from a
/// center at ×1.00 — turns "×0.980 / ×1.072" decimals into an instant read.
struct MultiplierGauge: View {
    let value: Double          // ~0.88 … 1.12
    var span: Double = 0.12    // ± this maps to the full half‑width

    var body: some View {
        let edge = max(-1.0, min(1.0, (value - 1.0) / span))
        DivergingBar(edge: edge,
                     leftColor: Theme.Palette.negative,
                     rightColor: Theme.Palette.positive,
                     height: 7)
    }
}

// MARK: - Split bar (two‑sided proportion)

/// A two‑color proportion bar (away vs home, over vs under). `leftFraction` is
/// the left share of the total (0…1).
struct SplitBar: View {
    let leftFraction: Double
    let leftColor: Color
    let rightColor: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                leftColor.frame(width: max(0, geo.size.width * CGFloat(min(max(leftFraction, 0), 1))))
                rightColor
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

// MARK: - Prob bar (single value fill)

/// A single‑value fill over an inset groove (cover %, best‑bet %, hit rate).
/// `fraction` 0…1; an optional `reference` draws a benchmark tick (e.g. break‑even).
struct ProbBar: View {
    let fraction: Double
    var tint: Color = Theme.Palette.accent
    var reference: Double? = nil
    var height: CGFloat = 8

    private func clamp(_ v: Double) -> CGFloat { CGFloat(min(max(v, 0), 1)) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.background)
                Capsule().fill(tint)
                    .frame(width: max(0, geo.size.width * clamp(fraction)))
                if let reference {
                    Rectangle().fill(Theme.Palette.textPrimary.opacity(0.5))
                        .frame(width: 1.5)
                        .offset(x: geo.size.width * clamp(reference) - 0.75)
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Range gauge

/// A value's position on a track between two labeled extremes — the signature
/// "where does this sit" gauge (52‑week range, valuation, XP‑to‑next‑tier).
/// `filled` fills the track up to the marker (progress); otherwise it's a plain
/// track with just the dot. `gradient` paints the whole track (e.g. red→green).
struct RangeGauge: View {
    let fraction: Double            // 0…1 marker position
    var loLabel: String? = nil
    var hiLabel: String? = nil
    var tint: Color = Theme.Palette.accent
    var filled: Bool = false
    var gradient: [Color]? = nil

    private func clamp(_ v: Double) -> CGFloat { CGFloat(min(max(v, 0), 1)) }

    private var trackStyle: AnyShapeStyle {
        if let gradient {
            return AnyShapeStyle(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
        }
        return AnyShapeStyle(Theme.Palette.background)
    }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let x = geo.size.width * clamp(fraction)
                ZStack(alignment: .leading) {
                    Capsule().fill(trackStyle).frame(height: 6).frame(maxHeight: .infinity)
                    if filled && gradient == nil {
                        Capsule().fill(tint).frame(width: max(6, x), height: 6).frame(maxHeight: .infinity)
                    }
                    Circle().fill(tint)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(Theme.Palette.surface, lineWidth: 2))
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .offset(x: x - 6.5)
                }
            }
            .frame(height: 14)
            if loLabel != nil || hiLabel != nil {
                HStack(spacing: 0) {
                    if let loLabel { Text(loLabel) }
                    Spacer(minLength: 0)
                    if let hiLabel { Text(hiLabel) }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }
}

// MARK: - Sparkline

/// A tiny axis‑free trend line with a soft area fill, normalized to its own
/// min…max (a 30‑day‑trend style mini chart). Reused by hero cards + Models.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = Theme.Palette.accent
    var lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            if pts.count > 1 {
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.20), tint.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let range = max(hi - lo, 0.0001)
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * stepX,
                    y: size.height * (1 - CGFloat((v - lo) / range)))
        }
    }
}
