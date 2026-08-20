import SwiftUI

/// One skater's season, read two ways: what he produced (Game Score) and what
/// happened to the run of play while he was out there (on-ice expected goals).
///
/// Everything is shown as a league percentile inside his own position group —
/// a defenceman shouldn't read as a bottom-percentile player for scoring less
/// than a winger. Players under the ice-time floor get their raw numbers but no
/// percentile, because a rate off a small sample is noise wearing a rank.
struct PlayerImpactSheet: View {
    let skater: SkaterImpact
    var teamColor: Color = Theme.Palette.accent

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                header
                if skater.isRanked {
                    percentileCard
                } else {
                    unrankedNote
                }
                productionCard
                if skater.evIcetime != nil { runOfPlayCard }
            }
            .padding(Theme.Spacing.md)
        }
        .frame(maxHeight: 640)
    }

    // MARK: - Header

    private var header: some View {
        Card {
            VStack(spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    CrestView(abbrev: skater.team, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skater.name)
                            .font(Theme.Font.title())
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(skater.position) · \(skater.gamesPlayed) GP · \(String(format: "%.1f", skater.toiPerGame)) min/gp")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                Divider().overlay(Theme.Palette.border)
                HStack(spacing: Theme.Spacing.sm) {
                    StatPill(label: "Game Score", value: String(format: "%.1f", skater.gameScore))
                    Divider().frame(height: 32).overlay(Theme.Palette.border)
                    StatPill(label: "per 60", value: String(format: "%.2f", skater.gameScorePer60))
                    Divider().frame(height: 32).overlay(Theme.Palette.border)
                    StatPill(label: "Points", value: "\(Int(skater.points))")
                }
            }
        }
    }

    // MARK: - Percentiles

    typealias Metric = PercentileMetric

    /// Ordered by how much they say about a player, not alphabetically.
    private var metrics: [Metric] {
        [
            Metric(key: "game_score_per60", label: "Production",
                   detail: "Game Score per 60 — goals, assists, shots, penalties and possession in one number"),
            Metric(key: "xgf_pct_rel", label: "On-ice impact",
                   detail: "Share of expected goals with him on the ice, minus the same share when he's off it"),
            Metric(key: "xgf_per60", label: "Offense",
                   detail: "Expected goals his team creates per 60 at 5-on-5"),
            Metric(key: "xga_per60", label: "Defense",
                   detail: "Expected goals allowed per 60 at 5-on-5 — ranked so higher is better"),
            Metric(key: "finishing", label: "Finishing",
                   detail: "Goals above or below what his shots were worth"),
            Metric(key: "penalty_differential", label: "Penalties",
                   detail: "Drawn minus taken"),
        ]
    }

    private var percentileCard: some View {
        SectionCard("League percentile · \(skater.positionGroup == "D" ? "vs defencemen" : "vs forwards")") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // The bars are centred on the 50th, which is unreadable unless
                // the scale is stated. "80th" means better than 80% of his peers,
                // not a score out of 100.
                Text("Ranked 0–100 against every \(skater.positionGroup == "D" ? "defenceman" : "forward") in the league. 50 is average — bars fill right of centre for above, left for below.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textTertiary)
                scaleLegend
                ForEach(metrics.compactMap { m in
                    skater.percentile(m.key).map { (m, $0) }
                }, id: \.0.key) { metric, pct in
                    percentileRow(metric, pct)
                }
            }
        }
    }

    private var scaleLegend: some View { PercentileLegend() }

    private func percentileRow(_ metric: Metric, _ pct: Int) -> some View {
        PercentileRow(metric: metric, percentile: pct)
    }

    private var unrankedNote: some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "hourglass")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text("Not enough ice time to rank against the league yet — the raw numbers are below.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Raw numbers

    private var productionCard: some View {
        SectionCard("Production") {
            VStack(spacing: Theme.Spacing.xs) {
                statRow("Goals", String(Int(skater.goals)))
                statRow("Primary assists", String(Int(skater.primaryAssists)))
                statRow("Secondary assists", String(Int(skater.secondaryAssists)))
                statRow("Finishing vs expected", signed(skater.finishing),
                        tint: skater.finishing >= 0 ? Theme.Palette.positive : Theme.Palette.negative)
                statRow("Penalties drawn − taken", signed(skater.penaltyDifferential),
                        tint: skater.penaltyDifferential >= 0 ? Theme.Palette.positive : Theme.Palette.negative)
            }
        }
    }

    private var runOfPlayCard: some View {
        SectionCard("5-on-5 run of play") {
            VStack(spacing: Theme.Spacing.sm) {
                if let xgf = skater.xgfPct {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("EXPECTED GOALS SHARE")
                                .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.5)
                                .foregroundStyle(Theme.Palette.textSecondary)
                            Spacer()
                            Text(String(format: "%.1f%%", xgf))
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(teamColor)
                        }
                        SplitBar(leftFraction: xgf / 100,
                                 leftColor: teamColor,
                                 rightColor: Theme.Palette.textTertiary.opacity(0.4))
                    }
                }
                if let rel = skater.xgfPctRel {
                    statRow("vs. when he's off the ice", signed(rel) + " pts",
                            tint: rel >= 0 ? Theme.Palette.positive : Theme.Palette.negative)
                }
                if let f = skater.xgfPer60 { statRow("xG for / 60", String(format: "%.2f", f)) }
                if let a = skater.xgaPer60 { statRow("xG against / 60", String(format: "%.2f", a)) }
                if let z = skater.zoneStartPct {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("ZONE STARTS")
                                .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.5)
                                .foregroundStyle(Theme.Palette.textSecondary)
                            Spacer()
                            Text(String(format: "%.0f%% offensive", z))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        SplitBar(leftFraction: z / 100,
                                 leftColor: Theme.Palette.accent,
                                 rightColor: Theme.Palette.textTertiary.opacity(0.4))
                        Text("How often his shifts start in the offensive zone — sheltered deployment inflates the numbers above.")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
        }
    }

    private func statRow(_ label: String, _ value: String,
                         tint: Color = Theme.Palette.textPrimary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    private func signed(_ v: Double) -> String {
        String(format: v >= 0 ? "+%.1f" : "%.1f", v)
    }
}
