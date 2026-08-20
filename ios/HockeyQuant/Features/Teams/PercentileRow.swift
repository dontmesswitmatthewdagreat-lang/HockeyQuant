import SwiftUI

/// One metric expressed as a league percentile, shared by the skater and goalie
/// impact sheets.
///
/// The bar is centred on the 50th rather than filling from zero, because the
/// question a percentile answers is "better or worse than his peers", and a
/// left-filling bar reads that instantly where a 0–100 fill doesn't.
struct PercentileMetric: Hashable {
    let key: String
    let label: String
    let detail: String
}

struct PercentileRow: View {
    let metric: PercentileMetric
    let percentile: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(metric.label.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.5)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                Text("\(percentile)\(Self.ordinalSuffix(percentile))")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.tint(for: percentile))
                Text("percentile")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            DivergingBar(edge: (Double(percentile) - 50) / 50)
            Text(metric.detail)
                .font(.system(size: 10))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    static func tint(for pct: Int) -> Color {
        if pct >= 75 { return Theme.Palette.positive }
        if pct <= 25 { return Theme.Palette.negative }
        return Theme.Palette.textPrimary
    }

    static func ordinalSuffix(_ n: Int) -> String {
        switch n % 100 {
        case 11...13: return "th"
        default:
            switch n % 10 {
            case 1: return "st"
            case 2: return "nd"
            case 3: return "rd"
            default: return "th"
            }
        }
    }
}

/// The scale anchors that make a centred bar readable.
struct PercentileLegend: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("0")
            Spacer()
            Text("50 · avg")
            Spacer()
            Text("100")
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Theme.Palette.textTertiary)
    }
}
