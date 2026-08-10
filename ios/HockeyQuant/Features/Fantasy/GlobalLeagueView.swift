import SwiftUI

/// The open, app-wide global league: anyone can join, duplicate players are
/// allowed (no draft — free pick per slot), ranked on a cumulative leaderboard.
struct GlobalLeagueView: View {
    let store: FantasyStore

    @State private var data: GlobalResponse?
    @State private var leaderboard: [GlobalLeaderboardRow] = []
    @State private var matchup: CupMatch?
    @State private var tab = 0
    @State private var loading = true
    @State private var teamName = ""
    @State private var joining = false
    @State private var pickingSlot: RosterSlot?
    @State private var error: String?
    @Environment(\.cardSurfaceOverride) private var cardSurface

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            if loading && data == nil {
                ProgressView().tint(Theme.Palette.accent)
            } else if let d = data, !d.joined {
                joinView
            } else if let d = data {
                joinedView(d)
            }
        }
        .environment(\.cardSurfaceOverride, Theme.Palette.fantasySurface)
        .toolbar {
            // The ranked weekly mode lives beside the season-long league, not
            // inside it — the two share a home but not a format.
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { DuelDraftView() } label: {
                    Image(systemName: "person.2.fill")
                }
                .accessibilityLabel("Weekly duel")
            }
        }
        .navigationTitle("Global League")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $pickingSlot) { slot in
            // Budget for this slot = remaining cap + whatever the current occupant frees up.
            let budget = (data?.remaining ?? 0) + (slot.player?.cost ?? 0)
            SlotPickerSheet(store: store, slotType: slot.slotType, budget: budget) { player in
                Task { await setSlot(slot.slot, player.id) }
            }
        }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func load() async {
        loading = true
        do {
            data = try await store.global()
            leaderboard = try await store.globalLeaderboard()
            matchup = (try? await store.cupMatchup())?.match
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        loading = false
    }

    private var joinView: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                Card {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "globe").font(.system(size: 40)).foregroundStyle(Theme.Palette.accent)
                        Text("The Global League").font(Theme.Font.title()).foregroundStyle(Theme.Palette.textPrimary)
                        Text("One open league for everyone. Pick any players you like — duplicates allowed — and climb the season-long cumulative leaderboard.")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity)
                }
                TextField("Your team name", text: $teamName)
                    .padding(Theme.Spacing.md).background(Theme.Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).stroke(Theme.Palette.border, lineWidth: 1))
                PressableButton(action: join) {
                    HStack { if joining { ProgressView().tint(.white) }; Text("Join the global league").font(Theme.Font.headline()) }
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
                        .background(teamName.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.Palette.accent.opacity(0.4) : Theme.Palette.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }.disabled(teamName.trimmingCharacters(in: .whitespaces).isEmpty || joining)
            }.padding(Theme.Spacing.md)
        }
    }

    private func joinedView(_ d: GlobalResponse) -> some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("My Roster").tag(0); Text("Leaderboard").tag(1)
            }.pickerStyle(.segmented).padding(Theme.Spacing.md)
            ScrollView {
                VStack(spacing: Theme.Spacing.xs) {
                    if tab == 0 {
                        if let m = matchup { matchupCard(m) }
                        budgetCard(d)
                        Text("Tap a slot to sign a player — your roster must fit under your Cap Space.")
                            .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, Theme.Spacing.xs)
                        ForEach(d.myRoster) { slot in rosterSlotRow(slot) }
                    } else {
                        ForEach(Array(leaderboard.enumerated()), id: \.element.id) { i, row in leaderRow(i + 1, row) }
                    }
                }.padding(.horizontal, Theme.Spacing.md).padding(.bottom, Theme.Spacing.lg)
            }
        }
    }

    // MARK: Weekly Cup matchup

    private func cupColor(_ m: CupMatch) -> Color {
        m.didWin ? Theme.Palette.positive : (m.didLose ? Theme.Palette.negative : Theme.Palette.accent)
    }

    private func matchupCard(_ m: CupMatch) -> some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Week \(m.week) · Cup Match")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Spacer()
                    Text(m.didWin ? "WON" : (m.didLose ? "LOST" : "TIE"))
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(cupColor(m))
                        .clipShape(Capsule())
                }
                HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                    teamColumn(name: m.myTeam, score: m.myScore, mine: true)
                    Text("vs").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                    teamColumn(name: m.opponentTeam, score: m.opponentScore, mine: false)
                }
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill").font(.system(size: 12))
                    Text(m.cupDelta >= 0 ? "+\(m.cupDelta) Cups" : "\(m.cupDelta) Cups")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(cupColor(m))
                if m.isGhost {
                    Text("No live opponent near you yet — you played the league average. Cups still count.")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func teamColumn(name: String, score: Double, mine: Bool) -> some View {
        VStack(spacing: 2) {
            Text(name).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(String(format: "%.1f", score))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(mine ? Theme.Palette.accent : Theme.Palette.textSecondary)
            Text(mine ? "You" : "Opponent").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
        }.frame(maxWidth: .infinity)
    }

    private func budgetCard(_ d: GlobalResponse) -> some View {
        Card {
            VStack(spacing: Theme.Spacing.xs) {
                HStack {
                    budgetStat("Cap Space", d.cap, Theme.Palette.accent)
                    Spacer()
                    budgetStat("Spent", d.spent, Theme.Palette.textPrimary)
                    Spacer()
                    budgetStat("Free", d.remaining, d.remaining > 0 ? Theme.Palette.positive : Theme.Palette.negative)
                }
                GeometryReader { geo in
                    let frac = d.cap > 0 ? min(1, Double(d.spent) / Double(d.cap)) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Palette.border)
                        Capsule().fill(d.spent > d.cap ? Theme.Palette.negative : Theme.Palette.accent)
                            .frame(width: max(2, geo.size.width * frac))
                    }
                }.frame(height: 6)
                if d.maxCap > 0 {
                    Text("League salary cap \(d.maxCap.asCapMoney) — rises each season")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func budgetStat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value.asCapMoney).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(color)
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.Palette.textPrimary)
        }
    }

    private func rosterSlotRow(_ slot: RosterSlot) -> some View {
        Button { pickingSlot = slot } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(FantasySlot.slotName(slot.slot)).font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Palette.textTertiary).frame(width: 72, alignment: .leading)
                if let p = slot.player {
                    CrestView(abbrev: p.team, size: 24)
                    Text(p.fullName).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary)
                } else {
                    Text("Tap to pick").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.accent)
                }
                Spacer()
                if let p = slot.player {
                    Text((p.cost ?? 0).asCapMoney).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.accent)
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.sm).padding(.vertical, 8)
            .background(cardSurface ?? Theme.Palette.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        }
    }

    private func leaderRow(_ rank: Int, _ row: GlobalLeaderboardRow) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("\(rank)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.Palette.textSecondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.teamName).font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                Text("@\(row.username ?? "manager") · \(row.goals) goals").font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer()
            Text(String(format: "%.1f", row.points)).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.accent)
        }
        .padding(Theme.Spacing.sm)
        .background(row.isMe ? Theme.Palette.accent.opacity(0.10) : (cardSurface ?? Theme.Palette.surface))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).stroke(row.isMe ? Theme.Palette.accent : .clear, lineWidth: 1.5))
    }

    private func join() {
        joining = true
        Task {
            do { _ = try await store.globalJoin(teamName: teamName); await load() }
            catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            joining = false
        }
    }

    private func setSlot(_ slot: String, _ playerId: String) async {
        do { try await store.globalSetSlot(slot: slot, playerId: playerId); await load() }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}

/// Picks any eligible player of a given slot type (used by the global free-pick roster).
struct SlotPickerSheet: View {
    let store: FantasyStore
    let slotType: String
    var budget: Int = .max          // most a single player in this slot can cost
    let onPick: (FantasyPlayer) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var players: [FantasyPlayer] = []
    @State private var query = ""
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(players) { p in
                        let cost = p.cost ?? 0
                        let affordable = cost <= budget
                        Button { if affordable { onPick(p); dismiss() } } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                CrestView(abbrev: p.team, size: 26)
                                Text(p.fullName).foregroundStyle(Theme.Palette.textPrimary)
                                Spacer()
                                Text(cost.asCapMoney).font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(affordable ? Theme.Palette.accent : Theme.Palette.negative)
                            }
                            .opacity(affordable ? 1 : 0.45)
                        }
                        .disabled(!affordable)
                    }
                } header: {
                    if budget != .max {
                        Text("\(budget.asCapMoney) to spend on this slot").textCase(nil)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
            .overlay { if loading { ProgressView() } }
            .searchable(text: $query)
            .onChange(of: query) { _, _ in Task { await search() } }
            .navigationTitle("Pick \(FantasySlot.label(slotType))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await search() }
        }
    }

    private func search() async {
        loading = true
        do { players = try await store.players(slotType: slotType, query: query.isEmpty ? nil : query) }
        catch { players = [] }
        loading = false
    }
}
