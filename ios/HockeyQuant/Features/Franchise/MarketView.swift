import SwiftUI

/// The card marketplace: buy cards (Coins) or propose card-for-card trades, manage your
/// own listings, and handle incoming/outgoing trade offers.
struct MarketView: View {
    let store: FranchiseStore
    @State private var tab = 0
    @State private var loading = true
    @State private var pendingCard: PlayerCard?       // tapped buy-grid card (Buy / Offer dialog)
    @State private var offerTarget: PlayerCard?       // card we're proposing a trade for
    @State private var showList = false
    @State private var working = false
    @State private var toast: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 3)

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            VStack(spacing: 0) {
                coinsBar
                Picker("", selection: $tab) {
                    Text("Buy").tag(0)
                    Text(offersBadge).tag(1)
                    Text("Mine").tag(2)
                }
                .pickerStyle(.segmented).padding(.horizontal, Theme.Spacing.md).padding(.bottom, Theme.Spacing.xs)
                if loading && store.market.isEmpty {
                    Spacer(); ProgressView().tint(Theme.Palette.accent); Spacer()
                } else if tab == 0 { buyGrid } else if tab == 1 { offersList } else { sellList }
            }
            if let toast {
                Text(toast).font(Theme.Font.headline()).foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Palette.positive).clipShape(Capsule())
                    .padding(.bottom, 60).frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Marketplace")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload(); loading = false }
        .sheet(isPresented: $showList) {
            ListCardSheet(cards: store.collection) { cardId, price in
                Task { if await store.listCard(cardId, price: price) { flash("Listed!") } }
            }
        }
        .sheet(item: $offerTarget) { target in
            ProposeOfferSheet(target: target, myCards: store.collection, maxCoins: store.coins) { fromCardId, coins in
                Task {
                    guard let toCardId = target.cardId else { return }
                    if await store.proposeOffer(toCardId: toCardId, fromCardId: fromCardId, coins: coins) { flash("Offer sent!") }
                }
            }
        }
        .confirmationDialog(pendingCard?.fullName ?? "", isPresented: Binding(get: { pendingCard != nil }, set: { if !$0 { pendingCard = nil } }), titleVisibility: .visible, presenting: pendingCard) { card in
            Button("Buy for \(card.price.asCoins) Coins") { Task { await buy(card) } }
                .disabled(store.coins < card.price)
            Button("Propose a trade") { offerTarget = card }
            Button("Cancel", role: .cancel) { pendingCard = nil }
        } message: { card in
            Text("\(CardRarity.label(card.rarity)) · listed by @\(card.seller ?? "manager")")
        }
    }

    private var offersBadge: String {
        store.incomingOffers.isEmpty ? "Offers" : "Offers (\(store.incomingOffers.count))"
    }

    private func reload() async { await store.loadMarket(); await store.loadOffers() }

    private var coinsBar: some View {
        HStack {
            Text("MARKETPLACE").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "bitcoinsign.circle.fill").font(.system(size: 16)).foregroundStyle(Color(hex: 0xFFD23F))
                Text(store.coins.asCoins).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.textPrimary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: Buy

    @ViewBuilder private var buyGrid: some View {
        if store.market.isEmpty {
            EmptyStateView(systemImage: "cart", title: "Nothing for sale", message: "No cards are listed right now — check back later.")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                    ForEach(store.market) { card in
                        Button { pendingCard = card } label: {
                            VStack(spacing: 2) {
                                CardView(card: card, showPrice: true)
                                Text("@\(card.seller ?? "manager")").font(.system(size: 8)).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                            }
                        }.disabled(working)
                    }
                }.padding(Theme.Spacing.md)
            }.refreshable { await reload() }
        }
    }

    // MARK: Offers

    @ViewBuilder private var offersList: some View {
        if store.incomingOffers.isEmpty && store.outgoingOffers.isEmpty {
            EmptyStateView(systemImage: "arrow.left.arrow.right", title: "No trade offers", message: "Propose a trade from the Buy tab, or wait for offers to come in.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    if !store.incomingOffers.isEmpty {
                        sectionLabel("INCOMING")
                        ForEach(store.incomingOffers) { offer in offerCard(offer, incoming: true) }
                    }
                    if !store.outgoingOffers.isEmpty {
                        sectionLabel("OUTGOING").padding(.top, Theme.Spacing.xs)
                        ForEach(store.outgoingOffers) { offer in offerCard(offer, incoming: false) }
                    }
                }.padding(Theme.Spacing.md)
            }.refreshable { await reload() }
        }
    }

    private func offerCard(_ offer: TradeOffer, incoming: Bool) -> some View {
        // For incoming: they give fromCard(+coins), you give toCard. For outgoing: reverse perspective.
        let theyGive = offer.fromCard, youGive = offer.toCard
        let counterpart = incoming ? offer.fromUser : offer.toUser
        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(incoming ? "@\(counterpart ?? "manager") offers you" : "Your offer to @\(counterpart ?? "manager")")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                HStack(spacing: Theme.Spacing.sm) {
                    miniCard(incoming ? theyGive : youGive, label: incoming ? "You get" : "You give")
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.left.arrow.right").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.Palette.accent)
                        if offer.fromCoins > 0 {
                            Text("+\(offer.fromCoins.asCoins)").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Color(hex: 0xFFD23F))
                            Text(incoming ? "to you" : "you add").font(.system(size: 8)).foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    miniCard(incoming ? youGive : theyGive, label: incoming ? "You give" : "You get")
                }
                if incoming {
                    HStack(spacing: Theme.Spacing.sm) {
                        actionButton("Accept", color: Theme.Palette.positive) { Task { if await store.acceptOffer(offer.offerId) { flash("Trade complete!") } } }
                        actionButton("Decline", color: Theme.Palette.negative, filled: false) { Task { _ = await store.declineOffer(offer.offerId) } }
                    }
                } else {
                    actionButton("Withdraw offer", color: Theme.Palette.negative, filled: false) { Task { _ = await store.declineOffer(offer.offerId) } }
                }
            }
        }
    }

    private func miniCard(_ card: PlayerCard?, label: String) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
            if let card {
                Circle().fill(CardRarity.color(card.rarity)).frame(width: 8, height: 8)
                Text(card.fullName).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            } else {
                Text("—").foregroundStyle(Theme.Palette.textTertiary)
            }
        }.frame(maxWidth: .infinity)
    }

    private func actionButton(_ title: String, color: Color, filled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.Font.headline()).foregroundStyle(filled ? .white : color)
                .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.xs)
                .background(filled ? color : color.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        }.buttonStyle(.plain).disabled(working)
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
    }

    // MARK: My listings

    @ViewBuilder private var sellList: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.sm) {
                PressableButton(action: { showList = true }) {
                    HStack { Image(systemName: "tag.fill"); Text("List a card for sale").font(Theme.Font.headline()) }
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Palette.accent).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }
                if store.myListings.isEmpty {
                    Text("You haven't listed any cards.").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity).padding(.top, Theme.Spacing.md)
                }
                ForEach(store.myListings) { l in listingRow(l) }
            }.padding(Theme.Spacing.md)
        }.refreshable { await reload() }
    }

    private func listingRow(_ l: PlayerCard) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle().fill(CardRarity.color(l.rarity)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(l.fullName).font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary).lineLimit(1)
                Text("\(l.price.asCoins) Coins · \((l.status ?? "open").capitalized)").font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer()
            if l.status == "open", let lid = l.listingId {
                Button("Cancel") { Task { if await store.cancelListing(lid) { flash("Delisted") } } }
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.negative)
            }
        }
        .padding(Theme.Spacing.sm).background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    // MARK: Actions

    private func buy(_ card: PlayerCard) async {
        guard let lid = card.listingId else { return }
        working = true
        if await store.buyListing(lid) { flash("Bought \(card.fullName)!") }
        working = false
    }

    private func flash(_ msg: String) {
        Haptics.success()
        withAnimation { toast = msg }
        Task { @MainActor in try? await Task.sleep(for: .seconds(2)); withAnimation { toast = nil } }
    }
}

/// Picks one of your cards + a Coin price to list on the marketplace.
struct ListCardSheet: View {
    let cards: [PlayerCard]
    let onList: (String, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: PlayerCard?
    @State private var priceM: Double = 0   // price in hundreds of coins for the stepper

    var body: some View {
        NavigationStack {
            List {
                if let sel = selected {
                    Section("Price") {
                        Stepper(value: $priceM, in: 1...100, step: 1) {
                            Text("\(Int(priceM * 100).asCoins) Coins").font(.system(size: 15, weight: .heavy, design: .rounded))
                        }
                        Button("List \(sel.fullName)") { onList(sel.cardId ?? sel.playerId, Int(priceM * 100)); dismiss() }
                            .foregroundStyle(Theme.Palette.accent)
                    }
                }
                Section("Pick a card") {
                    ForEach(cards) { c in
                        Button {
                            selected = c
                            priceM = max(1, Double(c.price / 100))      // suggest the rarity base price
                        } label: { cardRow(c, selected: selected?.id == c.id) }
                    }
                }
            }
            .navigationTitle("List a card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Proposes a card-for-card trade: pick which of your cards to give (+ optional Coins) for `target`.
struct ProposeOfferSheet: View {
    let target: PlayerCard
    let myCards: [PlayerCard]
    let maxCoins: Int
    let onPropose: (String, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var give: PlayerCard?
    @State private var coins: Double = 0

    private var coinStep: Double { 100 }
    private var coinCap: Double { Double(min(maxCoins, 50_000)) }

    var body: some View {
        NavigationStack {
            List {
                Section("You want") {
                    cardRow(target, selected: false)
                    Text("Listed by @\(target.seller ?? "manager")").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
                }
                if give != nil || coins > 0 {
                    Section("Sweeten with Coins (optional)") {
                        Stepper(value: $coins, in: 0...max(0, coinCap), step: coinStep) {
                            Text(coins > 0 ? "+\(Int(coins).asCoins) Coins" : "No Coins added")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                        }
                    }
                }
                Section("You give") {
                    ForEach(myCards) { c in
                        Button { give = c } label: { cardRow(c, selected: give?.id == c.id) }
                    }
                }
                if let g = give {
                    Section {
                        Button("Send offer (\(g.fullName)\(coins > 0 ? " + \(Int(coins).asCoins) Coins" : ""))") {
                            onPropose(g.cardId ?? g.playerId, Int(coins)); dismiss()
                        }.foregroundStyle(Theme.Palette.accent)
                    }
                }
            }
            .navigationTitle("Propose a trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Shared one-line card row (rarity dot + name + optional checkmark).
@MainActor @ViewBuilder
func cardRow(_ c: PlayerCard, selected: Bool) -> some View {
    HStack {
        Circle().fill(CardRarity.color(c.rarity)).frame(width: 9, height: 9)
        Text(c.fullName).foregroundStyle(Theme.Palette.textPrimary)
        Text(CardRarity.label(c.rarity)).font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
        Spacer()
        if selected { Image(systemName: "checkmark").foregroundStyle(Theme.Palette.accent) }
    }
}
