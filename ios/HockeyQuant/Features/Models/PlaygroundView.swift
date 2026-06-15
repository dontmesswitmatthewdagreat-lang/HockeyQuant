import SwiftUI

/// Analytics & Simulation Playground — a "coming soon" teaser previewing the
/// what-if / Monte-Carlo / advanced-model tooling planned for the Models tab.
struct PlaygroundView: View {
    private struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let blurb: String
        var live = false
    }

    private let features: [Feature] = [
        Feature(icon: "dial.medium.fill", title: "What-if simulator",
                blurb: "Swap a starting goalie, nudge a team's form or fatigue, toggle an injury — and watch the predicted win probability and score shift live.", live: true),
        Feature(icon: "dice.fill", title: "Monte-Carlo sims",
                blurb: "Run a game or playoff series thousands of times to see the full distribution of outcomes, series odds, and the most likely scorelines.", live: true),
        Feature(icon: "chart.xyaxis.line", title: "Season & playoff odds",
                blurb: "Simulate the rest of the season to project playoff chances, seeding, and championship odds for every team.", live: true),
        Feature(icon: "list.bullet.rectangle", title: "Strategy backtester",
                blurb: "Set conditional rules (confidence, goalie/form/H2H agrees, rested) and backtest the model over history — accuracy curve, hit rate, coverage, and which signals carry the edge.", live: true),
        Feature(icon: "cpu", title: "Machine-learned model",
                blurb: "Pick the inputs and train a model on the season's games — see its out-of-sample accuracy vs the official model and the feature weights it learned.", live: true),
    ]

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    header
                    ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                        Group {
                            if feature.live {
                                NavigationLink { destination(feature) } label: { featureCard(feature) }
                                    .buttonStyle(.plain)
                            } else {
                                featureCard(feature)
                            }
                        }
                        .staggeredEntrance(index: index)
                    }
                    Text("In the works — tell us which you want first.")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.top, Theme.Spacing.sm)
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle("Playground")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(Theme.Palette.accent.opacity(0.16)).frame(width: 80, height: 80)
                Image(systemName: "flask.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.Palette.accent)
            }
            Text("Analytics & Simulation")
                .font(Theme.Font.title())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("A lab for what-if scenarios, simulations, and machine-learned models.")
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.sm)
    }

    @ViewBuilder
    private func destination(_ feature: Feature) -> some View {
        if feature.title.contains("Monte-Carlo") { MonteCarloView() }
        else if feature.title.contains("Season") { SeasonOddsView() }
        else if feature.title.contains("backtester") { BacktestView() }
        else if feature.title.contains("Machine-learned") { MLModelView() }
        else { WhatIfSimulatorView() }
    }

    private func featureCard(_ feature: Feature) -> some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(Theme.Palette.accent.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: feature.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Palette.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(feature.title)
                            .font(Theme.Font.headline())
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(feature.live ? "OPEN" : "SOON")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(feature.live ? Theme.Palette.strong : Theme.Palette.accent)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background((feature.live ? Theme.Palette.strong : Theme.Palette.accent).opacity(0.14))
                            .clipShape(Capsule())
                        Spacer()
                        if feature.live {
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    Text(feature.blurb)
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
