import SwiftUI

/// Scoreline probability grid (away goals × home goals) from the model's
/// expected goals. Visualizes where the game is most likely to land.
struct PoissonHeatmapView: View {
    let awayMean: Double
    let homeMean: Double
    let awayAbbrev: String
    let homeAbbrev: String
    var tint: Color = Theme.Palette.accent

    private let maxGoals = 6

    private var matrix: [[Double]] {
        Poisson.matrix(awayMean: awayMean, homeMean: homeMean, maxGoals: maxGoals)
    }
    private var maxProb: Double { matrix.flatMap { $0 }.max() ?? 1 }
    private var argmax: (a: Int, h: Int, p: Double) {
        var best = (a: 0, h: 0, p: 0.0)
        for a in 0...maxGoals {
            for h in 0...maxGoals where matrix[a][h] > best.p {
                best = (a, h, matrix[a][h])
            }
        }
        return best
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Most likely score  \(awayAbbrev) \(argmax.a)–\(argmax.h) \(homeAbbrev)  ·  \(Int((argmax.p * 100).rounded()))%")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.textSecondary)

            grid

            HStack {
                Text("← \(homeAbbrev) goals")
                Spacer()
                Text("\(awayAbbrev) goals ↑")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    private var grid: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow {
                Color.clear.frame(width: 16, height: 16)
                ForEach(0...maxGoals, id: \.self) { h in
                    axisLabel("\(h)")
                }
            }
            ForEach(0...maxGoals, id: \.self) { a in
                GridRow {
                    axisLabel("\(a)")
                    ForEach(0...maxGoals, id: \.self) { h in
                        cell(a: a, h: h)
                    }
                }
            }
        }
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 16)
    }

    private func cell(a: Int, h: Int) -> some View {
        let prob = matrix[a][h]
        let intensity = maxProb > 0 ? prob / maxProb : 0
        let isPeak = a == argmax.a && h == argmax.h
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(tint.opacity(0.08 + 0.85 * intensity))
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if isPeak {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Theme.Palette.textPrimary, lineWidth: 1.5)
                }
            }
            .accessibilityLabel("\(awayAbbrev) \(a), \(homeAbbrev) \(h): \(Int((prob * 100).rounded())) percent")
    }
}
