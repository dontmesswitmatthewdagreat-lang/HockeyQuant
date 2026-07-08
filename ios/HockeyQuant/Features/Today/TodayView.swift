import SwiftUI

/// The Schedule screen, Venmo-band edition: a curved hero header (date, slate
/// story, day strip, slate-ring centerpiece), a Game of the Night card, then
/// slim rows sectioned LIVE / UPCOMING / FINAL — finals graded against the
/// model. Tap anything → hero-expand into the full breakdown.
struct TodayView: View {
    @State private var model = TodayViewModel()
    @State private var showingDatePicker = false
    @State private var expandedID: String?

    private var dateBinding: Binding<Date> {
        Binding(get: { model.selectedDate }, set: { model.selectedDate = $0 })
    }

    /// The currently-expanded game, looked up live from the loaded list so polling
    /// keeps the open breakdown (score / grid / shot map) current.
    private var expandedGame: ScheduleGame? {
        guard let id = expandedID, case .loaded(let games) = model.state else { return nil }
        return games.first { $0.id == id }
    }

    private var loadedGames: [ScheduleGame] {
        if case .loaded(let games) = model.state { return games }
        return []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundView().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        heroBand
                        content
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.top, Theme.Spacing.xs)
                            .padding(.bottom, 72)
                    }
                }
                .refreshable { await model.load() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingDatePicker) { datePickerSheet }
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

    // MARK: - Hero band

    private var liveGames: [ScheduleGame] { loadedGames.filter(\.isLive) }
    private var upcomingGames: [ScheduleGame] { loadedGames.filter(\.isUpcoming) }
    private var finalGames: [ScheduleGame] { loadedGames.filter(\.isFinal) }
    private var strongCalls: Int {
        loadedGames.filter { $0.prediction.confidence.uppercased() == "STRONG" }.count
    }

    private var heroBand: some View {
        HeroBand(tint: Theme.Palette.accent, centerpieceOverhang: 36) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.xs) {
                    BandPill(text: model.monthLabel, systemImage: "calendar")
                    Spacer()
                    BandIconButton(systemImage: "calendar") { showingDatePicker = true }
                        .accessibilityLabel("Jump to a date")
                    AvatarButton()
                }
                Text(model.dateLabel)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(slateStory)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                DayStripView(model: model, onBand: true)
                    .padding(.horizontal, -Theme.Spacing.md)   // strip manages its own insets
                    .padding(.bottom, Theme.Spacing.sm)        // room for the ring
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } centerpiece: {
            SlateRingBadge(games: loadedGames.count,
                           strongCalls: strongCalls,
                           liveCount: liveGames.count)
        }
    }

    private var slateStory: String {
        let games = loadedGames
        guard !games.isEmpty else {
            if case .loading = model.state { return "Reading the slate…" }
            return "No games on this date"
        }
        if !liveGames.isEmpty {
            return "\(games.count) games · \(liveGames.count) live right now"
        }
        if upcomingGames.isEmpty {
            let hits = finalGames.filter(modelHit).count
            return "\(games.count) finals · model went \(hits)/\(finalGames.count)"
        }
        var parts = ["\(games.count) game\(games.count == 1 ? "" : "s")"]
        if strongCalls > 0 { parts.append("\(strongCalls) strong call\(strongCalls == 1 ? "" : "s")") }
        if let first = upcomingGames.first { parts.append("first puck \(startTime(first.prediction))") }
        return parts.joined(separator: " · ")
    }

    private func modelHit(_ game: ScheduleGame) -> Bool {
        guard let s = game.score else { return false }
        let winner = s.homeScore > s.awayScore ? game.prediction.home.team : game.prediction.away.team
        return winner.uppercased() == game.prediction.pick.uppercased()
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            VStack(spacing: Theme.Spacing.sm) {
                LoadingShimmer(height: 190)
                ForEach(0..<4, id: \.self) { _ in LoadingShimmer(height: 76) }
            }
        case .loaded:
            gameSections
        case .empty:
            EmptyStateView(
                systemImage: "calendar.badge.exclamationmark",
                title: "No games \(model.dateLabel.lowercased())",
                message: "Tap a day above (the dots mark game days) to find scheduled games."
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        case .error(let message):
            ErrorStateView(message: message) { Task { await model.load() } }
                .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    /// The game the page leads with: the closest live game, else the model's
    /// strongest upcoming call, else the biggest final.
    private var heroGame: ScheduleGame? {
        if !liveGames.isEmpty {
            return liveGames.min {
                abs(($0.score?.homeScore ?? 0) - ($0.score?.awayScore ?? 0))
                    < abs(($1.score?.homeScore ?? 0) - ($1.score?.awayScore ?? 0))
            }
        }
        if !upcomingGames.isEmpty { return upcomingGames.max { $0.prediction.diff < $1.prediction.diff } }
        return finalGames.max { $0.prediction.diff < $1.prediction.diff }
    }

    private var gameSections: some View {
        let hero = heroGame
        let live = liveGames.filter { $0.id != hero?.id }
        let upcoming = upcomingGames.filter { $0.id != hero?.id }
        let finals = finalGames.filter { $0.id != hero?.id }
        var index = 0
        func next() -> Int { defer { index += 1 }; return index }

        return VStack(spacing: Theme.Spacing.md) {
            if let hero {
                HeroGameCard(game: hero) { expand(hero.id) }
                    .staggeredEntrance(index: next())
            }
            if !live.isEmpty {
                section("Live", games: live, startIndex: next())
            }
            if !upcoming.isEmpty {
                section("Upcoming", games: upcoming, startIndex: next())
            }
            if !finals.isEmpty {
                finalsSection(finals, startIndex: next())
            }
        }
    }

    private func section(_ title: String, games: [ScheduleGame], startIndex: Int) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            SectionLabel(title)
            ForEach(Array(games.enumerated()), id: \.element.id) { i, game in
                ScheduleRow(game: game) { expand(game.id) }
                    .staggeredEntrance(index: min(startIndex + i, 9))
            }
        }
    }

    private func finalsSection(_ finals: [ScheduleGame], startIndex: Int) -> some View {
        let hits = finalGames.filter(modelHit).count
        return VStack(spacing: Theme.Spacing.xs) {
            SectionLabel("Final") {
                Text("Model \(hits)/\(finalGames.count)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(hits * 2 >= finalGames.count ? Theme.Palette.positive : Theme.Palette.textTertiary)
            }
            ForEach(Array(finals.enumerated()), id: \.element.id) { i, game in
                ScheduleRow(game: game) { expand(game.id) }
                    .staggeredEntrance(index: min(startIndex + i, 9))
            }
        }
    }

    // MARK: - Date picker

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
}
