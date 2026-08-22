import SwiftUI

/// The NHL entry draft, played interactively: pick a team, then draft against
/// 31 AI GMs. (Distinct from Fantasy's `DraftRoomView`, which drafts NHL players
/// into a private-league roster.)
///
/// Once a class has actually been drafted the room becomes a re-draft, which is
/// the better version of this feature — there's a real first round to be judged
/// against instead of a projection nobody can be wrong about yet. Where the
/// league really took a player is therefore hidden while you draft and only
/// revealed in the verdict; showing it on the board would hand you the answer.
struct EntryDraftRoomView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var room: DraftRoom?
    @State private var engine: DraftRoomEngine?
    @State private var team: String?
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var aiRunner: Task<Void, Never>?
    /// Set once the user re-runs the lottery, which also means the order has
    /// diverged from the real draft.
    @State private var lottery: DraftLottery.Outcome?

    private let api = APIClient()

    var body: some View {
        ZStack {
            Theme.backgroundView()
            content
        }
        .navigationTitle(engine == nil ? "Draft Room" : "\(room?.yearLabel ?? "") First Round")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear { aiRunner?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    LoadingShimmer(height: 120)
                    LoadingShimmer(height: 260)
                }
                .padding(Theme.Spacing.md)
            }
        } else if let errorMessage {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if let engine {
            if engine.isComplete {
                DraftResultsView(engine: engine) { restart() }
            } else {
                DraftBoardView(engine: engine,
                               onPick: { entry in pick(entry, in: engine) },
                               onTraded: { runAI(engine) })
            }
        } else if let room {
            setup(room)
        }
    }

    // MARK: - Setup

    private func setup(_ room: DraftRoom) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(room.isRedraftMode ? "RE-DRAFT" : "DRAFT ROOM")
                            .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.8)
                            .foregroundStyle(Theme.Palette.accent)
                        Text(room.isRedraftMode
                             ? "Re-draft the \(room.yearLabel) first round"
                             : "Run the \(room.yearLabel) first round")
                            .font(Theme.Font.title())
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(room.isRedraftMode
                             ? "You're on the clock for one team. The other 31 GMs draft the way our mock does — and at the end you'll see how your picks stack up against what the league actually did."
                             : "You're on the clock for one team. The other 31 GMs draft the way our mock does, off the same Central Scouting board.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Palette.textSecondary)
                        // Once the lottery is re-run the stated basis is no
                        // longer what produced this order.
                        if let basis = lottery == nil ? room.orderBasis : "Lottery re-run — hypothetical order" {
                            Text(basis)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Palette.textTertiary)
                                .padding(.top, 2)
                        }
                    }
                }

                lotteryCard(room)

                SectionCard("Pick your team") {
                    let cols = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 6)
                    LazyVGrid(columns: cols, spacing: Theme.Spacing.sm) {
                        ForEach(room.order.uniqued(), id: \.self) { abbrev in
                            Button { team = abbrev } label: {
                                CrestView(abbrev: abbrev, size: 40)
                                    .opacity(team == nil || team == abbrev ? 1 : 0.35)
                                    .overlay {
                                        if team == abbrev {
                                            Circle().strokeBorder(Theme.Palette.accent, lineWidth: 2)
                                                .padding(-3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let team {
                    startCard(room, team: team)
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    // MARK: - Lottery re-roll

    @ViewBuilder
    private func lotteryCard(_ room: DraftRoom) -> some View {
        if let odds = room.lotteryOdds, odds.count >= 2 {
            SectionCard("Draft lottery", accessory: AnyView(
                Button {
                    reroll(odds: odds)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "dice.fill").font(.system(size: 11, weight: .bold))
                        Text(lottery == nil ? "Re-run it" : "Again")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Palette.accent)
                }
            )) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if let lottery {
                        HStack(spacing: Theme.Spacing.sm) {
                            lotteryWinner("1ST", lottery.firstWinner, room)
                            lotteryWinner("2ND", lottery.secondWinner, room)
                            Spacer(minLength: 0)
                        }
                        let movers = lottery.movement
                            .filter { $0.value != 0 }
                            .sorted { abs($0.value) > abs($1.value) }
                            .prefix(4)
                        if !movers.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(movers, id: \.key) { team, places in
                                    HStack(spacing: 2) {
                                        CrestView(abbrev: team, size: 16)
                                        Image(systemName: places > 0 ? "arrow.up" : "arrow.down")
                                            .font(.system(size: 8, weight: .heavy))
                                        Text("\(abs(places))")
                                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    }
                                    .foregroundStyle(places > 0 ? Theme.Palette.positive
                                                                : Theme.Palette.negative)
                                }
                            }
                        }
                        Text("Re-drawn from the final standings, so this order is a what-if — it drops the real lottery result and any traded picks.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    } else {
                        Text("Roll the balls again and see who lands the first pick. A team can climb at most \(DraftLottery.maxClimb) places, same as the real thing.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
        }
    }

    private func lotteryWinner(_ label: String, _ team: String, _ room: DraftRoom) -> some View {
        HStack(spacing: 6) {
            CrestView(abbrev: team, size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text(team)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
        }
    }

    private func reroll(odds: [LotteryOdds]) {
        // Always draw from the pre-lottery standings order. Re-rolling on top of
        // an order that already had a lottery applied would move the wrong teams
        // and credit the win to whoever happened to hold the top slot.
        guard var current = room,
              let base = current.standingsOrder, base.count >= odds.count,
              let outcome = DraftLottery.reroll(odds: odds, order: base) else { return }
        current.applyLottery(outcome)
        Haptics.success()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            room = current
            lottery = outcome
        }
    }

    private func startCard(_ room: DraftRoom, team: String) -> some View {
        let slots = room.order.enumerated().compactMap { $0.element == team ? $0.offset + 1 : nil }
        return Card {
            VStack(spacing: Theme.Spacing.sm) {
                Text(room.teamName(team))
                    .font(Theme.Font.headlineHeavy())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(slots.isEmpty
                     ? "No first-round pick — pick another team."
                     : "You pick at \(slots.map { "#\($0)" }.joined(separator: ", "))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                let need = room.need(for: team)
                if !need.primary.isEmpty {
                    HStack(spacing: 6) {
                        StatusPill(text: "Needs \(Self.groupLabel(need.primary))",
                                   color: Theme.Palette.accent)
                        if !need.secondary.isEmpty {
                            StatusPill(text: "then \(Self.groupLabel(need.secondary))",
                                       color: Theme.Palette.textTertiary)
                        }
                    }
                }
                PressableButton(action: { start(room, team: team) }) {
                    CapsuleActionLabel(title: "Start the draft", systemImage: "play.fill",
                                       prominent: true)
                }
                .disabled(slots.isEmpty)
                .opacity(slots.isEmpty ? 0.5 : 1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    static func groupLabel(_ group: String) -> String {
        switch group {
        case "F": "forwards"
        case "D": "defense"
        case "G": "goaltending"
        default: group
        }
    }

    // MARK: - Flow

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let fetched = try await api.draftRoom()
            room = fetched
            // Default to the favorite team when it actually holds a pick.
            if team == nil, let favorite = auth.favoriteTeam,
               fetched.order.contains(favorite) {
                team = favorite
            }
            errorMessage = nil
        } catch {
            Log.error("draft room", error)
            errorMessage = error.localizedDescription
        }
    }

    private func start(_ room: DraftRoom, team: String) {
        let made = DraftRoomEngine(room: room, userTeam: team)
        engine = made
        runAI(made)
    }

    private func pick(_ entry: DraftBoardEntry, in engine: DraftRoomEngine) {
        guard engine.userSelect(entry) != nil else { return }
        Haptics.success()
        runAI(engine)
    }

    /// Let the AI GMs pick up to the user's next turn, one at a time so the
    /// board visibly empties instead of jumping.
    private func runAI(_ engine: DraftRoomEngine) {
        aiRunner?.cancel()
        aiRunner = Task { @MainActor in
            while !engine.isComplete && !engine.isUserTurn {
                if Task.isCancelled { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    _ = engine.aiSelect()
                }
                if reduceMotion { continue }
                try? await Task.sleep(for: .milliseconds(420))
            }
        }
    }

    private func restart() {
        aiRunner?.cancel()
        engine = nil
    }
}

private extension Array where Element: Hashable {
    /// The draft order repeats teams that own more than one pick; the team
    /// picker must not show a crest twice.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
