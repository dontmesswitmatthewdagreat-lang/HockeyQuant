import SwiftUI

/// The gamification home: your level/XP/streak, "call the game" daily picks,
/// achievements, and a link to the leaderboard. Requires sign-in.
struct PlayView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(GamificationStore.self) private var game

    @State private var model = PlayViewModel()
    @State private var fantasyStore: FantasyStore?
    @State private var showingDatePicker = false

    // Celebration state
    @State private var confettiTrigger = 0
    @State private var xpToast: Int?
    @State private var achievementToShow: Achievement?
    @State private var achievementQueue: [Achievement] = []

    private var dateBinding: Binding<Date> {
        Binding(get: { model.selectedDate }, set: { model.selectedDate = $0 })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Play is the one dark "dashboard" tab; the rest of the app stays
                // light with team blobs. Flat charcoal background + no in-card blobs;
                // `.environment(\.colorScheme, .dark)` (below) flips the tokens dark.
                Theme.Palette.background.ignoresSafeArea()
                if auth.isInitializing {
                    ProgressView()
                } else if !auth.isSignedIn {
                    signInPrompt
                } else {
                    signedInContent
                }
            }
            .environment(\.cardTeamBlobs, false)
            .navigationBarTitleDisplayMode(.inline)   // custom adaptive "Play" lives in the content
            .toolbarColorScheme(.dark, for: .navigationBar)   // dark nav chrome to match the dark tab
            .toolbar {
                if auth.isSignedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { LeaderboardView() } label: {
                            Label("Leaderboard", systemImage: "trophy.fill")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { AvatarButton() }
            }
            .overlay {
                if let achievement = achievementToShow {
                    AchievementUnlockView(achievement: achievement) { dismissAchievement() }
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if let xpToast {
                    CelebrationToast(icon: "dollarsign.circle.fill", title: "+\(xpToast) Cap Space!", subtitle: "Your picks came through.")
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay { ConfettiView(trigger: confettiTrigger).ignoresSafeArea() }
        }
        .environment(\.colorScheme, .dark)   // Play stays dark; every other tab is light
        .onChange(of: game.pendingXpGain) { _, _ in processCelebrations() }
        .onChange(of: game.pendingAchievements.count) { _, _ in processCelebrations() }
        .task(id: auth.isSignedIn) {
            guard auth.isSignedIn else { return }
            if fantasyStore == nil { fantasyStore = FantasyStore(auth: auth) }
            await game.loadStats()
            await game.loadSeason()
            await game.loadAchievements()
            await game.loadPicks(date: model.dateString)
            await model.loadGames()
        }
        .task(id: model.dateString) {
            guard auth.isSignedIn else { return }
            await game.loadPicks(date: model.dateString)
        }
    }

    // MARK: - Celebrations

    private func processCelebrations() {
        if game.pendingXpGain > 0 {
            let gain = game.pendingXpGain
            confettiTrigger += 1
            Haptics.success()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { xpToast = gain }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.8))
                if xpToast == gain { withAnimation { xpToast = nil } }
            }
        }
        if !game.pendingAchievements.isEmpty {
            achievementQueue.append(contentsOf: game.pendingAchievements)
            if achievementToShow == nil {
                confettiTrigger += 1
                withAnimation { achievementToShow = achievementQueue.first }
            }
        }
        if game.pendingXpGain > 0 || !game.pendingAchievements.isEmpty {
            game.clearCelebrations()
        }
    }

    private func dismissAchievement() {
        if !achievementQueue.isEmpty { achievementQueue.removeFirst() }
        withAnimation { achievementToShow = achievementQueue.first }
        if achievementToShow != nil { confettiTrigger += 1 }
    }

    // MARK: - Sign-in gate

    private var signInPrompt: some View {
        VStack(alignment: .leading, spacing: 0) {
            AdaptiveBlobTitle(text: "Play").padding(.horizontal, Theme.Spacing.md)
            Spacer()
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Palette.accent)
                Text("Call the game")
                    .font(Theme.Font.title())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Sign in on the Profile tab to make daily picks, build streaks, earn XP, and climb the leaderboard.")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.xl)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Signed in

    private var signedInContent: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                titleRow.staggeredEntrance(index: 0)
                // Identity HUD — who you are as a GM (tier / XP / streak). Tap → SeasonView.
                NavigationLink { SeasonView() } label: {
                    GMIdentityCard(stats: game.stats ?? .empty, season: game.seasonStats)
                }
                .buttonStyle(.plain)
                .staggeredEntrance(index: 1)
                modesSection.staggeredEntrance(index: 2)
                trophyCase.staggeredEntrance(index: 3)
                slateSection.staggeredEntrance(index: 4)
            }
            .padding(Theme.Spacing.md)
        }
        .refreshable {
            // Stats/achievements first so reward celebrations fire even if the
            // (slower, cancel-prone) games request is interrupted.
            await game.loadStats()
            await game.loadSeason()
            await game.loadAchievements()
            await game.loadPicks(date: model.dateString)
            await model.loadGames()
        }
        .sheet(isPresented: $showingDatePicker) { datePickerSheet }
    }

    private var titleRow: some View {
        AdaptiveBlobTitle(text: "Play")
            .overlay(alignment: .trailing) { PillChip(text: Season.current.id) }
    }

    // MARK: - Game modes (ranked hero + 2 mode tiles)

    private var modesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel("Game Modes")
            NavigationLink { globalDestination } label: {
                RankedModeTile(stats: game.stats ?? .empty)
            }
            .buttonStyle(.plain)
            HStack(spacing: Theme.Spacing.sm) {
                NavigationLink { FantasyHomeView() } label: {
                    ModeTile(title: "Private Leagues", icon: "person.3.fill",
                             subtitle: "Fantasy hockey with your friends", tint: Theme.Palette.accent)
                }
                .buttonStyle(.plain)
                NavigationLink { FranchiseView() } label: {
                    ModeTile(title: "My Franchise", icon: "rectangle.stack.fill",
                             subtitle: "Collect cards & build your dream team", tint: Theme.Palette.accentAlt)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var globalDestination: some View {
        if let fantasyStore {
            GlobalLeagueView(store: fantasyStore)
        } else {
            ProgressView().tint(Theme.Palette.accent)
        }
    }

    // MARK: - Trophy case (achievements)

    private var trophyCase: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel("Trophy Case") {
                NavigationLink { AchievementsView() } label: {
                    HStack(spacing: 3) {
                        Text("\(game.earnedIds.count)/\(game.achievements.count)")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.accent)
                }
            }
            Card {
                if game.achievements.isEmpty {
                    Text("Make picks to start earning badges.")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.md) {
                            ForEach(game.achievements) { achievement in
                                badge(achievement, earned: game.earnedIds.contains(achievement.id))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tonight's slate (date + call-the-game)

    private var slateSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel("Tonight's Slate") {
                if let progress = slateProgress {
                    PillChip(text: progress, systemImage: "hockey.puck.fill")
                }
            }
            dateBar
            gamesSection
        }
    }

    /// "{picked}/{games} called" for the loaded slate, or nil when no games.
    private var slateProgress: String? {
        guard case .loaded(let games) = model.gamesState, !games.isEmpty else { return nil }
        let picked = games.filter { g in
            game.pick(forGameId: GamificationStore.gameId(date: model.dateString, away: g.away.team, home: g.home.team)) != nil
        }.count
        return "\(picked)/\(games.count) called"
    }

    private func badge(_ achievement: Achievement, earned: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(earned ? Theme.Palette.accent.opacity(0.16) : Theme.Palette.background)
                    .frame(width: 48, height: 48)
                Image(systemName: achievement.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(earned ? Theme.Palette.accent : Theme.Palette.textPrimary)
            }
            Text(achievement.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(earned ? Theme.Palette.textPrimary : Theme.Palette.textPrimary)
                .lineLimit(1)
                .frame(width: 60)
        }
        .opacity(earned ? 1 : 0.55)
        .accessibilityLabel("\(achievement.name): \(achievement.description) — \(earned ? "earned" : "locked")")
    }

    // MARK: - Date bar

    private var dateBar: some View {
        HStack(spacing: 0) {
            stepButton("chevron.left") { model.step(days: -1) }.accessibilityLabel("Previous day")
            PressableButton(action: { showingDatePicker = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 12, weight: .bold))
                    Text(model.dateLabel).font(Theme.Font.headlineHeavy())
                }
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Choose date")
            stepButton("chevron.right") { model.step(days: 1) }.accessibilityLabel("Next day")
        }
        .padding(.horizontal, Theme.Spacing.xs).padding(.vertical, Theme.Spacing.xxs)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).stroke(Theme.Palette.border, lineWidth: 1))
    }

    private func stepButton(_ name: String, action: @escaping () -> Void) -> some View {
        PressableButton(action: action) {
            Image(systemName: name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
    }

    private var datePickerSheet: some View {
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

    // MARK: - Games

    @ViewBuilder
    private var gamesSection: some View {
        switch model.gamesState {
        case .loading:
            ForEach(0..<3, id: \.self) { _ in LoadingShimmer(height: 150) }
        case .empty:
            EmptyStateView(
                systemImage: "calendar.badge.exclamationmark",
                title: "No games \(model.dateLabel.lowercased())",
                message: "Find a date with games to make your picks."
            )
        case .error(let message):
            ErrorStateView(message: message) { Task { await model.loadGames() } }
        case .loaded(let games):
            ForEach(Array(games.enumerated()), id: \.element.id) { index, prediction in
                let id = GamificationStore.gameId(date: model.dateString, away: prediction.away.team, home: prediction.home.team)
                CallGameCard(
                    game: prediction,
                    pick: game.pick(forGameId: id),
                    isSubmitting: game.submitting.contains(id),
                    onPick: { team in
                        Task { await game.submitPick(game: prediction, dateString: model.dateString, pick: team) }
                    }
                )
                .staggeredEntrance(index: index)
            }
        }
    }
}
