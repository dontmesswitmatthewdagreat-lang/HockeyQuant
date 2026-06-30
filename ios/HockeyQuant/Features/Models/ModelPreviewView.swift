import SwiftUI

/// Shows how a custom model picks the games for a date — the payoff of tuning.
/// Uses the existing `GET /api/models/{id}/predictions/{date}` endpoint.
struct ModelPreviewView: View {
    let modelId: String
    let modelName: String

    @Environment(AuthStore.self) private var auth

    enum State {
        case loading
        case loaded([GamePrediction])
        case empty
        case error(String)
    }

    @SwiftUI.State private var state: State = .loading
    @SwiftUI.State private var date = Date()
    @SwiftUI.State private var showingDatePicker = false
    @Namespace private var previewNS

    private let api = APIClient()
    private let columns = [GridItem(.flexible(), spacing: Theme.Spacing.sm),
                           GridItem(.flexible(), spacing: Theme.Spacing.sm)]

    private var dateBinding: Binding<Date> {
        Binding(get: { date }, set: { date = $0 })
    }

    private var dateString: String { APIClient.apiDateString(date) }
    private var dateLabel: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            VStack(spacing: 0) {
                dateBar
                content
            }
        }
        .navigationTitle(modelName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: dateString) { await load() }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker("Date", selection: dateBinding, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Pick a date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingDatePicker = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var dateBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            stepButton("chevron.left") { step(-1) }
            PressableButton(action: { showingDatePicker = true }) {
                Text(dateLabel)
                    .font(Theme.Font.headline())
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(maxWidth: .infinity)
            }
            stepButton("chevron.right") { step(1) }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(.ultraThinMaterial)
    }

    private func stepButton(_ name: String, action: @escaping () -> Void) -> some View {
        PressableButton(action: action) {
            Image(systemName: name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 36, height: 36)
                .background(Theme.Palette.surface)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.Palette.border, lineWidth: 1))
        }
    }

    private func step(_ days: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: days, to: date) { date = next }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                    ForEach(0..<4, id: \.self) { _ in LoadingShimmer(height: 132) }
                }
                .padding(Theme.Spacing.md)
            }
        case .empty:
            EmptyStateView(
                systemImage: "calendar.badge.exclamationmark",
                title: "No games \(dateLabel.lowercased())",
                message: "Pick a date with scheduled games to see this model's calls."
            )
        case .error(let message):
            ErrorStateView(message: message) { Task { await load() } }
        case .loaded(let games):
            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                    ForEach(games) { game in
                        GameTileView(game: ScheduleGame(prediction: game, score: nil),
                                     namespace: previewNS, isExpanded: false) {}
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
    }

    private func load() async {
        state = .loading
        guard let token = await auth.accessToken() else {
            state = .error("You need to be signed in.")
            return
        }
        do {
            let response = try await api.modelPredictions(modelId: modelId, dateString: dateString, token: token)
            state = response.predictions.isEmpty ? .empty : .loaded(response.predictions)
        } catch {
            Log.error("Model preview failed", error)
            state = .error(error.localizedDescription)
        }
    }
}
