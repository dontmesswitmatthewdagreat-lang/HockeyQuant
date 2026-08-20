import SwiftUI

/// A goalie's season, led by goals saved above expected.
///
/// Save percentage alone is unfair to goalies behind bad defences — it counts a
/// point shot the same as a breakaway. GSAx fixes that by asking a better
/// question: given the shots this goalie actually faced, how many goals did he
/// prevent that an average goalie wouldn't have?
struct GoalieImpactSheet: View {
    let goalie: GoalieImpact
    var teamColor: Color = Theme.Palette.accent

    /// Ordered by how much each says about a goalie.
    private var metrics: [PercentileMetric] {
        [
            PercentileMetric(key: "gsax", label: "Goals saved above expected",
                             detail: "The headline number — goals prevented beyond what his shots were worth"),
            PercentileMetric(key: "gsax_per60", label: "GSAx per 60",
                             detail: "The same thing as a rate, so a backup isn't punished for playing less"),
            PercentileMetric(key: "hd_gsax", label: "High-danger saves",
                             detail: "Goals saved above expected on high-danger shots — where goalies separate"),
            PercentileMetric(key: "hd_save_pct", label: "High-danger save %",
                             detail: "Save rate on the chances most likely to go in"),
            PercentileMetric(key: "save_pct", label: "Save %",
                             detail: "Raw stop rate — context-free, which is why it's ranked last"),
            PercentileMetric(key: "rebound_control", label: "Rebound control",
                             detail: "Rebounds allowed vs. expected, ranked against other goalies"),
            PercentileMetric(key: "workload_per60", label: "Workload",
                             detail: "Shots faced per 60 — not good or bad, just how busy he was"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                header
                if goalie.isRanked { percentileCard } else { unrankedNote }
                numbersCard
            }
            .padding(Theme.Spacing.md)
        }
        .frame(maxHeight: 640)
    }

    private var header: some View {
        Card {
            VStack(spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    CrestView(abbrev: goalie.team, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goalie.name)
                            .font(Theme.Font.title())
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("G · \(goalie.gamesPlayed) GP")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                Divider().overlay(Theme.Palette.border)
                HStack(spacing: Theme.Spacing.sm) {
                    StatPill(label: "GSAx", value: signed(goalie.gsax))
                    Divider().frame(height: 32).overlay(Theme.Palette.border)
                    StatPill(label: "Save %",
                             value: goalie.savePct.map { String(format: "%.1f", $0) } ?? "—")
                    Divider().frame(height: 32).overlay(Theme.Palette.border)
                    StatPill(label: "HD Save %",
                             value: goalie.hdSavePct.map { String(format: "%.1f", $0) } ?? "—")
                }
            }
        }
    }

    private var percentileCard: some View {
        SectionCard("League percentile · vs goalies") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Ranked 0–100 against every goalie in the league. 50 is average — bars fill right of centre for above, left for below.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textTertiary)
                PercentileLegend()
                ForEach(metrics.compactMap { m in
                    goalie.percentile(m.key).map { (m, $0) }
                }, id: \.0.key) { metric, pct in
                    PercentileRow(metric: metric, percentile: pct)
                }
            }
        }
    }

    private var unrankedNote: some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "hourglass")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text("Under 500 minutes played — not enough to rank against the league yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer(minLength: 0)
            }
        }
    }

    private var numbersCard: some View {
        // Rebound control is deliberately absent: its baseline isn't calibrated
        // to actual rebounds, so the raw figure is negative for nearly every
        // goalie and would read as damning. The percentile above is the honest
        // form of it.
        SectionCard("The season") {
            VStack(spacing: Theme.Spacing.xs) {
                statRow("Shots faced", String(Int(goalie.shotsAgainst)))
                statRow("Goals against", String(Int(goalie.goalsAgainst)))
                statRow("Goals saved above expected", signed(goalie.gsax),
                        tint: goalie.gsax >= 0 ? Theme.Palette.positive : Theme.Palette.negative)
                statRow("High-danger shots faced", String(Int(goalie.hdShots)))
                statRow("High-danger goals saved", signed(goalie.hdGsax),
                        tint: goalie.hdGsax >= 0 ? Theme.Palette.positive : Theme.Palette.negative)
                statRow("Shots faced per 60", String(format: "%.1f", goalie.workloadPer60))
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
