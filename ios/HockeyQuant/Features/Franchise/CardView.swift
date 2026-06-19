import SwiftUI

/// A collectible player card: headshot/crest, name, position, rarity badge, and either the
/// player's value (collection) or its Coin price (shop). Rarity tints the border.
struct CardView: View {
    let card: PlayerCard
    var showPrice: Bool = false

    var body: some View {
        let color = CardRarity.color(card.rarity)
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(color.opacity(0.18)).frame(width: 52, height: 52)
                if let hs = card.headshot, let url = URL(string: hs) {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                        placeholder: { CrestView(abbrev: card.team, size: 40) }
                        .frame(width: 52, height: 52).clipShape(Circle())
                } else {
                    CrestView(abbrev: card.team, size: 40)
                }
            }
            Text(card.fullName).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.65)
            Text("\(card.rosterPos) · \(card.team)").font(.system(size: 9)).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            Text(CardRarity.label(card.rarity).uppercased())
                .font(.system(size: 8, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2).background(color).clipShape(Capsule())
            if showPrice {
                HStack(spacing: 3) {
                    Image(systemName: "bitcoinsign.circle.fill").font(.system(size: 9))
                    Text(card.price.asCoins).font(.system(size: 11, weight: .heavy, design: .rounded))
                }.foregroundStyle(Theme.Palette.accent)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).stroke(color, lineWidth: 1.5))
    }
}
