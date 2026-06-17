import SwiftUI

/// Live draft room. Shows whose turn it is, the lottery-assigned required
/// position, the eligible pool, and your roster. Polls while waiting on others.
struct DraftRoomView: View {
    let store: FantasyStore
    let leagueId: String

    @State private var draft: DraftResponse?
    @State private var working = false
    @State private var error: String?
    @State private var revealKey = 0   // drives the position-reveal animation
    @State private var lastAutoFired = -1   // guards expiry auto-pick to once per pick

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            if let draft {
                content(draft)
            } else {
                ProgressView().tint(Theme.Palette.accent)
            }
        }
        .environment(\.cardSurfaceOverride, Theme.Palette.fantasySurface)
        .navigationTitle("Draft")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Poll for other managers' picks; when a pick clock expires, any open
            // client advances it (live drafts), with the server cron as backstop.
            while !Task.isCancelled {
                await refresh()
                if let d = draft {
                    if d.state.status == "complete" { break }
                    if d.state.status == "in_progress", isExpired(d.state.pickDeadline), lastAutoFired != d.state.pickNumber {
                        lastAutoFired = d.state.pickNumber
                        await autoFireExpired(d.state.pickNumber)
                    }
                }
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    @ViewBuilder
    private func content(_ draft: DraftResponse) -> some View {
        if draft.state.status == "complete" {
            completeView(draft)
        } else {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    progress(draft.state)
                    onTheClock(draft)
                    if draft.state.isMyPick {
                        pickList(draft)
                    } else {
                        waitingPool(draft)
                    }
                    myRoster(draft)
                }
                .padding(Theme.Spacing.md)
            }
        }
    }

    // MARK: - Progress

    private func progress(_ s: DraftState) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("Round \(s.round)").font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Text("Pick \(s.pickNumber) / \(s.totalPicks)").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.border).frame(height: 6)
                    Capsule().fill(Theme.Palette.accent)
                        .frame(width: geo.size.width * CGFloat(s.totalPicks > 0 ? Double(s.pickNumber) / Double(s.totalPicks) : 0), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - On the clock

    private func onTheClock(_ draft: DraftResponse) -> some View {
        let s = draft.state
        return Card {
            VStack(spacing: Theme.Spacing.sm) {
                Text(s.isMyPick ? "YOU'RE ON THE CLOCK" : "ON THE CLOCK")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(s.isMyPick ? Theme.Palette.accent : Theme.Palette.textTertiary)
                Text(s.currentTeamName ?? "—")
                    .font(Theme.Font.title())
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let u = s.currentUsername { Text("@\(u)").font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary) }

                // Lottery-assigned required position — the "wheel" result.
                if let req = s.requiredSlotType {
                    VStack(spacing: 4) {
                        Text("MUST DRAFT").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: slotIcon(req))
                            Text(FantasySlot.label(req)).font(.system(size: 20, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Palette.accent)
                        .clipShape(Capsule())
                        .id(revealKey)
                        .transition(.scale.combined(with: .opacity))
                    }
                    .padding(.top, Theme.Spacing.xs)
                }
                pickClock(s.pickDeadline)
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: s.pickNumber) { _, _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { revealKey += 1 }
        }
    }

    @ViewBuilder
    private func pickClock(_ deadline: String?) -> some View {
        if let deadline, let date = parseISO(deadline) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let remaining = date.timeIntervalSince(ctx.date)
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                    Text(remaining > 0 ? "\(clockString(remaining)) to pick" : "Time expired — auto-picking…")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(remaining > 60 ? Theme.Palette.textSecondary : Theme.Palette.negative)
                .padding(.top, 2)
            }
        }
    }

    private func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s) ?? {
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s)
        }()
    }

    private func clockString(_ s: TimeInterval) -> String {
        let t = Int(s)
        if t >= 3600 { return "\(t / 3600)h \((t % 3600) / 60)m" }
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private func isExpired(_ deadline: String?) -> Bool {
        guard let deadline, let date = parseISO(deadline) else { return false }
        return date.timeIntervalSinceNow <= 0
    }

    private func autoFireExpired(_ expectedPick: Int) async {
        // Idempotent server-side via expected_pick; ignore races.
        draft = (try? await store.autopick(leagueId, expectedPick: expectedPick)) ?? draft
    }

    // MARK: - Pick list (my turn)

    private func pickList(_ draft: DraftResponse) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("AVAILABLE \(FantasySlot.label(draft.state.requiredSlotType ?? "").uppercased())")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                autopickButton()
            }
            ForEach(Array(draft.availablePlayers.enumerated()), id: \.element.id) { index, player in
                playerRow(player, canDraft: true)
                    .staggeredEntrance(index: min(index, 8))
            }
            if draft.availablePlayers.isEmpty {
                Text("No eligible players available.").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    private func waitingPool(_ draft: DraftResponse) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("WAITING…").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                autopickButton()  // commissioner can autopick for AFK managers
            }
            ForEach(draft.availablePlayers.prefix(6)) { player in
                playerRow(player, canDraft: false)
            }
        }
    }

    private func playerRow(_ player: FantasyPlayer, canDraft: Bool) -> some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                CrestView(abbrev: player.team, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.fullName).font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary).lineLimit(1)
                    Text("\(player.team)\(player.sweater.map { " · #\($0)" } ?? "") · \(player.rosterPos)")
                        .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer()
                if canDraft {
                    PressableButton(action: { pick(player.id) }) {
                        Text("Draft").font(Theme.Font.caption())
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 6)
                            .background(Theme.Palette.accent).clipShape(Capsule())
                    }
                    .disabled(working)
                }
            }
        }
    }

    private func autopickButton() -> some View {
        PressableButton(action: { autopick() }) {
            HStack(spacing: 4) { Image(systemName: "wand.and.stars"); Text("Auto") }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.accent)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.Palette.accent.opacity(0.12)).clipShape(Capsule())
        }
        .disabled(working)
    }

    // MARK: - My roster

    private func myRoster(_ draft: DraftResponse) -> some View {
        let me = draft.members.first(where: { $0.isMe })
        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("MY ROSTER").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 2), spacing: Theme.Spacing.xs) {
                    ForEach(me?.roster ?? []) { slot in
                        slotChip(slot)
                    }
                }
            }
        }
    }

    private func slotChip(_ slot: RosterSlot) -> some View {
        HStack(spacing: 6) {
            Text(FantasySlot.slotName(slot.slot))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: 58, alignment: .leading)
            if let p = slot.player {
                Text(p.fullName).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.Palette.textPrimary).lineLimit(1)
            } else {
                Text("—").font(.system(size: 12)).foregroundStyle(Theme.Palette.textTertiary.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xs).padding(.vertical, 6)
        .background(slot.player != nil ? Theme.Palette.accent.opacity(0.08) : Theme.Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }

    // MARK: - Complete

    private func completeView(_ draft: DraftResponse) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                Card {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(Theme.Palette.strong)
                        Text("Draft complete!").font(Theme.Font.title()).foregroundStyle(Theme.Palette.textPrimary)
                        Text("Every roster is full. Weekly matchups & scoring are coming next.")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity)
                }
                myRoster(draft)
            }
            .padding(Theme.Spacing.md)
        }
    }

    // MARK: - Actions

    private func refresh() async {
        do { draft = try await store.draftState(leagueId) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    private func pick(_ playerId: String) {
        working = true
        Task {
            do { draft = try await store.pick(leagueId, playerId: playerId); Haptics.success() }
            catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            working = false
        }
    }

    private func autopick() {
        working = true
        Task {
            do { draft = try await store.autopick(leagueId) }
            catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            working = false
        }
    }

    private func slotIcon(_ slotType: String) -> String {
        switch slotType {
        case "G": return "shield.lefthalf.filled"
        case "LHD", "RHD": return "figure.hockey"
        default: return "hockey.puck.fill"
        }
    }
}
