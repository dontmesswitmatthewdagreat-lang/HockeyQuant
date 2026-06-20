import SwiftUI

/// The dream-team lineup: 12 slots (2 each of LW/RW/C/LHD/RHD + starter & backup G).
/// Tap a slot to assign an owned card of that position. The lineup feeds the nightly
/// challenge.
struct LineupView: View {
    let store: FranchiseStore
    @State private var loading = true
    @State private var pickingSlot: LineupSlot?

    var body: some View {
        ZStack {
            Theme.backgroundView(stops: Theme.Palette.backgroundStopsPrimary).ignoresSafeArea()
            if loading && store.lineup.isEmpty {
                ProgressView().tint(Theme.Palette.accent)
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.sm) {
                        ratingCard
                        ForEach(store.lineup) { slotRow($0) }
                    }
                    .padding(Theme.Spacing.md)
                }
                .refreshable { await store.loadLineup() }
            }
        }
        .navigationTitle("Dream Team")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadLineup(); await store.loadCollection(); loading = false }
        .sheet(item: $pickingSlot) { slot in
            LineupPickerSheet(slot: slot, cards: store.collection.filter { $0.rosterPos == slot.slotType }) { cardId in
                Task { await store.setLineupSlot(slot.slot, cardId: cardId) }
            }
        }
    }

    private var ratingCard: some View {
        let filled = store.lineup.filter { $0.card != nil }.count
        return Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TEAM VALUE").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                    Text("\(filled)/\(store.lineup.count) slots set").font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer()
                Text(store.lineupRating.asCapMoney).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.accent)
            }
        }
    }

    private func slotRow(_ slot: LineupSlot) -> some View {
        Button { pickingSlot = slot } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(FantasySlot.slotName(slot.slot))
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: 74, alignment: .leading)
                if let c = slot.card {
                    Circle().fill(CardRarity.color(c.rarity)).frame(width: 9, height: 9)
                    Text(c.fullName).font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary).lineLimit(1)
                    Spacer()
                    Text(c.cost.asCapMoney).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.accent)
                } else {
                    Text("Tap to set").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.accent)
                    Spacer()
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.sm).padding(.vertical, 10)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(slot.card != nil ? CardRarity.color(slot.card!.rarity).opacity(0.5) : Theme.Palette.border, lineWidth: 1))
        }
    }
}

/// Picks an owned card of the slot's position (or clears the slot).
struct LineupPickerSheet: View {
    let slot: LineupSlot
    let cards: [PlayerCard]
    let onPick: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if slot.card != nil {
                    Button(role: .destructive) { onPick(nil); dismiss() } label: {
                        Label("Clear this slot", systemImage: "xmark.circle")
                    }
                }
                Section("\(FantasySlot.label(slot.slotType)) cards") {
                    if cards.isEmpty {
                        Text("No \(FantasySlot.label(slot.slotType)) cards yet — buy some from the shop.")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    ForEach(cards) { c in
                        Button { onPick(c.cardId); dismiss() } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Circle().fill(CardRarity.color(c.rarity)).frame(width: 9, height: 9)
                                Text(c.fullName).foregroundStyle(Theme.Palette.textPrimary)
                                Spacer()
                                Text("\(c.team) · \(CardRarity.label(c.rarity))").font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pick \(FantasySlot.slotName(slot.slot))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
