import SwiftUI

/// The Models tab: build/tune your own prediction models (weightings) and
/// compete on the public model leaderboard. Requires sign-in.
struct ModelsView: View {
    @Environment(AuthStore.self) private var auth
    @State private var model = ModelsViewModel()
    @State private var editor: ModelEditorMode?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundView().ignoresSafeArea()
                if auth.isInitializing {
                    ProgressView()
                } else if !auth.isSignedIn {
                    signInPrompt
                } else {
                    content
                }
            }
            .navigationTitle("Models")
            .toolbar {
                if auth.isSignedIn {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { ModelsLeaderboardView() } label: {
                            Label("Leaderboard", systemImage: "trophy.fill")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { PlaygroundView() } label: {
                            Label("Playground", systemImage: "flask.fill")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { editor = .create } label: {
                            Label("New", systemImage: "plus")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { AvatarButton() }
            }
            .sheet(item: $editor) { mode in
                ModelEditorView(mode: mode) { await reload() }
            }
        }
        .task(id: auth.isSignedIn) { await reload() }
    }

    private func reload() async {
        guard auth.isSignedIn, let token = await auth.accessToken() else { return }
        await model.load(token: token)
    }

    // MARK: - Sign-in gate

    private var signInPrompt: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 44))
                .foregroundStyle(Theme.Palette.accent)
            Text("Build your model")
                .font(Theme.Font.title())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Sign in on the Profile tab to tune your own prediction weightings and compete with the field.")
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(0..<3, id: \.self) { _ in LoadingShimmer(height: 130) }
                }
                .padding(Theme.Spacing.md)
            }
        case .error(let message):
            ErrorStateView(message: message) { Task { await reload() } }
        case .loaded(let models):
            if models.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        ForEach(Array(models.enumerated()), id: \.element.id) { index, m in
                            Button { editor = .edit(m) } label: { ModelCard(model: m) }
                                .buttonStyle(.plain)
                                .staggeredEntrance(index: index)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
                .refreshable { await reload() }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            EmptyStateView(
                systemImage: "slider.horizontal.3",
                title: "No models yet",
                message: "Create your first model and tune the weightings your way."
            )
            PressableButton(action: { editor = .create }) {
                Label("New model", systemImage: "plus")
                    .font(Theme.Font.headline())
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Palette.accent)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Model card

struct ModelCard: View {
    let model: UserModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.name)
                            .font(Theme.Font.headline())
                            .foregroundStyle(Theme.Palette.textPrimary)
                        if let desc = model.description, !desc.isEmpty {
                            Text(desc)
                                .font(Theme.Font.caption())
                                .foregroundStyle(Theme.Palette.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    accuracyVerdict
                }
                if let acc = model.accuracy, acc.totalPredictions > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        Text("\(Int(acc.accuracyPct.rounded()))%")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.Palette.accent)
                        Text("\(acc.correctPredictions)/\(acc.totalPredictions) graded")
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Palette.textTertiary)
                        Spacer(minLength: 0)
                    }
                    // Where this model's accuracy lands on a coin‑flip → elite track.
                    RangeGauge(fraction: normAcc(acc.accuracyPct), loLabel: "40%", hiLabel: "65%",
                               tint: Theme.Palette.textPrimary,
                               gradient: [Theme.Palette.negative, Theme.Palette.moderate, Theme.Palette.positive])
                } else {
                    Text("No graded picks yet")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                Divider().overlay(Theme.Palette.border)
                Text("WEIGHTS")
                    .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.6)
                    .foregroundStyle(Theme.Palette.textTertiary)
                VStack(spacing: 7) {
                    ForEach(Array(model.weights.rows.enumerated()), id: \.offset) { i, row in
                        weightRow(row.label, row.value, WeightBar.colors[i % WeightBar.colors.count])
                    }
                }
            }
        }
    }

    private var maxWeight: Double { max(model.weights.rows.map(\.value).max() ?? 1, 1) }

    private func weightRow(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 92, alignment: .leading)
            ProbBar(fraction: value / maxWeight, tint: color, height: 7)
            Text("\(Int(value))")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 22, alignment: .trailing)
        }
    }

    private func normAcc(_ pct: Double) -> Double { min(max((pct - 40) / 25, 0), 1) }

    @ViewBuilder
    private var accuracyVerdict: some View {
        if let acc = model.accuracy, acc.totalPredictions > 0 {
            let p = acc.accuracyPct
            if p >= 55 {
                StatusPill(text: "Sharp", systemImage: "flame.fill", color: Theme.Palette.positive, solid: true)
            } else if p >= 52.4 {
                StatusPill(text: "Profitable", systemImage: "checkmark", color: Theme.Palette.positive)
            } else if p >= 50 {
                StatusPill(text: "Break-even", color: Theme.Palette.moderate)
            } else {
                StatusPill(text: "Below", color: Theme.Palette.negative)
            }
        } else {
            StatusPill(text: "Untested", color: Theme.Palette.textTertiary)
        }
    }
}

// MARK: - Weight distribution bar

struct WeightBar: View {
    let weights: ModelWeights

    static let colors: [Color] = [
        Color(hex: 0x14CA64), Color(hex: 0x0A84FF), Color(hex: 0xF5A623),
        Color(hex: 0xAF52DE), Color(hex: 0x8A93A1),
    ]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(weights.rows.enumerated()), id: \.offset) { index, row in
                    Self.colors[index % Self.colors.count]
                        .frame(width: max(0, geo.size.width * CGFloat(row.value / max(weights.total, 1))))
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }
}

struct WeightLegend: View {
    let weights: ModelWeights

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(weights.rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 3) {
                    Circle().fill(WeightBar.colors[index % WeightBar.colors.count]).frame(width: 6, height: 6)
                    Text("\(Int(row.value))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
    }
}
