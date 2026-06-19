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
                // Play tab: background blobs use the team's PRIMARY only; the
                // SECONDARY drifts inside the cards (via `cardTeamBlobs` below).
                Theme.backgroundView(stops: Theme.Palette.backgroundStopsPrimary).ignoresSafeArea()
                if auth.isInitializing {
                    ProgressView()
                } else if !auth.isSignedIn {
                    signInPrompt
                } else {
                    signedInContent
                }
            }
            .environment(\.cardTeamBlobs, true)
            .navigationBarTitleDisplayMode(.inline)   // custom adaptive "Play" lives in the content
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
            VStack(spacing: Theme.Spacing.md) {
                AdaptiveBlobTitle(text: "Play")
                // Ranked core: the Global League — Cups, arena, Cap Space (tap to manage your team).
                NavigationLink { globalDestination } label: {
                    PlayHeaderCard(stats: game.stats ?? .empty)
                }
                .buttonStyle(.plain)
                NavigationLink { SeasonView() } label: {
                    SeasonBanner(stats: game.seasonStats)
                }
                .buttonStyle(.plain)
                // The two other modes.
                NavigationLink { FantasyHomeView() } label: {
                    modeBanner("Private Leagues", icon: "person.3.fill", subtitle: "Fantasy hockey with your friends")
                }
                .buttonStyle(.plain)
                NavigationLink { FranchiseView() } label: {
                    modeBanner("My Franchise", icon: "rectangle.stack.fill", subtitle: "Collect player cards & build your dream team")
                }
                .buttonStyle(.plain)
                achievementsStrip
                dateBar
                gamesSection
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

    @ViewBuilder
    private var globalDestination: some View {
        if let fantasyStore {
            GlobalLeagueView(store: fantasyStore)
        } else {
            ProgressView().tint(Theme.Palette.accent)
        }
    }

    private func modeBanner(_ title: String, icon: String, subtitle: String) -> some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(Theme.Palette.accent.opacity(0.14)).frame(width: 46, height: 46)
                    Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.Palette.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.Font.headlineHeavy()).foregroundStyle(Theme.Palette.textPrimary)
                    Text(subtitle).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Palette.textPrimary)
            }
        }
    }

    private var achievementsStrip: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    sectionHeader("Achievements")
                    Spacer()
                    NavigationLink { AchievementsView() } label: {
                        HStack(spacing: 4) {
                            Text("\(game.earnedIds.count)/\(game.achievements.count)")
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        }
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.accent)
                    }
                }
                if game.achievements.isEmpty {
                    Text("Make picks to start earning badges.")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textPrimary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(game.achievements) { achievement in
                                badge(achievement, earned: game.earnedIds.contains(achievement.id))
                            }
                        }
                    }
                }
            }
        }
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
        HStack(spacing: Theme.Spacing.md) {
            stepButton("chevron.left") { model.step(days: -1) }.accessibilityLabel("Previous day")
            PressableButton(action: { showingDatePicker = true }) {
                Text(model.dateLabel)
                    .font(Theme.Font.headlineHeavy())
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Choose date")
            stepButton("chevron.right") { model.step(days: 1) }.accessibilityLabel("Next day")
        }
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

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.Palette.textPrimary)
    }
}
