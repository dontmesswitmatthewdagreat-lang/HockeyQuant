import SwiftUI

/// The Schedule screen: pick any date and browse that day's predictions as
/// collapsible cards. Live data from the FastAPI backend.
struct TodayView: View {
    @State private var model = TodayViewModel()
    @State private var showingDatePicker = false

    private var dateBinding: Binding<Date> {
        Binding(get: { model.selectedDate }, set: { model.selectedDate = $0 })
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
        }
        .task {
            model.warmUp()
            await model.load()
        }
    }

    // MARK: - Header (compact, custom — no large-title gap)

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Text("Schedule")
                    .font(Theme.Font.title())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                AvatarButton()
            }
            dateRow
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.sm)
    }

    private var dateRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            scrubButton(systemName: "chevron.left") { model.step(days: -1) }
                .accessibilityLabel("Previous day")

            // Prominent, obviously-tappable date control → opens the calendar.
            PressableButton(action: { showingDatePicker = true }) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.accent)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.dateLabel)
                            .font(Theme.Font.headline())
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(APIClient.apiDateString(model.selectedDate))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .stroke(Theme.Palette.accent.opacity(0.4), lineWidth: 1)
                )
            }
            .accessibilityLabel("Choose date — opens a calendar")

            scrubButton(systemName: "chevron.right") { model.step(days: 1) }
                .accessibilityLabel("Next day")
        }
    }

    private func scrubButton(systemName: String, action: @escaping () -> Void) -> some View {
        PressableButton(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 40, height: 40)
                .background(Theme.Palette.surface)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.Palette.border, lineWidth: 1))
        }
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
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(0..<6, id: \.self) { _ in LoadingShimmer(height: 78) }
                }
                .padding(Theme.Spacing.md)
            }
        case .loaded(let games):
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                        GameCardView(game: game, dateString: APIClient.apiDateString(model.selectedDate))
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
                message: "Tap the date above to jump to a day with scheduled games."
            )
            Spacer()
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await model.load() }
            }
            Spacer()
        }
    }
}
