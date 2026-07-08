import SwiftUI

/// The gamification home, Rocket Money-style: a personal greeting, the Cap Space
/// "balance" hero, tonight's slate as a progress ring + compact game rows (tap a
/// row → pick sheet), and the game modes as a grouped list. Requires sign-in.
struct PlayView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(GamificationStore.self) private var game

    @State private var model = PlayViewModel()
    @State private var fantasyStore: FantasyStore?
    @State private var showingDatePicker = false
    @State private var pickSheetGame: GamePrediction?
    @State private var segment = 0   // 0 = Slate, 1 = My Stats

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
            // The curved hero band carries the top controls (trophy, avatar).
            .toolbar(.hidden, for: .navigationBar)
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
            Text("Play")
                .font(Theme.Font.display())
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
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
                heroBand.staggeredEntrance(index: 0)   // full-bleed curved header
                VStack(spacing: Theme.Spacing.lg) {
                    actionTiles.staggeredEntrance(index: 1)
                    BigSegment(selection: $segment, options: ["Slate", "My Stats"])
                        .staggeredEntrance(index: 2)
                    ZStack {
                        if segment == 0 {
                            slateCard.transition(.opacity)
                        } else {
                            statsSegment.transition(.opacity)
                        }
                    }
                    .staggeredEntrance(index: 3)
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
            .padding(.bottom, Theme.Spacing.md)
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
        .sheet(item: $pickSheetGame) { prediction in pickSheet(prediction) }
    }

    // MARK: - Hero band (curved header)

    private var heroBand: some View {
        let xp = game.seasonStats.xp
        let tier = GMTier.current(forXp: xp)
        let cups = (game.stats ?? .empty).stanleyCups
        return VStack(spacing: Theme.Spacing.sm) {
            HeroBand(tint: Theme.Palette.accent, centerpieceOverhang: 36) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.xs) {
                        BandPill(text: tier.name, systemImage: tier.icon)
                        BandPill(text: "\(cups) Cups", systemImage: "trophy.fill")
                        Spacer()
                        NavigationLink { LeaderboardView() } label: { bandIcon("trophy.fill") }
                            .buttonStyle(.plain)
                        AvatarButton()
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(timeGreeting)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        HStack(alignment: .firstTextBaseline) {
                            Text(auth.username ?? "GM")
                                .font(.system(size: 26, weight: .heavy))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Spacer()
                            BandPill(text: Season.current.id)
                        }
                    }
                    .padding(.bottom, Theme.Spacing.md)   // room for the overlapping badge
                }
            } centerpiece: {
                ZStack {
                    Circle().fill(Theme.Palette.surfaceRaised)
                    Circle().stroke(.white, lineWidth: 3)
                    Image(systemName: tier.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(tier.color)
                }
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.30), radius: 6, y: 2)
            }
            xpStrip
        }
    }

    private func bandIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(.white.opacity(0.18))
            .clipShape(Circle())
    }

    private var xpStrip: some View {
        let xp = game.seasonStats.xp
        let tier = GMTier.current(forXp: xp)
        let next = GMTier.next(forXp: xp)
        return VStack(spacing: 5) {
            RangeGauge(fraction: next == nil ? 1 : GMTier.progress(forXp: xp),
                       tint: tier.color, filled: true)
            Text(next.map { "\(xp) / \($0.threshold) XP → \($0.name)" } ?? "Max tier · \(xp) XP")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var timeGreeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: - Quick-action tiles

    private var actionTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.sm), GridItem(.flexible())],
                  spacing: Theme.Spacing.sm) {
            NavigationLink { globalDestination } label: {
                ActionTile(icon: "trophy.fill", title: "Global League", tint: Theme.Palette.accent)
            }
            .buttonStyle(.plain)
            NavigationLink { FantasyHomeView() } label: {
                ActionTile(icon: "person.3.fill", title: "Private Leagues", tint: Theme.Palette.accentAlt)
            }
            .buttonStyle(.plain)
            NavigationLink { FranchiseView() } label: {
                ActionTile(icon: "rectangle.stack.fill", title: "My Franchise", tint: Color(hex: 0xAF52DE))
            }
            .buttonStyle(.plain)
            NavigationLink { OffseasonView() } label: {
                ActionTile(icon: "arrow.triangle.swap", title: "Offseason GM", tint: Color(hex: 0xFF9500))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Color(hex: 0xFF9500))
                            .clipShape(Circle())
                            .padding(8)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - My Stats segment (balance card + achievements)

    private var statsSegment: some View {
        let stats = game.stats ?? .empty
        return VStack(spacing: Theme.Spacing.md) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("CAP SPACE")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(Theme.Palette.textTertiary)
                    Text(stats.capSpace.asCapMoney)
                        .font(.system(size: 46, weight: .heavy))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .contentTransition(.numericText())
                    HStack(spacing: Theme.Spacing.sm) {
                        NavigationLink { SeasonView() } label: {
                            CapsuleActionLabel(title: "Season")
                        }
                        .buttonStyle(.plain)
                        NavigationLink { LeaderboardView() } label: {
                            CapsuleActionLabel(title: "Leaderboard", prominent: true)
                        }
                        .buttonStyle(.plain)
                    }
                    Divider().overlay(Theme.Palette.border)
                    HStack(spacing: Theme.Spacing.sm) {
                        metric("Record", "\(stats.picksCorrect)–\(max(0, stats.picksMade - stats.picksCorrect))")
                        metricDivider
                        metric("Accuracy", stats.picksMade > 0 ? "\(Int(stats.accuracy.rounded()))%" : "—")
                        metricDivider
                        metric("Beat AI", "\(stats.beatsModel)")
                        metricDivider
                        metric("Cups", "\(stats.stanleyCups)")
                    }
                }
            }
            Card(padding: 0) {
                NavigationLink { AchievementsView() } label: {
                    ModeRow(icon: "rosette", tint: Theme.Palette.moderate, title: "Achievements",
                            subtitle: "Badges for streaks & milestones",
                            value: "\(game.earnedIds.count)/\(game.achievements.count)")
                }
                .buttonStyle(.plain)
                .padding(.vertical, Theme.Spacing.xxs)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Divider().frame(height: 26).overlay(Theme.Palette.border)
    }

    // MARK: - Tonight's slate (ring + game rows)

    private var slateCard: some View {
        Card {
            VStack(spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    SlateRing(picked: slateCounts.picked, total: slateCounts.total)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tonight's picks")
                            .font(Theme.Font.headlineHeavy())
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(slateSubtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                dateControls
                slateRows
            }
        }
    }

    private var slateCounts: (picked: Int, total: Int) {
        guard case .loaded(let games) = model.gamesState else { return (0, 0) }
        let picked = games.filter { g in
            game.pick(forGameId: GamificationStore.gameId(date: model.dateString, away: g.away.team, home: g.home.team)) != nil
        }.count
        return (picked, games.count)
    }

    private var slateSubtitle: String {
        if case .loading = model.gamesState { return "Loading the slate…" }
        let (picked, total) = slateCounts
        if total == 0 { return "No games \(model.dateLabel.lowercased())" }
        if picked == total { return "All called — good luck" }
        return "\(total - picked) left to call"
    }

    private var dateControls: some View {
        HStack(spacing: 0) {
            stepButton("chevron.left") { model.step(days: -1) }.accessibilityLabel("Previous day")
            PressableButton(action: { showingDatePicker = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 11, weight: .bold))
                    Text(model.dateLabel).font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Choose date")
            stepButton("chevron.right") { model.step(days: 1) }.accessibilityLabel("Next day")
        }
        .padding(.vertical, 2)
        .background(Theme.Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }

    private func stepButton(_ name: String, action: @escaping () -> Void) -> some View {
        PressableButton(action: action) {
            Image(systemName: name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 40, height: 32)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private var slateRows: some View {
        switch model.gamesState {
        case .loading:
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(0..<3, id: \.self) { _ in LoadingShimmer(height: 44) }
            }
        case .empty:
            Text("Find a date with games to make your picks.")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .error(let message):
            ErrorStateView(message: message) { Task { await model.loadGames() } }
        case .loaded(let games):
            VStack(spacing: 0) {
                ForEach(Array(games.enumerated()), id: \.element.id) { index, prediction in
                    let id = GamificationStore.gameId(date: model.dateString, away: prediction.away.team, home: prediction.home.team)
                    let pick = game.pick(forGameId: id)
                    Button {
                        // Open the pick sheet until the game is graded (you can
                        // still change an ungraded call).
                        if pick?.correct == nil {
                            Haptics.tap()
                            pickSheetGame = prediction
                        }
                    } label: {
                        SlateGameRow(game: prediction, pick: pick)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, Theme.Spacing.xs)
                    if index < games.count - 1 {
                        Divider().overlay(Theme.Palette.border).padding(.leading, 64)
                    }
                }
            }
        }
    }

    // MARK: - Pick sheet

    private func pickSheet(_ prediction: GamePrediction) -> some View {
        let id = GamificationStore.gameId(date: model.dateString, away: prediction.away.team, home: prediction.home.team)
        return VStack(spacing: Theme.Spacing.md) {
            Text("Make the call")
                .font(Theme.Font.title())
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.top, Theme.Spacing.md)
            Text("Who wins \(prediction.away.info.abbrev) @ \(prediction.home.info.abbrev)?")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.textSecondary)
            CallGameCard(
                game: prediction,
                pick: game.pick(forGameId: id),
                isSubmitting: game.submitting.contains(id),
                onPick: { team in
                    Task {
                        await game.submitPick(game: prediction, dateString: model.dateString, pick: team)
                        pickSheetGame = nil
                    }
                }
            )
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.background.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var globalDestination: some View {
        if let fantasyStore {
            GlobalLeagueView(store: fantasyStore)
        } else {
            ProgressView().tint(Theme.Palette.accent)
        }
    }

    // MARK: - Date picker sheet

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
}
