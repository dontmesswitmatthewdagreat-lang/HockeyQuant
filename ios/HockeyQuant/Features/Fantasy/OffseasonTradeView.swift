import SwiftUI

/// Off-season trade market: give one of your players (+ optional Cap Space) for a
/// same-position player on a rival (CPU) team. CPU GMs accept fair offers instantly.
struct OffseasonTradeView: View {
    let store: FantasyStore
    let leagueId: String
    var onTraded: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var rosters: [DraftMember] = []
    @State private var loading = true
    @State private var myPlayerId: String?
    @State private var targetMemberId: String?
    @State private var theirPlayerId: String?
    @State private var sweetenerM: Double = 0      // Cap Space sweetener, in $M
    @State private var working = false
    @State private var resultMessage: String?
    @State private var error: String?

    private var me: DraftMember? { rosters.first(where: { $0.isMe }) }
    private var myCapM: Double { Double(me?.capSpace ?? 0) / 1_000_000 }
    private var mySlot: RosterSlot? { me?.roster.first { $0.player?.id == myPlayerId } }
    private var theirPlayer: FantasyPlayer? {
        rosters.first { $0.id == targetMemberId }?.roster.first { $0.player?.id == theirPlayerId }?.player
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundView().ignoresSafeArea()
                if loading { ProgressView().tint(Theme.Palette.accent) } else { content }
            }
            .environment(\.cardSurfaceOverride, Theme.Palette.fantasySurface)
            .navigationTitle("Trade Market")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
            .alert("Trade", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
                Button("OK", role: .cancel) { resultMessage = nil }
            } message: { Text(resultMessage ?? "") }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Cap Space: \((me?.capSpace ?? 0).asCapMoney)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.accent)

                section("YOU GIVE") {
                    ForEach(myFilledSlots) { slot in
                        playerRow(slot.player!, sub: posLabel(slot), selected: myPlayerId == slot.player!.id) {
                            myPlayerId = slot.player!.id; targetMemberId = nil; theirPlayerId = nil; sweetenerM = 0
                        }
                    }
                }

                if let st = mySlot?.slotType {
                    section("YOU GET · \(FantasySlot.label(st))") {
                        if targets(forSlotType: st).isEmpty {
                            Text("No rival has a \(FantasySlot.label(st)) to trade.")
                                .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
                        }
                        ForEach(targets(forSlotType: st), id: \.self) { t in
                            playerRow(t.player, sub: "\(t.teamName) · \(t.player.cost.map { $0.asCapMoney } ?? "")",
                                      selected: theirPlayerId == t.player.id) {
                                targetMemberId = t.memberId; theirPlayerId = t.player.id
                                let gap = Double((t.player.cost ?? 0) - (mySlot?.player?.cost ?? 0)) / 1_000_000
                                sweetenerM = max(0, min(myCapM, (gap / 0.5).rounded() * 0.5))
                            }
                        }
                    }
                }

                if theirPlayerId != nil { offerCard }
            }
            .padding(Theme.Spacing.md)
        }
    }

    private var offerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("ADD CAP SPACE").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                Stepper(value: $sweetenerM, in: 0...max(0, myCapM), step: 0.5) {
                    Text("Sweetener: \(String(format: "$%.1fM", sweetenerM))")
                        .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.textPrimary)
                }
                Text("You send \(mySlot?.player?.fullName ?? "") + \(String(format: "$%.1fM", sweetenerM)) for \(theirPlayer?.fullName ?? "").")
                    .font(.system(size: 11)).foregroundStyle(Theme.Palette.textSecondary)
                PressableButton(action: propose) {
                    HStack { if working { ProgressView().tint(.white) }; Text("Propose trade").font(Theme.Font.headline()) }
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Palette.accent).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }.disabled(working)
            }
        }
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
            content()
        }
    }

    private func playerRow(_ p: FantasyPlayer, sub: String, selected: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: Theme.Spacing.sm) {
                if p.isProspect == true {
                    Text("#\(p.prospectRanking ?? 0)").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.accent).frame(width: 30)
                } else {
                    CrestView(abbrev: p.team, size: 28)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.fullName).font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary).lineLimit(1)
                    Text(sub).font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                }
                Spacer()
                Text((p.cost ?? 0).asCapMoney).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.accent)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Theme.Palette.accent : Theme.Palette.textTertiary)
            }
            .padding(Theme.Spacing.sm)
            .background(selected ? Theme.Palette.accent.opacity(0.12) : (Theme.Palette.fantasySurface))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).stroke(selected ? Theme.Palette.accent : Theme.Palette.border, lineWidth: selected ? 1.5 : 1))
        }
    }

    private var myFilledSlots: [RosterSlot] { (me?.roster ?? []).filter { $0.player != nil } }

    private func posLabel(_ slot: RosterSlot) -> String {
        slot.slotType == "FARM" ? "Prospect" : FantasySlot.label(slot.slotType)
    }

    struct Target: Hashable { let memberId: String; let teamName: String; let player: FantasyPlayer }
    private func targets(forSlotType st: String) -> [Target] {
        var out: [Target] = []
        for m in rosters where !m.isMe {
            for s in m.roster where s.slotType == st {
                if let p = s.player { out.append(Target(memberId: m.id, teamName: m.teamName, player: p)) }
            }
        }
        return out.sorted { ($0.player.cost ?? 0) > ($1.player.cost ?? 0) }
    }

    private func load() async {
        loading = true
        do { rosters = try await store.rosters(leagueId) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        loading = false
    }

    private func propose() {
        guard let mid = targetMemberId, let mine = myPlayerId, let theirs = theirPlayerId else { return }
        working = true
        Task {
            do {
                let r = try await store.offseasonTrade(leagueId, toMemberId: mid, myPlayerId: mine, theirPlayerId: theirs,
                                                       myCap: Int((sweetenerM * 1_000_000).rounded()))
                if r.status == "accepted" { Haptics.success() }
                resultMessage = r.detail ?? r.status
                if r.status == "accepted" {
                    myPlayerId = nil; targetMemberId = nil; theirPlayerId = nil; sweetenerM = 0
                    await load(); onTraded()
                }
            } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            working = false
        }
    }
}
