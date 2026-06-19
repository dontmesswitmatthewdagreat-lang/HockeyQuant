import SwiftUI

/// My Franchise — a personal card-collection mode (one per account). Buy player cards
/// from a rotating shop with Coins, build a dream-team lineup, and play nightly
/// challenges vs a real NHL team. Scaffold for now; built out across the next stages.
struct FranchiseView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        ZStack {
            Theme.backgroundView(stops: Theme.Palette.backgroundStopsPrimary).ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    Card {
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "rectangle.stack.fill.badge.plus")
                                .font(.system(size: 44)).foregroundStyle(Theme.Palette.accent)
                            Text("My Franchise").font(Theme.Font.title()).foregroundStyle(Theme.Palette.textPrimary)
                            Text("Collect player cards, buy from the daily shop with Coins, build your dream team, and challenge a real NHL team each night.")
                                .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                                .multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity)
                    }
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("COMING SOON").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                            featureRow("creditcard.fill", "Player cards by rarity")
                            featureRow("cart.fill", "Daily rotating shop")
                            featureRow("person.3.sequence.fill", "Dream-team lineup")
                            featureRow("flame.fill", "Nightly challenge vs an NHL team")
                            featureRow("arrow.left.arrow.right", "Trade cards with other players")
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle("My Franchise")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Theme.Palette.accent).frame(width: 22)
            Text(text).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary)
        }
    }
}
