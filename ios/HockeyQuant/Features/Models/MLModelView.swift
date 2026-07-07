import SwiftUI
import Charts

/// Interactive ML lab: toggle which features to include and a logistic-regression
/// model retrains live on the season's games — out-of-sample accuracy, AUC, and
/// the learned feature weights.
struct MLModelView: View {
    /// When presented as a creation flow (from Models "+ New"), called after a
    /// successful save so the presenter can dismiss + refresh the models list.
    var onSaved: (() -> Void)? = nil

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

    // Training window: how many of the most recent graded games to learn from.
    // 0 = uninitialized; set to "all" once the first result reports the total.
    @State private var windowGames: Double = 0

    @State private var showSave = false
    @State private var saveName = ""
    @State private var saving = false
    @State private var saveMessage: String?
    @State private var saveOK = false

    // First-run tutorial (recallable from the ? toolbar button).
    @AppStorage("mlBuilderTutorialSeen") private var tutorialSeen = false
    @State private var showTutorial = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                featureCard
                trainingCard
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showTutorial = true } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("How ML models work")
            }
        }
        .task { await retrain() }
        .onAppear {
            if !tutorialSeen {
                tutorialSeen = true
                showTutorial = true
            }
        }
        .sheet(isPresented: $showTutorial) { MLTutorialSheet() }
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
            let r = try await api.createMLModel(name: saveName, features: feats, model: modelKind, window: windowParam, token: token)
            saveMessage = "Saved “\(r.name)” — \(Int(r.accuracy.rounded()))% over \(r.backfilled) games. Find it on the models leaderboard."
            saveOK = true
            if let onSaved {
                // Let the confirmation flash, then hand control back to the presenter.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.0))
                    onSaved()
                }
            }
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

    // MARK: - Training window

    /// The `window` value to send: 0 (= all history) when the slider sits at max.
    private var windowParam: Int {
        guard let total = result?.totalGames, windowGames > 0, Int(windowGames) < total else { return 0 }
        return Int(windowGames)
    }

    @ViewBuilder private var trainingCard: some View {
        if let r = result, let total = r.totalGames, total > 90 {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Training data").font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                        Spacer()
                        Text("\(windowGames > 0 ? Int(windowGames) : r.n) of \(total) games")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.Palette.accent)
                            .contentTransition(.numericText())
                    }
                    Text(rangeLabel(r))
                        .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                    Slider(value: $windowGames, in: 80...Double(total), step: 10) { editing in
                        if !editing { scheduleRetrain() }
                    }
                    .tint(Theme.Palette.accent)
                    if let curve = r.curve, curve.count > 1 {
                        curveChart(curve, current: windowGames > 0 ? Int(windowGames) : r.n)
                        Text("Out-of-sample accuracy vs how much recent history the model trains on. More seasons join this slider as they're tracked.")
                            .font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
        }
    }

    private func rangeLabel(_ r: MLModelResponse) -> String {
        guard let range = r.dateRange, range.count == 2,
              let from = Self.dayParser.date(from: range[0]),
              let to = Self.dayParser.date(from: range[1]) else {
            return "Trained on the most recent graded games."
        }
        return "Trained on \(Self.dayFmt.string(from: from)) – \(Self.dayFmt.string(from: to))"
    }

    private func curveChart(_ curve: [MLCurvePoint], current: Int) -> some View {
        let lo = (curve.map(\.accuracy).min() ?? 45) - 2
        let hi = (curve.map(\.accuracy).max() ?? 65) + 2
        return Chart {
            RuleMark(x: .value("Window", current))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Theme.Palette.textTertiary.opacity(0.7))
            ForEach(curve) { p in
                LineMark(x: .value("Games", p.games), y: .value("Accuracy", p.accuracy))
                    .foregroundStyle(Theme.Palette.accent)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Games", p.games), y: .value("Accuracy", p.accuracy))
                    .foregroundStyle(Theme.Palette.accent)
                    .symbolSize(28)
            }
        }
        .chartYScale(domain: lo...hi)
        .chartXAxisLabel("games trained on", alignment: .center)
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .frame(height: 120)
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

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
        if let r = try? await api.mlModel(features: feats, model: modelKind, window: windowParam) {
            withAnimation(.easeOut(duration: 0.2)) { result = r }
            // First result: park the slider at "all available history".
            if windowGames == 0, let total = r.totalGames { windowGames = Double(total) }
        }
        training = false
    }
}

// MARK: - Tutorial (auto-shown on first visit; recallable via the ? button)

struct MLTutorialSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundView().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        intro
                        section(icon: "checklist", tint: Theme.Palette.accent,
                                title: "1 · Pick your inputs",
                                text: "Each feature is a per-game signal, measured as home minus away — goalie form (GSAX), rest, streaks, special teams, injuries, head-to-head, the quality score, and expected goals. Fewer, stronger inputs often beat kitchen-sink models.")
                        section(icon: "slider.horizontal.3", tint: Theme.Palette.accentAlt,
                                title: "2 · Choose the model kind",
                                text: "")
                        kindCards
                        section(icon: "calendar", tint: Theme.Palette.positive,
                                title: "3 · Set the training window",
                                text: "The slider controls how much recent history the model learns from. More games = steadier, less noisy weights. Fewer games = it adapts faster to how teams are playing right now, but can overfit. The chart shows measured accuracy at each window size — let the data decide.")
                        section(icon: "target", tint: Theme.Palette.moderate,
                                title: "4 · Trust the out-of-sample number",
                                text: "Accuracy is 5-fold cross-validated: the model is always scored on games it never saw during training. That's the honest number to compare against the official model — anything else is memorization.")
                        section(icon: "square.and.arrow.down", tint: Color(hex: 0xAF52DE),
                                title: "5 · Save it and it goes live",
                                text: "Saving adds it to Your Models and the leaderboard with its backfilled record. From then on it automatically calls each night's official slate, and its picks are graded like any other model.")
                        gotIt
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationTitle("How ML models work")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var intro: some View {
        Text("You pick the ingredients; the model learns the recipe from the season's graded games — no sliders to hand-tune.")
            .font(Theme.Font.body())
            .foregroundStyle(Theme.Palette.textSecondary)
    }

    private var kindCards: some View {
        VStack(spacing: Theme.Spacing.sm) {
            kindCard(name: "Logistic regression",
                     blurb: "Learns one weight per signal — like the classic sliders, but fit by math instead of by hand. Simple, stable on small data, and you can read exactly what it leans on.",
                     bestFor: "Best for: a strong, interpretable default.")
            kindCard(name: "Gradient-boosted",
                     blurb: "Builds dozens of small if/then rules that stack — it can catch combinations a linear model can't (say, a rested team and a hot goalie). More powerful, but hungrier for data and easier to overfit on short windows.",
                     bestFor: "Best for: squeezing out non-linear patterns once there's plenty of history.")
        }
    }

    private func kindCard(name: String, blurb: String, bestFor: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(name)
                    .font(Theme.Font.headlineHeavy())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(blurb)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text(bestFor)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Palette.accent)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section(icon: String, tint: Color, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.16))
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                }
                .frame(width: 28, height: 28)
                Text(title)
                    .font(Theme.Font.headlineHeavy())
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private var gotIt: some View {
        PressableButton(action: { dismiss() }) {
            Text("Got it — let's build")
                .font(Theme.Font.headline())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Palette.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .padding(.top, Theme.Spacing.xs)
    }
}
