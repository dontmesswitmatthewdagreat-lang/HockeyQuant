import SwiftUI

enum ModelEditorMode: Identifiable {
    case create
    case edit(UserModel)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let m): return m.id
        }
    }
}

/// Create or edit a custom model: name, description, and five weight sliders
/// that must sum to 100.
struct ModelEditorView: View {
    let mode: ModelEditorMode
    let onSaved: () async -> Void

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var weights: ModelWeights
    @State private var multipliers: ModelMultipliers
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false

    private let api = APIClient()

    init(mode: ModelEditorMode, onSaved: @escaping () async -> Void) {
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _description = State(initialValue: "")
            _weights = State(initialValue: .official)
            _multipliers = State(initialValue: .official)
        case .edit(let m):
            _name = State(initialValue: m.name)
            _description = State(initialValue: m.description ?? "")
            _weights = State(initialValue: m.weights)
            _multipliers = State(initialValue: m.resolvedMultipliers)
        }
    }

    private var isEditing: Bool { if case .edit = mode { return true } else { return false } }
    private var total: Double { weights.total }
    private var balanced: Bool { abs(total - 100) < 0.5 }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && balanced && !isSaving }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    presetsCard
                    nameCard
                    weightsCard
                    multipliersCard
                    if isEditing, case .edit(let m) = mode { previewLink(m) }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Palette.negative)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if isEditing { deleteButton }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Palette.background)
            .navigationTitle(isEditing ? "Edit model" : "New model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else {
                        Button("Save") { save() }.disabled(!canSave)
                    }
                }
            }
            .alert("Delete model?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the model and its prediction history.")
            }
        }
    }

    // MARK: - Cards

    private var nameCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                labeledField("NAME", placeholder: "e.g. Goalie Truther", text: $name)
                labeledField("DESCRIPTION (OPTIONAL)", placeholder: "What's your angle?", text: $description)
            }
        }
    }

    private func labeledField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
            TextField(placeholder, text: text)
                .font(Theme.Font.body())
                .padding(Theme.Spacing.sm)
                .background(Theme.Palette.background)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .stroke(Theme.Palette.border, lineWidth: 1)
                )
        }
    }

    private var weightsCard: some View {
        Card {
            VStack(spacing: Theme.Spacing.md) {
                HStack {
                    Text("WEIGHTS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                    Spacer()
                    Text("Total \(Int(total.rounded()))/100")
                        .font(Theme.Font.caption())
                        .foregroundStyle(balanced ? Theme.Palette.strong : Theme.Palette.moderate)
                }
                WeightBar(weights: weights)
                ForEach(Array(weights.rows.enumerated()), id: \.offset) { _, row in
                    sliderRow(label: row.label, keyPath: row.key)
                }
                HStack(spacing: Theme.Spacing.sm) {
                    secondaryButton("Normalize to 100", systemImage: "wand.and.stars") { normalize() }
                    secondaryButton("Reset to official", systemImage: "arrow.uturn.backward") { weights = .official }
                }
            }
        }
    }

    private func sliderRow(label: String, keyPath: WritableKeyPath<ModelWeights, Double>) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Text("\(Int(weights[keyPath: keyPath].rounded()))")
                    .font(Theme.Font.mono()).foregroundStyle(Theme.Palette.textSecondary)
            }
            Slider(
                value: Binding(
                    get: { weights[keyPath: keyPath] },
                    set: { weights[keyPath: keyPath] = $0.rounded() }
                ),
                in: 0...100, step: 1
            )
            .tint(Theme.Palette.accent)
        }
    }

    private func secondaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        PressableButton(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.Palette.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        }
    }

    // MARK: - Presets

    private var presetsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("ARCHETYPES")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.leading, Theme.Spacing.xs)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(ModelPreset.all) { preset in
                        PressableButton(action: { apply(preset) }) {
                            VStack(spacing: 4) {
                                Image(systemName: preset.icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(Theme.Palette.accent)
                                Text(preset.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.Palette.textPrimary)
                            }
                            .frame(width: 92, height: 64)
                            .background(Theme.Palette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                    .stroke(Theme.Palette.border, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }

    private func apply(_ preset: ModelPreset) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            weights = preset.weights
            multipliers = preset.multipliers
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = preset.name }
        Haptics.tap()
    }

    // MARK: - Factor emphasis (multiplier levers)

    private var multipliersCard: some View {
        Card {
            VStack(spacing: Theme.Spacing.md) {
                HStack {
                    Text("FACTOR EMPHASIS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                    Spacer()
                    Text(multipliers.isOfficial ? "Official" : "Custom")
                        .font(Theme.Font.caption())
                        .foregroundStyle(multipliers.isOfficial ? Theme.Palette.textTertiary : Theme.Palette.accent)
                }
                Text("How hard each situational factor swings this model. 100% = official.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(multipliers.rows.enumerated()), id: \.offset) { _, row in
                    multiplierRow(label: row.label, keyPath: row.key)
                }
            }
        }
    }

    private func multiplierRow(label: String, keyPath: WritableKeyPath<ModelMultipliers, Double>) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Text("\(Int((multipliers[keyPath: keyPath] * 100).rounded()))%")
                    .font(Theme.Font.mono())
                    .foregroundStyle(multipliers[keyPath: keyPath] == 1 ? Theme.Palette.textSecondary : Theme.Palette.accent)
            }
            Slider(
                value: Binding(
                    get: { multipliers[keyPath: keyPath] },
                    set: { multipliers[keyPath: keyPath] = ($0 * 20).rounded() / 20 }
                ),
                in: 0...2, step: 0.05
            )
            .tint(Theme.Palette.accent)
        }
    }

    private func previewLink(_ model: UserModel) -> some View {
        NavigationLink {
            ModelPreviewView(modelId: model.id, modelName: model.name)
        } label: {
            HStack {
                Label("Preview this model's picks", systemImage: "sparkles.tv")
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
            }
            .font(Theme.Font.headline())
            .foregroundStyle(Theme.Palette.accent)
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.accent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
    }

    private var deleteButton: some View {
        PressableButton(action: { showDeleteConfirm = true }) {
            Label("Delete model", systemImage: "trash")
                .font(Theme.Font.headline())
                .foregroundStyle(Theme.Palette.negative)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Palette.negative.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
    }

    // MARK: - Actions

    private func normalize() {
        let t = weights.total
        guard t > 0 else { weights = .official; return }
        let scale = 100 / t
        weights.offense = (weights.offense * scale).rounded()
        weights.defense = (weights.defense * scale).rounded()
        weights.goaltending = (weights.goaltending * scale).rounded()
        weights.pointsPct = (weights.pointsPct * scale).rounded()
        weights.winRate = (weights.winRate * scale).rounded()
        // Fix any rounding drift by adjusting the largest bucket.
        let drift = 100 - weights.total
        if drift != 0 { weights.offense += drift }
    }

    private func save() {
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            guard let token = await auth.accessToken() else {
                errorMessage = "You need to be signed in."
                return
            }
            let request = CreateModelRequest(
                name: name.trimmingCharacters(in: .whitespaces),
                description: description.isEmpty ? nil : description,
                weights: weights,
                multipliers: multipliers
            )
            do {
                switch mode {
                case .create:
                    _ = try await api.createModel(request, token: token)
                case .edit(let m):
                    _ = try await api.updateModel(id: m.id, request, token: token)
                }
                await onSaved()
                Haptics.success()
                dismiss()
            } catch {
                Log.error("Save model failed", error)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete() {
        guard case .edit(let m) = mode else { return }
        isDeleting = true
        Task {
            defer { isDeleting = false }
            guard let token = await auth.accessToken() else { return }
            do {
                try await api.deleteModel(id: m.id, token: token)
                await onSaved()
                dismiss()
            } catch {
                Log.error("Delete model failed", error)
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Preset archetypes

/// One-tap model personalities. Each sets the base weights AND the factor
/// emphasis to express a distinct strategy.
struct ModelPreset: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let weights: ModelWeights
    let multipliers: ModelMultipliers

    static let all: [ModelPreset] = [
        ModelPreset(
            name: "Balanced", icon: "circle.grid.cross",
            weights: .official, multipliers: .official
        ),
        ModelPreset(
            name: "Goalie Truther", icon: "figure.hockey",
            weights: ModelWeights(offense: 25, defense: 15, goaltending: 45, pointsPct: 10, winRate: 5),
            multipliers: .official
        ),
        ModelPreset(
            name: "Run & Gun", icon: "bolt.fill",
            weights: ModelWeights(offense: 60, defense: 10, goaltending: 20, pointsPct: 5, winRate: 5),
            multipliers: .official
        ),
        ModelPreset(
            name: "Defensive Wall", icon: "shield.fill",
            weights: ModelWeights(offense: 20, defense: 35, goaltending: 35, pointsPct: 5, winRate: 5),
            multipliers: .official
        ),
        ModelPreset(
            name: "Momentum Rider", icon: "flame.fill",
            weights: .official,
            multipliers: ModelMultipliers(fatigue: 1, streak: 2.0, specialTeams: 1, injuries: 1, h2h: 1.5)
        ),
        ModelPreset(
            name: "Fade the Tired", icon: "zzz",
            weights: .official,
            multipliers: ModelMultipliers(fatigue: 2.0, streak: 1, specialTeams: 1, injuries: 1.5, h2h: 1)
        ),
        ModelPreset(
            name: "Chalk", icon: "checkmark.seal.fill",
            weights: ModelWeights(offense: 30, defense: 10, goaltending: 20, pointsPct: 25, winRate: 15),
            multipliers: ModelMultipliers(fatigue: 0.5, streak: 0.5, specialTeams: 0.5, injuries: 1, h2h: 0.5)
        ),
    ]
}
