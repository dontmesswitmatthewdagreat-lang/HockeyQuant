import SwiftUI

/// The open, app-wide global league: anyone can join, duplicate players are
/// allowed (no draft — free pick per slot), ranked on a cumulative leaderboard.
struct GlobalLeagueView: View {
    let store: FantasyStore

    @State private var data: GlobalResponse?
    @State private var leaderboard: [GlobalLeaderboardRow] = []
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
        .navigationTitle("Global League")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $pickingSlot) { slot in
            SlotPickerSheet(store: store, slotType: slot.slotType) { player in
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
                        Text("Tap a slot to pick any eligible player (duplicates allowed).")
                            .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, Theme.Spacing.xs)
                        ForEach(d.myRoster) { slot in rosterSlotRow(slot) }
                    } else {
                        ForEach(Array(leaderboard.enumerated()), id: \.element.id) { i, row in leaderRow(i + 1, row) }
                    }
                }.padding(.horizontal, Theme.Spacing.md).padding(.bottom, Theme.Spacing.lg)
            }
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
    let onPick: (FantasyPlayer) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var players: [FantasyPlayer] = []
    @State private var query = ""
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                ForEach(players) { p in
                    Button { onPick(p); dismiss() } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            CrestView(abbrev: p.team, size: 26)
                            Text(p.fullName).foregroundStyle(Theme.Palette.textPrimary)
                            Spacer()
                            Text(p.team).font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                        }
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
