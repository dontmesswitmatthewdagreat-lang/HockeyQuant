import SwiftUI

/// The Schedule screen: a horizontal day strip, a 2-column grid of matchup tiles
/// (live games first), and a hero-expand into the full breakdown. Live data from
/// the FastAPI backend.
struct TodayView: View {
    @State private var model = TodayViewModel()
    @State private var showingDatePicker = false
    @State private var expandedID: String?

    private let columns = [GridItem(.flexible(), spacing: Theme.Spacing.sm),
                           GridItem(.flexible(), spacing: Theme.Spacing.sm)]

    private var dateBinding: Binding<Date> {
        Binding(get: { model.selectedDate }, set: { model.selectedDate = $0 })
    }

    /// The currently-expanded game, looked up live from the loaded list so polling
    /// keeps the open breakdown (score / grid / shot map) current.
    private var expandedGame: ScheduleGame? {
        guard let id = expandedID, case .loaded(let games) = model.state else { return nil }
        return games.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundView().ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    content
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingDatePicker) { datePickerSheet }
            // Present the breakdown as a full-screen cover — its own layout context
            // with correct safe-area insets (no parent ignoresSafeArea interference).
            .fullScreenCover(isPresented: coverPresented) { expandedCover }
        }
        .task {
            model.warmUp()
            await model.load()
        }
        .onDisappear { model.stopPolling() }
    }

    private var coverPresented: Binding<Bool> {
        Binding(get: { expandedID != nil }, set: { if !$0 { expandedID = nil } })
    }

    @ViewBuilder private var expandedCover: some View {
        if let game = expandedGame {
            GameExpandedView(game: game, dateString: APIClient.apiDateString(model.selectedDate)) {
                expandedID = nil
            }
        } else {
            Color.clear.onAppear { expandedID = nil }
        }
    }

    private func expand(_ id: String) {
        Haptics.tap()
        expandedID = id
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Schedule")
                        .font(Theme.Font.title())
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(model.monthLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer()
                PressableButton(action: { showingDatePicker = true }) {
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.accent)
                        .frame(width: 38, height: 38)
                        .background(Theme.Palette.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.Palette.border, lineWidth: 1))
                }
                .accessibilityLabel("Jump to a date")
                AvatarButton()
            }
            .padding(.horizontal, Theme.Spacing.md)
            DayStripView(model: model)
        }
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.sm)
    }

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker("Game date", selection: dateBinding, displayedComponents: .date)
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

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                    ForEach(0..<6, id: \.self) { _ in LoadingShimmer(height: 132) }
                }
                .padding(Theme.Spacing.md)
            }
        case .loaded(let games):
            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                    ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                        GameTileView(game: game) { expand(game.id) }
                            .staggeredEntrance(index: index)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .refreshable { await model.load() }
        case .empty:
            EmptyStateView(
                systemImage: "calendar.badge.exclamationmark",
                title: "No games \(model.dateLabel.lowercased())",
                message: "Tap a day above (the dots mark game days) to find scheduled games."
            )
            Spacer()
        case .error(let message):
            ErrorStateView(message: message) { Task { await model.load() } }
            Spacer()
        }
    }
}
