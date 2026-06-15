import SwiftUI

/// Public leaderboard of all user models, ranked by accuracy.
struct ModelsLeaderboardView: View {
    @Environment(AuthStore.self) private var auth
    @State private var entries: [ModelLeaderboardEntry] = []
    @State private var loading = true
    @State private var errorMessage: String?

    private let api = APIClient()

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            content
        }
        .navigationTitle("Model Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { entries = try await api.modelsLeaderboard() }
        catch {
            Log.error("models leaderboard", error)
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(0..<6, id: \.self) { _ in LoadingShimmer(height: 72) }
                }
                .padding(Theme.Spacing.md)
            }
        } else if let errorMessage {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if entries.isEmpty {
            EmptyStateView(
                systemImage: "trophy",
                title: "No ranked models yet",
                message: "Create a model and view its picks to get on the board."
            )
        } else {
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(sortedEntries.enumerated()), id: \.element.id) { index, entry in
                        row(rank: index + 1, entry: entry, decimals: accuracyDecimals)
                            .staggeredEntrance(index: index)
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
    }

    /// Precise accuracy from correct/total (the backend's `accuracy_pct` is
    /// rounded to 1 decimal — too coarse to order near-ties).
    private func precise(_ e: ModelLeaderboardEntry) -> Double {
        e.totalPredictions > 0 ? Double(e.correctPredictions) / Double(e.totalPredictions) * 100 : 0
    }

    /// Re-sorted by precise accuracy (graded models first), so display order is
    /// correct even when the backend's rounded sort ties.
    private var sortedEntries: [ModelLeaderboardEntry] {
        entries.sorted { a, b in
            if (a.totalPredictions > 0) != (b.totalPredictions > 0) { return a.totalPredictions > 0 }
            if a.totalPredictions == 0 && b.totalPredictions == 0 { return a.modelName < b.modelName }
            let pa = precise(a), pb = precise(b)
            return pa != pb ? pa > pb : a.totalPredictions > b.totalPredictions
        }
    }

    /// Minimum decimals (2→3) needed so adjacent entries are distinguishable.
    private var accuracyDecimals: Int {
        let accs = sortedEntries.filter { $0.totalPredictions > 0 }.map(precise)
        for d in 2...3 {
            let scale = pow(10.0, Double(d))
            var distinct = true
            for i in 1..<max(accs.count, 1) where i < accs.count {
                if (accs[i - 1] * scale).rounded() == (accs[i] * scale).rounded() { distinct = false; break }
            }
            if distinct { return d }
        }
        return 3
    }

    private func row(rank: Int, entry: ModelLeaderboardEntry, decimals: Int) -> some View {
        let isMine = entry.userId == auth.session?.user.id.uuidString
        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    rankBadge(rank)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(entry.modelName)
                                .font(Theme.Font.headline())
                                .foregroundStyle(Theme.Palette.textPrimary)
                            if entry.isML {
                                Text("ML")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(Theme.Palette.strong)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Theme.Palette.strong.opacity(0.16))
                                    .clipShape(Capsule())
                            }
                        }
                        Text("by \(entry.displayUser)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        if entry.totalPredictions > 0 {
                            Text(String(format: "%.\(decimals)f%%", precise(entry)))
                                .font(Theme.Font.statNumber())
                                .foregroundStyle(Theme.Palette.accent)
                                .monospacedDigit()
                        } else {
                            Text("—").font(Theme.Font.statNumber()).foregroundStyle(Theme.Palette.textTertiary)
                        }
                        Text("\(entry.correctPredictions)/\(entry.totalPredictions)")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                if let weights = entry.weights, !entry.isML {
                    WeightBar(weights: weights)
                } else if entry.isML, let kind = entry.mlKind {
                    Text("\(kind.capitalized) · auto-learned weights")
                        .font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(isMine ? Theme.Palette.accent : Color.clear, lineWidth: 1.5)
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
