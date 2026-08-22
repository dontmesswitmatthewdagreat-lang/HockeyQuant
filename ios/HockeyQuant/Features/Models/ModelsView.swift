import SwiftUI

/// The Models tab: build/tune your own prediction models (weightings) and
/// compete on the public model leaderboard. Requires sign-in.
struct ModelsView: View {
    @Environment(AuthStore.self) private var auth
    @State private var model = ModelsViewModel()
    @State private var editor: ModelEditorMode?

    // "+ New" builder chooser → classic slider editor or the ML trainer.
    private enum BuilderKind { case classic, ml }
    @State private var showChooser = false
    @State private var pendingBuilder: BuilderKind?
    @State private var showMLBuilder = false
    @State private var mlDetail: UserModel?
    @State private var expandedModelIds: Set<String> = []
    @State private var segment = 0   // 0 = My Models, 1 = The Lab

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
            // The curved hero band carries the top controls (+ New, avatar).
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editor) { mode in
                ModelEditorView(mode: mode) { await reload() }
            }
            // Builder chooser: pick a path, then the target sheet opens on dismiss
            // (opening a second sheet mid-dismissal races otherwise).
            .sheet(isPresented: $showChooser, onDismiss: {
                switch pendingBuilder {
                case .classic: editor = .create
                case .ml: showMLBuilder = true
                case nil: break
                }
                pendingBuilder = nil
            }) {
                builderChooser
                    .presentationDetents([.height(320)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showMLBuilder) { mlBuilderSheet }
            .floatingCard(item: $mlDetail) { m in
                MLModelDetailSheet(model: m) { await reload() }
            }
        }
        .task(id: auth.isSignedIn) { await reload() }
    }

    // MARK: - Builder chooser

    private var builderChooser: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New model")
                    .font(Theme.Font.title())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Pick how you want to build it.")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            chooserOption(icon: "slider.horizontal.3", tint: Theme.Palette.accent,
                          title: "Classic builder",
                          subtitle: "Hand-tune the factor weights and emphasis with sliders.") {
                pendingBuilder = .classic
                showChooser = false
            }
            chooserOption(icon: "cpu.fill", tint: Color(hex: 0xAF52DE),
                          title: "Machine-learned",
                          subtitle: "Pick the inputs — it trains on the season's games and reports out-of-sample accuracy.") {
                pendingBuilder = .ml
                showChooser = false
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.background)
    }

    private func chooserOption(icon: String, tint: Color, title: String, subtitle: String,
                               action: @escaping () -> Void) -> some View {
        PressableButton(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(tint.opacity(0.16))
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Font.headlineHeavy())
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(Theme.Spacing.sm)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Theme.Palette.border, lineWidth: 1))
        }
    }

    private var mlBuilderSheet: some View {
        NavigationStack {
            MLModelView(onSaved: {
                showMLBuilder = false
                Task { await reload() }
            })
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showMLBuilder = false }
                }
            }
        }
    }

    private func reload() async {
        guard auth.isSignedIn, let token = await auth.accessToken() else { return }
        await model.load(token: token)
    }

    /// Sources this user has already forked, so the marketplace can say so on a
    /// later visit instead of offering the same copy again.
    private var forkedSourceIds: Set<String> {
        guard case .loaded(let models) = model.state else { return [] }
        return Set(models.compactMap(\.forkedFrom))
    }

    /// List a model on the marketplace, or take it back down. Reloads so the
    /// card shows the fork count the backend actually has.
    private func publish(_ m: UserModel, _ isPublic: Bool) async {
        guard let token = await auth.accessToken() else { return }
        do {
            try await APIClient().publishModel(id: m.id, public: isPublic, token: token)
            await reload()
        } catch {
            Log.error("publish model", error)
        }
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
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    modelsBand(models)   // full-bleed curved header
                    VStack(spacing: Theme.Spacing.lg) {
                        BigSegment(selection: $segment, options: ["My Models", "The Lab"])
                        ZStack {
                            if segment == 0 {
                                modelsSegment(models).transition(.opacity)
                            } else {
                                labGrid.transition(.opacity)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
                .padding(.bottom, Theme.Spacing.md)
            }
            .refreshable { await reload() }
        }
    }

    // MARK: - Hero band (curved header)

    private func modelsBand(_ models: [UserModel]) -> some View {
        HeroBand(tint: Theme.Palette.accent) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Spacer()
                    BandIconButton(systemImage: "plus") { showChooser = true }
                    AvatarButton()
                }
                Text("Models")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
                Text("\(models.count) model\(models.count == 1 ? "" : "s") · 6 lab tools · a marketplace")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    // MARK: - My Models segment

    private func modelsSegment(_ models: [UserModel]) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            if models.isEmpty {
                emptyModelsCard
            } else {
                ForEach(Array(models.enumerated()), id: \.element.id) { index, m in
                    ModelCard(
                        model: m,
                        isExpanded: expandedModelIds.contains(m.id),
                        onToggle: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                if expandedModelIds.contains(m.id) {
                                    expandedModelIds.remove(m.id)
                                } else {
                                    expandedModelIds.insert(m.id)
                                }
                            }
                        },
                        // ML models aren't slider-editable — show their detail instead.
                        onOpen: { if m.isML { mlDetail = m } else { editor = .edit(m) } },
                        onPublish: { isPublic in await publish(m, isPublic) }
                    )
                    .staggeredEntrance(index: index)
                }
                Button { showChooser = true } label: {
                    CapsuleActionLabel(title: "New model", systemImage: "plus", prominent: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyModelsCard: some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.Palette.accent)
                Text("No models yet")
                    .font(Theme.Font.headline())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Create your first model and tune the weightings your way.")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                PressableButton(action: { editor = .create }) {
                    Label("New model", systemImage: "plus")
                        .font(Theme.Font.headline())
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.Palette.accent)
                        .clipShape(Capsule())
                }
                .padding(.top, Theme.Spacing.xxs)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - The Lab segment (tool tile grid)

    private var labGrid: some View {
        VStack(spacing: Theme.Spacing.md) {
            toolGrid
            // The marketplace isn't a tool you run on your own models, it's where
            // you take someone else's — so it gets its own row rather than a
            // seventh tile that would leave the grid ragged.
            NavigationLink {
                ModelMarketplaceView(alreadyForked: forkedSourceIds,
                                     onForked: { await reload() })
            } label: {
                marketplaceRow
            }
            .buttonStyle(.plain)
        }
    }

    private var marketplaceRow: some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(Theme.Palette.accent.opacity(0.16))
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model marketplace")
                        .font(Theme.Font.headlineHeavy())
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("Browse what other GMs published and fork a copy to tune yourself.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    private var toolGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 3)
        return LazyVGrid(columns: cols, spacing: Theme.Spacing.sm) {
            NavigationLink { WhatIfSimulatorView() } label: {
                ActionTile(icon: "dial.medium.fill", title: "What-if", tint: Theme.Palette.accent)
            }
            .buttonStyle(.plain)
            NavigationLink { MonteCarloView() } label: {
                ActionTile(icon: "dice.fill", title: "Monte-Carlo", tint: Theme.Palette.accentAlt)
            }
            .buttonStyle(.plain)
            NavigationLink { SeasonOddsView() } label: {
                ActionTile(icon: "chart.xyaxis.line", title: "Season odds", tint: Theme.Palette.positive)
            }
            .buttonStyle(.plain)
            NavigationLink { BacktestView() } label: {
                ActionTile(icon: "list.bullet.rectangle.fill", title: "Backtester", tint: Theme.Palette.moderate)
            }
            .buttonStyle(.plain)
            NavigationLink { MLModelView() } label: {
                ActionTile(icon: "cpu.fill", title: "ML model", tint: Color(hex: 0xAF52DE))
            }
            .buttonStyle(.plain)
            NavigationLink { ModelsLeaderboardView() } label: {
                ActionTile(icon: "trophy.fill", title: "Leaderboard", tint: Color(hex: 0xC9A227))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Model card

struct ModelCard: View {
    let model: UserModel
    var isExpanded: Bool = true
    var onToggle: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil
    var onPublish: ((Bool) async -> Void)? = nil

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // Header taps toggle expansion; the action row inside opens edit/detail.
                PressableButton(action: { onToggle?() }) {
                    HStack(alignment: .center, spacing: Theme.Spacing.xs) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.name)
                                .font(Theme.Font.headline())
                                .foregroundStyle(Theme.Palette.textPrimary)
                                .multilineTextAlignment(.leading)
                            if let desc = model.description, !desc.isEmpty {
                                Text(desc)
                                    .font(Theme.Font.caption())
                                    .foregroundStyle(Theme.Palette.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: Theme.Spacing.xs)
                        if model.isPublished {
                            StatusPill(text: "Listed", systemImage: "shippingbox.fill",
                                       color: Theme.Palette.accent)
                        }
                        if model.isML {
                            StatusPill(text: "ML", systemImage: "cpu", color: Color(hex: 0xAF52DE), solid: true)
                        }
                        accuracyVerdict
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? -180 : 0))
                    }
                    .contentShape(Rectangle())
                }

                if isExpanded {
                    expandedContent
                        .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder private var expandedContent: some View {
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
        if model.isML {
            Text("FEATURES · \(model.mlKindLabel.uppercased())")
                .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.6)
                .foregroundStyle(Theme.Palette.textTertiary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)],
                      alignment: .leading, spacing: 6) {
                ForEach(model.mlFeatures ?? [], id: \.self) { f in
                    Text(f)
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
            VStack(spacing: 7) {
                ForEach(Array(model.weights.rows.enumerated()), id: \.offset) { i, row in
                    weightRow(row.label, row.value, WeightBar.colors[i % WeightBar.colors.count])
                }
            }
        }
        if let onPublish {
            Divider().overlay(Theme.Palette.border)
            MarketplacePublishRow(model: model, onChange: onPublish)
        }
        if onOpen != nil {
            PressableButton(action: { onOpen?() }) {
                HStack(spacing: 4) {
                    Image(systemName: model.isML ? "info.circle" : "slider.horizontal.3")
                        .font(.system(size: 11, weight: .bold))
                    Text(model.isML ? "View details" : "Edit weights")
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .heavy))
                }
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.xxs)
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

// MARK: - ML model detail (info + delete; ML models aren't slider-editable)

struct MLModelDetailSheet: View {
    let model: UserModel
    var onChanged: () async -> Void

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var errorMessage: String?
    private let api = APIClient()

    private let mlTint = Color(hex: 0xAF52DE)

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                Text(model.name.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                header
                if let acc = model.accuracy, acc.totalPredictions > 0 {
                    accuracyCard(acc)
                }
                featuresCard
                howItWorks
                deleteButton
                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.negative)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .frame(maxHeight: 640)
        .confirmationDialog("Delete “\(model.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete model", role: .destructive) { Task { await deleteModel() } }
        } message: {
            Text("This removes the model and its tracked predictions.")
        }
    }

    private var header: some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(mlTint.opacity(0.16))
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(mlTint)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.mlKindLabel) ML model")
                        .font(Theme.Font.headlineHeavy())
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("\((model.mlFeatures ?? []).count) features · trained on the season's graded games")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func accuracyCard(_ acc: ModelAccuracyStats) -> some View {
        SectionCard("Accuracy") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text("\(Int(acc.accuracyPct.rounded()))%")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.accent)
                    Text("\(acc.correctPredictions)/\(acc.totalPredictions) graded")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textTertiary)
                    Spacer(minLength: 0)
                }
                RangeGauge(fraction: min(max((acc.accuracyPct - 40) / 25, 0), 1),
                           loLabel: "40%", hiLabel: "65%",
                           tint: Theme.Palette.textPrimary,
                           gradient: [Theme.Palette.negative, Theme.Palette.moderate, Theme.Palette.positive])
            }
        }
    }

    private var featuresCard: some View {
        SectionCard("Features") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)],
                      alignment: .leading, spacing: 6) {
                ForEach(model.mlFeatures ?? [], id: \.self) { f in
                    Text(f)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(mlTint)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(mlTint.opacity(0.10))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var howItWorks: some View {
        SectionCard("How it works") {
            Text("This model was trained once on the season's graded games and keeps its learned weights. It automatically calls each night's official slate, and its picks are graded like any other model. ML models can't be edited — train a new one from + New to try different inputs.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var deleteButton: some View {
        PressableButton(action: { confirmDelete = true }) {
            HStack(spacing: 6) {
                if deleting { ProgressView().tint(.white) } else { Image(systemName: "trash.fill") }
                Text(deleting ? "Deleting…" : "Delete model")
            }
            .font(Theme.Font.headline())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Palette.negative)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .disabled(deleting)
    }

    private func deleteModel() async {
        guard let token = await auth.accessToken() else {
            errorMessage = "Sign in to delete this model."
            return
        }
        deleting = true
        errorMessage = nil
        do {
            try await api.deleteModel(id: model.id, token: token)
            await onChanged()
            dismiss()
        } catch {
            errorMessage = "Couldn't delete: \(error.localizedDescription)"
        }
        deleting = false
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
