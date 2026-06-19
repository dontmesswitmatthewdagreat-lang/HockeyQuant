import SwiftUI

/// The manager's full card collection, as a grid of cards (best rarity first).
struct CollectionView: View {
    let store: FranchiseStore
    @State private var loading = true

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 3)

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            if loading && store.collection.isEmpty {
                ProgressView().tint(Theme.Palette.accent)
            } else if store.collection.isEmpty {
                EmptyStateView(systemImage: "rectangle.stack",
                               title: "No cards yet",
                               message: "Buy cards from the shop to start your collection.")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                        ForEach(store.collection) { CardView(card: $0) }
                    }
                    .padding(Theme.Spacing.md)
                }
                .refreshable { await store.loadCollection() }
            }
        }
        .navigationTitle("Collection (\(store.collection.count))")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadCollection(); loading = false }
    }
}
