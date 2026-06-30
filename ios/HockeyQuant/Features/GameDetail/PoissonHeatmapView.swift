import SwiftUI

/// Scoreline probability grid (away goals × home goals). Shows the model's
/// projected score distribution (a gradient heat-map, peak = most likely). While a
/// game is *in progress* it conditions on the current score + time remaining so the
/// heat shifts and narrows; for a final it shows the projection with the actual
/// result marked. The reveal animation ripples outward from the focus cell.
struct PoissonHeatmapView: View {
    let awayMean: Double
    let homeMean: Double
    let awayAbbrev: String
    let homeAbbrev: String
    var tint: Color = Theme.Palette.accent
    var liveAway: Int? = nil
    var liveHome: Int? = nil
    var fractionElapsed: Double = 0     // 0 = pregame … 1 = final
    var isFinal: Bool = false

    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLive: Bool { liveAway != nil && !isFinal }
    private var active: Bool { liveAway != nil }     // live or final → has an actual score
    private var actualCell: (a: Int, h: Int)? {
        guard active, let a = liveAway, let h = liveHome else { return nil }
        return (a, h)
    }

    private var maxGoals: Int {
        let m = max(actualCell?.a ?? 0, actualCell?.h ?? 0)
        return min(9, max(6, m + 1))
    }

    /// Heat distribution: live-conditioned while in progress, projection otherwise
    /// (so pregame AND final keep a full gradient).
    private var matrix: [[Double]] {
        if isLive, let a = liveAway, let h = liveHome, fractionElapsed > 0 {
            let f = min(max(fractionElapsed, 0), 1)
            let rem = Poisson.matrix(awayMean: awayMean * (1 - f),
                                     homeMean: homeMean * (1 - f), maxGoals: maxGoals)
            var m = Array(repeating: Array(repeating: 0.0, count: maxGoals + 1), count: maxGoals + 1)
            guard a <= maxGoals, h <= maxGoals else { return m }
            for fa in a...maxGoals {
                for fh in h...maxGoals { m[fa][fh] = rem[fa - a][fh - h] }
            }
            return m
        }
        return Poisson.matrix(awayMean: awayMean, homeMean: homeMean, maxGoals: maxGoals)
    }

    private var maxProb: Double { matrix.flatMap { $0 }.max() ?? 1 }
    private var argmax: (a: Int, h: Int, p: Double) {
        var best = (a: 0, h: 0, p: 0.0)
        for a in 0...maxGoals {
            for h in 0...maxGoals where matrix[a][h] > best.p { best = (a, h, matrix[a][h]) }
        }
        return best
    }
    /// The reveal always ripples out from the model's most-likely (peak) cell.
    private var origin: (a: Int, h: Int) { (argmax.a, argmax.h) }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header
            HStack {
                Text("↓ \(homeAbbrev) goals")
                Spacer()
                Text("\(awayAbbrev) goals →")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: 340)
            grid
                .frame(maxWidth: 340)
                .animation(.easeInOut(duration: 0.5), value: liveAway)
                .animation(.easeInOut(duration: 0.5), value: liveHome)
            if active { legend }
        }
        .onAppear {
            guard !revealed else { return }
            if reduceMotion { revealed = true; return }
            // Hold the reveal until the hero-expand morph + fade finish, so the
            // outward ripple actually plays on-screen.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.45))
                revealed = true
            }
        }
    }

    @ViewBuilder private var header: some View {
        if let act = actualCell {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(isFinal ? "Final" : "Live")
                        .foregroundStyle(isFinal ? Theme.Palette.textSecondary : Theme.Palette.live)
                    Text("\(awayAbbrev) \(act.a)–\(act.h) \(homeAbbrev)")
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .contentTransition(.numericText())
                }
                .font(Theme.Font.caption())
                Text("Model's most likely was \(awayAbbrev) \(argmax.a)–\(argmax.h) \(homeAbbrev)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        } else {
            HStack(spacing: 5) {
                Text("Most likely")
                Text("\(awayAbbrev) \(argmax.a)–\(argmax.h) \(homeAbbrev)")
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(.numericText())
                Text("· \(Int((argmax.p * 100).rounded()))%")
            }
            .font(Theme.Font.caption())
            .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var grid: some View {
        // Away (the team listed first in the score) runs left→right across the top;
        // home runs top→bottom down the side.
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow {
                Color.clear.frame(width: 16, height: 16)
                ForEach(0...maxGoals, id: \.self) { a in axisLabel("\(a)") }   // top = away goals
            }
            ForEach(0...maxGoals, id: \.self) { h in                          // rows = home goals
                GridRow {
                    axisLabel("\(h)")
                    ForEach(0...maxGoals, id: \.self) { a in cell(a: a, h: h) }
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
        let isActual = actualCell.map { $0.a == a && $0.h == h } ?? false
        let isPeak = a == argmax.a && h == argmax.h
        let dist = (Double((a - origin.a) * (a - origin.a) + (h - origin.h) * (h - origin.h))).squareRoot()
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(tint.opacity(0.08 + 0.85 * intensity))           // gradient on every cell → peak is darkest
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {                                              // model's most-likely score
                if isPeak {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white, lineWidth: 2)
                }
            }
            .overlay {                                              // actual / live result
                if isActual {
                    Circle().fill(Color.white)
                        .overlay(Circle().fill(tint).padding(2.5))
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.35), radius: 1)
                }
            }
            .scaleEffect(revealed ? 1 : 0.2)
            .opacity(revealed ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.72).delay(dist * 0.085), value: revealed)
            .accessibilityLabel("\(awayAbbrev) \(a), \(homeAbbrev) \(h): \(Int((prob * 100).rounded())) percent\(isActual ? ", actual result" : "")\(isPeak ? ", model's most likely" : "")")
    }

    private var legend: some View {
        HStack(spacing: Theme.Spacing.md) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tint.opacity(0.7))
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Color.white, lineWidth: 2))
                    .frame(width: 13, height: 13)
                Text("model's most likely").font(.system(size: 10)).foregroundStyle(Theme.Palette.textSecondary)
            }
            HStack(spacing: 4) {
                Circle().fill(Color.white).overlay(Circle().fill(tint).padding(2.5))
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(Theme.Palette.border, lineWidth: 0.5))
                Text(isFinal ? "actual final" : "live score").font(.system(size: 10)).foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: 340)
    }
}
