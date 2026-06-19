import SwiftUI

/// The daily-rotating card shop. Tap an affordable card to buy it with Coins; the
/// rotation is the same for everyone and refreshes each day.
struct ShopView: View {
    let store: FranchiseStore
    @State private var loading = true
    @State private var pending: PlayerCard?
    @State private var buying = false
    @State private var toast: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 3)

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            VStack(spacing: 0) {
                coinsBar
                if loading && store.shop.isEmpty {
                    Spacer(); ProgressView().tint(Theme.Palette.accent); Spacer()
                } else {
                    ScrollView {
                        Text("Today's featured cards — tap to buy. New cards daily.")
                            .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.Spacing.md).padding(.top, Theme.Spacing.xs)
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                            ForEach(store.shop) { card in
                                let affordable = store.coins >= card.price
                                Button { pending = card } label: {
                                    CardView(card: card, showPrice: true).opacity(affordable ? 1 : 0.45)
                                }
                                .disabled(!affordable || buying)
                            }
                        }
                        .padding(Theme.Spacing.md)
                    }
                }
            }
            if let toast {
                Text(toast)
                    .font(Theme.Font.headline()).foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Palette.positive).clipShape(Capsule())
                    .padding(.bottom, 60).frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Card Shop")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadShop(); loading = false }
        .alert("Buy card", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { card in
            Button("Buy for \(card.price.asCoins) Coins") { Task { await buy(card) } }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { card in
            Text("Add \(card.fullName) (\(CardRarity.label(card.rarity))) to your collection?")
        }
    }

    private var coinsBar: some View {
        HStack {
            Text("CARD SHOP").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "bitcoinsign.circle.fill").font(.system(size: 16)).foregroundStyle(Color(hex: 0xFFD23F))
                Text(store.coins.asCoins).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.textPrimary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
    }

    private func buy(_ card: PlayerCard) async {
        buying = true
        let ok = await store.buy(card.playerId)
        buying = false
        if ok {
            Haptics.success()
            withAnimation { toast = "Added \(card.fullName)!" }
            Task { @MainActor in try? await Task.sleep(for: .seconds(2)); withAnimation { toast = nil } }
        }
    }
}
