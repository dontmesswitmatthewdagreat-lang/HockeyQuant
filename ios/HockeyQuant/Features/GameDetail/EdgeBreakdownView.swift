import SwiftUI

/// A deterministic, always-accurate replacement for the old AI "Why [team]?" card.
/// For each real model factor it shows which side is favored (a diverging bar) and
/// distills the strongest ones into a one-line plain-English verdict — no LLM.
struct EdgeBreakdownView: View {
    let game: GamePrediction

    @State private var appeared = false

    private var away: TeamInfo { game.away.info }
    private var home: TeamInfo { game.home.info }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header
            ForEach(factors) { f in
                HStack(spacing: Theme.Spacing.sm) {
                    Text(f.label)
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 104, alignment: .leading)
                    DivergingBar(edge: appeared ? f.edge : 0,
                                 leftColor: away.color, rightColor: home.color)
                    StatusPill(text: f.favored(away: away.abbrev, home: home.abbrev),
                               color: f.favoredColor(away: away.color, home: home.color))
                        .frame(width: 52, alignment: .trailing)
                }
            }
            verdictRow
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.05)) { appeared = true }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(away.abbrev).foregroundStyle(away.color)
            Text("◄ who leans which way ►")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(maxWidth: .infinity)
            Text(home.abbrev).foregroundStyle(home.color)
        }
        .font(.system(size: 11, weight: .heavy, design: .rounded))
    }

    private var verdictRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Palette.accent)
            Text(verdict)
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(.top, 2)
    }

    // MARK: - Factor math (edge: −1 = away … +1 = home)

    private var factors: [EdgeFactor] {
        let a = game.away, h = game.home
        var list: [EdgeFactor] = [
            EdgeFactor(label: "Goalie (GSAX)", edge: clamp((h.goalieGsax - a.goalieGsax) / 8)),
            EdgeFactor(label: "Form / streak", edge: clamp((h.streakMult - a.streakMult) / 0.12)),
            EdgeFactor(label: "Special teams", edge: clamp((h.stMult - a.stMult) / 0.10)),
            EdgeFactor(label: "Fatigue", edge: clamp((h.fatigueMult - a.fatigueMult) / 0.10)),
            EdgeFactor(label: "Injuries", edge: clamp((h.injuryMult - a.injuryMult) / 0.10)),
            EdgeFactor(label: "Head-to-head", edge: clamp((h.h2hMult - a.h2hMult) / 0.12)),
        ]
        if let l = game.bettingLines {
            list.insert(EdgeFactor(label: "Expected goals",
                                   edge: clamp((l.homeExpectedGoals - l.awayExpectedGoals) / 1.5)), at: 1)
        }
        return list
    }

    private var verdict: String {
        let pickHome = game.pickIsHome
        let favoring = factors
            .filter { pickHome ? $0.edge > EdgeFactor.threshold : $0.edge < -EdgeFactor.threshold }
            .sorted { abs($0.edge) > abs($1.edge) }
            .prefix(2)
            .map { $0.shortLabel }
        guard !favoring.isEmpty else {
            return "\(game.pick) is a slim, low-confidence edge — close to a coin flip."
        }
        let joined = favoring.count == 2 ? "\(favoring[0]) and \(favoring[1])" : favoring[0]
        return "\(game.pick)'s edge comes from \(joined)."
    }

    private func clamp(_ v: Double) -> Double { min(1, max(-1, v)) }
}

private struct EdgeFactor: Identifiable {
    static let threshold = 0.12
    let label: String
    let edge: Double
    var id: String { label }

    var shortLabel: String {
        label.replacingOccurrences(of: " (GSAX)", with: "")
            .replacingOccurrences(of: "Goalie", with: "goaltending")
            .lowercased()
    }

    func favored(away: String, home: String) -> String {
        abs(edge) < Self.threshold ? "EVEN" : (edge > 0 ? home : away)
    }

    func favoredColor(away: Color, home: Color) -> Color {
        abs(edge) < Self.threshold ? Theme.Palette.textTertiary : (edge > 0 ? home : away)
    }
}
