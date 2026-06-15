import SwiftUI
import Charts

/// Interactive ML lab: toggle which features to include and a logistic-regression
/// model retrains live on the season's games — out-of-sample accuracy, AUC, and
/// the learned feature weights.
struct MLModelView: View {
    private let api = APIClient(environment: .production)
    @Environment(AuthStore.self) private var auth

    // Feature catalog (mirrors the backend ids).
    private let catalog: [(id: String, label: String)] = [
        ("h2h", "Head-to-head"), ("streak", "Form / streak"), ("goalie", "Goalie (GSAX)"),
        ("st", "Special teams"), ("injury", "Injuries"), ("fatigue", "Fatigue / rest"),
        ("base_score", "Quality score"), ("xg_diff", "Expected goals"),
    ]

    @State private var selected: Set<String> = ["h2h", "streak", "goalie", "st", "injury", "fatigue", "base_score", "xg_diff"]
    @State private var modelKind = "logistic"
    @State private var result: MLModelResponse?
    @State private var training = true
    @State private var task: Task<Void, Never>?

    @State private var showSave = false
    @State private var saveName = ""
    @State private var saving = false
    @State private var saveMessage: String?
    @State private var saveOK = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                featureCard
                if let r = result {
                    accuracyCard(r)
                    weightsCard(r)
                    if auth.isSignedIn { saveCard(r) }
                } else if training { LoadingShimmer(height: 160) }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Palette.background)
        .navigationTitle("Machine-Learned Model")
        .navigationBarTitleDisplayMode(.inline)
        .task { await retrain() }
        .alert("Save as model", isPresented: $showSave) {
            TextField("Model name", text: $saveName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await save() } }
        } message: {
            Text("Trains on your selected features and adds it to the models leaderboard, scored out-of-sample against hand-tuned models.")
        }
    }

    private func saveCard(_ r: MLModelResponse) -> some View {
        Card {
            VStack(spacing: Theme.Spacing.xs) {
                Button {
                    saveName = "My \(r.kind == "boosted" ? "Boosted" : "Logistic") Model"
                    showSave = true
                } label: {
                    HStack(spacing: 6) {
                        if saving { ProgressView().tint(.white) } else { Image(systemName: "square.and.arrow.down.fill") }
                        Text(saving ? "Saving…" : "Save as model")
                    }
                    .font(Theme.Font.headline()).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Palette.accent).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }
                .disabled(saving)
                if let msg = saveMessage {
                    Text(msg).font(Theme.Font.caption())
                        .foregroundStyle(saveOK ? Theme.Palette.strong : Theme.Palette.moderate)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func save() async {
        guard let token = await auth.accessToken() else {
            saveMessage = "Sign in to save a model."; saveOK = false; return
        }
        saving = true; saveMessage = nil
        let feats = catalog.map(\.id).filter(selected.contains)
        do {
            let r = try await api.createMLModel(name: saveName, features: feats, model: modelKind, token: token)
            saveMessage = "Saved “\(r.name)” — \(Int(r.accuracy.rounded()))% over \(r.backfilled) games. Find it on the models leaderboard."
            saveOK = true
        } catch {
            saveMessage = "Couldn't save: \(error.localizedDescription)"; saveOK = false
        }
        saving = false
    }

    // MARK: - Features

    private var featureCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Features").font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                Text("Pick the inputs — the model retrains on the season's games and reports out-of-sample accuracy.")
                    .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                Picker("Model", selection: $modelKind) {
                    Text("Logistic").tag("logistic")
                    Text("Gradient-boosted").tag("boosted")
                }
                .pickerStyle(.segmented)
                .onChange(of: modelKind) { _, _ in scheduleRetrain() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Theme.Spacing.xs)], alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(catalog, id: \.id) { f in
                        let on = selected.contains(f.id)
                        Button {
                            if on { if selected.count > 1 { selected.remove(f.id) } } else { selected.insert(f.id) }
                            scheduleRetrain()
                        } label: {
                            Text(f.label).font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(on ? Theme.Palette.accent.opacity(0.16) : Theme.Palette.surface)
                                .foregroundStyle(on ? Theme.Palette.accent : Theme.Palette.textSecondary)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(on ? Theme.Palette.accent : Theme.Palette.border, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Accuracy

    private func accuracyCard(_ r: MLModelResponse) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text("\(r.accuracy, specifier: "%.1f")%")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(r.accuracy > r.officialAccuracy ? Theme.Palette.strong : Theme.Palette.textPrimary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("±\(r.accuracyStd, specifier: "%.1f")  ·  AUC \(r.auc, specifier: "%.2f")").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                        Text("5-fold cross-validated (out-of-sample)").font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    if training { Spacer(); ProgressView().tint(Theme.Palette.accent) }
                }
                bar("ML model", r.accuracy, Theme.Palette.accent, best: true)
                bar("Official model", r.officialAccuracy, Theme.Palette.moderate, best: false)
                bar("Always home", r.homeRate, Theme.Palette.textTertiary, best: false)
                Text("Trained on \(r.n) graded games.").font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    private func bar(_ label: String, _ pct: Double, _ color: Color, best: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(label).font(.system(size: 11, weight: best ? .bold : .regular)).foregroundStyle(Theme.Palette.textSecondary).frame(width: 92, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.border)
                    Capsule().fill(color).frame(width: g.size.width * CGFloat(pct / 100))
                }
            }.frame(height: 8)
            Text("\(pct, specifier: "%.1f")%").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Theme.Palette.textPrimary).frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: - Weights

    private func weightsCard(_ r: MLModelResponse) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(r.kind == "boosted" ? "Feature importance" : "Learned weights").font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                Text(r.kind == "boosted"
                     ? "Gain-based importance — how much the boosted trees relied on each signal."
                     : "Standardized coefficients — magnitude = how much the model leans on each signal; sign = direction (toward home).")
                    .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                Chart(r.weights) { w in
                    BarMark(x: .value("Weight", w.weight), y: .value("Feature", w.label))
                        .foregroundStyle(w.weight >= 0 ? Theme.Palette.strong : Theme.Palette.moderate)
                }
                .chartYScale(domain: r.weights.map(\.label))
                .chartXAxisLabel(r.kind == "boosted" ? "Importance" : "Learned weight")
                .frame(height: CGFloat(r.weights.count * 30 + 24))
            }
        }
    }

    // MARK: - Train

    private func scheduleRetrain() {
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await retrain()
        }
    }

    private func retrain() async {
        training = true
        let feats = catalog.map(\.id).filter(selected.contains)
        if let r = try? await api.mlModel(features: feats, model: modelKind) {
            withAnimation(.easeOut(duration: 0.2)) { result = r }
        }
        training = false
    }
}
