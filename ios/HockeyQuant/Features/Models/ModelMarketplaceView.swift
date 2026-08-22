import SwiftUI

/// The model marketplace: every published model, and a one-tap fork into your
/// own workspace.
///
/// The listing endpoint serves raw model rows with no accuracy on them, so the
/// public leaderboard is fetched alongside and joined by model id. Without that
/// a browser can only see how *popular* a model is, and popularity is the one
/// number a marketplace shouldn't be judged on when the product's whole claim
/// is graded accuracy.
struct ModelMarketplaceView: View {
    /// Called after a successful fork. The forked copy lands in the owner's
    /// model list, which is a screen already on the stack behind this one — it
    /// has to be told, or you go back to a list that's missing what you just took.
    /// Sources the viewer already has a copy of. Forking twice is allowed by the
    /// backend (two variants of one idea is a reasonable thing to want), but the
    /// screen should say you've taken it rather than silently making a duplicate.
    var alreadyForked: Set<String> = []
    var onForked: (() async -> Void)?

    @Environment(AuthStore.self) private var auth

    @State private var models: [MarketplaceModel] = []
    @State private var accuracy: [String: ModelLeaderboardEntry] = [:]
    @State private var sort = 0                       // 0 = forks, 1 = accuracy
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var forking: String?
    @State private var forked: Set<String> = []
    @State private var toast: String?
    /// A failed fork can't take over the screen — the listing is still good.
    @State private var actionError: String?

    private let api = APIClient()

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            content
        }
        .navigationTitle("Marketplace")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .overlay(alignment: .top) {
            if let toast {
                CelebrationToast(icon: "arrow.triangle.branch",
                                 title: "Forked", subtitle: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert("Couldn't fork", isPresented: Binding(get: { actionError != nil },
                                                     set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if loading && models.isEmpty {
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(0..<4, id: \.self) { _ in LoadingShimmer(height: 150) }
                }
                .padding(Theme.Spacing.md)
            }
        } else if let errorMessage, models.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if models.isEmpty {
            EmptyStateView(
                systemImage: "shippingbox",
                title: "Nothing published yet",
                message: "Publish one of your models from the Models tab and it shows up here for everyone to fork."
            )
        } else {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    intro
                    BigSegment(selection: $sort, options: ["Most forked", "Most accurate"])
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, model in
                        card(model)
                            .staggeredEntrance(index: index)
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
    }

    private var intro: some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Palette.accent)
                Text("Fork any published model to get your own editable copy. Its record here is the author's — your copy starts fresh.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    // MARK: - Model card

    private func card(_ model: MarketplaceModel) -> some View {
        let entry = accuracy[model.id]
        let mine = isMine(model)
        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.name)
                            .font(Theme.Font.headline())
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text("by \(model.authorName)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    if mine { StatusPill(text: "Yours", color: Theme.Palette.accent) }
                    if model.isML {
                        StatusPill(text: "ML", systemImage: "cpu",
                                   color: Color(hex: 0xAF52DE), solid: true)
                    }
                }

                if let desc = model.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: Theme.Spacing.md) {
                    metric(value: accuracyText(entry), label: gradedLabel(entry),
                           tint: precise(entry) != nil
                                 ? Theme.Palette.accent : Theme.Palette.textTertiary)
                    metric(value: "\(model.forks)",
                           label: model.forks == 1 ? "fork" : "forks",
                           tint: Theme.Palette.textPrimary)
                    Spacer(minLength: 0)
                }

                Divider().overlay(Theme.Palette.border)

                if model.isML {
                    Text("\(model.mlKindLabel.uppercased()) · \(model.mlFeatures.count) FEATURES")
                        .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.6)
                        .foregroundStyle(Theme.Palette.textTertiary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)],
                              alignment: .leading, spacing: 6) {
                        ForEach(model.mlFeatures, id: \.self) { feature in
                            Text(feature)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xAF52DE))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .frame(maxWidth: .infinity)
                                .background(Color(hex: 0xAF52DE).opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }
                } else {
                    Text("WEIGHTS")
                        .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.6)
                        .foregroundStyle(Theme.Palette.textTertiary)
                    WeightBar(weights: model.weights)
                    WeightLegend(weights: model.weights)
                }

                forkButton(model, mine: mine)
            }
        }
    }

    private func metric(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    @ViewBuilder
    private func forkButton(_ model: MarketplaceModel, mine: Bool) -> some View {
        if mine {
            Text("This is your model — it's live for everyone to fork.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, Theme.Spacing.xxs)
        } else if forked.contains(model.id) || alreadyForked.contains(model.id) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                Text("Forked to your models")
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.Palette.positive)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.xxs)
        } else {
            PressableButton(action: { Task { await fork(model) } }) {
                HStack(spacing: 6) {
                    if forking == model.id {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(auth.isSignedIn ? "Fork this model" : "Sign in to fork")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(auth.isSignedIn
                                           ? Theme.Palette.accent
                                           : Theme.Palette.accent.opacity(0.4)))
            }
            .disabled(!auth.isSignedIn || forking != nil)
        }
    }

    // MARK: - Derived

    private func isMine(_ model: MarketplaceModel) -> Bool {
        // Postgres stores the id lowercase; AuthStore hands back an uppercased
        // UUID. Comparing raw marks every model as somebody else's.
        model.userId.lowercased() == auth.userId?.lowercased()
    }

    /// Precise accuracy from correct/total — `accuracy_pct` is rounded to one
    /// decimal, which ties too easily to order a board by.
    private func precise(_ entry: ModelLeaderboardEntry?) -> Double? {
        guard let entry, entry.totalPredictions > 0 else { return nil }
        return Double(entry.correctPredictions) / Double(entry.totalPredictions) * 100
    }

    private func accuracyText(_ entry: ModelLeaderboardEntry?) -> String {
        precise(entry).map { String(format: "%.1f%%", $0) } ?? "—"
    }

    private func gradedLabel(_ entry: ModelLeaderboardEntry?) -> String {
        guard let entry, entry.totalPredictions > 0 else { return "untested" }
        return "of \(entry.totalPredictions) graded"
    }

    private var sorted: [MarketplaceModel] {
        guard sort == 1 else { return models }        // backend already orders by forks
        return models.sorted { lhs, rhs in
            switch (precise(accuracy[lhs.id]), precise(accuracy[rhs.id])) {
            case let (l?, r?): return l != r ? l > r : lhs.forks > rhs.forks
            case (_?, nil): return true               // untested models sink
            case (nil, _?): return false
            default: return lhs.forks > rhs.forks
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        loading = true
        defer { loading = false }
        // The leaderboard is decoration here — a failure there must not hide the
        // marketplace itself, so only the listing is allowed to fail the load.
        async let listing = api.marketplaceModels()
        async let board = api.modelsLeaderboard()
        do {
            models = try await listing
            accuracy = Dictionary(((try? await board) ?? []).map { ($0.modelId, $0) },
                                  uniquingKeysWith: { first, _ in first })
            errorMessage = nil
        } catch {
            Log.error("marketplace", error)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Fork

    private func fork(_ model: MarketplaceModel) async {
        guard let token = await auth.accessToken() else { return }
        forking = model.id
        defer { forking = nil }
        do {
            let result = try await api.forkModel(id: model.id, token: token)
            forked.insert(model.id)
            Haptics.success()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                toast = "\(result.name) is in your models."
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.8))
                withAnimation { toast = nil }
            }
            await load()          // fork_count moved; pick up the new number
            await onForked?()
        } catch {
            Log.error("fork model", error)
            actionError = error.localizedDescription
        }
    }
}

// MARK: - Publish control (shown on your own model cards)

/// The listing switch for a model you own, plus what it has earned there.
///
/// The toggle moves immediately and reverts if the call fails: publishing is a
/// one-tap decision, and a switch that sits still until a cold-started Render
/// answers reads as broken.
struct MarketplacePublishRow: View {
    let model: UserModel
    let onChange: (Bool) async -> Void

    @State private var pending: Bool?
    @State private var busy = false

    private var isListed: Bool { pending ?? model.isPublished }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: isListed ? "shippingbox.fill" : "lock.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isListed ? Theme.Palette.accent : Theme.Palette.textTertiary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(isListed ? "On the marketplace" : "Private")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer(minLength: 0)
            if busy {
                ProgressView()
            } else {
                Toggle("", isOn: Binding(get: { isListed }, set: { toggle(to: $0) }))
                    .labelsHidden()
                    .tint(Theme.Palette.accent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Publish \(model.name) to the marketplace")
    }

    private var subtitle: String {
        if !isListed { return "Publish it so other GMs can fork a copy." }
        if model.forks > 0 {
            return "Forked \(model.forks) time\(model.forks == 1 ? "" : "s") · anyone can copy it"
        }
        return "Listed for anyone to fork. No forks yet."
    }

    private func toggle(to newValue: Bool) {
        guard !busy else { return }
        pending = newValue
        busy = true
        Task {
            await onChange(newValue)
            busy = false
            // The parent reloads on success, so `model` becomes the truth again;
            // if it didn't move, dropping the optimistic value shows what stuck.
            pending = nil
        }
    }
}
