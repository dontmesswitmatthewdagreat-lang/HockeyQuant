import SwiftUI

/// The season meta-game: your "GM track" tier, progress, season stats, the full
/// ladder, and season-long goals. Pushed within the Play navigation stack.
struct SeasonView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(GamificationStore.self) private var game
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var ring: Double = 0

    private var stats: SeasonStats { game.seasonStats }
    private var tier: GMTier { GMTier.current(forXp: stats.xp) }
    private var nextTier: GMTier? { GMTier.next(forXp: stats.xp) }

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    heroCard
                    statsCard
                    goalsCard
                    ladderCard
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle(Season.current.label)
        .navigationBarTitleDisplayMode(.inline)
        .task { await game.loadSeason() }
        .onChange(of: stats.xp) { _, _ in animateRing() }
        .onAppear { animateRing() }
    }

    private func animateRing() {
        let target = GMTier.progress(forXp: stats.xp)
        guard !reduceMotion else { ring = target; return }
        withAnimation(.easeOut(duration: 0.9)) { ring = target }
    }

    // MARK: - Hero

    private var heroCard: some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    Circle().stroke(Theme.Palette.border, lineWidth: 7).frame(width: 110, height: 110)
                    Circle()
                        .trim(from: 0, to: max(0.02, ring))
                        .stroke(tier.color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 110, height: 110)
                    Image(systemName: tier.icon)
                        .font(.system(size: 40))
                        .foregroundStyle(tier.color)
                }
                Text("GM TRACK")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text(tier.name)
                    .font(Theme.Font.title())
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let nextTier {
                    Text("\(stats.xp) / \(nextTier.threshold) XP → \(nextTier.name)")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Text("Top tier reached — \(stats.xp) season XP")
                        .font(Theme.Font.caption())
                        .foregroundStyle(tier.color)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Season stats

    private var statsCard: some View {
        Card {
            VStack(spacing: Theme.Spacing.md) {
                sectionHeader("This season")
                HStack(spacing: Theme.Spacing.sm) {
                    StatPill(label: "Season XP", value: "\(stats.xp)")
                    Divider().frame(height: 30).overlay(Theme.Palette.border)
                    StatPill(label: "Picks", value: "\(stats.picks)")
                    Divider().frame(height: 30).overlay(Theme.Palette.border)
                    StatPill(label: "Accuracy", value: stats.picks > 0 ? "\(Int(stats.accuracy.rounded()))%" : "—")
                }
                Divider().overlay(Theme.Palette.border)
                HStack(spacing: Theme.Spacing.sm) {
                    StatPill(label: "Best streak", value: "\(stats.bestStreak)")
                    Divider().frame(height: 30).overlay(Theme.Palette.border)
                    StatPill(label: "Beat model", value: "\(stats.beatsModel)")
                    Divider().frame(height: 30).overlay(Theme.Palette.border)
                    StatPill(label: "Correct", value: "\(stats.correct)")
                }
            }
        }
    }

    // MARK: - Season goals

    private var goalsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionHeader("Season goals")
                ForEach(SeasonGoal.all(for: stats)) { goal in
                    goalRow(goal)
                }
            }
        }
    }

    private func goalRow(_ goal: SeasonGoal) -> some View {
        VStack(spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: goal.isComplete ? "checkmark.circle.fill" : goal.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(goal.isComplete ? Theme.Palette.positive : Theme.Palette.textSecondary)
                Text(goal.name)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Text("\(min(goal.current, goal.target))/\(goal.target)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.background)
                    Capsule().fill(goal.isComplete ? Theme.Palette.positive : Theme.Palette.accent)
                        .frame(width: geo.size.width * CGFloat(goal.progress))
                }
            }
            .frame(height: 5)
        }
    }

    // MARK: - Tier ladder

    private var ladderCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionHeader("GM track")
                ForEach(GMTier.ladder) { rung in
                    ladderRow(rung)
                    if rung.id != GMTier.ladder.last?.id {
                        Divider().overlay(Theme.Palette.border).padding(.leading, 44)
                    }
                }
            }
        }
    }

    private func ladderRow(_ rung: GMTier) -> some View {
        let reached = stats.xp >= rung.threshold
        let isCurrent = rung.id == tier.id
        return HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(reached ? rung.color.opacity(0.18) : Theme.Palette.background)
                    .frame(width: 36, height: 36)
                Image(systemName: reached ? rung.icon : "lock.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(reached ? rung.color : Theme.Palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(rung.name)
                    .font(Theme.Font.caption())
                    .foregroundStyle(reached ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
                Text("\(rung.threshold) XP")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer()
            if isCurrent {
                Text("YOU")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(rung.color)
                    .clipShape(Capsule())
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.Palette.textTertiary)
    }
}
