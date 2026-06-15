import SwiftUI

/// Full badge collection — every achievement, earned (colored) vs locked (greyed),
/// with its unlock description. Pushed from the Play tab's Achievements section.
struct AchievementsView: View {
    @Environment(GamificationStore.self) private var game

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    summary
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                        ForEach(game.achievements) { a in
                            tile(a, earned: game.earnedIds.contains(a.id))
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.inline)
        .task { await game.loadAchievements() }
    }

    private var summary: some View {
        let earned = game.earnedIds.count
        let total = max(game.achievements.count, 1)
        return Card {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle().stroke(Theme.Palette.border, lineWidth: 6).frame(width: 56, height: 56)
                    Circle().trim(from: 0, to: CGFloat(earned) / CGFloat(total))
                        .stroke(Theme.Palette.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 56, height: 56)
                    Text("\(earned)").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.textPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(earned) of \(game.achievements.count) badges")
                        .font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                    Text("Earn badges by making correct picks, building streaks, and beating the model.")
                        .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func tile(_ a: Achievement, earned: Bool) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZStack {
                Circle()
                    .fill(earned ? Theme.Palette.accent.opacity(0.16) : Theme.Palette.background)
                    .frame(width: 56, height: 56)
                Image(systemName: earned ? a.icon : "lock.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(earned ? Theme.Palette.accent : Theme.Palette.textTertiary)
            }
            Text(a.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(earned ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
                .multilineTextAlignment(.center).lineLimit(1)
            Text(a.description)
                .font(.system(size: 10))
                .foregroundStyle(Theme.Palette.textTertiary)
                .multilineTextAlignment(.center).lineLimit(2)
                .frame(minHeight: 26, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(earned ? Theme.Palette.accent.opacity(0.4) : Theme.Palette.border, lineWidth: 1)
        )
        .opacity(earned ? 1 : 0.7)
        .accessibilityLabel("\(a.name): \(a.description) — \(earned ? "earned" : "locked")")
    }
}
