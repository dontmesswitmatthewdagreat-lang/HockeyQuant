import SwiftUI

/// Global leaderboard ranked by Stanley Cups. Pushed within the Play navigation stack.
struct LeaderboardView: View {
    @Environment(GamificationStore.self) private var game
    @State private var loading = true
    @State private var tab = 0   // 0 = Global, 1 = Leagues

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Global").tag(0)
                    Text("Leagues").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)

                if tab == 0 { global } else { PickemLeaguesView() }
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await game.loadLeaderboard()
            loading = false
        }
    }

    @ViewBuilder
    private var global: some View {
        if loading {
            ScrollView {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(0..<8, id: \.self) { _ in LoadingShimmer(height: 48) }
                }
                .padding(Theme.Spacing.md)
            }
        } else if game.leaderboard.isEmpty {
            EmptyStateView(
                systemImage: "trophy",
                title: "No rankings yet",
                message: "Be the first — make picks, build your team, and win weekly matchups to earn Stanley Cups."
            )
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(game.leaderboard.enumerated()), id: \.element.id) { index, entry in
                    row(rank: index + 1, entry: entry)
                        .staggeredEntrance(index: index)
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    private func row(rank: Int, entry: LeaderboardEntry) -> some View {
        let isMe = entry.userId == game.currentUserId
        return HStack(spacing: Theme.Spacing.sm) {
            rankBadge(rank)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textPrimary)
                HStack(spacing: 4) {
                    Image(systemName: entry.arena.icon).font(.system(size: 9)).foregroundStyle(entry.arena.color)
                    Text("\(entry.arena.name) · \(entry.picksCorrect)/\(entry.picksMade) · \(Int(entry.accuracy.rounded()))%")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            Spacer()
            if entry.currentStreak > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill").font(.system(size: 10))
                    Text("\(entry.currentStreak)").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.Palette.moderate)
            }
            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 3) {
                    Image(systemName: "trophy.fill").font(.system(size: 11)).foregroundStyle(Color(hex: 0xFFD23F))
                    Text("\(entry.stanleyCups)").font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                }
                Text("CUPS").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(isMe ? Theme.Palette.accent.opacity(0.10) : Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(isMe ? Theme.Palette.accent : Theme.Palette.border, lineWidth: isMe ? 1.5 : 1)
        )
    }

    private func rankBadge(_ rank: Int) -> some View {
        let color: Color = switch rank {
        case 1: Color(hex: 0xFFD23F)
        case 2: Color(hex: 0xC0C0C0)
        case 3: Color(hex: 0xCD7F32)
        default: Theme.Palette.textTertiary
        }
        return Text("\(rank)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(rank <= 3 ? .white : Theme.Palette.textSecondary)
            .frame(width: 28, height: 28)
            .background(rank <= 3 ? color : Theme.Palette.background)
            .clipShape(Circle())
    }
}
