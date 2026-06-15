import SwiftUI

/// Trades for private leagues: see incoming/outgoing trades, accept/reject, and
/// propose a one-for-one swap of same-position players (before the deadline).
struct TradesView: View {
    let store: FantasyStore
    let leagueId: String
    let season: FantasySeasonResponse

    @State private var trades: [TradeItem] = []
    @State private var rosters: [DraftMember] = []
    @State private var loading = true
    @State private var working = false
    @State private var showPropose = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    PressableButton(action: { showPropose = true }) {
                        HStack { Image(systemName: "plus.circle.fill"); Text("Propose a trade").font(Theme.Font.headline()) }
                            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
                            .background(Theme.Palette.accent).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    }
                    if loading {
                        ForEach(0..<2, id: \.self) { _ in LoadingShimmer(height: 70) }
                    } else if trades.isEmpty {
                        EmptyStateView(systemImage: "arrow.left.arrow.right.circle", title: "No trades yet",
                                       message: "Propose a one-for-one swap of same-position players with another manager.")
                    } else {
                        ForEach(trades) { t in tradeCard(t) }
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle("Trades")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showPropose) {
            ProposeTradeSheet(store: store, leagueId: leagueId, rosters: rosters) { Task { await load() } }
        }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func load() async {
        loading = true
        do {
            async let t = store.trades(leagueId)
            async let r = store.rosters(leagueId)
            trades = try await t; rosters = try await r
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        loading = false
    }

    private func tradeCard(_ t: TradeItem) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text(t.incoming ? "INCOMING" : (t.status == "pending" ? "OUTGOING" : t.status.uppercased()))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(t.incoming ? Theme.Palette.accent : Theme.Palette.textTertiary)
                    Spacer()
                    Text(FantasySlot.label(t.slotType)).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
                }
                HStack(spacing: Theme.Spacing.sm) {
                    swapSide(t.proposerTeam, t.proposerPlayer)
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(Theme.Palette.textTertiary)
                    swapSide(t.receiverTeam, t.receiverPlayer)
                }
                if t.incoming && t.status == "pending" {
                    HStack(spacing: Theme.Spacing.sm) {
                        PressableButton(action: { respond(t, accept: true) }) {
                            Text("Accept").font(Theme.Font.caption()).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(Theme.Palette.strong).clipShape(Capsule())
                        }.disabled(working)
                        PressableButton(action: { respond(t, accept: false) }) {
                            Text("Reject").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.negative)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(Theme.Palette.negative.opacity(0.12)).clipShape(Capsule())
                        }.disabled(working)
                    }
                }
            }
        }
    }

    private func swapSide(_ team: String?, _ player: TradePlayer?) -> some View {
        VStack(spacing: 2) {
            Text(player?.fullName ?? "—").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary).lineLimit(1)
            Text(team ?? "").font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
        }.frame(maxWidth: .infinity)
    }

    private func respond(_ t: TradeItem, accept: Bool) {
        working = true
        Task {
            do { try await store.respondTrade(leagueId, tradeId: t.id, accept: accept); await load() }
            catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            working = false
        }
    }
}

private struct ProposeTradeSheet: View {
    let store: FantasyStore
    let leagueId: String
    let rosters: [DraftMember]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var myPlayer: FantasyPlayer?
    @State private var oppMemberId: String?
    @State private var theirPlayer: FantasyPlayer?
    @State private var working = false
    @State private var error: String?

    private var myRoster: [RosterSlot] { rosters.first(where: { $0.isMe })?.roster ?? [] }
    private var opponents: [DraftMember] { rosters.filter { !$0.isMe } }
    private var oppRoster: [RosterSlot] { rosters.first(where: { $0.id == oppMemberId })?.roster ?? [] }

    var body: some View {
        NavigationStack {
            Form {
                Section("You give") {
                    picker(myRoster, selected: myPlayer) { p in myPlayer = p; theirPlayer = nil }
                }
                Section("Opponent") {
                    Picker("Manager", selection: Binding(get: { oppMemberId ?? "" }, set: { oppMemberId = $0; theirPlayer = nil })) {
                        Text("Select").tag("")
                        ForEach(opponents) { o in Text(o.teamName).tag(o.id) }
                    }
                }
                if let mine = myPlayer, oppMemberId != nil {
                    Section("You get (\(FantasySlot.label(mine.rosterPos)))") {
                        let eligible = oppRoster.filter { $0.player != nil && $0.slotType == mine.rosterPos }
                        if eligible.isEmpty {
                            Text("That manager has no \(FantasySlot.label(mine.rosterPos)) to trade.")
                                .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
                        } else {
                            picker(eligible, selected: theirPlayer) { p in theirPlayer = p }
                        }
                    }
                }
            }
            .navigationTitle("Propose trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }.disabled(myPlayer == nil || theirPlayer == nil || oppMemberId == nil || working)
                }
            }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func picker(_ slots: [RosterSlot], selected: FantasyPlayer?, onPick: @escaping (FantasyPlayer) -> Void) -> some View {
        ForEach(slots.compactMap { $0.player }, id: \.id) { p in
            Button {
                onPick(p)
            } label: {
                HStack {
                    Text("\(p.fullName) · \(p.team)").foregroundStyle(Theme.Palette.textPrimary)
                    Spacer()
                    if selected?.id == p.id { Image(systemName: "checkmark").foregroundStyle(Theme.Palette.accent) }
                }
            }
        }
    }

    private func send() {
        guard let mine = myPlayer, let theirs = theirPlayer, let opp = oppMemberId else { return }
        working = true
        Task {
            do {
                try await store.proposeTrade(leagueId, toMemberId: opp, myPlayerId: mine.id, theirPlayerId: theirs.id)
                onDone(); dismiss()
            } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            working = false
        }
    }
}
