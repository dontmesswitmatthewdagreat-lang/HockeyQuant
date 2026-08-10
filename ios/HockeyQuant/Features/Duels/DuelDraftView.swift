import SwiftUI

/// The Global League draft: your board, the clock, and both rosters filling in.
///
/// The board is the whole game here — you're handed a small, random set of
/// players at one slot and have to take one. Scarce slots offer two, depth
/// slots offer five, so the screen leads with what's on offer and how long
/// you have, and keeps the roster underneath as reference.
struct DuelDraftView: View {
    @Environment(AuthStore.self) private var auth

    @State private var current: DuelCurrent?
    @State private var loading = true
    @State private var picking: Int?
    @State private var error: String?
    @State private var now = Date()

    /// Drives the countdown. One second is plenty — the window is hours.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Theme.backgroundView()
            content
        }
        .navigationTitle("Weekly Duel")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onReceive(tick) { now = $0 }
    }

    @ViewBuilder
    private var content: some View {
        if loading && current == nil {
            ProgressView().controlSize(.large)
        } else if let duel = current?.duel {
            ScrollView {
                VStack(spacing: 16) {
                    header(duel)
                    if duel.isDrafting {
                        if current?.onTheClock == true {
                            clock
                            board
                        } else {
                            waitingCard
                        }
                    } else {
                        liveCard(duel)
                    }
                    rosters(duel)
                }
                .padding(16)
            }
        } else {
            queueCard
        }
    }

    // MARK: - Pieces

    private func header(_ duel: Duel) -> some View {
        Card {
            VStack(spacing: 6) {
                Text("WEEK OF \(duel.weekStart)")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text(duel.isDrafting ? "Drafting" : "Live")
                    .font(Theme.Font.headlineHeavy())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Pick \(min(duel.pickNo + 1, 12)) of 12")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var clock: some View {
        let remaining = current?.deadline.map { $0.timeIntervalSince(now) } ?? 0
        let urgent = remaining < 3600
        return Card {
            VStack(spacing: 4) {
                Text("ON THE CLOCK")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text(countdown(remaining))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(urgent ? Color(hex: 0xD64545) : Theme.Palette.accent)
                Text(remaining > 0
                     ? "Pick before the clock runs out or it picks for you."
                     : "Time's up — the clock is picking for you.")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let slot = currentPick?.slotLabel {
                HStack {
                    Text(slot.uppercased())
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.accent)
                    Spacer()
                    Text("\(current?.board?.count ?? 0) options")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            ForEach(current?.board ?? []) { player in
                boardRow(player)
            }
            if let error {
                Text(error)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Color(hex: 0xD64545))
            }
        }
    }

    private func boardRow(_ player: DuelBoardPlayer) -> some View {
        Button {
            Task { await pick(player) }
        } label: {
            Card {
                HStack(spacing: 12) {
                    CrestView(abbrev: player.team ?? "", size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.name)
                            .font(Theme.Font.headline())
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text([player.pos, player.team].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    if picking == player.nhlId {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(picking != nil)
    }

    private var waitingCard: some View {
        Card {
            VStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.Palette.accent)
                Text("Opponent is picking")
                    .font(Theme.Font.headline())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Pull to refresh — you'll be back up shortly.")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func liveCard(_ duel: Duel) -> some View {
        Card {
            VStack(spacing: 6) {
                Text("ROSTERS LOCKED")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text("Scores settle Sunday night")
                    .font(Theme.Font.headline())
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let a = duel.scoreA, let b = duel.scoreB {
                    Text(String(format: "%.1f – %.1f", a, b))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func rosters(_ duel: Duel) -> some View {
        let mine = (current?.picks ?? []).filter { $0.userId.lowercased() == myId }
        let theirs = (current?.picks ?? []).filter { $0.userId.lowercased() != myId }
        return VStack(spacing: 12) {
            rosterCard("YOUR ROSTER", picks: mine)
            rosterCard("OPPONENT", picks: theirs)
        }
    }

    private func rosterCard(_ title: String, picks: [DuelPick]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
                ForEach(picks.sorted { $0.pickNo < $1.pickNo }) { pick in
                    HStack {
                        Text(pick.slotLabel)
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(width: 96, alignment: .leading)
                        Text(pick.isDone ? "Picked" : "—")
                            .font(Theme.Font.body())
                            .foregroundStyle(pick.isDone
                                             ? Theme.Palette.textPrimary
                                             : Theme.Palette.textSecondary)
                        Spacer()
                        if pick.autoPicked {
                            Text("AUTO")
                                .font(Theme.Font.caption())
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var queueCard: some View {
        Card {
            VStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.Palette.accent)
                Text(current?.queued == true ? "You're in the queue" : "No duel this week")
                    .font(Theme.Font.headlineHeavy())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(current?.queued == true
                     ? "You'll be matched Monday and drafted against a GM near your rating."
                     : "Join the queue to be matched with another GM for next week.")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                Button(current?.queued == true ? "Leave queue" : "Join queue") {
                    Task { await toggleQueue() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Palette.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .padding(16)
    }

    // MARK: - Helpers

    /// AuthStore surfaces an uppercased UUID while Postgres stores it lower —
    /// comparing them raw silently shows you the opponent's side as your own.
    private var myId: String? { auth.userId?.lowercased() }

    private var currentPick: DuelPick? {
        (current?.picks ?? [])
            .filter { !$0.isDone && $0.userId.lowercased() == myId }
            .min { $0.pickNo < $1.pickNo }
    }

    private func countdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    private func load() async {
        guard let token = await auth.accessToken() else { loading = false; return }
        loading = true
        defer { loading = false }
        do { current = try await APIClient().duelCurrent(token: token) }
        catch { self.error = error.localizedDescription }
    }

    private func pick(_ player: DuelBoardPlayer) async {
        guard let token = await auth.accessToken(), let duel = current?.duel else { return }
        picking = player.nhlId
        defer { picking = nil }
        do {
            _ = try await APIClient().duelPick(duelId: duel.id, nhlId: player.nhlId, token: token)
            error = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggleQueue() async {
        guard let token = await auth.accessToken() else { return }
        do {
            if current?.queued == true {
                try await APIClient().duelLeaveQueue(token: token)
            } else {
                try await APIClient().duelJoinQueue(token: token)
            }
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
