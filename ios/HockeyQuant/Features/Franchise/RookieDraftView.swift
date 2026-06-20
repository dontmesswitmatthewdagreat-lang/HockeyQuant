import SwiftUI

/// The annual rookie-card draft: spend your performance-allocated picks to draft rookie
/// cards (the real prospect class) into your collection.
struct RookieDraftView: View {
    let store: FranchiseStore
    @State private var loading = true
    @State private var pending: PlayerCard?
    @State private var drafting = false
    @State private var toast: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 3)

    var body: some View {
        ZStack {
            Theme.backgroundView(stops: Theme.Palette.backgroundStopsPrimary).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if loading && store.rookieBoard.isEmpty {
                    Spacer(); ProgressView().tint(Theme.Palette.accent); Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                            ForEach(store.rookieBoard) { card in
                                Button { pending = card } label: {
                                    CardView(card: card).opacity(store.rookiePicksRemaining > 0 ? 1 : 0.5)
                                }
                                .disabled(store.rookiePicksRemaining == 0 || drafting)
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
        .navigationTitle("Rookie Draft")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadRookieDraft(); loading = false }
        .alert("Draft rookie", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { card in
            Button("Draft \(card.fullName)") { Task { await draft(card) } }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { card in
            Text("Spend a rookie pick on #\(card.prospectRanking ?? 0) \(card.fullName) (\(CardRarity.label(card.rarity)))?")
        }
    }

    private var header: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.rookieSeason > 0 ? "ROOKIE DRAFT · \(String(store.rookieSeason))" : "ROOKIE DRAFT")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                    Text("Picks earned from last season's challenge wins (+ a base 3).")
                        .font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer()
                VStack(spacing: 0) {
                    Text("\(store.rookiePicksRemaining)").font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.accent)
                    Text("PICKS").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .padding(Theme.Spacing.md)
    }

    private func draft(_ card: PlayerCard) async {
        drafting = true
        let ok = await store.draftRookie(card.playerId)
        drafting = false
        if ok {
            Haptics.success()
            withAnimation { toast = "Drafted \(card.fullName)!" }
            Task { @MainActor in try? await Task.sleep(for: .seconds(2)); withAnimation { toast = nil } }
        }
    }
}
