import SwiftUI

/// My Franchise — a personal card-collection mode (one per account). Buy player cards
/// from a rotating shop with Coins, build a dream-team lineup, and play nightly
/// challenges vs a real NHL team. Built out across stages; shop/lineup/challenge land next.
struct FranchiseView: View {
    @Environment(AuthStore.self) private var auth
    @State private var store: FranchiseStore?
    @State private var loading = true

    var body: some View {
        ZStack {
            Theme.backgroundView(stops: Theme.Palette.backgroundStopsPrimary).ignoresSafeArea()
            if let store, let s = store.summary {
                content(store, s)
            } else if loading {
                ProgressView().tint(Theme.Palette.accent)
            } else {
                EmptyStateView(systemImage: "rectangle.stack.fill",
                               title: "Couldn't load your franchise",
                               message: "Pull to refresh and try again.")
            }
        }
        .navigationTitle("My Franchise")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store == nil { store = FranchiseStore(auth: auth) }
            await store?.load()
            loading = false
        }
    }

    private func content(_ store: FranchiseStore, _ s: FranchiseSummary) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                walletCard(store, s)
                NavigationLink { ShopView(store: store) } label: {
                    modeRow("Card Shop", icon: "cart.fill", subtitle: "Today's featured cards — buy with Coins")
                }.buttonStyle(.plain)
                NavigationLink { LineupView(store: store) } label: {
                    modeRow("Dream Team", icon: "person.3.sequence.fill", subtitle: "\(s.lineupFilled)/\(s.lineupSlots) slots set — build your lineup")
                }.buttonStyle(.plain)
                NavigationLink { ChallengeView(store: store) } label: {
                    modeRow("Nightly Challenge", icon: "flame.fill", subtitle: challengeSubtitle(s))
                }.buttonStyle(.plain)
                NavigationLink { CollectionView(store: store) } label: { collectionCard(s) }
                    .buttonStyle(.plain)
                comingSoonCard
            }
            .padding(Theme.Spacing.md)
        }
        .refreshable { await store.load() }
    }

    private func walletCard(_ store: FranchiseStore, _ s: FranchiseSummary) -> some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("COINS").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                    Text("+\(s.dailyReward.asCoins) daily login bonus").font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "bitcoinsign.circle.fill").font(.system(size: 20)).foregroundStyle(Color(hex: 0xFFD23F))
                    Text(store.coins.asCoins).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.textPrimary)
                }
            }
        }
    }

    private func modeRow(_ title: String, icon: String, subtitle: String) -> some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(Theme.Palette.accent.opacity(0.14)).frame(width: 42, height: 42)
                    Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Theme.Palette.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.Font.headlineHeavy()).foregroundStyle(Theme.Palette.textPrimary)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    private func collectionCard(_ s: FranchiseSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("COLLECTION").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                    Spacer()
                    Text("\(s.collectionCount) cards").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
                }
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(CardRarity.order.reversed(), id: \.self) { r in
                        let n = s.byRarity[r] ?? 0
                        if n > 0 { rarityChip(r, n) }
                    }
                    if s.collectionCount == 0 {
                        Text("No cards yet — buy some from the shop.").font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
        }
    }

    private func rarityChip(_ rarity: String, _ count: Int) -> some View {
        let color = CardRarity.color(rarity)
        return HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(count)").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.14)).clipShape(Capsule())
    }

    private func challengeSubtitle(_ s: FranchiseSummary) -> String {
        if let c = s.todayChallenge {
            if c.graded { return (c.won ?? false) ? "Last night: you won!" : "Last night: tough loss" }
            return "Locked in vs \(c.opponentTeam) tonight"
        }
        return "Take your dream team vs a real NHL team"
    }

    private var comingSoonCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("COMING SOON").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                featureRow("arrow.left.arrow.right", "Trade cards with other players")
            }
        }
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Theme.Palette.accent).frame(width: 22)
            Text(text).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary)
        }
    }
}
